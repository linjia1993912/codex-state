# 09 · 应用入口与生命周期

> 文件：`Sources/CodexState/CodexStateApp.swift`

`CodexState` 可执行 target 只做三件事：启动 accessory App、装配依赖、维护一个 5 分钟一次的刷新循环。

## 1. `CodexStateApp`

```swift
@main
struct CodexStateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

- 使用 `@NSApplicationDelegateAdaptor` 把 `AppDelegate` 注入 SwiftUI 生命周期。
- `body` 仅声明一个空 `Settings Scene`：UI 实际由 `NSPanel` 承载，SwiftUI Scene 仅作为启动入口。

## 2. `AppDelegate`

```swift
@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var panelController: NotchPanelController?
    private var hotKey: GlobalHotKey?
    private var refreshTask: Task<Void, Never>?
}
```

### 2.1 `applicationDidFinishLaunching(_:)`

执行步骤：

1. `NSApp.setActivationPolicy(.accessory)` — 不在 Dock 显示图标，符合"小工具"定位。
2. 解析 `CODEX_HOME`：
   - 优先 `ProcessInfo.processInfo.environment["CODEX_HOME"]`。
   - 回退 `~/.codex`。
3. 解析缓存路径 `~/Library/Caches/CodexState/usage-cache.json`，自动创建父目录。
4. 装配：
   - `SessionUsageRepository(cacheURL:)`。
   - `CodexRPCClient()`。
   - `UsageStore(remoteLoader: rpcClient.read, sessionLoader: { try repository.load(home: codexHome, calendar: .current) }, catalog: try ModelPriceCatalog.bundled())`。
   - `NotchPanelController(store: store)`。
5. 注册全局快捷键：
   ```swift
   hotKey = GlobalHotKey.registerIfAvailable { [weak panelController] in
       panelController?.toggleExpanded()
   }
   ```
6. `panelController.show()` 显示面板。
7. `startRefreshing(store: store)` 启动定时刷新。

任何错误通过 `NSApp.presentError(error)` 报告给用户。

### 2.2 `applicationWillTerminate(_:)`

```swift
func applicationWillTerminate(_ notification: Notification) {
    refreshTask?.cancel()
    hotKey?.stop()
    panelController?.stop()
}
```

- 显式取消 `refreshTask`，避免 5 分钟的睡眠任务在应用生命周期外继续持有 `store`。
- `hotKey?.stop()` 注销 Carbon 事件。
- `panelController.stop()` 移除点击监听并 `orderOut(nil)`。

### 2.3 `startRefreshing(store:)`

```swift
private func startRefreshing(store: UsageStore) {
    refreshTask = Task { [weak store] in
        await store?.refresh(force: true)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled else { break }
            await store?.refresh(force: true)
        }
    }
}
```

- 启动后立即强制刷新一次，避免界面长时间停留在空快照。
- 之后每 5 分钟刷新一次；`Task.sleep` 抛出取消错误时不会传播（`try?`）。
- 使用 `[weak store]` 避免循环引用；若 `AppDelegate` 被释放，store 与 refresh 任务可同时回收。

## 3. 资源装配图

```
        CodexStateApp (@main)
              │
              ▼
        AppDelegate.applicationDidFinishLaunching
              │
   ┌──────────┼──────────────┬──────────────┐
   ▼          ▼              ▼              ▼
CODEX_HOME  cacheURL   CodexRPCClient  ModelPriceCatalog.bundled()
   │          │              │              │
   ▼          ▼              ▼              ▼
SessionUsageRepository   UsageStore    NotchPanelController
                              ▲              │
                              │              ▼
                       refresh loop    GlobalHotKey (⌥⌘U)
```

## 4. 与其它模块的关系

- **不持有任何业务数据**：所有数据都从 `CodexStateCore` 装配。
- **不直接构造 SwiftUI 视图**：视图由 `NotchPanelController.makeHostingView()` 构造。
- **不进行计算**：包括聚合、价格估算、屏幕选择都委托给 Core。

## 5. 行为约定

- 应用必须运行在 `accessory` 模式，遵循 macOS 状态栏组件的"无 Dock 图标"行为。
- `applicationWillTerminate` 必须显式清理：任何后台 `Task` / Carbon 句柄泄漏都可能导致下次启动冲突。
- `panelController` 在显示前必须存在 `store`；两者生命周期一致。
