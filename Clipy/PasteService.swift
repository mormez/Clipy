import AppKit

final class PasteService {
    static let shared = PasteService()
    private init() {}

    func paste(item: ClipItem) {
        ClipboardMonitor.shared.pause()
        setClipboard(item: item)
        simulatePaste()
    }

    func pasteString(_ string: String) {
        ClipboardMonitor.shared.pause()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        simulatePaste()
    }

    private func setClipboard(item: ClipItem) {
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

    private func simulatePaste() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            vDown?.flags = .maskCommand
            vDown?.post(tap: .cgAnnotatedSessionEventTap)
            let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            vUp?.flags = .maskCommand
            vUp?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
