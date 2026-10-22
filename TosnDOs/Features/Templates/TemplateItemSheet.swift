import SwiftUI
import SwiftData

/// Settings for one template task: the fields that do not fit on a row.
/// Mirrors the main app's task editor, minus dates — a template stores offsets
/// relative to the day the list is created, not absolute dates.
struct TemplateItemSheet: View {
    @Bindable var item: TemplateItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var priority: Binding<TaskPriority> {
        Binding(
            get: { item.priority },
            set: { item.priority = $0; save() }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task name", text: $item.title, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Notes", text: $item.note, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.subheadline)
                }

                Section {
                    Picker("Priority", selection: priority) {
                        ForEach(TaskPriority.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                }

                Section {
                    ForEach(item.orderedChecks) { check in
                        TextField("Check", text: Binding(
                            get: { check.title },
                            set: { check.title = $0; save() }
                        ))
                        .font(.subheadline)
                    }
                    .onDelete { offsets in
                        let checks = item.orderedChecks
                        for index in offsets where index < checks.count {
                            context.delete(checks[index])
                        }
                        save()
                    }

                    Button {
                        addCheck()
                    } label: {
                        Label("Add check", systemImage: "plus")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                } header: {
                    Text("Checks")
                } footer: {
                    Text("Checks become subtasks when the list is created.")
                }
            }
            .navigationTitle(item.title.isEmpty ? String(localized: "New task") : item.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func addCheck() {
        let check = TemplateCheck(title: "", sortIndex: Double(item.orderedChecks.count))
        context.insert(check)
        check.item = item
        save()
    }

    private func save() {
        item.template?.updatedAt = .now
        try? context.save()
    }
}
