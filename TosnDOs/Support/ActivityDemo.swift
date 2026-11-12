#if DEBUG && os(iOS)
import ActivityKit
import Foundation
import SwiftData

/// Temporary: seeds one task that is close enough to its deadline for a Live Activity,
/// so the widget can be checked in the simulator without tapping through the UI.
enum ActivityDemo {
    @MainActor
    static func seed(_ context: ModelContext) {
        UserDefaults.standard.set(true, forKey: PreferenceKey.remindViaLiveActivity)

        let existing = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        let task = existing.first { $0.title == "Pay the rent" } ?? {
            let created = TodoItem(title: "Pay the rent", dueDate: nil, hasDueTime: true,
                                   list: nil, sortIndex: 0)
            context.insert(created)
            return created
        }()

        task.dueDate = Date().addingTimeInterval(25 * 60)
        task.hasDueTime = true
        task.endReminderEnabled = true
        task.endReminderLeadMinutes = 15
        try? context.save()

        LiveActivityService.refresh(for: task)

        #if DEBUG
        let endsAt = task.endDate ?? task.dueDate
        print("activity demo: enabled=\(UserDefaults.standard.bool(forKey: PreferenceKey.remindViaLiveActivity)) "
              + "authorized=\(ActivityAuthorizationInfo().areActivitiesEnabled) "
              + "endsAt=\(String(describing: endsAt)) "
              + "live=\(Activity<TodoActivityAttributes>.activities.count)")
        #endif
    }
}
#endif
