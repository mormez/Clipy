import AppKit
import Foundation

extension Notification.Name {
    static let clipboardHistoryChanged = Notification.Name("com.clipy.historyChanged")
    static let snippetsChanged = Notification.Name("com.clipy.snippetsChanged")
    static let preferencesChanged = Notification.Name("com.clipy.preferencesChanged")
    static let hotkeyChanged = Notification.Name("com.clipy.hotkeyChanged")
    static let stopHotkeyRecording = Notification.Name("com.clipy.stopHotkeyRecording")
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
