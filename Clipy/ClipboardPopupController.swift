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
    // Left column: which row is highlighted (flat items + folders combined)
    var selectedFolderIndex: Int = 0
    // Right column: which folder is open (nil = closed)
    var expandedFolderIndex: Int? = nil
    // Right column: which item is highlighted
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
    private var keyMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?
    let state = PopupState()

    private var currentFolders: [PopupFolder] = []
    private var currentFlatItems: [ClipItem] = []
    private var currentStyle: HistoryMenuStyle = .alwaysGrouped

    // Layout constants
    private let colW: CGFloat    = 260   // width of each column
    private let shadowPad: CGFloat = 16
    private let headerH: CGFloat  = 50
    private let folderRowH: CGFloat = 40
    private let itemRowH: CGFloat   = 44
    private let maxH: CGFloat       = 500

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

    // MARK: - Groups

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
        case .alwaysGrouped:   return ([], makeFolders(items, offset: 0))
        case .hybridFirstFlat: return (Array(items.prefix(ps)), makeFolders(Array(items.dropFirst(ps)), offset: ps))
        case .flatWhenFew:
            return items.count <= ps ? (items, []) : ([], makeFolders(items, offset: 0))
        }
    }

    // MARK: - Panel

    private func buildPanel() {
        if panel == nil {
            let p = ClipboardPanel(
                contentRect: NSRect(x: 0, y: 0, width: colW, height: 100),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            p.titleVisibility = .hidden; p.titlebarAppearsTransparent = true
            p.standardWindowButton(.closeButton)?.isHidden = true
            p.standardWindowButton(.miniaturizeButton)?.isHidden = true
            p.standardWindowButton(.zoomButton)?.isHidden = true
            p.isFloatingPanel = true; p.level = .floating
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
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
            onSelectItem:     { [weak self] item in self?.paste(item) },
            onExpandFolder:   { [weak self] fi in
                self?.state.expandedFolderIndex = fi
                self?.state.selectedItemIndex   = 0
                self?.resizeAndRefresh()
            },
            onCollapseFolder: { [weak self] in
                self?.state.expandedFolderIndex = nil
                self?.resizeAndRefresh()
            }
        )
    }

    private func resizeAndRefresh() {
        sizePanel()
        clampToScreen()
        panel?.contentView = NSHostingView(rootView: makeView())
    }

    private func sizePanel() {
        let hasItems = state.expandedFolderIndex != nil
        let totalW   = hasItems ? colW * 2 : colW

        let leftRows  = CGFloat(currentFlatItems.count) * itemRowH
                      + CGFloat(currentFolders.count)   * folderRowH
        let rightRows: CGFloat = {
            guard let fi = state.expandedFolderIndex, fi < currentFolders.count else { return 0 }
            return CGFloat(currentFolders[fi].items.count) * itemRowH
        }()

        let contentH  = headerH + max(leftRows, rightRows)
        let h         = min(contentH + shadowPad, maxH + shadowPad)
        panel?.setContentSize(NSSize(width: totalW, height: h))
    }

    private func positionPanel() {
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

    private func clampToScreen() {
        guard let panel, let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        var o  = panel.frame.origin
        let pf = panel.frame
        // Keep right edge on screen (panel grew to the right)
        if o.x + pf.width > sf.maxX - 8 { o.x = sf.maxX - pf.width - 8 }
        if o.x < sf.minX + 8             { o.x = sf.minX + 8 }
        if o.y < sf.minY + 8             { o.y = sf.minY + 8 }
        if o.y + pf.height > sf.maxY - 8 { o.y = sf.maxY - pf.height - 8 }
        panel.setFrameOrigin(o)
    }

    // MARK: - Keyboard

    private var isFlatMode: Bool {
        currentStyle == .flatWhenFew && !currentFlatItems.isEmpty && currentFolders.isEmpty
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if isFlatMode          { return handleFlat(event) }
        if state.expandedFolderIndex != nil { return handleItemLevel(event) }
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
        let flatN   = currentFlatItems.count
        let totalN  = flatN + currentFolders.count
        switch event.keyCode {
        case 125: state.selectedFolderIndex = min(state.selectedFolderIndex + 1, totalN - 1); return nil
        case 126: state.selectedFolderIndex = max(state.selectedFolderIndex - 1, 0);          return nil
        case 124, 36, 76: // → or Enter
            let row = state.selectedFolderIndex
            if row < flatN {
                paste(currentFlatItems[row])
            } else {
                let fi = row - flatN
                state.expandedFolderIndex = fi
                state.selectedItemIndex   = 0
                resizeAndRefresh()
            }
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
        let items = currentFolders[fi].items
        switch event.keyCode {
        case 125: state.selectedItemIndex = min(state.selectedItemIndex + 1, items.count - 1); return nil
        case 126: state.selectedItemIndex = max(state.selectedItemIndex - 1, 0);               return nil
        case 123, 53: // ← or Esc: close right column
            state.expandedFolderIndex = nil
            resizeAndRefresh()
            return nil
        case 36, 76:
            if state.selectedItemIndex < items.count { paste(items[state.selectedItemIndex]) }
            return nil
        default:
            if let ch = event.characters, let d = Int(ch), (1...9).contains(d), d-1 < items.count {
                paste(items[d-1]); return nil
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

// MARK: - Root view

struct ClipboardPopupView: View {
    var state: PopupState
    let style: HistoryMenuStyle
    let flatItems: [ClipItem]
    let folders: [PopupFolder]
    let onSelectItem: (ClipItem) -> Void
    let onExpandFolder: (Int) -> Void
    let onCollapseFolder: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column — always visible
            VStack(spacing: 0) {
                popupHeader
                Divider()
                leftContent
            }

            // Right column — visible when a folder is expanded
            if let fi = state.expandedFolderIndex, fi < folders.count {
                Divider()
                VStack(spacing: 0) {
                    rightHeader
                    Divider()
                    itemsList(folder: folders[fi])
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 8)
        .padding(8)
    }

    // MARK: Headers

    private var popupHeader: some View {
        HStack(spacing: 6) {
            if let img = NSImage(named: "MenuBarIcon") {
                Image(nsImage: img).resizable().scaledToFit().frame(width: 16, height: 16)
            }
            Text("Clipboard History").font(.system(size: 12, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var rightHeader: some View {
        HStack(spacing: 6) {
            Button(action: onCollapseFolder) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if let fi = state.expandedFolderIndex, fi < folders.count {
                Text(folders[fi].label).font(.system(size: 12, weight: .semibold))
            }
            Spacer()
            Text("⏎ paste").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Left column content

    @ViewBuilder
    private var leftContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Flat items (hybrid style)
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

                // Folder rows
                ForEach(Array(folders.enumerated()), id: \.offset) { fi, folder in
                    let rowIndex = flatItems.count + fi
                    let isOpen   = state.expandedFolderIndex == fi
                    PopupFolderRow(
                        label: folder.label,
                        count: folder.items.count,
                        isSelected: (state.expandedFolderIndex == nil && state.selectedFolderIndex == rowIndex) || isOpen,
                        hoverEnabled: state.hoverEnabled,
                        onSelect: { onExpandFolder(fi) },
                        onHover: { if $0 {
                            state.selectedFolderIndex = rowIndex
                            // Open folder on hover (like NSMenu submenus)
                            onExpandFolder(fi)
                        }}
                    )
                    if fi < folders.count - 1 { Divider().padding(.leading, 10) }
                }
            }
        }
    }

    // MARK: Right column — items

    private func itemsList(folder: PopupFolder) -> some View {
        ScrollView {
            VStack(spacing: 0) {
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
        }
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
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(label).font(.system(size: 12))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
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
                .resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: item.type == .fileURL ? "folder" : "doc.text")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
