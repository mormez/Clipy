import AppKit

final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem!
    private var historyObserver: NSObjectProtocol?
    private var snippetsObserver: NSObjectProtocol?

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Modern Clipy")
            btn.image?.isTemplate = true
        }
        buildMenu()

        historyObserver = NotificationCenter.default.addObserver(
            forName: .clipboardHistoryChanged, object: nil, queue: .main) { [weak self] _ in
            self?.buildMenu()
        }
        snippetsObserver = NotificationCenter.default.addObserver(
            forName: .snippetsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.buildMenu()
        }
    }

    func showMenu() {
        statusItem.button?.performClick(nil)
    }

    func buildMenu() {
        let menu = NSMenu()

        // --- History ---
        addHeader("Clipboard History", to: menu)
        let items = ClipboardHistory.shared.items
        if items.isEmpty {
            let e = NSMenuItem(title: "  (empty)", action: nil, keyEquivalent: "")
            e.isEnabled = false
            menu.addItem(e)
        } else if items.count <= 10 {
            // 10 or fewer — show inline with number shortcuts
            for (i, item) in items.enumerated() {
                menu.addItem(makeHistoryItem(item: item, shortcut: "\(i + 1)"))
            }
        } else {
            // Group into submenus of 10: "1 – 10", "11 – 20", etc.
            let pageSize = 10
            let pages = stride(from: 0, to: items.count, by: pageSize).map {
                Array(items[$0 ..< min($0 + pageSize, items.count)])
            }
            for (pageIndex, page) in pages.enumerated() {
                let start = pageIndex * pageSize + 1
                let end   = start + page.count - 1
                let folder = NSMenuItem(title: "  \(start) – \(end)", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                for (i, item) in page.enumerated() {
                    // Keep 1-9, use 0 for the 10th item
                    let key = i < 9 ? "\(i + 1)" : "0"
                    sub.addItem(makeHistoryItem(item: item, shortcut: key))
                }
                folder.submenu = sub
                menu.addItem(folder)
            }
        }

        menu.addItem(.separator())

        // --- Snippets ---
        let folders = SnippetManager.shared.folders
        if !folders.isEmpty {
            addHeader("Snippets", to: menu)
            for folder in folders {
                let folderItem = NSMenuItem(title: "  \(folder.name)", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                for snippet in folder.snippets {
                    let si = NSMenuItem(title: snippet.title, action: #selector(pasteSnippet(_:)), keyEquivalent: "")
                    si.representedObject = snippet
                    si.target = self
                    sub.addItem(si)
                }
                if sub.items.isEmpty {
                    let empty = NSMenuItem(title: "(no snippets)", action: nil, keyEquivalent: "")
                    empty.isEnabled = false
                    sub.addItem(empty)
                }
                folderItem.submenu = sub
                menu.addItem(folderItem)
            }
            menu.addItem(.separator())
        }

        // --- Actions ---
        let diagItem = NSMenuItem(title: "🔍 Test Accessibility…", action: #selector(testAccessibility), keyEquivalent: "")
        diagItem.target = self
        menu.addItem(diagItem)

        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let snippetsEditor = NSMenuItem(title: "Edit Snippets…", action: #selector(openSnippetsEditor), keyEquivalent: "")
        snippetsEditor.target = self
        menu.addItem(snippetsEditor)

        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit Modern Clipy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func addHeader(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        item.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        menu.addItem(item)
    }

    @objc private func pasteHistoryItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipItem else { return }
        PasteService.shared.paste(item: item)
    }

    @objc private func pasteSnippet(_ sender: NSMenuItem) {
        guard let snippet = sender.representedObject as? Snippet else { return }
        PasteService.shared.pasteString(snippet.content)
    }

    @objc private func testAccessibility() {
        let trusted = AXIsProcessTrustedWithOptions(nil)
        let alert = NSAlert()
        alert.messageText = trusted ? "✅ Accessibility Granted" : "❌ Accessibility NOT Granted"
        alert.informativeText = trusted
            ? "Accessibility is working. If paste still fails, try clicking a history item now."
            : "Accessibility permission is not granted to this build of ModernClipy.\n\nGo to System Settings → Privacy & Security → Accessibility, remove ModernClipy if present, then relaunch the app and grant permission again."
        alert.addButton(withTitle: "OK")
        if !trusted {
            alert.addButton(withTitle: "Open System Settings")
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    private func makeHistoryItem(item: ClipItem, shortcut: String) -> NSMenuItem {
        let mi = NSMenuItem(
            title: "  \(item.displayTitle)",
            action: #selector(pasteHistoryItem(_:)),
            keyEquivalent: shortcut
        )
        mi.keyEquivalentModifierMask = []
        mi.representedObject = item
        mi.target = self
        if item.type == .image, let img = item.thumbnailImage {
            mi.image = img.scaled(to: NSSize(width: 24, height: 24))
        }
        return mi
    }

    @objc private func clearHistory() {
        ClipboardHistory.shared.clear()
    }

    @objc private func openSnippetsEditor() {
        SnippetsEditorWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
