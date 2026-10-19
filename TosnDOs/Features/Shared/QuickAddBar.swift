import SwiftUI
import SwiftData

/// The only always-visible input in the app.
///
/// Type, press return, done — the date words are parsed on the fly so the
/// user never has to open a picker for the common case. The bar shows what it
/// understood before committing, which is what makes text input trustworthy.
struct QuickAddBar: View {
    var targetList: TodoList?
    /// Used when the typed text contains no date of its own.
    var defaultDue: Date?

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme

    @State private var text = ""
    @FocusState private var focused: Bool

    private var preview: ParsedTaskInput {
        NaturalDateParser.parse(text)
    }

    private var previewLabel: String? {
        guard !text.isEmpty, preview.dueDate != nil else { return nil }
        let formatter = Date.FormatStyle.dateTime.month(.abbreviated).day()
        guard let due = preview.dueDate else { return nil }
        if preview.hasTime {
            return "\(due.formatted(formatter)) \(due.formatted(date: .omitted, time: .shortened))"
        }
        return due.formatted(formatter)
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.06), in: Circle())

            TextField("New task", text: $text, axis: .vertical)
                .scaledFont(15.5)
                .lineLimit(1...3)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(add)

            if let previewLabel {
                MetaChip(icon: "calendar", text: previewLabel, tint: Theme.accent)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: add) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add task"))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassSurface(radius: 26, interactive: true)
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: text.isEmpty)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: previewLabel)
        .sensoryFeedback(.impact(weight: .light), trigger: text) { old, new in
            old.isEmpty && !new.isEmpty
        }
    }

    private func add() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let parsed = NaturalDateParser.parse(trimmed)
        let task = TodoItem(
            title: parsed.title,
            dueDate: parsed.dueDate ?? defaultDue,
            hasDueTime: parsed.hasTime,
            list: targetList,
            sortIndex: WorkspaceService.nextTaskIndex(in: targetList)
        )
        context.insert(task)
        try? context.save()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            text = ""
        }
        focused = true
    }
}
