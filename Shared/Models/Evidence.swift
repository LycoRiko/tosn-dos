import Foundation
import SwiftData

/// Kept separate from `notes` so it can cascade with the task.
enum EvidenceKind: Int, CaseIterable, Identifiable {
    case text = 0
    case image = 1
    case place = 2
    case time = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .text: return String(localized: "Text")
        case .image: return String(localized: "Screenshot")
        case .place: return String(localized: "Place")
        case .time: return String(localized: "Time")
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .place: return "mappin.and.ellipse"
        case .time: return "clock"
        }
    }
}

@Model
final class Evidence {
    var uid: UUID = UUID()
    var kindRaw: Int = EvidenceKind.text.rawValue
    var text: String = ""
    /// Screenshots live outside the row: they are megabytes, not bytes.
    @Attribute(.externalStorage) var imageData: Data?
    var createdAt: Date = Date()

    var task: TodoItem?

    init(kind: EvidenceKind, text: String = "", imageData: Data? = nil, task: TodoItem? = nil) {
        self.uid = UUID()
        self.kindRaw = kind.rawValue
        self.text = text
        self.imageData = imageData
        self.createdAt = .now
        self.task = task
    }

    var kind: EvidenceKind {
        get { EvidenceKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    /// What a row shows before the detail is opened.
    var summary: String {
        if kind == .image { return text.isEmpty ? String(localized: "Screenshot") : text }
        return text
    }
}
