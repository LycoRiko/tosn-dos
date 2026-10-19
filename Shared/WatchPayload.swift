import Foundation

/// What travels between the phone and the watch.
///
/// Only plain data crosses the wire — no SwiftData objects, no model context.
/// The watch keeps its own store and mirrors whatever the last snapshot said,
/// so a dropped message is never fatal: the next snapshot fixes everything.
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
