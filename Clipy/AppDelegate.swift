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

    // Check silently — no blocking popup. Show a warning item in the menu instead,
    // which disappears automatically once the user grants permission.
    private func startAccessibilityCheck() {
        checkAccessibility()
        // Poll every 5 s so the warning clears as soon as the user grants permission
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
