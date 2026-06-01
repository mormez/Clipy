import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?
    private var prefsObserver: NSObjectProtocol?
    private var hotkeyObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        _ = Preferences.shared
        _ = ClipboardHistory.shared
        _ = SnippetManager.shared

        menuBarManager = MenuBarManager()
        ClipboardMonitor.shared.start()
        registerHotkeys()

        // Rebuild menus when non-hotkey preferences change
        prefsObserver = NotificationCenter.default.addObserver(
            forName: .preferencesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.menuBarManager?.buildMenu()
        }

        // Re-register hotkey ONLY when the hotkey preferences change
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyChanged, object: nil, queue: .main) { [weak self] _ in
            self?.registerHotkeys()
        }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stop()
        HotkeyManager.shared.unregisterAll()
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    private func registerHotkeys() {
        let p = Preferences.shared
        HotkeyManager.shared.register(
            keyCode: p.mainMenuKeyCode,
            modifiers: p.mainMenuModifiers
        ) {
            ClipboardPopupController.shared.toggle()
        }
    }
}
