import AppKit
import Foundation

extension Notification.Name {
    static let clipboardHistoryChanged = Notification.Name("com.modernclipboard.historyChanged")
    static let snippetsChanged = Notification.Name("com.modernclipboard.snippetsChanged")
    static let preferencesChanged = Notification.Name("com.modernclipboard.preferencesChanged")
    static let hotkeyChanged = Notification.Name("com.modernclipboard.hotkeyChanged")
    static let stopHotkeyRecording = Notification.Name("com.modernclipboard.stopHotkeyRecording")
}

extension NSImage {
    func scaled(to size: NSSize) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: size),
             from: NSRect(origin: .zero, size: self.size),
             operation: .sourceOver,
             fraction: 1.0)
        result.unlockFocus()
        return result
    }
}
