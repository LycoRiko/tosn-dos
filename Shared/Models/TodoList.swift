import Foundation
import SwiftData

/// A workspace list. Lists own their tasks (cascade), so deleting a list is a
/// single, unsurprising operation.
@Model
final class TodoList {
    var uid: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var symbol: String = "list.bullet"
    var colorHex: Int = 0x5E5CE6
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var sortIndex: Double = 0

    // Per-list backdrop. Empty name means "inherit the global background".
    var backgroundImageName: String = ""
    var backgroundBlur: Double = 24
    var backgroundOpacity: Double = 0.92

    // Optional deadline for the whole list, plus an optional reminder.
    var deadline: Date?
    var deadlineReminderEnabled: Bool = false
    var deadlineLeadMinutes: Int = 1440

    // Which period of a repeating template this list belongs to. Kept off the
    // title so several "Weekly clean" lists stay distinguishable without
    // turning their names into dates.
    var periodDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \TodoItem.list)
    var tasks: [TodoItem]? = []

    init(
        title: String,
        symbol: String = "list.bullet",
        colorHex: Int = 0x5E5CE6,
        notes: String = "",
        sortIndex: Double = 0
    ) {
        self.title = title
        self.symbol = symbol
        self.colorHex = colorHex
        self.notes = notes
        self.sortIndex = sortIndex
        self.createdAt = .now
    }
}

extension TodoList {
    var orderedTasks: [TodoItem] {
        (tasks ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var openTaskCount: Int {
        (tasks ?? []).reduce(0) { $0 + ($1.isCompleted || $1.isWaiting ? 0 : 1) }
    }

    /// Tasks that can actually be acted on. Waiting ones are parked on someone
    /// else, so they stay out of every count, out of the ring, and out of
    /// "is this list finished".
    var actionableTasks: [TodoItem] {
        (tasks ?? []).filter { !$0.isWaiting }
    }

    var waitingCount: Int {
        (tasks ?? []).filter(\.isWaiting).count
    }

    var doneTaskCount: Int {
        actionableTasks.reduce(0) { $0 + ($1.isCompleted ? 1 : 0) }
    }

    var progress: Double {
        let total = actionableTasks.count
        guard total > 0 else { return 0 }
        return Double(doneTaskCount) / Double(total)
    }

    /// When the last task in this list was checked off.
    var lastCompletedAt: Date? {
        (tasks ?? []).compactMap(\.completedAt).max()
    }

    var isFinished: Bool {
        let total = actionableTasks.count
        return total > 0 && doneTaskCount == total
    }

    /// How long the list took: from the moment it was created to the last tick.
    /// Reopening and finishing again moves the end point, because the question
    /// this answers is "how long did it take", not "how long did the first pass take".
    var workedDuration: TimeInterval? {
        guard isFinished, let finished = lastCompletedAt else { return nil }
        let seconds = finished.timeIntervalSince(createdAt)
        return seconds > 0 ? seconds : nil
    }
}

/// One checklist line inside a task.
@Model
final class Subtask {
    var uid: UUID = UUID()
    var title: String = ""
    var isDone: Bool = false
    var sortIndex: Double = 0
    var parent: TodoItem?

    init(title: String, isDone: Bool = false, sortIndex: Double = 0) {
        self.title = title
        self.isDone = isDone
        self.sortIndex = sortIndex
    }
}

/// Cross-list label. Many-to-many with `TodoItem.tags`.
@Model
final class Tag {
    var uid: UUID = UUID()
    var name: String = ""
    var colorHex: Int = 0x5E5CE6
    var createdAt: Date = Date()

    var items: [TodoItem]? = []

    init(name: String, colorHex: Int = 0x5E5CE6) {
        self.name = name
        self.colorHex = colorHex
        self.createdAt = .now
    }
}
