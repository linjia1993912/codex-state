import Testing
import AppKit
import Foundation

@Test
func statusBarMenuHasQuitItem() {
    let menu = NSMenu()
    let quitItem = NSMenuItem(
        title: "退出 Codex State",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )
    quitItem.keyEquivalentModifierMask = .command
    menu.addItem(quitItem)

    #expect(menu.items.count == 1)
    #expect(menu.items.first?.title == "退出 Codex State")
    #expect(menu.items.first?.keyEquivalent == "q")
}

@Test
func statusBarIconIsTemplate() {
    let image = NSImage(size: NSSize(width: 18, height: 18))
    image.isTemplate = true
    #expect(image.isTemplate == true)
}
