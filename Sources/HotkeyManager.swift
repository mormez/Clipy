import AppKit
import Carbon

// Uses Carbon RegisterEventHotKey so events are consumed and never reach the frontmost app.

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeys:  [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), carbonHotKeyHandler, 1, &spec, selfPtr, &eventHandler)
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32 {
        let id = nextID; nextID += 1
        handlers[id] = handler
        let hkID = EventHotKeyID(signature: makeFourCC("MCPY"), id: id)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hkID, GetEventDispatcherTarget(), 0, &ref)
        if let ref { hotkeys[id] = ref }
        return id
    }

    func unregister(id: UInt32) {
        if let ref = hotkeys[id] { UnregisterEventHotKey(ref) }
        hotkeys.removeValue(forKey: id)
        handlers.removeValue(forKey: id)
    }

    func unregisterAll() {
        hotkeys.values.forEach { UnregisterEventHotKey($0) }
        hotkeys.removeAll()
        handlers.removeAll()
        nextID = 1
    }

    fileprivate func fire(id: UInt32) {
        DispatchQueue.main.async { self.handlers[id]?() }
    }
}

private func carbonHotKeyHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    var hkID = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )
    manager.fire(id: hkID.id)
    return noErr
}

private func makeFourCC(_ s: String) -> OSType {
    s.unicodeScalars.reduce(OSType(0)) { ($0 << 8) | OSType($1.value) }
}
