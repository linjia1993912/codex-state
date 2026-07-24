import AppKit
import QuartzCore
import SwiftUI

@MainActor
public final class NotchPanelController: NSObject {
    public let model: NotchViewModel

    /// 固定窗口尺寸（参考 codex-island：固定大窗口 + hitTest 控制点击穿透）。
    /// 不随状态变化，避免 NSWindow frame 动画与 SwiftUI 动画不同步。
    /// 宽度需容纳 peek 最宽情况（notch.width + 2*logoTabWidth + 2*pillSlotWidth）。
    public static let windowSize = CGSize(width: 500, height: 360)

    private let store: UsageStore
    private let panel: NSPanel
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    // 全局鼠标移动监听：用于检测光标进入/离开岛区域，驱动 ignoresMouseEvents。
    // 状态切换（collapsed↔peek）由 SwiftUI .onHover 处理。
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    // 10Hz 轮询定时器：collapsed 状态下 ignoresMouseEvents=true 时，
    // mouseMoved 事件穿透到下层应用，监听器收不到。轮询确保光标位置始终被检测。
    private var trackingTimer: Timer?
    // 启动冷却期标志：应用刚启动时光标可能在胶囊区域，避免立即展开 peek。
    // show() 后延迟启用 hover 检测，保证用户感知到 collapsed 默认状态。
    private var hoverDetectionEnabled = false
    // 持久持有 hosting view，避免状态切换时重建丢失 SwiftUI @State
    private var hostingView: NotchHostingView<NotchRootView>!

    public init(store: UsageStore) {
        self.store = store
        self.model = NotchViewModel(
            presentation: .collapsed,
            notchInfo: NotchInfo.detect(from: NotchPanelController.preferredScreen())
        )
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 默认让窗口点击穿透：只有光标进入岛的可视区域时才接收事件。
        panel.ignoresMouseEvents = true
        hostingView = makeHostingView()
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func show() {
        reposition(animated: false)
        panel.orderFrontRegardless()
        installMouseTracking()
        observePresentation()
        // 启动冷却期：1.5s 内不响应 hover，避免光标恰好在胶囊区域导致立即展开 peek
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.hoverDetectionEnabled = true
        }
    }

    public func toggleExpanded() {
        setPresentation(model.presentation == .expanded ? .collapsed : .expanded)
    }

    /// 状态栏左键点击：切换详情面板。
    public func showExpanded() {
        // 状态栏点击时光标不在面板内，updateMouseEventsBasedOnCursor 不会 makeKey，
        // 这里显式 makeKey 确保详情面板可交互。
        NSApp.activate(ignoringOtherApps: false)
        panel.makeKey()
        panel.orderFrontRegardless()
        setPresentation(model.presentation == .expanded ? .collapsed : .expanded)
    }

    public func stop() {
        removeClickMonitors()
        removeMouseMonitors()
        panel.orderOut(nil)
    }

    private func setPresentation(_ value: NotchPresentation) {
        guard model.presentation != value else { return }
        let anim = value == .collapsed ? Animation.islandClose : Animation.islandOpen
        withAnimation(anim) {
            model.presentation = value
        }
        updateMouseEvents()
        updateClickMonitors()
    }

