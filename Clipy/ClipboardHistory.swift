import Foundation
import AppKit

final class ClipboardHistory {
    static let shared = ClipboardHistory()

    private(set) var items: [ClipItem] = []
    private let storageKey = "com.modernclipboard.history"

    private init() { load() }

    func add(_ item: ClipItem) {
        items.removeAll { ClipItem.hasSameContent($0, item) }
        items.insert(item, at: 0)
        let max = Preferences.shared.maxHistoryItems
        if items.count > max { items = Array(items.prefix(max)) }
        save()
        notify()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
        notify()
    }

    func clear() {
        items.removeAll()
        save()
        notify()
    }

    func markUsed(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].lastUsedAt = Date()
        save()
    }

    func trim(to count: Int) {
        if items.count > count {
            items = Array(items.prefix(count))
            save()
            notify()
        }
    }

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .clipboardHistoryChanged, object: nil)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let loaded = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        items = loaded
    }
}
