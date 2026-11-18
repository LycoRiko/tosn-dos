import SwiftUI
import SwiftData

/// Shows the parsed date before committing — that is what makes text input trustworthy.
struct QuickAddBar: View {
    var targetList: TodoList?
    /// Used when the typed text contains no date of its own.
    var defaultDue: Date?

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme

    @State private var text = ""
    @FocusState private var focused: Bool
    /// Set when the user edits the parsed date; typing again throws it away.
    @State private var override: Date?
    @State private var overrideHasTime = false
    @State private var clearedDate = false
    @State private var showsDateEditor = false

    private var preview: ParsedTaskInput {
        NaturalDateParser.parse(text)
    }

    /// What the task will actually get: the user's edit first, then the parse.
    private var effectiveDue: Date? {
        if let override { return override }
        return clearedDate ? nil : preview.dueDate
    }

    private var effectiveHasTime: Bool {
        override != nil ? overrideHasTime : preview.hasTime
    }

    private var previewLabel: String? {
        guard !text.isEmpty, let due = effectiveDue else { return nil }
        let formatter = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if effectiveHasTime {
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
                .accessibilityIdentifier("today.quickAdd")

            if let previewLabel {
                Button {
                    focused = false
                    override = effectiveDue
                    overrideHasTime = effectiveHasTime
                    showsDateEditor = true
                } label: {
                    MetaChip(icon: "calendar", text: previewLabel, tint: Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Change date"))
                .popover(isPresented: $showsDateEditor, arrowEdge: .bottom) {
                    dateEditor
                }
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
        .frame(maxWidth: 720)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: text.isEmpty)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: previewLabel)
        .onChange(of: text) { _, _ in
            // A new sentence means new dates; the manual edit only covered the old one.
            override = nil
            clearedDate = false
        }
        .sensoryFeedback(.impact(weight: .light), trigger: text) { old, new in
            old.isEmpty && !new.isEmpty
        }
    }

    private var dateEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker(
                "Date",
                selection: Binding(
                    get: { effectiveDue ?? .now },
                    set: { override = $0 }
                ),
                displayedComponents: overrideHasTime ? [.date, .hourAndMinute] : [.date]
            )
            .datePickerStyle(.compact)

            Toggle("Include time", isOn: $overrideHasTime)

            Button(role: .destructive) {
                clearedDate = true
                override = nil
                showsDateEditor = false
            } label: {
                Label("Remove date", systemImage: "calendar.badge.minus")
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func add() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let parsed = NaturalDateParser.parse(trimmed)
        let wantsReminder = UserDefaults.standard.bool(forKey: PreferenceKey.defaultReminderEnabled)
        let typedDue = effectiveDue
        let cleared = clearedDate && !text.isEmpty
        let task = TodoItem(
            title: parsed.title,
            dueDate: cleared ? nil : (typedDue ?? defaultDue),
            hasDueTime: cleared ? false : effectiveHasTime,
            list: targetList,
            sortIndex: WorkspaceService.nextTaskIndex(in: targetList)
        )
        task.endDate = parsed.endDate

        if wantsReminder, task.dueDate != nil {
            task.endReminderEnabled = true
            task.endReminderLeadMinutes = UserDefaults.standard.object(forKey: PreferenceKey.defaultReminderLead) as? Int ?? 1440
        }
        context.insert(task)
        try? context.save()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            text = ""
        }
        override = nil
        clearedDate = false
        focused = true
    }
}
