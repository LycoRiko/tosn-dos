import Foundation
import SwiftData

/// Raw `Int` for migration safety; `off` is zero so old records read as "no repeat".
enum RepeatRule: Int, CaseIterable, Identifiable, Codable, Sendable {
    case off = 0
    case daily = 1
    case weekly = 2
    case monthly = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: return String(localized: "Off")
        case .daily: return String(localized: "Every day")
        case .weekly: return String(localized: "Every week")
        case .monthly: return String(localized: "Every month")
        }
    }
}

/// Blueprint only: never in Today, never counted.
/// The hierarchy mirrors the runtime model, so instantiation is a straight copy.
@Model
final class ListTemplate {
    var uid: UUID = UUID()
    var title: String = ""
    var summary: String = ""
    var symbol: String = "checklist"
    var colorHex: Int = 0x5E5CE6
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lastUsedAt: Date?
    var usageCount: Int = 0

    // Periods count from `repeatStart`, not creation, so turning repeat on today
    // does not backfill. `lastGeneratedAt` covers skipped periods too.
    var repeatRuleRaw: Int = 0
    var repeatStart: Date?
    var lastGeneratedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \TemplateItem.template)
    var items: [TemplateItem]? = []

    init(
        title: String,
        summary: String = "",
        symbol: String = "checklist",
        colorHex: Int = 0x5E5CE6
    ) {
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.colorHex = colorHex
        self.createdAt = .now
        self.updatedAt = .now
    }
}

extension ListTemplate {
    var repeatRule: RepeatRule {
        get { RepeatRule(rawValue: repeatRuleRaw) ?? .off }
        set { repeatRuleRaw = newValue.rawValue }
    }

    var orderedItems: [TemplateItem] {
        (items ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var taskCount: Int { (items ?? []).count }

    var checkCount: Int {
        (items ?? []).reduce(0) { $0 + ($1.checks?.count ?? 0) }
    }

    var isBlank: Bool { (items ?? []).isEmpty }
}

/// One task line inside a template.
@Model
final class TemplateItem {
    var uid: UUID = UUID()
    var title: String = ""
    var note: String = ""
    var priorityRaw: Int = TaskPriority.none.rawValue
    var sortIndex: Double = 0
    var template: ListTemplate?

    @Relationship(deleteRule: .cascade, inverse: \TemplateCheck.item)
    var checks: [TemplateCheck]? = []

    init(title: String, note: String = "", priority: TaskPriority = .none, sortIndex: Double = 0) {
        self.title = title
        self.note = note
        self.priorityRaw = priority.rawValue
        self.sortIndex = sortIndex
    }
}

extension TemplateItem {
    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var orderedChecks: [TemplateCheck] {
        (checks ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }
}

/// One pre-written checklist line (becomes a `Subtask`).
@Model
final class TemplateCheck {
    var uid: UUID = UUID()
    var title: String = ""
    var sortIndex: Double = 0
    var item: TemplateItem?

    init(title: String, sortIndex: Double = 0) {
        self.title = title
        self.sortIndex = sortIndex
    }
}
