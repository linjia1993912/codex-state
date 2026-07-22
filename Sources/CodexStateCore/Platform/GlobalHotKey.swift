import Carbon.HIToolbox
import Foundation

@MainActor
public final class GlobalHotKey {
    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    public init(action: @escaping () -> Void) throws {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, pointer in
                guard let pointer else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(pointer).takeUnretainedValue()
                Task { @MainActor in hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_U),
            UInt32(cmdKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registerStatus == noErr else {
            RemoveEventHandler(eventHandler)
            eventHandler = nil
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(registerStatus))
        }
    }

    public static func registerIfAvailable(
        action: @escaping () -> Void,
        using register: @MainActor (@escaping () -> Void) throws -> GlobalHotKey = GlobalHotKey.init(action:)
    ) -> GlobalHotKey? {
        do {
            return try register(action)
        } catch {
            // 快捷键可能被其他应用占用；面板和数据刷新不应因此停止。
            NSLog("CodexState：全局快捷键注册失败：%@", error.localizedDescription)
            return nil
        }
    }

    public func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
    }

    private static let signature: OSType = 0x43535547 // “CSUG” 仅用于区分本应用快捷键。
}
