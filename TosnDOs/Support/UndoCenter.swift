import SwiftUI
import Observation

/// Deletes stay unsaved until the window closes.
@Observable
@MainActor
final class UndoCenter {
    static let shared = UndoCenter()

    private(set) var message: String?

    private var pendingCommit: (() -> Void)?
    private var pendingUndo: (() -> Bool)?
    private var timer: Task<Void, Never>?

    private init() {}

    /// Commits any pending deletion first, so two deletes cannot overwrite each other.
    func stage(message: String, commit: @escaping () -> Void, undo: @escaping () -> Bool) {
        flush()

        self.message = message
        pendingCommit = commit
        pendingUndo = undo

        announce("\(message). \(String(localized: "You can undo this."))")

        timer?.cancel()
        timer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    func perform() {
        let undo = pendingUndo
        clearState()
        // Announce success only when rollback really restored the object.
        if undo?() == true {
            announce(String(localized: "Undone"))
        }
    }

    /// VoiceOver cannot see the banner, so announce instead.
    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    func flush() {
        let commit = pendingCommit
        clearState()
        commit?()
    }

    private func clearState() {
        timer?.cancel()
        timer = nil
        pendingCommit = nil
        pendingUndo = nil
        message = nil
    }
}

struct UndoBanner: View {
    private var center = UndoCenter.shared

    @ViewBuilder
    var body: some View {
        if let message = center.message {
            HStack(spacing: 12) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button("Undo") { center.perform() }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("You can undo this."))
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("You can undo this."))
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 100)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: center.message)
        }
    }
}
