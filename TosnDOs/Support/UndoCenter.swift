import SwiftUI
import Observation

/// 撤销的唯一入口。
///
/// 做法不是快照重建，而是**延迟落盘**：删除只改内存，五秒后才 `save()`；
/// 点「撤销」就是 `rollback()`。好处是对任务、清单、模板、材料一视同仁，
/// 不需要为每种类型写一份快照。
///
/// 代价：这五秒里如果还有别的未保存改动，会一起被撤回去。项目里所有编辑
/// 都是即时 `save()`，所以这个窗口里基本只剩删除本身。
@Observable
@MainActor
final class UndoCenter {
    static let shared = UndoCenter()

    private(set) var message: String?

    private var pendingCommit: (() -> Void)?
    private var pendingUndo: (() -> Bool)?
    private var timer: Task<Void, Never>?

    private init() {}

    /// 登记一次可撤销的删除。会先把上一次挂着的删除落盘，避免互相覆盖。
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

    /// 点「撤销」。
    func perform() {
        let undo = pendingUndo
        clearState()
        // rollback 没成的话不要谎报「已撤销」。
        if undo?() == true {
            announce(String(localized: "Undone"))
        }
    }

    /// VoiceOver 用户看不到底部那一条，所以用播报代替。
    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    /// 五秒到了（或者又删了一次）：把删除落盘。
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

/// 底部那一条。样式固定，别在别处再写第二份。
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
