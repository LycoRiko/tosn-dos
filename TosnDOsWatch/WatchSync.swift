import Foundation
import SwiftData
import WatchConnectivity

/// The watch half of the link.
///
/// The watch does not keep its own opinion about what today is: it mirrors the
/// phone's snapshot into its local store and shows whatever is left. Ticking a
/// row writes locally first (so the tap feels instant) and then tells the phone,
/// which is the copy everyone else reads.
@MainActor
final class WatchSync: NSObject {
    static let shared = WatchSync()

    private var context: ModelContext?

    func start(context: ModelContext) {
        self.context = context
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState != .activated {
            session.delegate = self
            session.activate()
        }
        requestSnapshot()
    }

    func requestSnapshot() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        session.sendMessage([WatchMessage.request: true], replyHandler: nil, errorHandler: nil)
    }

    /// Tick it here so the row disappears immediately, then let the phone know.
    func complete(task: TodoItem) {
        task.setCompleted(true)
        try? context?.save()

        let session = WCSession.default
        guard session.activationState == .activated else { return }
        session.sendMessage(
            [
                WatchMessage.complete: true,
                WatchMessage.taskID: task.uid.uuidString,
                WatchMessage.isCompleted: true
            ],
            replyHandler: nil,
            errorHandler: nil
        )
    }

    private func apply(_ snapshot: WatchSnapshot) {
        guard let context else { return }
        let existing = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
        let byUID = existing.reduce(into: [UUID: TodoItem]()) { result, task in
            result[task.uid] = task
        }
        let incoming = Set(snapshot.tasks.map(\.id))

        for payload in snapshot.tasks {
            if let local = byUID[payload.id] {
                if local.title != payload.title { local.title = payload.title }
                if local.dueDate != payload.dueDate { local.dueDate = payload.dueDate }
            } else {
                let task = TodoItem(title: payload.title, dueDate: payload.dueDate)
                task.uid = payload.id
                context.insert(task)
            }
        }

        // Anything the phone no longer lists as open is gone from the wrist too:
        // this is a mirror, not a second place to keep things.
        for task in existing where !incoming.contains(task.uid) {
            context.delete(task)
        }

        try? context.save()
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            WatchSync.shared.requestSnapshot()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[WatchMessage.payload] as? Data,
              let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data)
        else { return }
        Task { @MainActor in
            WatchSync.shared.apply(snapshot)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[WatchMessage.payload] as? Data,
              let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data)
        else { return }
        Task { @MainActor in
            WatchSync.shared.apply(snapshot)
        }
    }
}
