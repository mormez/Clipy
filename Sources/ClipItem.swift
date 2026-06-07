import AppKit
import Foundation

enum ClipType: String, Codable {
    case string
    case rtf
    case html
    case image
    case fileURL
}

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ClipType
    let stringValue: String?
    let imageData: Data?
    let timestamp: Date
    var lastUsedAt: Date? = nil

    var displayTitle: String {
        switch type {
        case .string, .rtf, .html:
            let text = (stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "(empty)" : String(text.prefix(100))
        case .image:
            return "[Image]"
        case .fileURL:
            return stringValue.map { URL(string: $0)?.lastPathComponent ?? $0 } ?? "[File]"
        }
    }

    var thumbnailImage: NSImage? {
        guard type == .image, let data = imageData else { return nil }
        return NSImage(data: data)
    }

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.type == rhs.type &&
        lhs.stringValue == rhs.stringValue &&
        lhs.imageData == rhs.imageData
    }

    static func hasSameContent(_ lhs: ClipItem, _ rhs: ClipItem) -> Bool {
        lhs == rhs
    }
}
