import Foundation

public struct CodexRemoteSnapshot: Equatable, Sendable {
    public let account: AccountSummary?
    public let quotaWindows: [QuotaWindow]

    public init(account: AccountSummary?, quotaWindows: [QuotaWindow]) {
        self.account = account
        self.quotaWindows = quotaWindows
    }
}

public enum CodexRPCError: LocalizedError {
    case executableNotFound
    case timedOut
    case invalidResponse
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound: "未找到 Codex 可执行文件"
        case .timedOut: "Codex RPC 响应超时"
        case .invalidResponse: "Codex RPC 响应无效"
        case let .server(message): "Codex RPC 服务错误：\(message)"
        }
    }
}

public enum CodexRPCCodec {
    static func encodeInitializedNotification() throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": [:],
        ])
        data.append(0x0A)
        return data
    }

    public static func decodeAccount(_ data: Data) throws -> AccountSummary? {
        let account = try decode(AccountResponse.self, from: data).account
        guard account?.type.lowercased() == "chatgpt" else { return nil }
        return AccountSummary(email: account?.email, plan: account?.planType)
    }

    public static func decodeRateLimits(_ data: Data) throws -> [QuotaWindow] {
        guard let limits = try decode(LimitsResponse.self, from: data).rateLimits else { return [] }
        return [("primary", limits.primary), ("secondary", limits.secondary)].compactMap { id, window in
            guard let window else { return nil }
            return QuotaWindow(
                id: id,
                title: title(for: id, durationMinutes: window.windowDurationMins),
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt.map(Date.init(timeIntervalSince1970:)),
                durationMinutes: window.windowDurationMins
            )
        }
    }

    static func validateResponse(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexRPCError.invalidResponse
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            throw CodexRPCError.server(message)
        }
        guard object["result"] != nil else { throw CodexRPCError.invalidResponse }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try validateResponse(data)
        do {
            return try JSONDecoder().decode(RPCResponse<Value>.self, from: data).result
        } catch {
            throw CodexRPCError.invalidResponse
        }
    }

    private static func title(for id: String, durationMinutes: Int?) -> String {
        guard let durationMinutes else { return id == "primary" ? "短周期额度" : "每周额度" }
        if durationMinutes >= 10_080 { return "每周额度" }
        if durationMinutes.isMultiple(of: 1_440) { return "\(durationMinutes / 1_440) 天额度" }
        if durationMinutes.isMultiple(of: 60) { return "\(durationMinutes / 60) 小时额度" }
        return id == "primary" ? "短周期额度" : "每周额度"
    }
}

public final class CodexRPCClient: @unchecked Sendable {
    private let executablePath: String?
    private let timeout: TimeInterval

    public init(executablePath: String? = nil, timeout: TimeInterval = 5) {
        self.executablePath = executablePath
        self.timeout = timeout
    }

    public func read() throws -> CodexRemoteSnapshot {
        let process = Process()
        let execURL = try resolveExecutable()
        process.executableURL = execURL
        // 参考 CodexBar：必须以 read-only 沙箱 + untrusted 审批模式启动 app-server，
        // 否则默认沙箱/审批策略会阻止 account/rateLimits 读取，导致额度窗口为空。
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server"]

        // codex 可能是 node 脚本（nvm 安装），需要 node 在 PATH 中。
        // GUI app 的 PATH 通常不包含 codex 所在目录，将其加入 PATH。
        var env = ProcessInfo.processInfo.environment
        let codexDir = execURL.deletingLastPathComponent().path
        let currentPATH = env["PATH"] ?? ""
        if !currentPATH.contains(codexDir) {
            env["PATH"] = codexDir + ":" + currentPATH
        }
        process.environment = env

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output

        let reader = JSONRPCLineReader(handle: output.fileHandleForReading)
        defer {
            reader.stop()
            input.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
        }

        try process.run()

        // initialize 需要启动 codex 运行时，超时要比普通请求更长（参考 CodexBar: 8s init / 3s request）
        _ = try request(
            id: 1,
            method: "initialize",
            params: ["clientInfo": ["name": "codex-state", "version": "1.0"], "capabilities": [:]],
            input: input.fileHandleForWriting,
            reader: reader,
            timeout: max(timeout, 10)
        )
        input.fileHandleForWriting.write(try CodexRPCCodec.encodeInitializedNotification())
        let accountData = try request(
            id: 2,
            method: "account/read",
            params: ["refreshToken": false],
            input: input.fileHandleForWriting,
            reader: reader
        )
        let limitsData = try request(
            id: 3,
            method: "account/rateLimits/read",
            params: [:],
            input: input.fileHandleForWriting,
            reader: reader
        )

        let account = try CodexRPCCodec.decodeAccount(accountData)
        let quotaWindows = try CodexRPCCodec.decodeRateLimits(limitsData)
        return CodexRemoteSnapshot(account: account, quotaWindows: quotaWindows)
    }

