#if os(iOS)
import Foundation
import SwiftData
import WatchConnectivity

/// The phone half of the watch link.
///
/// The phone owns the data; the watch mirrors "what is left today". Two things
/// flow back: a request for a snapshot when the watch opens, and a tick when
/// the user completes something on the wrist.
///
/// Delivery is best-effort on purpose. `updateApplicationContext` keeps the
/// latest snapshot and hands it over whenever the watch next wakes, so nothing
/// is lost if the watch app is not running at that moment.
@MainActor
final class PhoneWatchSync: NSObject {
    static let shared = PhoneWatchSync()

    private var context: ModelContext?
    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func start(context: ModelContext) {
        self.context = context
        guard let session, session.activationState != .activated else { return }
        session.delegate = self
        session.activate()
    }

    /// Pushes the current "left today" list. Safe to call often — the system
    /// keeps only the newest context.
    func pushSnapshot() {
        guard let context, let session, session.activationState == .activated else { return }
        let snapshot = Self.makeSnapshot(in: context)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? session.updateApplicationContext([WatchMessage.payload: data])
    }

    private static func makeSnapshot(in context: ModelContext) -> WatchSnapshot {
        let all = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        let open = TodayScope.snapshot(from: all).open
        let payload = open.map {
            WatchTaskPayload(
                id: $0.uid,
                title: $0.title,
                isCompleted: $0.isCompleted,
                dueDate: $0.dueDate
            )
        }
        return WatchSnapshot(generatedAt: .now, tasks: payload)
    }

    private func applyCompletion(taskID: UUID, isCompleted: Bool) {
        guard let context else { return }
        let all = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        guard let task = all.first(where: { $0.uid == taskID }) else { return }
        task.setCompleted(isCompleted)
        try? context.save()
        pushSnapshot()
    }
}

extension PhoneWatchSync: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            PhoneWatchSync.shared.pushSnapshot()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // A second watch took over; come back up for it.
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if message[WatchMessage.request] as? Bool == true {
                PhoneWatchSync.shared.pushSnapshot()
            }
            if message[WatchMessage.complete] as? Bool == true,
               let raw = message[WatchMessage.taskID] as? String,
               let uid = UUID(uuidString: raw),
               let completed = message[WatchMessage.isCompleted] as? Bool {
                PhoneWatchSync.shared.applyCompletion(taskID: uid, isCompleted: completed)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            if message[WatchMessage.request] as? Bool == true {
                PhoneWatchSync.shared.pushSnapshot()
            }
            replyHandler([:])
        }
    }
}
#endif
