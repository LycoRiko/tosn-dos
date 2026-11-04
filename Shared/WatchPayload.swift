import Foundation

/// Plain data only. A dropped snapshot is harmless: the next one replaces everything.
struct WatchTaskPayload: Codable, Identifiable {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var dueDate: Date?
}

struct WatchSnapshot: Codable {
    var generatedAt: Date
    var tasks: [WatchTaskPayload]
}

enum WatchMessage {
    /// Phone → watch: the full list of what is left today.
    static let snapshot = "snapshot"
    /// Watch → phone: "send me a snapshot" (sent on launch).
    static let request = "request"
    /// Watch → phone: the user ticked something off on the watch.
    static let complete = "complete"

    static let payload = "payload"
    static let taskID = "taskID"
    static let isCompleted = "isCompleted"
}
