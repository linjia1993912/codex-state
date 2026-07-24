import Foundation
import Testing
@testable import CodexStateCore

struct CodexRPCClientTests {
    @Test
    func initializedNotificationHasNoID() throws {
        let data = try CodexRPCCodec.encodeInitializedNotification()
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["jsonrpc"] as? String == "2.0")
        #expect(object["method"] as? String == "initialized")
        #expect(object["params"] as? [String: String] == [:])
        #expect(object["id"] == nil)
    }

    @Test
    func resolvesNewestExecutableFromNVMWhenPATHIsEmpty() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }

        for version in ["v18.20.0", "v22.1.0"] {
            let bin = home.appendingPathComponent(".nvm/versions/node/\(version)/bin", isDirectory: true)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let executable = bin.appendingPathComponent("codex")
            try Data().write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }

        // 注入排除 ChatGPT.app 的 fileManager，专注验证 nvm 解析逻辑，
        // 不受本机是否安装 ChatGPT.app 影响。
        let executable = try CodexRPCClient.resolveExecutable(
            explicitPath: nil,
            environment: ["PATH": ""],
            homeDirectory: home,
            fileManager: FileManagerExcludingChatGPTApp()
        )

        #expect(executable.path.hasSuffix("/.nvm/versions/node/v22.1.0/bin/codex"))
    }

    @Test
    func testDecodesChatGPTAccount() throws {
        let data = Data("""
        {"id":2,"result":{"account":{"type":"chatgpt","email":"ada@example.com","planType":"plus"}}}
        """.utf8)

        #expect(try CodexRPCCodec.decodeAccount(data) == AccountSummary(email: "ada@example.com", plan: "plus"))
    }

    @Test
    func testDecodesOnlySecondaryWeeklyWindow() throws {
        let data = Data("""
        {"id":3,"result":{"rateLimits":{"limitId":"codex","limitName":"Codex","planType":"plus","primary":null,"secondary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":1753747200}}}}
        """.utf8)

        #expect(try CodexRPCCodec.decodeRateLimits(data) == [
            QuotaWindow(
                id: "secondary",
                title: "每周额度",
                usedPercent: 42,
                resetsAt: Date(timeIntervalSince1970: 1_753_747_200),
                durationMinutes: 10_080
            )
        ])
    }
}

/// 测试用 FileManager 子类：排除系统已安装的 ChatGPT.app 内 codex，
/// 以便专注验证 nvm 解析逻辑，不受本机是否安装 ChatGPT.app 影响。
private final class FileManagerExcludingChatGPTApp: FileManager {
    override func isExecutableFile(atPath path: String) -> Bool {
        if path.contains("ChatGPT.app") { return false }
        return super.isExecutableFile(atPath: path)
    }
}
