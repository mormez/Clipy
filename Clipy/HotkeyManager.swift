import AppKit
import Carbon

// Supports multiple simultaneous global hotkeys (one per registered ID).

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var monitors: [UInt32: Any] = [:]
    private var handlers:  [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    private init() {}

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32 {
        let id = nextID; nextID += 1
        handlers[id] = handler

        let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            guard UInt32(event.keyCode) == keyCode else { return }
            var mods: UInt32 = 0
            let flags = event.modifierFlags
            if flags.contains(.control) { mods |= UInt32(controlKey) }
            if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
            if flags.contains(.command) { mods |= UInt32(cmdKey) }
            if flags.contains(.option)  { mods |= UInt32(optionKey) }
            guard mods == modifiers else { return }
            DispatchQueue.main.async { self.handlers[id]?() }
        }
        if let monitor { monitors[id] = monitor }
        return id
    }

    func unregister(id: UInt32) {
        if let m = monitors[id] { NSEvent.removeMonitor(m) }
        monitors.removeValue(forKey: id)
        handlers.removeValue(forKey: id)
    }

    func unregisterAll() {
        monitors.values.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        handlers.removeAll()
        nextID = 1
    }
}
