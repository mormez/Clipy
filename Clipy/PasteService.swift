import AppKit

final class PasteService {
    static let shared = PasteService()
    private init() {}

    // Menu-bar paste: capture previous app, set clipboard, re-activate, then paste.
    func paste(item: ClipItem) {
        ClipboardMonitor.shared.pause()
        setClipboard(item: item)
        let target = NSWorkspace.shared.frontmostApplication
        activateThenPaste(target)
    }

    func pasteString(_ string: String) {
        ClipboardMonitor.shared.pause()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        let target = NSWorkspace.shared.frontmostApplication
        activateThenPaste(target)
    }

    // Used by ClipboardPopupController which handles its own activation timing.
    func setClipboard(item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .string:
            if let s = item.stringValue { pb.setString(s, forType: .string) }
        case .rtf:
            if let s = item.stringValue, let d = s.data(using: .utf8) {
                pb.setData(d, forType: .rtf)
                pb.setString(s, forType: .string)
            }
        case .html:
            if let s = item.stringValue, let d = s.data(using: .utf8) {
                pb.setData(d, forType: .html)
                pb.setString(s, forType: .string)
            }
        case .image:
            if let d = item.imageData { pb.setData(d, forType: .tiff) }
        case .fileURL:
            if let s = item.stringValue, let url = URL(string: s) {
                pb.writeObjects([url as NSURL])
            }
        }
    }

    // Wait for the target app to become frontmost, then send Cmd+V.
    private func activateThenPaste(_ target: NSRunningApplication?) {
        var observer: NSObjectProtocol?
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard activated?.bundleIdentifier == target?.bundleIdentifier ||
                  activated?.processIdentifier == target?.processIdentifier else { return }
            if let o = observer {
                NSWorkspace.shared.notificationCenter.removeObserver(o)
                observer = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.triggerPaste()
            }
        }

        // Give the menu time to fully close, then activate target.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            target?.activate(options: .activateIgnoringOtherApps)
        }

        // Safety fallback — if notification never fires (e.g. target IS already front)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let o = observer {
                NSWorkspace.shared.notificationCenter.removeObserver(o)
                observer = nil
                self.triggerPaste()
            }
        }
    }

    func triggerPaste() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }
}
