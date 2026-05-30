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

        promptAccessibilityIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
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

    private func promptAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !trusted {
            showAccessibilityAlert()
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Clipy needs Accessibility permission to paste items to other apps. Please grant it in System Settings → Privacy & Security → Accessibility, then relaunch Clipy."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
