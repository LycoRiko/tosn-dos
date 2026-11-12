#if os(iOS)
import ActivityKit
import Foundation

/// Shared with the widget extension, which is why it lives in `Shared/`.
/// Attributes are value types only: an activity outlives the SwiftData context.
struct TodoActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isDone: Bool
        /// The widget counts down to this; nil when the task has no time left to give.
        var endsAt: Date?
    }

    var uid: String
    var title: String
}
#endif
