import Carbon

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?

    private init() { installHandler() }

    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // InstallApplicationEventHandler is a C macro — call InstallEventHandler directly
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let event, let ptr = userData else {
                    return OSStatus(eventNotHandledErr)
                }
                var hkID = EventHotKeyID()
                withUnsafeMutablePointer(to: &hkID) { hkPtr in
                    _ = GetEventParameter(
                        event,
                        OSType(kEventParamDirectObject),
                        OSType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        UnsafeMutableRawPointer(hkPtr)
                    )
                }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
                let hotKeyID = hkID.id
                DispatchQueue.main.async { mgr.handlers[hotKeyID]?() }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &eventHandlerRef
        )
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32 {
        let id = nextID
        nextID += 1
        let hkID = EventHotKeyID(signature: 0x434C5059 /* CLPY */, id: id)
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else { return 0 }
        handlers[id] = handler
        refs[id] = ref
        return id
    }

    func unregister(id: UInt32) {
        if let ref = refs[id] { UnregisterEventHotKey(ref) }
        refs.removeValue(forKey: id)
        handlers.removeValue(forKey: id)
    }

    func unregisterAll() {
        refs.values.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
        nextID = 1
    }
}
