import Foundation
import Carbon
import ServiceManagement

final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var maxHistoryItems: Int {
        didSet {
            set(maxHistoryItems, for: .maxHistoryItems)
            ClipboardHistory.shared.trim(to: maxHistoryItems)
        }
    }
    @Published var mainMenuKeyCode: UInt32 {
        didSet { set(Int(mainMenuKeyCode), for: .mainMenuKeyCode) }
    }
    @Published var mainMenuModifiers: UInt32 {
        didSet { set(Int(mainMenuModifiers), for: .mainMenuModifiers) }
    }
    @Published var excludedBundleIDs: [String] {
        didSet { set(excludedBundleIDs, for: .excludedBundleIDs) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            set(launchAtLogin, for: .launchAtLogin)
            updateLoginItem()
        }
    }

    private init() {
        maxHistoryItems = ud.object(forKey: Key.maxHistoryItems.rawValue) as? Int ?? 100
        mainMenuKeyCode = UInt32(ud.object(forKey: Key.mainMenuKeyCode.rawValue) as? Int ?? kVK_ANSI_V)
        mainMenuModifiers = UInt32(ud.object(forKey: Key.mainMenuModifiers.rawValue) as? Int ?? (controlKey | shiftKey))
        excludedBundleIDs = ud.stringArray(forKey: Key.excludedBundleIDs.rawValue) ?? []
        launchAtLogin = ud.bool(forKey: Key.launchAtLogin.rawValue)
    }

    private let ud = UserDefaults.standard

    private enum Key: String {
        case maxHistoryItems, mainMenuKeyCode, mainMenuModifiers, excludedBundleIDs, launchAtLogin
    }

    private func set(_ value: Any, for key: Key) {
        ud.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Best-effort; user can set this manually if needed
        }
    }
}
