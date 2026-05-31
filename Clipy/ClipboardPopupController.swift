import AppKit
import SwiftUI
import Observation

// MARK: - Data types

struct PopupFolder {
    let label: String
    let items: [ClipItem]
    let startNumber: Int
}

enum ExpandedPane: Equatable {
    case clipboard(folderIndex: Int)
    case snippet(folderIndex: Int)
}

// MARK: - State

@Observable
final class PopupState {
    var items: [ClipItem] = []
    var hoverEnabled = false
    var selectedRowIndex: Int = 0     // across all rows in the folder panel
    var expandedPane: ExpandedPane? = nil
    var selectedItemIndex: Int = 0
}

// MARK: - Panel subclass

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
    private var itemPanel: NSPanel?
    private var keyMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?
    let state = PopupState()

    private var currentFolders: [PopupFolder] = []
    private var currentFlatItems: [ClipItem] = []
    private var currentStyle: HistoryMenuStyle = .alwaysGrouped

    private let folderColW: CGFloat     = 200
    private var itemColW: CGFloat       { CGFloat(Preferences.shared.itemsPanelWidth) }
    private let headerH: CGFloat        = 50
    private let folderRowH: CGFloat     = 40
    private let sectionHeaderH: CGFloat = 28
    private let bottomMargin: CGFloat   = 12
    private let maxH: CGFloat           = 600
    // Row height scales with preview lines: 24px base + 20px per line
    private var itemRowH: CGFloat       { CGFloat(24 + 20 * Preferences.shared.previewLines) }

    // Computed row layout — kept in sync with the folder panel view
    private var flatCount: Int     { currentFlatItems.count }
    private var clipCount: Int     { currentFolders.count }
    private var snippetFolders: [SnippetFolder] { SnippetManager.shared.folders }
    private var snippetCount: Int  { snippetFolders.count }
    private var totalRows: Int     { flatCount + clipCount + snippetCount }

    private func rowKind(_ row: Int) -> RowKind {
        if row < flatCount                        { return .flatItem(row) }
        if row < flatCount + clipCount            { return .clipFolder(row - flatCount) }
        return .snippetFolder(row - flatCount - clipCount)
    }

    private enum RowKind {
        case flatItem(Int)
        case clipFolder(Int)
        case snippetFolder(Int)
    }

    private init() {}

    func toggle() { if panel?.isVisible == true { hide() } else { show() } }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        state.items = ClipboardHistory.shared.items
        state.hoverEnabled = false
        guard !state.items.isEmpty else { return }

        currentStyle = Preferences.shared.historyMenuStyle
        (currentFlatItems, currentFolders) = computeGroups(items: state.items, style: currentStyle)

        state.selectedRowIndex = 0
        state.expandedPane     = nil
        state.selectedItemIndex = 0

        buildFolderPanel()
        sizeFolderPanel()
        positionFolderPanel()

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
        hideItemPanel()
        panel?.orderOut(nil)
    }

    // MARK: - Group computation

    private func computeGroups(items: [ClipItem], style: HistoryMenuStyle) -> ([ClipItem], [PopupFolder]) {
        let ps = 10
        func makeFolders(_ src: [ClipItem], offset: Int) -> [PopupFolder] {
            stride(from: 0, to: src.count, by: ps).enumerated().map { pi, start in
                let gi = Array(src[start ..< min(start + ps, src.count)])
                return PopupFolder(label: "\(offset + start + 1) – \(offset + (pi + 1) * ps)",
                                   items: gi, startNumber: offset + start + 1)
            }
        }
        switch style {
        case .alwaysGrouped:
            return ([], makeFolders(items, offset: 0))
        case .hybridFirstFlat:
            return (Array(items.prefix(ps)), makeFolders(Array(items.dropFirst(ps)), offset: ps))
        case .flatWhenFew:
            return items.count <= ps ? (items, []) : ([], makeFolders(items, offset: 0))
        }
    }

    // MARK: - Folder panel

    private func buildFolderPanel() {
        if panel == nil {
            let p = ClipboardPanel(
                contentRect: NSRect(x: 0, y: 0, width: folderColW, height: 100),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            p.isFloatingPanel = true; p.level = .floating
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.keyDownHandler = { [weak self] event in
                guard let self else { return false }
                return self.handle(event) == nil
            }
            panel = p
        }
        installFolderHostingView()
    }

    private func installFolderHostingView() {
        let fh = NSHostingView(rootView: makeFolderView())
        fh.sizingOptions = []
        fh.autoresizingMask = [.width, .height]
        panel?.contentView = fh
    }

    private func makeFolderView() -> FolderPanelView {
        FolderPanelView(
            state: state,
            style: currentStyle,
            flatItems: currentFlatItems,
            clipFolders: currentFolders,
            snippetFolders: snippetFolders,
            onSelectFlatItem: { [weak self] item in self?.pasteItem(item) },
            onSelectClipFolder: { [weak self] fi in self?.openClipFolder(fi) },
            onSelectSnippetFolder: { [weak self] si in self?.openSnippetFolder(si) }
        )
    }

    private func sizeFolderPanel() {
        var h: CGFloat = headerH
        h += CGFloat(flatCount)  * itemRowH
        h += CGFloat(clipCount)  * folderRowH
        if snippetCount > 0 {
            h += sectionHeaderH  // "Snippets" label
            h += CGFloat(snippetCount) * folderRowH
        }
        h += bottomMargin
        panel?.setContentSize(NSSize(width: folderColW, height: min(h, maxH)))
    }

    private func positionFolderPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let pf = panel.frame
        var x = NSEvent.mouseLocation.x - pf.width / 2
        var y = NSEvent.mouseLocation.y - pf.height - 8
        if y < sf.minY + 8 { y = NSEvent.mouseLocation.y + 8 }
        x = max(sf.minX + 8, min(x, sf.maxX - pf.width - 8))
        y = max(sf.minY + 8, min(y, sf.maxY - pf.height - 8))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func refreshFolderPanel() {
        installFolderHostingView()
    }

    // MARK: - Items panel (shared for clipboard items and snippets)

    private func openClipFolder(_ fi: Int) {
        guard fi < currentFolders.count else { return }
        state.expandedPane     = .clipboard(folderIndex: fi)
        state.selectedItemIndex = 0
        let folder = currentFolders[fi]
        showItemPanel(
            title: folder.label,
            count: folder.items.count,
            builder: {
                ItemsPanelView(
                    state: self.state,
                    panelWidth: self.itemColW,
                    previewLines: Preferences.shared.previewLines,
                    title: folder.label,
                    rows: folder.items.enumerated().map { i, item in
                        ItemRow(number: folder.startNumber + i, title: item.displayTitle,
                                icon: item.type == .fileURL ? "folder" : "doc.text",
                                thumbnailImage: item.thumbnailImage)
                    },
                    onSelectRow: { [weak self] i in
                        if i < folder.items.count { self?.pasteItem(folder.items[i]) }
                    }
                )
            }
        )
        refreshFolderPanel()
    }

    private func openSnippetFolder(_ si: Int) {
        guard si < snippetFolders.count else { return }
        state.expandedPane     = .snippet(folderIndex: si)
        state.selectedItemIndex = 0
        let folder = snippetFolders[si]
        showItemPanel(
            title: folder.name,
            count: folder.snippets.count,
            builder: {
                ItemsPanelView(
                    state: self.state,
                    panelWidth: self.itemColW,
                    previewLines: Preferences.shared.previewLines,
                    title: folder.name,
                    rows: folder.snippets.enumerated().map { i, snippet in
                        ItemRow(number: i + 1, title: snippet.title,
                                icon: "text.quote", thumbnailImage: nil)
                    },
                    onSelectRow: { [weak self] i in
                        if i < folder.snippets.count { self?.pasteSnippet(folder.snippets[i]) }
                    }
                )
            }
        )
        refreshFolderPanel()
    }

    private func closePane() {
        state.expandedPane = nil
        hideItemPanel()
        refreshFolderPanel()
    }

    private func showItemPanel(title: String, count: Int, builder: () -> ItemsPanelView) {
        if itemPanel == nil {
            let p = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isFloatingPanel = true; p.level = .floating
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            itemPanel = p
        }
        let h = min(headerH + CGFloat(count) * itemRowH + bottomMargin, maxH)
        // Size the panel FIRST so that when we assign contentView macOS
        // automatically fills the hosting view to the correct bounds,
        // giving SwiftUI the right proposed width.
        itemPanel?.setContentSize(NSSize(width: itemColW, height: h))
        let hosting = NSHostingView(rootView: builder())
        hosting.sizingOptions = []          // let the panel own the frame
        hosting.autoresizingMask = [.width, .height]
        itemPanel?.contentView = hosting    // macOS fills it to panel bounds
        positionItemPanel()
        itemPanel?.orderFront(nil)
    }

    private func positionItemPanel() {
        guard let panel, let itemPanel, let screen = NSScreen.main else { return }
        let sf  = screen.visibleFrame
        let pf  = panel.frame
        let ipf = itemPanel.frame

        // Align items panel top with the selected row's top edge
        let rowTop = rowTopScreenY(for: state.selectedRowIndex)
        var y = rowTop - ipf.height   // origin.y so that frame.maxY == rowTop

        var x = pf.maxX
        if x + ipf.width > sf.maxX - 8 { x = pf.minX - ipf.width }

        y = max(sf.minY + 8, min(y, sf.maxY - ipf.height - 8))
        x = max(sf.minX + 8, x)
        itemPanel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Screen Y of the top edge of `rowIndex` inside the folder panel.
    private func rowTopScreenY(for rowIndex: Int) -> CGFloat {
        guard let panel else { return 0 }
        let flatN = currentFlatItems.count
        let clipN = currentFolders.count

        // Accumulate visual distance from the panel's top down to the row's top
        var offset: CGFloat = headerH + 1   // header height + divider

        if rowIndex < flatN {
            offset += CGFloat(rowIndex) * (itemRowH + 1)
        } else if rowIndex < flatN + clipN {
            offset += CGFloat(flatN) * (itemRowH + 1)
            offset += CGFloat(rowIndex - flatN) * (folderRowH + 1)
        } else {
            offset += CGFloat(flatN) * (itemRowH + 1)
            offset += CGFloat(clipN) * (folderRowH + 1)
            if !snippetFolders.isEmpty { offset += 1 + sectionHeaderH + 1 }
            offset += CGFloat(rowIndex - flatN - clipN) * (folderRowH + 1)
        }

        // panel.frame.maxY is the panel's top in screen coords (Y increases upward)
        return panel.frame.maxY - offset
    }

    private func hideItemPanel() { itemPanel?.orderOut(nil) }

    // MARK: - Paste

    private func pasteItem(_ item: ClipItem) {
        let app = previousApp
        hide()
        ClipboardMonitor.shared.pause()
        PasteService.shared.setClipboard(item: item)
        activateThenPaste(app)
    }

    private func pasteSnippet(_ snippet: Snippet) {
        let app = previousApp
        hide()
        ClipboardMonitor.shared.pause()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet.content, forType: .string)
        activateThenPaste(app)
    }

    private func activateThenPaste(_ app: NSRunningApplication?) {
        var observer: NSObjectProtocol?
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { note in
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

    // MARK: - Keyboard

    private var isFlatMode: Bool {
        currentStyle == .flatWhenFew && !currentFlatItems.isEmpty && currentFolders.isEmpty
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if isFlatMode               { return handleFlat(event) }
        if state.expandedPane != nil { return handleItemLevel(event) }
        return handleFolderLevel(event)
    }

    private func handleFlat(_ event: NSEvent) -> NSEvent? {
        let n = currentFlatItems.count
        switch event.keyCode {
        case 125: state.selectedRowIndex = min(state.selectedRowIndex + 1, n - 1); return nil
        case 126: state.selectedRowIndex = max(state.selectedRowIndex - 1, 0);     return nil
        case 36, 76:
            if state.selectedRowIndex < n { pasteItem(currentFlatItems[state.selectedRowIndex]) }
            return nil
        case 53: hide(); return nil
        default:
            if let ch = event.characters, let d = Int(ch), (1...9).contains(d), d-1 < n {
                pasteItem(currentFlatItems[d-1]); return nil
            }
            return event
        }
    }

    private func handleFolderLevel(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 125:
            state.selectedRowIndex = min(state.selectedRowIndex + 1, totalRows - 1); return nil
        case 126:
            state.selectedRowIndex = max(state.selectedRowIndex - 1, 0);             return nil
        case 124, 36, 76:   // → or Enter
            switch rowKind(state.selectedRowIndex) {
            case .flatItem(let i):       pasteItem(currentFlatItems[i])
            case .clipFolder(let fi):    openClipFolder(fi)
            case .snippetFolder(let si): openSnippetFolder(si)
            }
            return nil
        case 53: hide(); return nil
        default:
            if let ch = event.characters, let d = Int(ch), (1...9).contains(d) {
                let fi = d - 1
                if fi < flatCount { pasteItem(currentFlatItems[fi]); return nil }
            }
            return event
        }
    }

    private func handleItemLevel(_ event: NSEvent) -> NSEvent? {
        let itemCount: Int = {
            switch state.expandedPane {
            case .clipboard(let fi): return fi < currentFolders.count ? currentFolders[fi].items.count : 0
            case .snippet(let si):   return si < snippetFolders.count ? snippetFolders[si].snippets.count : 0
            case nil: return 0
            }
        }()

        switch event.keyCode {
        case 125: state.selectedItemIndex = min(state.selectedItemIndex + 1, itemCount - 1); return nil
        case 126: state.selectedItemIndex = max(state.selectedItemIndex - 1, 0);             return nil
        case 123, 53: closePane(); return nil   // ← or Esc
        case 36, 76:
            guard state.selectedItemIndex < itemCount else { return nil }
            switch state.expandedPane {
            case .clipboard(let fi):
                pasteItem(currentFolders[fi].items[state.selectedItemIndex])
            case .snippet(let si):
                pasteSnippet(snippetFolders[si].snippets[state.selectedItemIndex])
            case nil: break
            }
            return nil
        default:
            if let ch = event.characters, let d = Int(ch), (1...9).contains(d), d-1 < itemCount {
                let i = d - 1
                switch state.expandedPane {
                case .clipboard(let fi): pasteItem(currentFolders[fi].items[i])
                case .snippet(let si):   pasteSnippet(snippetFolders[si].snippets[i])
                case nil: break
                }
                return nil
            }
            return event
        }
    }
}

// MARK: - Folder panel view

struct FolderPanelView: View {
    var state: PopupState
    let style: HistoryMenuStyle
    let flatItems: [ClipItem]
    let clipFolders: [PopupFolder]
    let snippetFolders: [SnippetFolder]
    let onSelectFlatItem: (ClipItem) -> Void
    let onSelectClipFolder: (Int) -> Void
    let onSelectSnippetFolder: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──
            HStack(spacing: 6) {
                if let img = NSImage(named: "MenuBarIcon") {
                    Image(nsImage: img).resizable().scaledToFit().frame(width: 16, height: 16)
                }
                Text("Clipboard History").font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // ── Flat clipboard items (hybrid style) ──
            ForEach(Array(flatItems.enumerated()), id: \.element.id) { i, item in
                PopupItemRow(
                    item: item, number: i + 1,
                    isSelected: state.expandedPane == nil && state.selectedRowIndex == i,
                    hoverEnabled: state.hoverEnabled,
                    onSelect: { onSelectFlatItem(item) },
                    onHover: { if $0 { state.selectedRowIndex = i } }
                )
                Divider().padding(.leading, 10)
            }

            // ── Clipboard folders ──
            ForEach(Array(clipFolders.enumerated()), id: \.offset) { fi, folder in
                let row = flatItems.count + fi
                PopupFolderRow(
                    label: folder.label,
                    count: folder.items.count,
                    isSelected: state.selectedRowIndex == row || state.expandedPane == .clipboard(folderIndex: fi),
                    hoverEnabled: state.hoverEnabled,
                    onSelect: { onSelectClipFolder(fi) },
                    onHover: { if $0 { state.selectedRowIndex = row } }
                )
                if fi < clipFolders.count - 1 { Divider().padding(.leading, 10) }
            }

            // ── Snippets section ──
            if !snippetFolders.isEmpty {
                Divider()

                // Section header
                HStack {
                    Text("Snippets")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.03))

                ForEach(Array(snippetFolders.enumerated()), id: \.element.id) { si, folder in
                    let row = flatItems.count + clipFolders.count + si
                    PopupFolderRow(
                        label: folder.name,
                        count: folder.snippets.count,
                        isSelected: state.selectedRowIndex == row || state.expandedPane == .snippet(folderIndex: si),
                        hoverEnabled: state.hoverEnabled,
                        onSelect: { onSelectSnippetFolder(si) },
                        onHover: { if $0 { state.selectedRowIndex = row } }
                    )
                    if si < snippetFolders.count - 1 { Divider().padding(.leading, 10) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Items panel view (shared for clipboard items and snippets)

struct ItemRow {
    let number: Int
    let title: String
    let icon: String
    let thumbnailImage: NSImage?
}

struct ItemsPanelView: View {
    var state: PopupState
    let panelWidth: CGFloat
    let previewLines: Int
    let title: String
    let rows: [ItemRow]
    let onSelectRow: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("⏎ paste  ←  back").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                ItemsRowView(
                    row: row,
                    previewLines: previewLines,
                    isSelected: state.selectedItemIndex == i,
                    hoverEnabled: state.hoverEnabled,
                    onSelect: { onSelectRow(i) },
                    onHover: { if $0 { state.selectedItemIndex = i } }
                )
                if i < rows.count - 1 { Divider().padding(.leading, 10) }
            }
        }
        .frame(width: panelWidth)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ItemsRowView: View {
    let row: ItemRow
    let previewLines: Int
    let isSelected: Bool
    let hoverEnabled: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(row.number)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .trailing)
                .padding(.top, 1)

            if let img = row.thumbnailImage {
                Image(nsImage: img.scaled(to: NSSize(width: 18, height: 18)))
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: row.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)
            }

            Text(row.title)
                .font(.system(size: 12))
                .lineLimit(previewLines)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { if hoverEnabled { onHover($0) } }
        .animation(.easeInOut(duration: 0.08), value: isSelected)
    }
}

// MARK: - Folder row

struct PopupFolderRow: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let hoverEnabled: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(.secondary)
            Text(label).font(.system(size: 12))
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { if hoverEnabled { onHover($0) } }
        .animation(.easeInOut(duration: 0.08), value: isSelected)
    }
}

// MARK: - Clipboard item row (kept for FolderPanelView flat items)

struct PopupItemRow: View {
    let item: ClipItem
    let number: Int
    let isSelected: Bool
    let hoverEnabled: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .trailing)
            typeIcon.frame(width: 18, height: 18)
            Text(item.displayTitle).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { if hoverEnabled { onHover($0) } }
        .animation(.easeInOut(duration: 0.08), value: isSelected)
    }

    @ViewBuilder private var typeIcon: some View {
        if item.type == .image, let img = item.thumbnailImage {
            Image(nsImage: img.scaled(to: NSSize(width: 18, height: 18)))
                .resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: item.type == .fileURL ? "folder" : "doc.text")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
