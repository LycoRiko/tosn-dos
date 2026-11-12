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
            fireDate: fireDate(anchor: deadline, leadMinutes: list.deadlineLeadMinutes)
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

    private static let startSuffix = ".start"
    private static let endSuffix = ".end"

    // MARK: - Tasks

    @MainActor
    static func sync(_ task: TodoItem) {
        let base = taskPrefix + task.uid.uuidString
        guard !task.isCompleted else {
            remove(base)
            return
        }

        let end = task.endDate ?? task.dueDate
        reschedule(
            identifier: base + endSuffix,
            title: task.title,
            fireDate: task.endReminderEnabled ? fireDate(anchor: end, leadMinutes: task.endReminderLeadMinutes) : nil
        )
        reschedule(
            identifier: base + startSuffix,
            title: task.title,
            fireDate: task.startReminderEnabled && task.endDate != nil
                ? startFireDate(start: task.dueDate, leadMinutes: task.startReminderLeadMinutes, end: task.endDate)
                : nil
        )
    }

    @MainActor
    static func apply(_ task: TodoItem) async {
        guard task.endReminderEnabled || task.startReminderEnabled, !task.isCompleted else {
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

    /// `remove` clears the two suffixed copies as well, so editing a time cannot
    /// leave an orphaned reminder behind.

    /// A reminder fires this long before the moment it warns about.
    static func fireDate(anchor: Date?, leadMinutes: Int) -> Date? {
        guard let anchor else { return nil }
        return anchor.addingTimeInterval(-Double(leadMinutes) * 60)
    }

    /// A start reminder must still land before the range ends; a reversed range
    /// (however it got that way) would otherwise queue a pointless reminder.
    static func startFireDate(start: Date?, leadMinutes: Int, end: Date?) -> Date? {
        guard let start else { return nil }
        let raw = start.addingTimeInterval(-Double(leadMinutes) * 60)
        guard let end, raw >= end else { return raw }
        return end.addingTimeInterval(-60)
    }

    // MARK: - Shared plumbing

    private static func authorizeIfNeeded() async {
        if await isAuthorized() == false {
            _ = await requestAuthorization()
        }
    }

    private static func remove(_ identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier, identifier + snoozeSuffix, identifier + startSuffix, identifier + endSuffix]
        )
    }

    /// Drops the old request, then schedules one at the given moment.
    private static func reschedule(identifier: String, title: String, fireDate: Date?) {
        remove(identifier)

        guard UserDefaults.standard.bool(forKey: PreferenceKey.remindViaNotification) else { return }
        guard let fireDate, fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(localized: "The deadline is coming up.")
        content.sound = .default
        content.categoryIdentifier = category
        if UserDefaults.standard.bool(forKey: PreferenceKey.remindViaTimeSensitive) {
            content.interruptionLevel = .timeSensitive
        }
        #if DEBUG
        print("reminder interruption level: \(content.interruptionLevel.rawValue)")
        #endif

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
