import AppKit
import SwiftUI
import Observation

// MARK: - Folder group (computed once per show)

struct PopupFolder {
    let label: String        // e.g. "1 – 10"
    let items: [ClipItem]
    let startNumber: Int     // absolute number of first item (1, 11, 21 …)
}

// MARK: - State

@Observable
final class PopupState {
    var items: [ClipItem] = []
    var hoverEnabled = false

    // Flat-list mode (flatWhenFew with ≤10 items)
    var selectedIndex: Int = 0

    // Folder-navigation mode
    var selectedFolderIndex: Int = 0
    var expandedFolderIndex: Int? = nil   // nil = showing folder list
    var selectedItemIndex: Int = 0
}

// MARK: - Panel subclass (prevents beep on unhandled keys)

private final class ClipboardPanel: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if keyDownHandler?(event) != true { super.keyDown(with: event) }
    }
}

// MARK: - Controller

final class ClipboardPopupController {
    static let shared = ClipboardPopupController()

    private var panel: ClipboardPanel?
    private var keyMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?
    let state = PopupState()

    // Computed once per show() so keyboard handler can reference them
    private var currentFolders: [PopupFolder] = []
    private var currentFlatItems: [ClipItem] = []
    private var currentStyle: HistoryMenuStyle = .alwaysGrouped

    private init() {}

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        state.items = ClipboardHistory.shared.items
        state.hoverEnabled = false
        guard !state.items.isEmpty else { return }

        currentStyle = Preferences.shared.historyMenuStyle
        (currentFlatItems, currentFolders) = computeGroups(items: state.items, style: currentStyle)

        // Reset navigation
        state.selectedIndex = 0
        state.selectedFolderIndex = 0
        state.expandedFolderIndex = nil
        state.selectedItemIndex = 0

