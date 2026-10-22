import SwiftUI

/// The single row used by every list in the app.
///
/// It shows only four things: completion, title, due state, and a compact
/// meta line. Anything else belongs in the editor — that constraint is what
/// keeps a 50-task day scannable.
struct TaskRow: View {
    @Bindable var task: TodoItem
    var showsListName: Bool = true
    var onToggle: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.photoBackground) private var photoBackground

    private var dueLabel: String? {
        DueDateFormat.label(for: task)
    }

    private var isLate: Bool {
        DueDateFormat.isLate(task)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CompletionButton(isOn: task.isCompleted) {
                toggle()
            }
            .padding(.top, -4)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    if task.priority == .high && !task.isCompleted {
                        Image(systemName: "exclamationmark.2")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(TaskPriority.high.color)
                            .accessibilityHidden(true)
                    }
                    Text(task.title.isEmpty ? String(localized: "Untitled") : task.title)
                        .scaledFont(15.5, weight: .medium)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .strikethrough(task.isCompleted, color: .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if hasMeta {
                    metaLine
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.vertical, photoBackground ? 4 : 0)
        .photoRowSurface(photoBackground)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: task.isCompleted)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: task.dueDate)
    }

    private var hasMeta: Bool {
        dueLabel != nil || task.subtaskCount > 0 || (showsListName && task.list != nil)
            || !task.orderedTags.isEmpty || task.isWaiting
    }

    private var metaLine: some View {
        HStack(spacing: 6) {
            if task.isWaiting, let waiting = task.waitingFor {
                MetaChip(icon: "hourglass", text: waiting, tint: .secondary)
            }

            if let dueLabel {
                MetaChip(
                    icon: task.hasDueTime ? "clock" : "calendar",
                    text: dueLabel,
                    tint: isLate ? Color(hex: 0xFF453A) : .secondary
                )
            }

            if task.subtaskCount > 0 {
                MetaChip(
                    icon: "checklist",
                    text: "\(task.doneSubtaskCount)/\(task.subtaskCount)",
                    tint: task.doneSubtaskCount == task.subtaskCount ? Theme.mint : .secondary
                )
            }

            if showsListName, let list = task.list {
                HStack(spacing: 4) {
                    Circle()
                        .fill(ListPalette.color(list.colorHex))
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(list.title)
                        .scaledFont(11.5, weight: .medium)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            ForEach(task.orderedTags.prefix(2)) { tag in
                TagPill(name: tag.name, color: ListPalette.color(tag.colorHex))
            }

            Spacer(minLength: 0)
        }
    }

    private func toggle() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            task.setCompleted(!task.isCompleted)
        }
        task.list?.reconcileCompletion()
        onToggle?()
        try? context.save()
    }
}
