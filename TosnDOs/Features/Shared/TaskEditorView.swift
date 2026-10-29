import SwiftUI
import SwiftData

/// Detail editor. Edits the model in place — there is no OK/Cancel dance,
/// because every field saves as you go. "Done" only dismisses.
struct TaskEditorView: View {
    @Bindable var task: TodoItem
    var onDone: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @Query(sort: \TodoList.sortIndex) private var lists: [TodoList]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var newTagName = ""
    @State private var newCheckTitle = ""
    @State private var newEvidenceText = ""
    @State private var hasDue: Bool
    @State private var dueDraft: Date
    @State private var hasDeadline: Bool
    @State private var deadlineDraft: Date

    init(task: TodoItem, onDone: (() -> Void)? = nil) {
        self.task = task
        self.onDone = onDone
        _hasDue = State(initialValue: task.dueDate != nil)
        _dueDraft = State(initialValue: task.dueDate ?? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
        _hasDeadline = State(initialValue: task.deadline != nil)
        _deadlineDraft = State(initialValue: task.deadline ?? Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now)
    }

    private var rowBackground: Color {
        Color.primary.opacity(scheme == .dark ? 0.07 : 0.045)
    }

    /// Typing a reason parks the task; clearing the field releases it. No
    /// separate switch, because the state and the reason are the same thing.
    private var waitingBinding: Binding<String> {
        Binding(
            get: { task.waitingFor ?? "" },
            set: { value in
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    task.stopWaiting()
                } else {
                    task.startWaiting(for: value)
                }
            }
        )
    }

