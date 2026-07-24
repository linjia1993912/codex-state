# 03 · Codex RPC 客户端

> 文件：`Sources/CodexStateCore/RPC/CodexRPCClient.swift`

RPC 层负责启动本机 Codex `app-server` 子进程，按 JSON-RPC 2.0 协议在 stdio 上完成：

1. `initialize` 握手 + `initialized` 通知。
2. `account/read`（强制 `refreshToken: false`）。
3. `account/rateLimits/read`。
4. 解码为 `CodexRemoteSnapshot { account, quotaWindows }` 供 `UsageStore` 消费。

## 1. 公共类型

### `CodexRemoteSnapshot`

```swift
public struct CodexRemoteSnapshot: Equatable, Sendable {
    public let account: AccountSummary?
    public let quotaWindows: [QuotaWindow]
}
```

### `CodexRPCError`

```swift
public enum CodexRPCError: LocalizedError {
    case executableNotFound
    case timedOut
    case invalidResponse
    case server(String)
}
```

- `executableNotFound` — `codex` 二进制无法在已知路径中找到。
- `timedOut` — 单次请求超过 `timeout`（默认 5 秒）。
- `invalidResponse` — JSON 形状不匹配或缺 `result`。
- `server(message)` — `error.message` 字段透传。

## 2. `CodexRPCCodec`

协议编解码的纯函数集合。`internal` 成员可被单元测试覆盖。

- `encodeInitializedNotification() -> Data` — 构造一个以 `0x0A` 结尾的 `{"jsonrpc":"2.0","method":"initialized","params":{}}`。
- `decodeAccount(_:) -> AccountSummary?` — 只接受 `type == "chatgpt"` 的账号；返回脱敏前的 `AccountSummary`。
- `decodeRateLimits(_:) -> [QuotaWindow]` — 把 `primary` / `secondary` 窗口映射为带本地化标题的 `QuotaWindow`：
  - `>= 10_080` 分钟 → "每周额度"。
  - 整除 `1_440` → "`N` 天额度"。
  - 整除 `60` → "`N` 小时额度"。
  - 其它 → 短周期 / 每周额度的回退标题。
- `validateResponse(_:)` — 顶层校验 `error.message` 与 `result` 字段存在。
- `decode(_:from:)` — 内部辅助，统一捕获 `DecodingError` 并转化为 `invalidResponse`。

## 3. `CodexRPCClient`

```swift
public final class CodexRPCClient: @unchecked Sendable {
    public init(executablePath: String? = nil, timeout: TimeInterval = 5)
    public func read() throws -> CodexRemoteSnapshot
}
```

`@unchecked Sendable` 因为内部管理 `Process` 和 `Pipe`，而 Swift 6 严格并发下它们不是 `Sendable`；但 `read()` 是同步阻塞调用，由 `UsageStore` 显式包到 `Task.detached` 中运行。

### 3.1 `read()` 流程

1. 解析可执行文件路径（见 `resolveExecutable`）。
2. 创建 `Process`，参数为 `app-server --listen stdio://`；`standardError` 指向 `FileHandle.nullDevice`。
3. 创建 `JSONRPCLineReader` 监听 stdout。
4. 发送 `initialize` 握手（`id = 1`）并写入 `initialized` 通知。
5. 发送 `account/read`（`id = 2`，`refreshToken: false`）。
6. 发送 `account/rateLimits/read`（`id = 3`）。
7. 在 `defer` 中依次停止 reader、关闭输入管道、终止子进程。
8. 返回 `CodexRemoteSnapshot`。

### 3.2 `resolveExecutable`

按以下顺序查找 `codex` 可执行文件：

1. 显式传入的 `executablePath`。
2. `$PATH` 中的 `codex`。
3. `/opt/homebrew/bin/codex` 与 `/usr/local/bin/codex`（Apple Silicon / Intel Homebrew）。
4. `~/.nvm/versions/node/*/bin/codex`（按目录名数字倒序，取最新 Node 版本下的安装）。

任一文件通过 `FileManager.isExecutableFile(atPath:)` 校验即可。

## 4. `JSONRPCLineReader`

```swift
private final class JSONRPCLineReader: @unchecked Sendable {
    init(handle: FileHandle)
    func prepare(for id: Int) -> DispatchSemaphore
    func takeResponse(for id: Int) -> Data?
    func cancel(id: Int)
    func stop()
}
```

- 通过 `FileHandle.readabilityHandler` 持续把字节追加到 `buffer`。
- 按 `0x0A` 拆行，解析为 JSON 对象；只关心 `id` 字段在 `waiters` 中的请求响应。
- 通知类消息（无 `id`）不会唤醒任何信号量，避免饥饿。
- `NSLock` 保护 `buffer / responses / waiters` 三个共享字段。
- `prepare / takeResponse / cancel` 三者配合形成"请求 → 阻塞等待 → 取出响应"协议；超时由 `request(...)` 外层决定。

## 5. 协议细节

请求帧格式：

```json
{"jsonrpc":"2.0","id":<int>,"method":"<name>","params":{...}}
\n
```

- 帧以单个 `\n` 结尾，与 Codex `app-server` 的 stdio 协议保持一致。
- `initialized` 通知与 `initialize` 响应严格顺序：先收到 `initialize` 的响应后再发送 `initialized` 通知，再发后续请求。

## 6. 测试要点

- `Tests/CodexStateCoreTests/CodexRPCClientTests.swift` 覆盖：
  - 可执行文件解析（包括 nvm 多版本）。
  - 超时与无效响应。
  - `account/read` 解码时仅保留 `chatgpt` 类型。
  - `rateLimits` 解码根据 `windowDurationMins` 选择标题。