    private func resolveExecutable() throws -> URL {
        try Self.resolveExecutable(
            explicitPath: executablePath,
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func resolveExecutable(
        explicitPath: String?,
        environment: [String: String],
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let nvmVersions = homeDirectory.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        let nvmPaths = (try? fileManager.contentsOfDirectory(
            at: nvmVersions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.sorted {
            $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
        }.map { $0.appendingPathComponent("bin/codex").path } ?? []
        // 优先使用 ChatGPT.app 内捆绑的 codex：它是独立 Mach-O 二进制，不依赖 node，
        // 且已验证能正常初始化 sqlite 状态运行时（nvm 的 codex 从 GUI app 启动时 sqlite 初始化失败）。
        let chatGPTAppCodex = "/Applications/ChatGPT.app/Contents/Resources/codex"
        let paths = explicitPath.map { [$0] } ?? (
            [chatGPTAppCodex]
            + (environment["PATH"] ?? "")
                .split(separator: ":")
                .map { "\($0)/codex" }
            + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            + nvmPaths
        )
        guard let path = paths.first(where: fileManager.isExecutableFile(atPath:)) else {
            throw CodexRPCError.executableNotFound
        }
        return URL(fileURLWithPath: path)
    }

    private func request(
        id: Int,
        method: String,
        params: [String: Any],
        input: FileHandle,
        reader: JSONRPCLineReader,
        timeout: TimeInterval? = nil
    ) throws -> Data {
        let resolvedTimeout = timeout ?? self.timeout
        let response = reader.prepare(for: id)
        let request = ["jsonrpc": "2.0", "id": id, "method": method, "params": params] as [String: Any]
        guard let data = try? JSONSerialization.data(withJSONObject: request) else {
            throw CodexRPCError.invalidResponse
        }
        input.write(data)
        input.write(Data([0x0A]))
        guard response.wait(timeout: .now() + resolvedTimeout) == .success, let data = reader.takeResponse(for: id) else {
            reader.cancel(id: id)
            throw CodexRPCError.timedOut
        }
        try CodexRPCCodec.validateResponse(data)
        return data
    }
}

private struct RPCResponse<Result: Decodable>: Decodable {
    let result: Result
}

private struct AccountResponse: Decodable {
    let account: RemoteAccount?
}

private struct RemoteAccount: Decodable {
    let type: String
    let email: String?
    let planType: String?
}

private struct LimitsResponse: Decodable {
    let rateLimits: RemoteRateLimits?
}

private struct RemoteRateLimits: Decodable {
    let primary: RemoteQuotaWindow?
    let secondary: RemoteQuotaWindow?
}

private struct RemoteQuotaWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}

private final class JSONRPCLineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var responses: [Int: Data] = [:]
    private var waiters: [Int: DispatchSemaphore] = [:]
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData)
        }
    }

    func prepare(for id: Int) -> DispatchSemaphore {
        lock.withLock {
            let waiter = DispatchSemaphore(value: 0)
            waiters[id] = waiter
            return waiter
        }
    }

    func takeResponse(for id: Int) -> Data? {
        lock.withLock {
            waiters[id] = nil
            defer { responses[id] = nil }
            return responses[id]
        }
    }

    func cancel(id: Int) {
        lock.withLock {
            waiters[id] = nil
            responses[id] = nil
        }
    }

    func stop() {
        handle.readabilityHandler = nil
    }

    private func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            buffer.append(data)
            // app-server 可能穿插通知，按 JSON-RPC id 缓存匹配的响应。
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = (object["id"] as? NSNumber)?.intValue,
                      let waiter = waiters[id] else { continue }
                responses[id] = line
                waiter.signal()
            }
        }
    }
}
