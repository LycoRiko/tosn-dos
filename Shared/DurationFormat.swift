import Foundation

/// Human-length durations, localized by Foundation so "3h 20m" becomes
/// "3时间20分" or "3 小时 20 分" without any strings of our own.
enum DurationFormat {
    static func short(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2)
        )
    }
}