        buildPanel()
        sizePanel()
        positionPanel()

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel, queue: .main
        ) { [weak self] _ in self?.hide() }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }

        panel?.acceptsMouseMovedEvents = true
        mouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self else { return event }
            self.state.hoverEnabled = true
            NSEvent.removeMonitor(self.mouseMoveMonitor as Any)
            self.mouseMoveMonitor = nil
            return event
        }

        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        if let o = resignObserver { NotificationCenter.default.removeObserver(o); resignObserver = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = mouseMoveMonitor { NSEvent.removeMonitor(m); mouseMoveMonitor = nil }
        panel?.orderOut(nil)
    }

    // MARK: - Group computation

    private func computeGroups(items: [ClipItem], style: HistoryMenuStyle) -> ([ClipItem], [PopupFolder]) {
        let pageSize = 10
        func makeFolders(_ source: [ClipItem], offset: Int) -> [PopupFolder] {
            stride(from: 0, to: source.count, by: pageSize).enumerated().map { pi, start in
                let groupItems = Array(source[start ..< min(start + pageSize, source.count)])
                let absStart = offset + start + 1
                let absEnd   = offset + (pi + 1) * pageSize
                return PopupFolder(label: "\(absStart) – \(absEnd)", items: groupItems, startNumber: absStart)
            }
        }
        switch style {
        case .alwaysGrouped:
            return ([], makeFolders(items, offset: 0))
        case .hybridFirstFlat:
            let flat = Array(items.prefix(pageSize))
            let rest = Array(items.dropFirst(pageSize))
            return (flat, makeFolders(rest, offset: pageSize))
        case .flatWhenFew:
            if items.count <= pageSize { return (items, []) }
            return ([], makeFolders(items, offset: 0))
        }
    }

    // MARK: - Panel setup

    private func buildPanel() {
        if panel == nil {
            let p = ClipboardPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 100),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.standardWindowButton(.closeButton)?.isHidden = true
            p.standardWindowButton(.miniaturizeButton)?.isHidden = true
            p.standardWindowButton(.zoomButton)?.isHidden = true
            p.isFloatingPanel = true
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.keyDownHandler = { [weak self] event in
                guard let self else { return false }
                return self.handle(event) == nil
            }
            panel = p
        }
        panel?.contentView = NSHostingView(rootView: makeView())
    }

    private func makeView() -> ClipboardPopupView {
        ClipboardPopupView(
            state: state,
            style: currentStyle,
            flatItems: currentFlatItems,
            folders: currentFolders,
            onSelectItem: { [weak self] item in self?.paste(item) },
            onExpandFolder: { [weak self] idx in self?.expandFolder(idx) },
            onCollapseFolder: { [weak self] in self?.collapseFolder() },
            onDismiss: { [weak self] in self?.hide() }
        )
    }

    private func expandFolder(_ index: Int) {
        state.expandedFolderIndex = index
        state.selectedItemIndex = 0
        resizeAndRefresh()
    }

    private func collapseFolder() {
        state.expandedFolderIndex = nil
        state.selectedItemIndex = 0
        resizeAndRefresh()
    }

    private func resizeAndRefresh() {
        sizePanel()
        clampToScreen()
        panel?.contentView = NSHostingView(rootView: makeView())
    }

    /// After a resize keep the panel fully visible — move it up if the
    /// bottom edge went off screen.
    private func clampToScreen() {
        guard let panel, let screen = NSScreen.main else { return }
        let sf  = screen.visibleFrame
        let pf  = panel.frame
        var origin = pf.origin

        // Clamp bottom edge
        if origin.y < sf.minY + 8 {
            origin.y = sf.minY + 8
        }
        // Clamp top edge (in case the panel is now taller than the screen)
        if origin.y + pf.height > sf.maxY - 8 {
            origin.y = sf.maxY - pf.height - 8
        }

        if origin != pf.origin {
            panel.setFrameOrigin(origin)
        }
    }

    private func sizePanel() {
        let shadowPad: CGFloat = 16
        let headerH: CGFloat  = 50
        let folderRowH: CGFloat = 40
        let itemRowH: CGFloat   = 46
        let flatItemH: CGFloat  = 46
        let maxH: CGFloat = 520
        let w: CGFloat = 460

        var contentH = headerH
        if isFlatMode {
            contentH += flatItemH * CGFloat(currentFlatItems.count)
        } else if let fi = state.expandedFolderIndex, fi < currentFolders.count {
            // Showing items inside expanded folder
            contentH += folderRowH  // back row
            contentH += itemRowH * CGFloat(currentFolders[fi].items.count)
        } else {
            // Showing folder list + flat items above (hybrid)
            contentH += flatItemH * CGFloat(currentFlatItems.count)
            contentH += folderRowH * CGFloat(currentFolders.count)
        }
        let h = min(contentH + shadowPad * 2, maxH + shadowPad * 2)
        panel?.setContentSize(NSSize(width: w, height: h))
    }

    private var isFlatMode: Bool {
        currentStyle == .flatWhenFew && currentFlatItems.count > 0 && currentFolders.isEmpty
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        let sf = screen.visibleFrame
        let pf = panel.frame
        var x = mouse.x - pf.width / 2
        var y = mouse.y - pf.height - 8
        if y < sf.minY + 8 { y = mouse.y + 8 }
        x = max(sf.minX + 8, min(x, sf.maxX - pf.width - 8))
        y = max(sf.minY + 8, min(y, sf.maxY - pf.height - 8))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Keyboard

    private func handle(_ event: NSEvent) -> NSEvent? {
        if isFlatMode { return handleFlat(event) }
        if state.expandedFolderIndex != nil { return handleItemLevel(event) }
        return handleFolderLevel(event)
    }

    private func handleFlat(_ event: NSEvent) -> NSEvent? {
        let count = currentFlatItems.count
        switch event.keyCode {
        case 125: state.selectedIndex = min(state.selectedIndex + 1, count - 1); return nil
        case 126: state.selectedIndex = max(state.selectedIndex - 1, 0); return nil
        case 36, 76:
            guard state.selectedIndex < count else { return nil }
            paste(currentFlatItems[state.selectedIndex]); return nil
        case 53: hide(); return nil
        default:
            if let ch = event.characters, let d = Int(ch), (1...9).contains(d), d - 1 < count {
                paste(currentFlatItems[d - 1]); return nil
            }
            return event
        }
    }

    private func handleFolderLevel(_ event: NSEvent) -> NSEvent? {
        // How many "rows" are there? flat items (hybrid) + folders
        let flatCount   = currentFlatItems.count
        let folderCount = currentFolders.count
        let totalRows   = flatCount + folderCount   // flat items first, then folders

        switch event.keyCode {
        case 125: // ↓
            state.selectedFolderIndex = min(state.selectedFolderIndex + 1, totalRows - 1)
            return nil
        case 126: // ↑
            state.selectedFolderIndex = max(state.selectedFolderIndex - 1, 0)
            return nil
        case 124, 36, 76: // → or Enter: expand (only if on a folder row) or paste (flat row)
            let row = state.selectedFolderIndex
            if row < flatCount {
                // It's a flat item row — paste it
                paste(currentFlatItems[row])
            } else {
                // It's a folder row — expand
                expandFolder(row - flatCount)
            }
            return nil
        case 53: hide(); return nil
        default:
            // Number keys on flat items
            if let ch = event.characters, let d = Int(ch), (1...9).contains(d) {
                let idx = d - 1
                if idx < flatCount { paste(currentFlatItems[idx]); return nil }
            }
            return event
        }
    }

    private func handleItemLevel(_ event: NSEvent) -> NSEvent? {
        guard let fi = state.expandedFolderIndex, fi < currentFolders.count else { return event }
        let folderItems = currentFolders[fi].items
        switch event.keyCode {
        case 125: state.selectedItemIndex = min(state.selectedItemIndex + 1, folderItems.count - 1); return nil
        case 126: state.selectedItemIndex = max(state.selectedItemIndex - 1, 0); return nil
        case 123, 53: collapseFolder(); return nil  // ← or Escape: back to folders
        case 36, 76:
            guard state.selectedItemIndex < folderItems.count else { return nil }
            paste(folderItems[state.selectedItemIndex]); return nil
        default:
            if let ch = event.characters, let d = Int(ch), (1...9).contains(d), d - 1 < folderItems.count {
                paste(folderItems[d - 1]); return nil
            }
            return event
        }
    }

    // MARK: - Paste

    func paste(_ item: ClipItem) {
        let app = previousApp
        hide()
        ClipboardMonitor.shared.pause()
        PasteService.shared.setClipboard(item: item)

        var observer: NSObjectProtocol?
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard activated?.bundleIdentifier == app?.bundleIdentifier ||
                  activated?.processIdentifier == app?.processIdentifier else { return }
            NSWorkspace.shared.notificationCenter.removeObserver(observer!)
            observer = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { PasteService.shared.triggerPaste() }
        }
        app?.activate(options: .activateIgnoringOtherApps)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let o = observer {
                NSWorkspace.shared.notificationCenter.removeObserver(o)
                observer = nil
                PasteService.shared.triggerPaste()
            }
        }
    }
}

