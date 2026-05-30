import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?
    private var mainMenuHotkeyID: UInt32 = 0
    private var prefsObserver: NSObjectProtocol?
    private var accessibilityTimer: Timer?

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

        startAccessibilityCheck()
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityTimer?.invalidate()
        ClipboardMonitor.shared.stop()
        HotkeyManager.shared.unregisterAll()
    }

    private func registerHotkeys() {
        HotkeyManager.shared.unregisterAll()
        let p = Preferences.shared
        mainMenuHotkeyID = HotkeyManager.shared.register(
            keyCode: p.mainMenuKeyCode,
            modifiers: p.mainMenuModifiers
        ) { [weak self] in
            self?.menuBarManager?.showMenu()
        }
    }

    // First call uses the prompt flag so macOS registers the app in the
    // Accessibility list. Subsequent polls are silent — no dialogs.
    private func startAccessibilityCheck() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        menuBarManager?.setAccessibilityWarning(!trusted)

        // Poll every 5 s so the warning clears the moment permission is granted
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkAccessibility()
        }
    }

    private func checkAccessibility() {
        let trusted = AXIsProcessTrustedWithOptions(nil)
        menuBarManager?.setAccessibilityWarning(!trusted)
    }

    // Called from the menu when the user clicks the warning item
    func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }
}
