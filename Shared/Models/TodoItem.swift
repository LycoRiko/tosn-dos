import Foundation
import SwiftData

/// Priority is stored as an `Int` raw value so the record stays
/// migration-safe and CloudKit-friendly (no enums, no unique constraints).
enum TaskPriority: Int, CaseIterable, Identifiable, Codable, Sendable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return String(localized: "None")
        case .low: return String(localized: "Low")
        case .medium: return String(localized: "Medium")
        case .high: return String(localized: "High")
        }
    }

    var symbolName: String {
        switch self {
        case .none: return "minus"
        case .low: return "arrow.down"
        case .medium: return "equal"
        case .high: return "exclamationmark"
        }
    }
}

/// A single task. This is the only record type the user actually writes,
/// so it stays deliberately flat: everything optional has a default, and the
/// relationships (list / tags / subtasks) are explicit.
@Model
final class TodoItem {
    var uid: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var isCompleted: Bool = false
    var completedAt: Date?
    var dueDate: Date?
    var hasDueTime: Bool = false
    /// A due date is when you plan to do it; the deadline is the last moment
    /// it may be done. Kept separate so a task can have both.
    var deadline: Date?
    var deadlineReminderEnabled: Bool = false
    var deadlineLeadMinutes: Int = 1440
    var priorityRaw: Int = TaskPriority.none.rawValue
    var createdAt: Date = Date()
    /// Fractional index keeps manual ordering cheap; ties fall back to title.
    var sortIndex: Double = 0

    /// Parking a task on somebody else. It keeps the task out of every count
    /// and out of Today, which is the whole point — a thing you cannot act on
    /// should not make today look heavier than it is.
    var waitingFor: String?
    var waitingSince: Date?

    var list: TodoList?

    @Relationship(deleteRule: .cascade, inverse: \Subtask.parent)
    var subtasks: [Subtask]? = []

    @Relationship(inverse: \Tag.items)
    var tags: [Tag]? = []

    /// 截图、原文、地点等材料。删任务时一并删除——没有归属的图片只会变成垃圾。
    @Relationship(deleteRule: .cascade, inverse: \Evidence.task)
    var evidences: [Evidence]? = []

    var orderedEvidences: [Evidence] {
        (evidences ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var evidenceCount: Int { evidences?.count ?? 0 }

    init(
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        hasDueTime: Bool = false,
        priority: TaskPriority = .none,
        list: TodoList? = nil,
        sortIndex: Double = 0
    ) {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.priorityRaw = priority.rawValue
        self.list = list
        self.sortIndex = sortIndex
        self.createdAt = .now
    }
}

extension TodoItem {
    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var orderedSubtasks: [Subtask] {
        (subtasks ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var doneSubtaskCount: Int {
        (subtasks ?? []).reduce(0) { $0 + ($1.isDone ? 1 : 0) }
    }

    var subtaskCount: Int { (subtasks ?? []).count }

    var checklistProgress: Double {
        let total = subtaskCount
        guard total > 0 else { return isCompleted ? 1 : 0 }
        return Double(doneSubtaskCount) / Double(total)
    }

    var orderedTags: [Tag] {
        (tags ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func isOverdue(at reference: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !isCompleted, let dueDate else { return false }
        if hasDueTime { return dueDate < reference }
        return dueDate < calendar.startOfDay(for: reference)
    }

    /// Waiting is a temporary state, not a second kind of task: it only holds
    /// while the task is open.
    var isWaiting: Bool {
        !isCompleted && !(waitingFor ?? "").isEmpty
    }

    func startWaiting(for reason: String, at date: Date = .now) {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        waitingFor = trimmed.isEmpty ? nil : trimmed
        waitingSince = trimmed.isEmpty ? nil : date
    }

    func stopWaiting() {
        waitingFor = nil
        waitingSince = nil
    }

    /// Toggling completion also stamps `completedAt`, which powers the stats view.
    func setCompleted(_ completed: Bool, at date: Date = .now) {
        isCompleted = completed
        completedAt = completed ? date : nil
        if completed {
            stopWaiting()
            for subtask in subtasks ?? [] { subtask.isDone = true }
        }
    }
}
