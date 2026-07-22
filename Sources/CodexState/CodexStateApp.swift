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
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var panelController: NotchPanelController?
    private var hotKey: GlobalHotKey?
    private var refreshTask: Task<Void, Never>?

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
            await store?.refresh(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { break }
                await store?.refresh(force: true)
            }
        }
    }
}
