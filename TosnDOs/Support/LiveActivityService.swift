#if os(iOS)
import ActivityKit
import Foundation

/// Local-only Live Activity: no push, no server. iOS cannot start one while the app is
/// closed, so this runs whenever the app is in front and keeps a single activity in step
/// with the task closest to its deadline.
@MainActor
enum LiveActivityService {

    private static var enabled: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKey.remindViaLiveActivity)
    }

    private static var authorized: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Start, update or end, whichever this task calls for.
    static func refresh(for task: TodoItem) {
        let uid = task.uid.uuidString
        guard enabled, authorized else { return end(uid: uid, done: task.isCompleted) }
        guard !task.isCompleted else { return end(uid: uid, done: true) }
        guard task.endReminderEnabled || task.startReminderEnabled,
              let endsAt = task.endDate ?? task.dueDate,
              endsAt > .now,
              endsAt.timeIntervalSinceNow <= 8 * 3600          // an activity lives 8 hours at most
        else { return end(uid: uid, done: false) }

        let state = TodoActivityAttributes.ContentState(isDone: false, endsAt: endsAt)
        let content = ActivityContent(state: state, staleDate: endsAt)

        if let live = Activity<TodoActivityAttributes>.activities.first(where: { $0.attributes.uid == uid }) {
            Task { await live.update(content) }
            return
        }
        endOthers(keeping: uid)
        do {
            _ = try Activity.request(
                attributes: TodoActivityAttributes(uid: uid, title: task.title),
                content: content
            )
        } catch {
            #if DEBUG
            // Silent failure here would look identical to "the switch does nothing".
            print("⚠️ Live Activity request failed: \(error)")
            #endif
        }
    }

    static func end(for task: TodoItem, done: Bool) {
        end(uid: task.uid.uuidString, done: done)
    }

    /// Called when the app comes back: pick the one task that needs attention soonest.
    static func reconcile(_ tasks: [TodoItem]) {
        guard enabled, authorized else {
            for live in Activity<TodoActivityAttributes>.activities {
                Task { await live.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }
        let candidates = tasks.filter {
            !$0.isCompleted && !$0.isWaiting
                && ($0.endReminderEnabled || $0.startReminderEnabled)
                && ($0.endDate ?? $0.dueDate).map { $0 > .now } == true
        }
        guard let next = candidates.min(by: {
            ($0.endDate ?? $0.dueDate ?? .distantFuture) < ($1.endDate ?? $1.dueDate ?? .distantFuture)
        }) else { return }
        refresh(for: next)
    }

    private static func end(uid: String, done: Bool) {
        for live in Activity<TodoActivityAttributes>.activities where live.attributes.uid == uid {
            Task {
                var state = live.content.state
                state.isDone = done
                await live.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
    }

    private static func endOthers(keeping uid: String) {
        for live in Activity<TodoActivityAttributes>.activities where live.attributes.uid != uid {
            Task { await live.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
#else
import Foundation

/// macOS has no ActivityKit; the settings switch simply does nothing there.
enum LiveActivityService {
    static func refresh(for task: TodoItem) {}
    static func end(for task: TodoItem, done: Bool) {}
    static func reconcile(_ tasks: [TodoItem]) {}
}
#endif
