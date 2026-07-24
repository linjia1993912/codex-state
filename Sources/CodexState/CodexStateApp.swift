import AppKit
import CodexStateCore
import SwiftUI

@main
struct CodexStateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
private final class StatusBarController {
    private let statusItem: NSStatusItem
    private let togglePanel: () -> Void

    init(togglePanel: @escaping () -> Void) {
        self.togglePanel = togglePanel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setup()
    }

    private func setup() {
        guard let button = statusItem.button else { return }

        button.image = StatusBarIconRenderer.draw(size: NSSize(width: 18, height: 18))
        button.image?.isTemplate = true
        button.image?.size = NSSize(width: 18, height: 18)
        button.toolTip = "Codex State"

        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(handleClick(_:))
        button.target = self
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        switch event.type {
        case .rightMouseUp:
            showMenu()
        default:
            togglePanel()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        guard let button = statusItem.button else { return }
        let origin = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: button)
    }
}

/// 纯代码绘制状态栏狐狸图标（template image）：填充黑色剪影 + destinationOut 挖出眼睛/鼻子透明孔。
/// isTemplate=true 时 AppKit 只看 alpha 通道，挖出的孔在浅色/深色菜单栏都能正确显示面部特征。
private enum StatusBarIconRenderer {
    static func draw(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        // 缩放比例：设计稿基于 18×18
        let s = size.width / 18.0

        // 脸部轮廓：心形剪影
        let face = NSBezierPath()
        face.move(to: NSPoint(x: 9 * s, y: 4 * s))
        face.curve(
            to: NSPoint(x: 4 * s, y: 8 * s),
            controlPoint1: NSPoint(x: 6 * s, y: 4 * s),
            controlPoint2: NSPoint(x: 4 * s, y: 5.5 * s)
        )
        face.curve(
            to: NSPoint(x: 9 * s, y: 16 * s),
            controlPoint1: NSPoint(x: 4 * s, y: 12.5 * s),
            controlPoint2: NSPoint(x: 6 * s, y: 16 * s)
        )
        face.curve(
            to: NSPoint(x: 14 * s, y: 8 * s),
            controlPoint1: NSPoint(x: 12 * s, y: 16 * s),
            controlPoint2: NSPoint(x: 14 * s, y: 12.5 * s)
        )
        face.curve(
            to: NSPoint(x: 9 * s, y: 4 * s),
            controlPoint1: NSPoint(x: 14 * s, y: 5.5 * s),
            controlPoint2: NSPoint(x: 12 * s, y: 4 * s)
        )
        face.close()

        // 左耳
        let leftEar = NSBezierPath()
        leftEar.move(to: NSPoint(x: 4 * s, y: 7 * s))
        leftEar.line(to: NSPoint(x: 2.5 * s, y: 1 * s))
        leftEar.line(to: NSPoint(x: 6.5 * s, y: 5 * s))
        leftEar.close()

        // 右耳
        let rightEar = NSBezierPath()
        rightEar.move(to: NSPoint(x: 14 * s, y: 7 * s))
        rightEar.line(to: NSPoint(x: 15.5 * s, y: 1 * s))
        rightEar.line(to: NSPoint(x: 11.5 * s, y: 5 * s))
        rightEar.close()

        // 填充剪影（颜色无所谓，template 只看 alpha）
        NSColor.black.setFill()
        face.fill()
        leftEar.fill()
        rightEar.fill()

        // 用 destinationOut 合成模式挖出眼睛和鼻子的透明孔
        let ctx = NSGraphicsContext.current
        let prevOp = ctx?.compositingOperation ?? .sourceOver
        ctx?.compositingOperation = .destinationOut

        let leftEye = NSBezierPath(ovalIn: NSRect(x: 6.3 * s, y: 7.3 * s, width: 2.4 * s, height: 3.0 * s))
        leftEye.fill()
        let rightEye = NSBezierPath(ovalIn: NSRect(x: 9.3 * s, y: 7.3 * s, width: 2.4 * s, height: 3.0 * s))
        rightEye.fill()
        let nose = NSBezierPath(ovalIn: NSRect(x: 8.0 * s, y: 10.5 * s, width: 2.0 * s, height: 1.4 * s))
        nose.fill()

        ctx?.compositingOperation = prevOp

        return image
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var panelController: NotchPanelController?
    private var hotKey: GlobalHotKey?
    private var refreshTask: Task<Void, Never>?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
            let cacheURL = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("CodexState/usage-cache.json")
            let repository = SessionUsageRepository(cacheURL: cacheURL)
            let rpcClient = CodexRPCClient()
            let store = UsageStore(
                remoteLoader: rpcClient.read,
                sessionLoader: { try repository.load(home: codexHome, calendar: .current) },
                catalog: try ModelPriceCatalog.bundled()
            )
            let panelController = NotchPanelController(store: store)

            self.store = store
            self.panelController = panelController
            hotKey = GlobalHotKey.registerIfAvailable { [weak panelController] in panelController?.toggleExpanded() }
            panelController.show()
            statusBarController = StatusBarController { [weak panelController] in
                panelController?.showExpanded()
            }
            startRefreshing(store: store)
        } catch {
            NSApp.presentError(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 显式取消可避免五分钟睡眠任务在应用生命周期外继续持有状态。
        refreshTask?.cancel()
        hotKey?.stop()
        panelController?.stop()
    }

    private func startRefreshing(store: UsageStore) {
        refreshTask = Task { [weak store] in
            // 首次加载失败时短间隔重试：codex app-server 冷启动偶发超过 initialize 超时，
            // 若不重试则用户需手动退出重开才能看到数据。成功后转入正常 5 分钟节律。
            while !Task.isCancelled {
                await store?.refresh(force: true)
                if let snapshot = store?.snapshot, !snapshot.isStale { break }
                try? await Task.sleep(for: .seconds(10))
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { break }
                await store?.refresh(force: true)
            }
        }
    }
}
