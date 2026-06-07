import AppKit

final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem!
    private var historyObserver: NSObjectProtocol?
    private var snippetsObserver: NSObjectProtocol?

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            if let icon = NSImage(named: "MenuBarIcon") {
                icon.size = NSSize(width: 18, height: 18)
                btn.image = icon
            } else {
                // Fallback if asset not found
                btn.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Modern Clipboard")
                btn.image?.isTemplate = true
            }
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
        } else {
            switch Preferences.shared.historyMenuStyle {

            case .flatWhenFew where items.count <= 10:
                // Flat: all items directly in the menu
                for (i, item) in items.enumerated() {
                    let number = i + 1
                    menu.addItem(makeHistoryItem(item: item, number: number, shortcut: i < 9 ? "\(number)" : "0"))
                }

            case .hybridFirstFlat:
                // First 10 flat, remaining in 11-20, 21-30… subfolders
                for (i, item) in items.prefix(10).enumerated() {
                    let number = i + 1
                    menu.addItem(makeHistoryItem(item: item, number: number, shortcut: i < 9 ? "\(number)" : "0"))
                }
                if items.count > 10 {
                    let rest = Array(items.dropFirst(10))
                    addPagedSubmenus(rest, startingAt: 11, to: menu)
                }

            default:
                // Always grouped: "1 – 10", "11 – 20", etc.
                addPagedSubmenus(items, startingAt: 1, to: menu)
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
        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let snippetsEditor = NSMenuItem(title: "Edit Snippets…", action: #selector(openSnippetsEditor), keyEquivalent: "")
        snippetsEditor.target = self
        menu.addItem(snippetsEditor)

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit Modern Clipboard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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

    /// Adds paged subfolders ("startingAt – startingAt+9", etc.) to `menu`.
    private func addPagedSubmenus(_ items: [ClipItem], startingAt first: Int, to menu: NSMenu) {
        let pageSize = 10
        let pages = stride(from: 0, to: items.count, by: pageSize).map {
            Array(items[$0 ..< min($0 + pageSize, items.count)])
        }
        for (pageIndex, page) in pages.enumerated() {
            let start = first + pageIndex * pageSize
            let end   = first + (pageIndex + 1) * pageSize - 1
            let folder = NSMenuItem(title: "  \(start) – \(end)", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (i, item) in page.enumerated() {
                let number = start + i
                let key    = i < 9 ? "\(i + 1)" : "0"
                sub.addItem(makeHistoryItem(item: item, number: number, shortcut: key))
            }
            folder.submenu = sub
            menu.addItem(folder)
        }
    }

    private func makeHistoryItem(item: ClipItem, number: Int, shortcut: String) -> NSMenuItem {
        let mi = NSMenuItem(
            title: "  \(number).  \(item.displayTitle)",
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

    @objc private func checkForUpdates() {
        UpdaterManager.shared.checkForUpdates()
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