// MARK: - Views

struct ClipboardPopupView: View {
    var state: PopupState
    let style: HistoryMenuStyle
    let flatItems: [ClipItem]
    let folders: [PopupFolder]
    let onSelectItem: (ClipItem) -> Void
    let onExpandFolder: (Int) -> Void
    let onCollapseFolder: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 10)
        .padding(8)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if let img = NSImage(named: "MenuBarIcon") {
                Image(nsImage: img).resizable().scaledToFit().frame(width: 18, height: 18)
            }
            Text("Clipboard History").font(.system(size: 13, weight: .semibold))
            Spacer()
            if state.expandedFolderIndex != nil {
                Text("← back  ·  ↑↓ navigate  ·  ⏎ paste")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            } else {
                Text("↑↓ navigate  ·  → open  ·  ⎋ close")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: Content switcher

    @ViewBuilder
    private var content: some View {
        if let fi = state.expandedFolderIndex, fi < folders.count {
            // Level 2: items inside the selected folder
            itemsView(folder: folders[fi], folderIndex: fi)
        } else {
            // Level 1: flat items (hybrid) + folder list
            ScrollView {
                VStack(spacing: 0) {
                    flatSection
                    folderSection
                }
            }
        }
    }

    // MARK: Flat items (hybrid top section)

    @ViewBuilder
    private var flatSection: some View {
        if !flatItems.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(flatItems.enumerated()), id: \.element.id) { i, item in
                    let rowIndex = i
                    PopupItemRow(
                        item: item, number: i + 1,
                        isSelected: state.expandedFolderIndex == nil && state.selectedFolderIndex == rowIndex,
                        hoverEnabled: state.hoverEnabled,
                        onSelect: { onSelectItem(item) },
                        onHover: { if $0 { state.selectedFolderIndex = rowIndex } }
                    )
                    if i < flatItems.count - 1 || !folders.isEmpty {
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
    }

    // MARK: Folder list (level 1)

    @ViewBuilder
    private var folderSection: some View {
        if !folders.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(folders.enumerated()), id: \.offset) { fi, folder in
                    let rowIndex = flatItems.count + fi
                    PopupFolderRow(
                        label: folder.label,
                        count: folder.items.count,
                        isSelected: state.expandedFolderIndex == nil && state.selectedFolderIndex == rowIndex,
                        hoverEnabled: state.hoverEnabled,
                        onSelect: { onExpandFolder(fi) },
                        onHover: { if $0 { state.selectedFolderIndex = rowIndex } }
                    )
                    if fi < folders.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
    }

    // MARK: Items view (level 2)

    private func itemsView(folder: PopupFolder, folderIndex: Int) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Back row
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(folder.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { onCollapseFolder() }

                Divider()

                ForEach(Array(folder.items.enumerated()), id: \.element.id) { i, item in
                    PopupItemRow(
                        item: item,
                        number: folder.startNumber + i,
                        isSelected: state.selectedItemIndex == i,
                        hoverEnabled: state.hoverEnabled,
                        onSelect: { onSelectItem(item) },
                        onHover: { if $0 { state.selectedItemIndex = i } }
                    )
                    if i < folder.items.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
    }
}

// MARK: - Folder Row

struct PopupFolderRow: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let hoverEnabled: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(label)
                .font(.system(size: 13))

            Spacer()

            Text("\(count) items")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { if hoverEnabled { onHover($0) } }
        .animation(.easeInOut(duration: 0.08), value: isSelected)
    }
}

// MARK: - Item Row

struct PopupItemRow: View {
    let item: ClipItem
    let number: Int
    let isSelected: Bool
    let hoverEnabled: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 18, alignment: .trailing)

            typeIcon.frame(width: 22, height: 22)

            Text(item.displayTitle)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { if hoverEnabled { onHover($0) } }
        .animation(.easeInOut(duration: 0.08), value: isSelected)
    }

    @ViewBuilder private var typeIcon: some View {
        if item.type == .image, let img = item.thumbnailImage {
            Image(nsImage: img.scaled(to: NSSize(width: 22, height: 22)))
                .resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: iconName)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var iconName: String {
        switch item.type {
        case .string, .rtf, .html: return "doc.text"
        case .image:  return "photo"
        case .fileURL: return "folder"
        }
    }
}
