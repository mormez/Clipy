import Foundation
import Carbon
import ServiceManagement

enum HistoryMenuStyle: Int, CaseIterable {
    case alwaysGrouped     = 0   // all items in 1-10, 11-20, … subfolders
    case hybridFirstFlat   = 1   // first 10 flat, older ones in 11-20, 21-30, … subfolders
    case flatWhenFew       = 2   // flat when ≤10, subfolders only when >10

    var label: String {
        switch self {
        case .alwaysGrouped:   return "Always in subfolders"
        case .hybridFirstFlat: return "First 10 flat, older in subfolders"
        case .flatWhenFew:     return "Flat when 10 or fewer"
        }
    }
}

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
    @Published var historyMenuStyle: HistoryMenuStyle {
        didSet { set(historyMenuStyle.rawValue, for: .historyMenuStyle) }
    }
    @Published var itemsPanelWidth: Int {
        didSet { set(itemsPanelWidth, for: .itemsPanelWidth) }
    }
    @Published var previewLines: Int {
        didSet { set(previewLines, for: .previewLines) }
    }

    private init() {
        maxHistoryItems  = ud.object(forKey: Key.maxHistoryItems.rawValue) as? Int ?? 20
        mainMenuKeyCode  = UInt32(ud.object(forKey: Key.mainMenuKeyCode.rawValue) as? Int ?? kVK_ANSI_V)
        mainMenuModifiers = UInt32(ud.object(forKey: Key.mainMenuModifiers.rawValue) as? Int ?? (controlKey | shiftKey))
        excludedBundleIDs = ud.stringArray(forKey: Key.excludedBundleIDs.rawValue) ?? []
        launchAtLogin    = ud.bool(forKey: Key.launchAtLogin.rawValue)
        itemsPanelWidth  = ud.object(forKey: Key.itemsPanelWidth.rawValue) as? Int ?? 400
        previewLines     = ud.object(forKey: Key.previewLines.rawValue) as? Int ?? 2

        // Migrate from old boolean alwaysGroupInSubfolders if present
        if let old = ud.object(forKey: "alwaysGroupInSubfolders") as? Bool {
            historyMenuStyle = old ? .alwaysGrouped : .flatWhenFew
            ud.removeObject(forKey: "alwaysGroupInSubfolders")
        } else {
            historyMenuStyle = HistoryMenuStyle(rawValue: ud.integer(forKey: Key.historyMenuStyle.rawValue)) ?? .alwaysGrouped
        }
    }

    private let ud = UserDefaults.standard

    private enum Key: String {
        case maxHistoryItems, mainMenuKeyCode, mainMenuModifiers
        case excludedBundleIDs, launchAtLogin, historyMenuStyle, itemsPanelWidth, previewLines
    }

    private func set(_ value: Any, for key: Key) {
        ud.set(value, forKey: key.rawValue)
        NotificationCenter.default.post(name: .preferencesChanged, object: nil)
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else             { try SMAppService.mainApp.unregister() }
        } catch {}
    }
}
