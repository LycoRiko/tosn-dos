import Foundation
import UserNotifications

final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// Foreground banners have to be asked for explicitly.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        guard action.hasPrefix(NotificationService.snoozePrefix) else { return }

        let request = response.notification.request
        guard let fireDate = Snooze.snoozeDate(forAction: action, now: .now) else { return }

        let content = UNMutableNotificationContent()
        content.title = request.content.title
        content.body = request.content.body
        content.sound = .default
        content.categoryIdentifier = NotificationService.category
        content.userInfo = request.content.userInfo

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = request.identifier + NotificationService.snoozeSuffix
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}

/// Pure date math, split out so it can be tested.
enum Snooze {
    static func snoozeDate(
        forAction action: String,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        switch action {
        case NotificationService.snoozeHour:
            return now.addingTimeInterval(3600)
        case NotificationService.snoozeEvening:
            return next(hour: 20, after: now, calendar: calendar)
        case NotificationService.snoozeMorning:
            return next(hour: 8, after: now, calendar: calendar, minimumDaysAhead: 1)
        default:
            return nil
        }
    }

    /// Tonight rolls to tomorrow after 20:00; morning is always the next day.
    private static func next(
        hour: Int,
        after now: Date,
        calendar: Calendar,
        minimumDaysAhead: Int = 0
    ) -> Date? {
        let today = calendar.startOfDay(for: now)
        guard let candidate = calendar.date(byAdding: .hour, value: hour, to: today) else { return nil }
        if candidate > now, minimumDaysAhead == 0 { return candidate }
        guard let future = calendar.date(
            byAdding: .day,
            value: max(minimumDaysAhead, 1),
            to: candidate
        ) else { return nil }
        return future
    }
}
