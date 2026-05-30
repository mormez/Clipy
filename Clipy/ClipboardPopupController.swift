import AppKit
import SwiftUI
import Observation

// MARK: - Folder group

struct PopupFolder {
    let label: String
    let items: [ClipItem]
    let startNumber: Int
}

// MARK: - State

@Observable
final class PopupState {
    var items: [ClipItem] = []
    var hoverEnabled = false
    var selectedFolderIndex: Int = 0
    var expandedFolderIndex: Int? = nil
    var selectedItemIndex: Int = 0
}

// MARK: - Panel subclass (key-capable, beep-free)

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

    // Main panel — folder list, stays as key window throughout
    private var panel: ClipboardPanel?
    // Items panel — separate floating panel, non-activating so
    // it never steals key-window status from the folder panel
    private var itemPanel: NSPanel?

    private var keyMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?
    let state = PopupState()

    private var currentFolders: [PopupFolder] = []
    private var currentFlatItems: [ClipItem] = []
    private var currentStyle: HistoryMenuStyle = .alwaysGrouped

    private let folderColW: CGFloat  = 200
    private let itemColW: CGFloat    = 600
    private let headerH: CGFloat     = 50
    private let folderRowH: CGFloat  = 40
    private let itemRowH: CGFloat    = 44
    private let bottomMargin: CGFloat = 12
    private let maxH: CGFloat        = 600

    private init() {}

    func toggle() { if panel?.isVisible == true { hide() } else { show() } }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        state.items = ClipboardHistory.shared.items
        state.hoverEnabled = false
        guard !state.items.isEmpty else { return }

        currentStyle = Preferences.shared.historyMenuStyle
        (currentFlatItems, currentFolders) = computeGroups(items: state.items, style: currentStyle)

        state.selectedFolderIndex = 0
        state.expandedFolderIndex = nil
        state.selectedItemIndex   = 0

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
        panel?.contentView = NSHostingView(rootView: folderView())
    }

    private func folderView() -> FolderPanelView {
        FolderPanelView(
            state: state,
            style: currentStyle,
            flatItems: currentFlatItems,
            folders: currentFolders,
            onSelectItem:   { [weak self] item in self?.paste(item) },
            onExpandFolder: { [weak self] fi in self?.openFolder(fi) }
        )
    }

    private func sizeFolderPanel() {
        let rows = CGFloat(currentFlatItems.count) * itemRowH
                 + CGFloat(currentFolders.count)   * folderRowH
        let h = min(headerH + rows + bottomMargin, maxH)
        panel?.setContentSize(NSSize(width: folderColW, height: h))
    }

    private func positionFolderPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let sf  = screen.visibleFrame
        let pf  = panel.frame
        var x   = NSEvent.mouseLocation.x - pf.width / 2
        var y   = NSEvent.mouseLocation.y - pf.height - 8
        if y < sf.minY + 8 { y = NSEvent.mouseLocation.y + 8 }
        x = max(sf.minX + 8, min(x, sf.maxX - pf.width - 8))
        y = max(sf.minY + 8, min(y, sf.maxY - pf.height - 8))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Items panel

    private func openFolder(_ fi: Int) {
        guard fi < currentFolders.count else { return }
        state.expandedFolderIndex = fi
        state.selectedItemIndex   = 0
        showItemPanel(for: fi)
        // Refresh folder view so selected folder stays highlighted
        panel?.contentView = NSHostingView(rootView: folderView())
    }

    private func closeFolder() {
        state.expandedFolderIndex = nil
        hideItemPanel()
        // Refresh folder view to clear the highlight on the folder
        panel?.contentView = NSHostingView(rootView: folderView())
    }

    private func showItemPanel(for fi: Int) {
        let folder = currentFolders[fi]

        // Build panel once, reuse across folders
        if itemPanel == nil {
            let p = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            p.isFloatingPanel = true
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            itemPanel = p
        }

        // Fresh content for this folder
        itemPanel?.contentView = NSHostingView(rootView:
            ItemsPanelView(
                state: state,
                folder: folder,
                onSelectItem: { [weak self] item in self?.paste(item) }
            )
        )

        // Size to fit all items in the folder
        let h = min(headerH + CGFloat(folder.items.count) * itemRowH + bottomMargin, maxH)
        itemPanel?.setContentSize(NSSize(width: itemColW, height: h))

        // Position: right of folder panel, top-aligned
        positionItemPanel()
        itemPanel?.orderFront(nil)
    }

    private func positionItemPanel() {
        guard let panel, let itemPanel, let screen = NSScreen.main else { return }
        let sf  = screen.visibleFrame
        let pf  = panel.frame
        let ipf = itemPanel.frame

        // Default: to the right, top-aligned with folder panel
        var x = pf.maxX
        var y = pf.maxY - ipf.height

        // If it goes off the right edge, show to the left instead
        if x + ipf.width > sf.maxX - 8 { x = pf.minX - ipf.width }
        // Vertical clamp
        y = max(sf.minY + 8, min(y, sf.maxY - ipf.height - 8))
        x = max(sf.minX + 8, x)

        itemPanel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func hideItemPanel() {
        itemPanel?.orderOut(nil)
    }

    // MARK: - Keyboard

    private var isFlatMode: Bool {
        currentStyle == .flatWhenFew && !currentFlatItems.isEmpty && currentFolders.isEmpty
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if isFlatMode                          { return handleFlat(event) }
        if state.expandedFolderIndex != nil    { return handleItemLevel(event) }
        return handleFolderLevel(event)
    }

    private func handleFlat(_ event: NSEvent) -> NSEvent? {
        let n = currentFlatItems.count
        switch event.keyCode {
        case 125: state.selectedFolderIndex = min(state.selectedFolderIndex + 1, n - 1); return nil
        case 126: state.selectedFolderIndex = max(state.selectedFolderIndex - 1, 0);     return nil
        case 36, 76:
            if state.selectedFolderIndex < n { paste(currentFlatItems[state.selectedFolderIndex]) }
            return nil
        case 53: hide(); return nil
        default:
            if let ch = event.characters, let d = Int(ch), (1...9).contains(d), d-1 < n {
                paste(currentFlatItems[d-1]); return nil
            }
            return event
        }
    }

    private func handleFolderLevel(_ event: NSEvent) -> NSEvent? {
        let flatN  = currentFlatItems.count
        let totalN = flatN + currentFolders.count
        switch event.keyCode {
        case 125: state.selectedFolderIndex = min(state.selectedFolderIndex + 1, totalN - 1); return nil
        case 126: state.selectedFolderIndex = max(state.selectedFolderIndex - 1, 0);          return nil
        case 124, 36, 76:
            let row = state.selectedFolderIndex
            if row < flatN { paste(currentFlatItems[row]) }
            else           { openFolder(row - flatN) }
            return nil
        case 53: hide(); return nil
        default:
            if let ch = event.characters, let d = Int(ch), (1...9).contains(d), d-1 < flatN {
                paste(currentFlatItems[d-1]); return nil
            }
            return event
        }
    }

    private func handleItemLevel(_ event: NSEvent) -> NSEvent? {
        guard let fi = state.expandedFolderIndex, fi < currentFolders.count else { return event }
        let folderItems = currentFolders[fi].items
        switch event.keyCode {
        case 125: state.selectedItemIndex = min(state.selectedItemIndex + 1, folderItems.count - 1); return nil
        case 126: state.selectedItemIndex = max(state.selectedItemIndex - 1, 0);                     return nil
        case 123, 53: closeFolder(); return nil   // ← or Esc
        case 36, 76:
            if state.selectedItemIndex < folderItems.count { paste(folderItems[state.selectedItemIndex]) }
            return nil
        default:
            if let ch = event.characters, let d = Int(ch), (1...9).contains(d), d-1 < folderItems.count {
                paste(folderItems[d-1]); return nil
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
}

// MARK: - Folder panel view

struct FolderPanelView: View {
    var state: PopupState
    let style: HistoryMenuStyle
    let flatItems: [ClipItem]
    let folders: [PopupFolder]
    let onSelectItem: (ClipItem) -> Void
    let onExpandFolder: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

            // Flat items (hybrid)
            ForEach(Array(flatItems.enumerated()), id: \.element.id) { i, item in
                PopupItemRow(
                    item: item, number: i + 1,
                    isSelected: state.expandedFolderIndex == nil && state.selectedFolderIndex == i,
                    hoverEnabled: state.hoverEnabled,
                    onSelect: { onSelectItem(item) },
                    onHover: { if $0 { state.selectedFolderIndex = i } }
                )
                Divider().padding(.leading, 10)
            }

            // Folders
            ForEach(Array(folders.enumerated()), id: \.offset) { fi, folder in
                let rowIndex = flatItems.count + fi
                let isOpen   = state.expandedFolderIndex == fi
                PopupFolderRow(
                    label: folder.label,
                    count: folder.items.count,
                    isSelected: state.selectedFolderIndex == rowIndex || isOpen,
                    hoverEnabled: state.hoverEnabled,
                    onSelect: { onExpandFolder(fi) },
                    onHover: { if $0 { state.selectedFolderIndex = rowIndex } }
                )
                if fi < folders.count - 1 { Divider().padding(.leading, 10) }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Items panel view

struct ItemsPanelView: View {
    var state: PopupState
    let folder: PopupFolder
    let onSelectItem: (ClipItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Text(folder.label).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("⏎ paste  ←  back").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

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
                if i < folder.items.count - 1 { Divider().padding(.leading, 10) }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

// MARK: - Item row

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
            Text(item.displayTitle)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
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