    var body: some View {
        List {
            Section {
                TextField("What needs doing?", text: $task.title, axis: .vertical)
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1...3)
                    .onSubmit(save)

                TextField("Notes", text: $task.notes, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(2...6)
                    .foregroundStyle(.secondary)
                    .onSubmit(save)
            }
            .listRowBackground(rowBackground)

            Section {
                materialsRows
            } header: {
                HStack {
                    Text("Materials")
                    Spacer()
                    if task.evidenceCount > 0 {
                        Text("\(task.evidenceCount)")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Screenshots, addresses and notes kept with this task.")
                    .font(.footnote)
            }
            .listRowBackground(rowBackground)

            Section {
                listPicker
                dueRows
                priorityPicker
            } header: {
                Text("Details")
            }
            .listRowBackground(rowBackground)

            Section {
                TextField("Waiting for", text: waitingBinding)
                    .onSubmit(save)
                if task.isWaiting {
                    Button("Stop waiting") {
                        task.stopWaiting()
                        save()
                    }
                }
            } header: {
                Text("Waiting")
            } footer: {
                Text("Waiting tasks move into their own group and stay out of Today and out of every count.")
                    .font(.footnote)
            }
            .listRowBackground(rowBackground)

            Section {
                deadlineRows
            } header: {
                Text("Deadline")
            } footer: {
                Text("The last moment this task may be done. Separate from the due date.")
                    .font(.footnote)
            }
            .listRowBackground(rowBackground)

            Section {
                tagEditor
            } header: {
                Text("Tags")
            }
            .listRowBackground(rowBackground)


            Section {
                checklistRows
            } header: {
                HStack {
                    Text("Checklist")
                    Spacer()
                    if task.subtaskCount > 0 {
                        Text("\(task.doneSubtaskCount)/\(task.subtaskCount)")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(rowBackground)

            Section {
                Button(role: .destructive) {
                    WorkspaceService.delete(task, in: context)
                    dismiss()
                } label: {
                    Label("Delete task", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .listRowBackground(rowBackground)
        }
        .groupedRows()
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Task")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    save()
                    if let onDone {
                        onDone()
                    } else {
                        dismiss()
                    }
                }
                .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Details

    private var listPicker: some View {
        Menu {
            Button {
                task.list = nil
                save()
            } label: {
                Label(String(localized: "No list"), systemImage: "tray")
            }
            Divider()
            ForEach(lists) { list in
                Button {
                    task.list = list
                    save()
                } label: {
                    Label(list.title, systemImage: list.symbol)
                }
            }
        } label: {
            HStack {
                Label {
                    Text("List")
                } icon: {
                    Image(systemName: "list.bullet")
                }
                Spacer()
                Text(task.list?.title ?? String(localized: "No list"))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var dueRows: some View {
        Toggle(isOn: $hasDue.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
            Label("Due date", systemImage: "calendar")
        }
        .onChange(of: hasDue) { _, newValue in
            withAnimation {
                task.dueDate = newValue ? dueDraft : nil
                if !newValue { task.hasDueTime = false }
            }
            save()
        }

        if hasDue {
            DatePicker(
                selection: $dueDraft,
                displayedComponents: task.hasDueTime ? [.date, .hourAndMinute] : [.date]
            ) {
                Text("Date")
            }
            .onChange(of: dueDraft) { _, newValue in
                task.dueDate = newValue
                save()
            }

            Toggle(isOn: $task.hasDueTime.animation(.easeInOut(duration: 0.2))) {
                Label("Include time", systemImage: "clock")
            }
            .onChange(of: task.hasDueTime) { _, _ in save() }
        }
    }

    @ViewBuilder
    private var deadlineRows: some View {
        Toggle(isOn: $hasDeadline.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
            Label("Deadline", systemImage: "hourglass")
        }
        .onChange(of: hasDeadline) { _, newValue in
            withAnimation {
                task.deadline = newValue ? deadlineDraft : nil
                if !newValue { task.deadlineReminderEnabled = false }
            }
            save()
            syncReminder()
        }

        if hasDeadline {
            DatePicker(selection: $deadlineDraft) {
                Text("Date")
            }
            .onChange(of: deadlineDraft) { _, newValue in
                task.deadline = newValue
                save()
                syncReminder()
            }

            Toggle(isOn: $task.deadlineReminderEnabled.animation(.easeInOut(duration: 0.2))) {
                Label("Remind me before this deadline", systemImage: "bell")
            }
            .onChange(of: task.deadlineReminderEnabled) { _, _ in
                save()
                syncReminder()
            }

            if task.deadlineReminderEnabled {
                Picker(selection: $task.deadlineLeadMinutes) {
                    ForEach(NotificationService.leadChoices, id: \.self) { minutes in
                        Text(NotificationService.title(forLead: minutes)).tag(minutes)
                    }
                } label: {
                    Text("Notify")
                }
                .onChange(of: task.deadlineLeadMinutes) { _, _ in
                    save()
                    syncReminder()
                }
            }
        }
    }

    private func syncReminder() {
        Task { await NotificationService.apply(task) }
    }

    private var priorityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Priority", systemImage: "flag")
                .font(.system(size: 15))
            Picker("Priority", selection: $task.priorityRaw) {
                ForEach(TaskPriority.allCases) { priority in
                    Text(priority.title).tag(priority.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: task.priorityRaw) { _, _ in save() }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Tags

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !task.orderedTags.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(task.orderedTags) { tag in
                        Button {
                            remove(tag)
                        } label: {
                            HStack(spacing: 4) {
                                Text(tag.name)
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ListPalette.color(tag.colorHex))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(ListPalette.color(tag.colorHex).opacity(0.13), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "number")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
                TextField("Add tag", text: $newTagName)
                    .font(.system(size: 14))
                    .onSubmit(addTag)
                if !newTagName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add", action: addTag)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let tag = allTags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            ?? {
                let created = Tag(name: name, colorHex: ListPalette.colors.randomElement() ?? 0x5E5CE6)
                context.insert(created)
                return created
            }()
        var current = task.tags ?? []
        if !current.contains(where: { $0.uid == tag.uid }) {
            current.append(tag)
            task.tags = current
        }
        newTagName = ""
        save()
    }

    private func remove(_ tag: Tag) {
        task.tags = (task.tags ?? []).filter { $0.uid != tag.uid }
        save()
    }

    // MARK: - Materials

    @ViewBuilder
    private var materialsRows: some View {
        ForEach(task.orderedEvidences) { evidence in
            materialRow(evidence)
        }
        .onDelete { offsets in
            let items = task.orderedEvidences
            for index in offsets where index < items.count {
                context.delete(items[index])
            }
            save()
        }

        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)
            TextField("Add a note or a link", text: $newEvidenceText)
                .font(.system(size: 15))
                .onSubmit(addEvidence)
        }
    }

    @ViewBuilder
    private func materialRow(_ evidence: Evidence) -> some View {
        HStack(spacing: 10) {
            if evidence.kind == .image, let data = evidence.imageData, let image = PlatformImage(data: data) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel(Text("Screenshot"))
            } else {
                Image(systemName: evidence.kind.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
            }

            TextField(evidence.kind.title, text: Binding(
                get: { evidence.text },
                set: { evidence.text = $0 }
            ))
            .font(.system(size: 15))
            .onSubmit(save)
        }
    }

    private func addEvidence() {
        let text = newEvidenceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let evidence = Evidence(kind: .text, text: text, task: task)
        context.insert(evidence)
        newEvidenceText = ""
        save()
    }

    @ViewBuilder
    private var checklistRows: some View {
        ForEach(task.orderedSubtasks) { subtask in
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        subtask.isDone.toggle()
                    }
                    save()
                } label: {
                    Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(subtask.isDone ? Theme.mint : Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)

                TextField("Item", text: Binding(
                    get: { subtask.title },
                    set: { subtask.title = $0 }
                ))
                .font(.system(size: 15))
                .strikethrough(subtask.isDone, color: .secondary)
                .foregroundStyle(subtask.isDone ? .secondary : .primary)
                .onSubmit(save)
            }
        }
        .onDelete { offsets in
            let items = task.orderedSubtasks
            for index in offsets where index < items.count {
                context.delete(items[index])
            }
            save()
        }

        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)
            TextField("Add checklist item", text: $newCheckTitle)
                .font(.system(size: 15))
                .onSubmit(addCheck)
        }
    }

    private func addCheck() {
        let title = newCheckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let subtask = Subtask(title: title, sortIndex: Double(task.subtaskCount))
        context.insert(subtask)
        subtask.parent = task
        newCheckTitle = ""
        save()
    }

    private func save() {
        try? context.save()
    }
}
