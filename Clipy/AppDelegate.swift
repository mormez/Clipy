import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?
    private var mainMenuHotkeyID: UInt32 = 0
    private var prefsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Warm up singletons
        _ = Preferences.shared
        _ = ClipboardHistory.shared
        _ = SnippetManager.shared

        menuBarManager = MenuBarManager()
        ClipboardMonitor.shared.start()
        registerHotkeys()

        prefsObserver = NotificationCenter.default.addObserver(
            forName: .preferencesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.registerHotkeys()
        }

        // Register with macOS so the app appears in System Settings → Accessibility.
        // The user grants permission once; macOS remembers it permanently.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    // Re-register whenever the app briefly activates (e.g. Preferences opens).
    // This is a safety net in case the hotkey was lost (e.g. recorder left open).
    func applicationDidBecomeActive(_ notification: Notification) {
        registerHotkeys()
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
        HotkeyManager.shared.unregisterAll()
        let p = Preferences.shared
        mainMenuHotkeyID = HotkeyManager.shared.register(
            keyCode: p.mainMenuKeyCode,
            modifiers: p.mainMenuModifiers
        ) {
            ClipboardPopupController.shared.toggle()
        }
    }
}
