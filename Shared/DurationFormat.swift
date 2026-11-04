import Foundation

/// "3h 20m" → "3 小时 20 分"; Foundation does the localising.
enum DurationFormat {
    static func short(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2)
        )
    }
}