    /// 观察 model.presentation 变化，统一同步鼠标事件与点击监听。
    /// 视图直接设置 model.presentation 时（onTapGesture / 关闭按钮），
    /// 控制器的 setPresentation 不会被调用，这里兜底确保监听器始终与状态同步。
    private func observePresentation() {
        withObservationTracking {
            _ = model.presentation
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateMouseEvents()
                self.updateClickMonitors()
                self.observePresentation()
            }
        }
    }

    /// 统一更新鼠标事件接收策略：
    /// - collapsed：光标在 hover 区内则接收事件并展开 peek，否则穿透
    /// - peek：始终接收事件（防止点击穿透）；光标离开 hover 区则收起
    /// - expanded：始终接收事件，保持面板交互
    private func updateMouseEvents() {
        switch model.presentation {
        case .collapsed:
            updateMouseEventsBasedOnCursor()
        case .peek:
            // peek 始终接收事件，防止点击穿透到下层应用
            panel.ignoresMouseEvents = false
            // 检测光标是否离开 hover 区 → 收起
            let cursor = NSEvent.mouseLocation
            let win = panel.frame
            let local = NSPoint(x: cursor.x - win.minX, y: cursor.y - win.minY)
            if !hoverDetectRect().contains(local) {
                setPresentation(.collapsed)
            }
        case .expanded:
            // expanded 始终接收事件，保持面板按钮可交互
            panel.ignoresMouseEvents = false
        }
    }

    /// 屏幕参数变化时重新检测刘海尺寸并更新视图。
    @objc private func screenParametersDidChange(_: Notification) {
        let newNotch = NotchInfo.detect(from: NotchPanelController.preferredScreen())
        guard newNotch != model.notchInfo else {
            reposition(animated: false)
            return
        }
        model.notchInfo = newNotch
        reposition(animated: false)
    }

    private func makeHostingView() -> NotchHostingView<NotchRootView> {
        let view = NotchHostingView(rootView: NotchRootView(store: store, model: model))
        // 可视矩形 = 当前状态的实际内容区域，用于 hitTest 精确控制点击穿透。
        view.visibleRectProvider = { [weak self] in
            guard let self else { return .zero }
            let bounds = self.hostingView.bounds
            let contentSize = IslandLayout(notch: self.model.notchInfo).size(for: self.model.presentation)
            // 内容在固定窗口内顶部居中对齐
            let contentX = (bounds.width - contentSize.width) / 2
            let contentY = bounds.height - contentSize.height
            return NSRect(
                x: max(contentX, 0),
                y: max(contentY, 0),
                width: contentSize.width,
                height: contentSize.height
            )
        }
        return view
    }

    private func reposition(animated: Bool) {
        guard let screen = Self.preferredScreen() else { return }
        let size = Self.windowSize
        let frame = NSRect(origin: ScreenPlacement.panelOrigin(screenFrame: screen.frame, panelSize: size), size: size)
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: - 鼠标追踪（参考 codex-island 的 IslandWindowController）

    /// 安装全局 + 本地 mouseMoved 监听 + 持续轮询。
    /// collapsed 状态下 ignoresMouseEvents=true，本地 mouseMoved 监听器收不到事件
    /// （事件穿透到下层窗口），全局监听器也可能不稳定。
    /// 因此保留 10Hz 轮询作为可靠的光标位置检测手段。
    private func installMouseTracking() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.updateMouseEvents() }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            handler(event)
            return event
        }
        // 持续 10Hz 轮询：collapsed 状态下 ignoresMouseEvents=true 时，
        // mouseMoved 事件穿透到下层应用，监听器收不到。轮询确保光标位置始终被检测。
        // 延迟 0.5s 启动避免应用刚启动时光标恰好在胶囊区域导致立即展开。
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMouseEvents() }
        }
        timer.fireDate = Date().addingTimeInterval(0.5)
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func removeMouseMonitors() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    /// 仅用于 collapsed 状态：根据光标位置决定是否接收事件。
    /// 光标在 hover 检测区内时接收事件并直接展开 peek（不依赖 SwiftUI .onHover，
    /// 因为 ignoresMouseEvents=true 时窗口不接收 tracking 事件，.onHover 不会触发）。
    private func updateMouseEventsBasedOnCursor() {
        // 启动冷却期内不响应 hover，保持 collapsed 默认状态
        guard hoverDetectionEnabled else { return }
        let cursor = NSEvent.mouseLocation
        let win = panel.frame
        let local = NSPoint(x: cursor.x - win.minX, y: cursor.y - win.minY)
        let visibleRect = hoverDetectRect()
        let inside = visibleRect.contains(local)

        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }

        if inside {
            NSApp.activate(ignoringOtherApps: false)
            panel.makeKey()
            if model.presentation == .collapsed {
                setPresentation(.peek)
            }
        } else {
            if model.presentation == .peek {
                setPresentation(.collapsed)
            }
        }
    }

    /// hover 检测矩形：使用当前状态的实际内容尺寸（参考 codex-island 的 updateMouseEventsBasedOnCursor）。
    /// collapsed 时检测区域 = compact 尺寸 + 极小余量（4pt），确保光标真正进入胶囊才触发 peek。
    /// peek 时检测区域 = peek 尺寸，光标离开 peek 范围才收起。
    private func hoverDetectRect() -> NSRect {
        let bounds = hostingView.bounds
        let contentSize = IslandLayout(notch: model.notchInfo).size(for: model.presentation)
        // 极小余量（4pt）避免像素级边界抖动
        let padding: CGFloat = 4
        return NSRect(
            x: (bounds.width - contentSize.width) / 2 - padding,
            y: bounds.height - contentSize.height - padding,
            width: contentSize.width + padding * 2,
            height: contentSize.height + padding * 2
        )
    }

    /// 当前状态的可视内容矩形（屏幕坐标），用于判断点击是否在面板外。
    private func contentRectInScreenCoordinates() -> NSRect {
        let contentSize = IslandLayout(notch: model.notchInfo).size(for: model.presentation)
        let win = panel.frame
        // 内容在窗口内顶部居中对齐
        let contentX = win.midX - contentSize.width / 2
        let contentY = win.maxY - contentSize.height
        return NSRect(x: contentX, y: contentY, width: contentSize.width, height: contentSize.height)
    }

    // MARK: - 点击监听（expanded 状态下点击外部收起）

    private func updateClickMonitors() {
        removeClickMonitors()
        guard model.presentation == .expanded else { return }
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            Task { @MainActor in self?.collapseIfClickIsOutside() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.collapseIfClickIsOutside()
            return event
        }
    }

    /// 点击在 expanded 内容区域外时收起面板。
    /// 注意：不能用 panel.frame 判断，因为固定窗口 500×360 比实际内容大，
    /// 点击窗口内但内容外的透明区域也应收起。
    private func collapseIfClickIsOutside() {
        guard model.presentation == .expanded else { return }
        let contentRect = contentRectInScreenCoordinates()
        if !contentRect.contains(NSEvent.mouseLocation) {
            setPresentation(.collapsed)
        }
    }

    private func removeClickMonitors() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        globalClickMonitor = nil
        localClickMonitor = nil
    }
}
