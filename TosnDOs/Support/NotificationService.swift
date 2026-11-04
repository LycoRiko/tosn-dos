import Foundation
import UserNotifications

/// Local deadline reminders. One pending request per list and per task, keyed by
/// their `uid`, so editing a deadline replaces the old reminder instead of
/// stacking a new one on top of it.
enum NotificationService {
    private static let listPrefix = "tosn.deadline."
    private static let taskPrefix = "tosn.task."

    /// Prefixes and category must match `NotificationRouter`.
    static let category = "tosn.reminder"
    static let snoozePrefix = "tosn.snooze."
    static let snoozeHour = "tosn.snooze.hour"
    static let snoozeEvening = "tosn.snooze.evening"
    static let snoozeMorning = "tosn.snooze.morning"
    static let snoozeSuffix = ".snooze"

    /// Safe to re-register on every launch: the system keeps the last set.
    static func registerCategories() {
        let actions = [
            UNNotificationAction(identifier: snoozeHour, title: String(localized: "1 hour")),
            UNNotificationAction(identifier: snoozeEvening, title: String(localized: "Tonight")),
            UNNotificationAction(identifier: snoozeMorning, title: String(localized: "Tomorrow morning"))
        ]
        let reminder = UNNotificationCategory(
            identifier: category,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([reminder])
    }

    /// Lead-time choices offered next to the reminder switch, in minutes.
    static let leadChoices: [Int] = [0, 60, 1440, 4320]

    static func title(forLead minutes: Int) -> String {
        switch minutes {
        case 0: return String(localized: "At the deadline")
        case 60: return String(localized: "1 hour before")
        case 1440: return String(localized: "1 day before")
        default: return String(localized: "3 days before")
        }
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    // MARK: - Lists

    /// Idempotent: drops the old request first and schedules nothing when the switch
    /// is off, the list is finished, or the fire date has passed.
    @MainActor
    static func sync(_ list: TodoList) {
        let deadline = list.deadlineReminderEnabled && !list.isFinished ? list.deadline : nil
        reschedule(
            identifier: listPrefix + list.uid.uuidString,
            title: list.title,
            deadline: deadline,
            leadMinutes: list.deadlineLeadMinutes
        )
    }

    /// Same as `sync`, but asks for permission first when it has never been
    /// granted. Used from the editor, where the user just opted in.
    @MainActor
    static func apply(_ list: TodoList) async {
        guard list.deadlineReminderEnabled, !list.isFinished else {
            cancel(list)
            return
        }
        await authorizeIfNeeded()
        sync(list)
    }

    @MainActor
    static func cancel(_ list: TodoList) {
        remove(listPrefix + list.uid.uuidString)
    }

    // MARK: - Tasks

    @MainActor
    static func sync(_ task: TodoItem) {
        let deadline = task.deadlineReminderEnabled && !task.isCompleted ? task.deadline : nil
        reschedule(
            identifier: taskPrefix + task.uid.uuidString,
            title: task.title,
            deadline: deadline,
            leadMinutes: task.deadlineLeadMinutes
        )
    }

    @MainActor
    static func apply(_ task: TodoItem) async {
        guard task.deadlineReminderEnabled, !task.isCompleted else {
            cancel(task)
            return
        }
        await authorizeIfNeeded()
        sync(task)
    }

    @MainActor
    static func cancel(_ task: TodoItem) {
        remove(taskPrefix + task.uid.uuidString)
    }

    // MARK: - Shared plumbing

    private static func authorizeIfNeeded() async {
        if await isAuthorized() == false {
            _ = await requestAuthorization()
        }
    }

    private static func remove(_ identifier: String) {
        // Drop the snoozed copy too, or editing a deadline resurrects it.
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier, identifier + snoozeSuffix])
    }

    /// Drops the old request, then schedules one at `deadline - leadMinutes`.
    private static func reschedule(
        identifier: String,
        title: String,
        deadline: Date?,
        leadMinutes: Int
    ) {
        remove(identifier)

        guard let deadline else { return }
        let fireDate = deadline.addingTimeInterval(-Double(leadMinutes) * 60)
        guard fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(localized: "The deadline is coming up.")
        content.sound = .default
        content.categoryIdentifier = category

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        )
    }
}
