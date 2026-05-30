import AppKit

final class PasteService {
    static let shared = PasteService()
    private init() {}

    // Used by the menu bar — sets clipboard then pastes with a short delay
    // so the menu has time to close and the previous app regains focus.
    func paste(item: ClipItem) {
        ClipboardMonitor.shared.pause()
        setClipboard(item: item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            PasteService.shared.triggerPaste()
        }
    }

    func pasteString(_ string: String) {
        ClipboardMonitor.shared.pause()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            PasteService.shared.triggerPaste()
        }
    }

    // Called by ClipboardPopupController after it has already re-activated
    // the target app — no extra delay needed here.
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
