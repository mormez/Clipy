import AppKit
import Carbon

// MARK: - Modern hotkey manager using NSEvent global monitor
// NSEvent.addGlobalMonitorForEvents is more reliable on modern macOS than
// Carbon RegisterEventHotKey, which can silently fail on macOS 26+.
// Requires Accessibility (already needed for paste simulation).

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var globalMonitor: Any?
    private var handler: (() -> Void)?

    // Kept for API compatibility; Carbon refs no longer used
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1

    private init() {}

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32 {
        self.handler = handler

        // Remove any existing monitor
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }

        // Global monitor: fires for keyDown events in any app
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            guard UInt32(event.keyCode) == keyCode else { return }

            // Convert NSEvent modifier flags → Carbon modifier bitmask for comparison
            var mods: UInt32 = 0
            let flags = event.modifierFlags
            if flags.contains(.control) { mods |= UInt32(controlKey) }
            if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
            if flags.contains(.command) { mods |= UInt32(cmdKey) }
            if flags.contains(.option)  { mods |= UInt32(optionKey) }
            guard mods == modifiers else { return }

            DispatchQueue.main.async { self.handler?() }
        }

        // Fall back to Carbon if global monitor couldn't be created (no Accessibility)
        if globalMonitor == nil {
            let id = nextID; nextID += 1
            let hkID = EventHotKeyID(signature: 0x434C5059, id: id)
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref) == noErr,
               let ref {
                refs[id] = ref
            }
        }

        let id = nextID; nextID += 1
        return id
    }

    func unregisterAll() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handler = nil
        nextID = 1
    }

    func unregister(id: UInt32) {
        // No-op in global monitor mode; unregisterAll handles cleanup
    }
}
