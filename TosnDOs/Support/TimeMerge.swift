import Foundation
import SwiftData

/// Old rows carry a separate `deadline`; this moves it into the range fields once
/// and stamps a version so it never runs twice.
@MainActor
enum TimeMerge {
    private static let versionKey = "data.version"
    static let current = 2

    static func runIfNeeded(_ context: ModelContext) {
        guard UserDefaults.standard.integer(forKey: versionKey) < current else { return }

        let tasks = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        for task in tasks where task.deadline != nil {
            let oldDeadline = task.deadline
            let wasOn = task.deadlineReminderEnabled
            let lead = task.deadlineLeadMinutes

            if task.dueDate == nil {
                task.dueDate = oldDeadline
                task.hasDueTime = true
                task.endReminderEnabled = wasOn
                task.endReminderLeadMinutes = lead
            } else {
                task.endDate = oldDeadline
                task.startReminderEnabled = wasOn
                task.startReminderLeadMinutes = lead
            }
            task.deadline = nil
        }

        try? context.save()
        UserDefaults.standard.set(current, forKey: versionKey)
    }
}
