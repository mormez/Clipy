import AppKit
import SwiftUI
import Observation

// MARK: - State (observed by SwiftUI)

@Observable
final class PopupState {
    var items: [ClipItem] = []
    var selectedIndex: Int = 0
    var hoverEnabled = false
    var groupingEnabled = false
}

// MARK: - Custom panel that silently swallows unhandled key events (prevents beep)

private final class ClipboardPanel: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // If our handler claims the event, do NOT call super.
        // Calling super on an unhandled key is what causes the system beep.
        if keyDownHandler?(event) != true {
            super.keyDown(with: event)
        }
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

    private init() {}

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        state.items = ClipboardHistory.shared.items   // full list up to maxHistoryItems
        state.selectedIndex = 0
        state.hoverEnabled = false
        let prefs = Preferences.shared
        state.groupingEnabled = prefs.alwaysGroupInSubfolders || state.items.count > 10
        guard !state.items.isEmpty else { return }

        buildPanel()
        sizePanel()
        positionPanel()

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel, queue: .main
        ) { [weak self] _ in self?.hide() }

        // Belt-and-suspenders: local monitor + panel subclass keyDown both handle keys.
        // The monitor fires first; returning nil removes the event entirely (no beep).
        // The panel subclass keyDown is a fallback that also prevents beep.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }

        // Enable hover selection only after the user moves the mouse deliberately.
        // We remove the monitor after the first move to keep overhead minimal.
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

    // MARK: - Panel setup

    private func buildPanel() {
        if panel == nil {
            let p = ClipboardPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 100),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
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
            // Wire the panel's keyDown to our handler (returns true = handled, no beep)
            p.keyDownHandler = { [weak self] event in
                guard let self else { return false }
                return self.handle(event) == nil  // nil means "consumed"
            }
            p.contentView = NSHostingView(rootView: popupView())
            panel = p
        } else {
            // Reuse existing panel — just refresh state (SwiftUI updates automatically)
        }
    }

    private func popupView() -> ClipboardPopupView {
        ClipboardPopupView(
            state: state,
            onSelect: { [weak self] item in self?.paste(item) },
            onDismiss: { [weak self] in self?.hide() }
        )
    }

    private func sizePanel() {
        let itemH: CGFloat = 46
        let sectionH: CGFloat = 26    // height of each group header
        let popupHeaderH: CGFloat = 50
        let shadowPad: CGFloat = 16
        let w: CGFloat = 460
        let maxH: CGFloat = 520       // cap so popup never gets unwieldy tall

        var contentH = popupHeaderH + itemH * CGFloat(state.items.count)
        if state.groupingEnabled {
            let numSections = max(1, (state.items.count + 9) / 10)
            contentH += sectionH * CGFloat(numSections)
        }
        let h = min(contentH + shadowPad * 2, maxH + shadowPad * 2)
        panel?.setContentSize(NSSize(width: w, height: h))
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        let sf = screen.visibleFrame
        let pf = panel.frame

        // Try to appear just below the cursor; flip above if too close to bottom
        var x = mouse.x - pf.width / 2
        var y = mouse.y - pf.height - 8
        if y < sf.minY + 8 { y = mouse.y + 8 }

        x = max(sf.minX + 8, min(x, sf.maxX - pf.width - 8))
        y = max(sf.minY + 8, min(y, sf.maxY - pf.height - 8))

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Keyboard

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 125: // ↓
            state.selectedIndex = min(state.selectedIndex + 1, state.items.count - 1)
            return nil
        case 126: // ↑
            state.selectedIndex = max(state.selectedIndex - 1, 0)
            return nil
        case 36, 76: // Return / numpad Enter
            guard state.selectedIndex < state.items.count else { return nil }
            paste(state.items[state.selectedIndex])
            return nil
        case 53: // Escape
            hide()
            return nil
        default:
            // Number keys 1–9 for instant selection
            if let ch = event.characters, let digit = Int(ch), (1...9).contains(digit) {
                let idx = digit - 1
                if idx < state.items.count { paste(state.items[idx]) }
                return nil
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

        // Re-activate the previous app, wait for it to become frontmost,
        // then send Cmd+V. Using the workspace notification is more reliable
        // than a fixed delay.
        var observer: NSObjectProtocol?
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard activated?.bundleIdentifier == app?.bundleIdentifier else { return }
            NSWorkspace.shared.notificationCenter.removeObserver(observer!)
            observer = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                PasteService.shared.triggerPaste()
            }
        }

        app?.activate(options: .activateIgnoringOtherApps)

        // Safety fallback in case notification never fires (e.g. same app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let o = observer {
                NSWorkspace.shared.notificationCenter.removeObserver(o)
                observer = nil
                PasteService.shared.triggerPaste()
            }
        }
    }
}

// MARK: - Popup View

struct ClipboardPopupView: View {
    var state: PopupState
    let onSelect: (ClipItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                if state.groupingEnabled {
                    groupedItemList
                } else {
                    flatItemList
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 10)
        .padding(8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 14, weight: .semibold))
            Text("Clipboard History")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("↑↓ navigate  ·  ⏎ paste  ·  ⎋ close")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // Flat list — used when grouping is off and ≤10 items
    private var flatItemList: some View {
        VStack(spacing: 0) {
            ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                PopupItemRow(
                    item: item,
                    number: index + 1,
                    isSelected: state.selectedIndex == index,
                    hoverEnabled: state.hoverEnabled,
                    onSelect: { onSelect(item) },
                    onHover: { if $0 { state.selectedIndex = index } }
                )
                if index < state.items.count - 1 {
                    Divider().padding(.leading, 46)
                }
            }
        }
    }

    // Grouped list — "1 – 10", "11 – 20" section headers
    private var groupedItemList: some View {
        let pageSize = 10
        let pages = stride(from: 0, to: state.items.count, by: pageSize).map { start in
            (start: start, items: Array(state.items[start ..< min(start + pageSize, state.items.count)]))
        }
        return VStack(spacing: 0) {
            ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, page in
                // Section header
                HStack {
                    Text("\(page.start + 1) – \(( pageIndex + 1) * pageSize)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.04))

                ForEach(Array(page.items.enumerated()), id: \.element.id) { i, item in
                    let absIndex = page.start + i
                    PopupItemRow(
                        item: item,
                        number: absIndex + 1,
                        isSelected: state.selectedIndex == absIndex,
                        hoverEnabled: state.hoverEnabled,
                        onSelect: { onSelect(item) },
                        onHover: { if $0 { state.selectedIndex = absIndex } }
                    )
                    if i < page.items.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
    }
}

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

            typeIcon
                .frame(width: 22, height: 22)

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
        case .image: return "photo"
        case .fileURL: return "folder"
        }
    }
}
