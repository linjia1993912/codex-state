# 07 · 平台层

> 文件：
> - `Sources/CodexStateCore/Platform/NotchPanelController.swift`
> - `Sources/CodexStateCore/Platform/ScreenPlacement.swift`
> - `Sources/CodexStateCore/Platform/GlobalHotKey.swift`

平台层负责窗口、屏幕定位与全局快捷键。它在 `@MainActor` 下工作，向上提供 SwiftUI 内容；向下调用 AppKit 与 Carbon。

## 1. `NotchPresentation`

```swift
public enum NotchPresentation: Equatable, Sendable {
    case collapsed
    case peek
    case expanded
}
```

三态切换由 `NotchRootView` 通过 hover / 点击 / 快捷键 / 外部点击驱动；`NotchPanelController` 仅持有当前值。

## 2. `PeekMetric` 与 `NotchLayoutPolicy`

```swift
public struct PeekMetric: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case quota, todayTokens, todayCost }
    public let kind: Kind
    public let title: String
    public let value: String
    public let progress: Double?
    public var usesWarningTint: Bool
}
```

`NotchLayoutPolicy.metrics(snapshot:now:)` 根据 RPC 返回情况动态决定悬停面板展示的两项指标：

| 条件 | 指标 1 | 指标 2 |
| --- | --- | --- |
| 至少 2 个额度窗口 | 前两个窗口的"剩余" | — |
| 1 个窗口 | 窗口剩余 | 今日 Tokens |
| 0 个窗口 | 今日 Tokens | 今日估算成本 |

- `usesWarningTint` 在 `quota` 类型且 `progress <= 0.1` 时为 `true`，UI 把进度条染成橙色。
- `formatTokens` 在 `>= 1_000_000` 时格式化为 `X.XXM`。

## 3. `ScreenPlacement`

```swift
public enum ScreenPlacement {
    public static func panelOrigin(screenFrame: NSRect, panelSize: NSSize) -> NSPoint
}
```

按屏幕顶部居中放置：

```swift
NSPoint(x: screenFrame.midX - panelSize.width / 2, y: screenFrame.maxY - panelSize.height)
```

- 不写入刘海的左右安全区距离，让 `NSScreen.safeAreaInsets` 由 `NotchPanelController` 在选择屏幕时使用。
- 纯函数，方便在 `ScreenPlacementTests` 中验证。

## 4. `NotchPanelController`

```swift
@MainActor
public final class NotchPanelController: NSObject {
    public private(set) var presentation: NotchPresentation = .collapsed
    public init(store: UsageStore)
    public static func size(for presentation: NotchPresentation) -> CGSize
    public func show()
    public func toggleExpanded()
    public func stop()
}
```

### 4.1 窗口配置

- `NSPanel`：
  - `styleMask = [.borderless, .nonactivatingPanel, .fullSizeContentView]`
  - `isOpaque = false`，`backgroundColor = .clear`，`hasShadow = false`
  - `level = .statusBar`
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
- 内容视图为 `NSHostingView<NotchRootView>`，每次切换 `presentation` 重新创建以注入新 Binding。

### 4.2 尺寸

| 状态 | 宽 × 高 |
| --- | --- |
| `.collapsed` / `.peek` | 300 × 112 |
| `.expanded` | 368 × 430 |

### 4.3 `show()`

- `reposition(size:animated: false)` 计算屏幕位置。
- `panel.orderFrontRegardless()` 强制显示。

### 4.4 `toggleExpanded()`

- 在 `.expanded` ↔ `.collapsed` 之间切换。
- 通过 `GlobalHotKey`（`⌥⌘U`）触发。

### 4.5 `reposition(size:animated:)`

- `preferredScreen()`：优先选择 `safeAreaInsets.top > 0` 的屏幕（带刘海的 MacBook），否则回退到 `NSScreen.main` 或第一块屏幕。
- 动画：使用 `NSAnimationContext` + `CAMediaTimingFunction(name: .easeInEaseOut)`，时长 0.18 秒。
- 当 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == true` 时禁用尺寸动画。

### 4.6 屏幕变化

- 监听 `NSApplication.didChangeScreenParametersNotification`，重新定位到合适屏幕。
- 在 `deinit` 中移除观察者。

### 4.7 点击收起

仅在 `.expanded` 时安装本地 + 全局鼠标监听器：

- `globalClickMonitor` 监听其它应用内的点击。
- `localClickMonitor` 监听本应用内的点击并放行事件。
- 若点击位置在 `panel.frame` 之外 → `setPresentation(.collapsed)`。

### 4.8 `stop()`

由 `AppDelegate.applicationWillTerminate` 调用：移除监听器并 `orderOut(nil)`。

## 5. `GlobalHotKey`

```swift
@MainActor
public final class GlobalHotKey {
    public init(action: @escaping () -> Void) throws
    public static func registerIfAvailable(action:using:) -> GlobalHotKey?
    public func stop()
}
```

- 使用 Carbon HIToolbox 的 `InstallEventHandler` + `RegisterEventHotKey`。
- 快捷键：`⌥⌘U`（`kVK_ANSI_U` + `cmdKey | optionKey`）。
- 事件签名 `0x43535547`（"CSUG"）用于区分本应用快捷键。
- `registerIfAvailable(...)` 捕获注册异常并 `NSLog`，**不会**抛错 — 注册失败时面板与数据刷新仍可工作。
- `stop()` 注销 hot key 与 event handler。

## 6. 平台层依赖

```
NotchPanelController ─▶ NotchRootView (UI 层)
                     ─▶ ScreenPlacement
                     ─▶ NSWorkspace (减少动态效果)
                     ─▶ AppKit (NSPanel / NSScreen)

GlobalHotKey        ─▶ Carbon.HIToolbox
```

无第三方依赖，符合 `AGENTS.md` 中"仅使用 Swift 标准库 / Foundation / SwiftUI / AppKit / Carbon"约定。
