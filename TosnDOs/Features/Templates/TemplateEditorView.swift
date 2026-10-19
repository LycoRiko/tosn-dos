import SwiftUI
import SwiftData

/// Template editor.
///
/// Editing is live on a draft object inserted when the sheet opens, so the
/// nested structure (task → checks) can be edited with real bindings. If the
/// sheet is cancelled while still blank, the draft is removed again.
struct TemplateEditorView: View {
    var template: ListTemplate?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var draft: ListTemplate?
    @State private var insertedHere = false

    var body: some View {
        Group {
            if let draft {
                editor(draft)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppBackground())
            }
        }
        .task { prepare() }
    }

    // MARK: - Editor

    private func editor(_ draft: ListTemplate) -> some View {
        List {
            Section {
                TextField("Template name", text: text(\.title))
                    .font(.body.weight(.medium))
                TextField("What is this list for?", text: text(\.summary), axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(1...3)
            }

            Section {
                IconColorPicker(symbol: text(\.symbol), colorHex: integer(\.colorHex))
            } header: {
                Text("Appearance")
            }

            Section {
                Picker("Repeat", selection: repeatRule(draft)) {
                    ForEach(RepeatRule.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
            } header: {
                Text("Repeat")
            } footer: {
                Text("A new list is made from this template each time you open the app after a period has passed.")
            }

            ForEach(draft.orderedItems) { item in
                itemSection(item)
            }

            Section {
                Button {
                    addItem(to: draft)
                } label: {
                    Label("Add task", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.medium))
                }
            }

            if !insertedHere {
                Section {
                    Button(role: .destructive) {
                        removeTemplate(draft)
                    } label: {
                        Label("Delete template", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .groupedRows()
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(insertedHere ? "New template" : "Edit template")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { cancel(draft) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { finish(draft) }
                    .fontWeight(.semibold)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private func itemSection(_ item: TemplateItem) -> some View {
        Section {
            TextField("Task name", text: Binding(
                get: { item.title },
                set: { item.title = $0; touch() }
            ))

            ForEach(item.orderedChecks) { check in
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    TextField("Check", text: Binding(
                        get: { check.title },
                        set: { check.title = $0; touch() }
                    ))
                    .font(.subheadline)
                }
            }
            .onDelete { offsets in
                let checks = item.orderedChecks
                for index in offsets where index < checks.count {
                    context.delete(checks[index])
                }
                touch()
            }

            Button {
                addCheck(to: item)
            } label: {
                Label("Add check", systemImage: "plus")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }

            Button(role: .destructive) {
                context.delete(item)
                touch()
            } label: {
                Label("Delete task", systemImage: "trash")
                    .font(.footnote)
            }
        } header: {
            Text(item.title.isEmpty ? String(localized: "New task") : item.title)
        }
    }

    // MARK: - Bindings

    private func text(_ keyPath: ReferenceWritableKeyPath<ListTemplate, String>) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? "" },
            set: { draft?[keyPath: keyPath] = $0; touch() }
        )
    }

    private func integer(_ keyPath: ReferenceWritableKeyPath<ListTemplate, Int>) -> Binding<Int> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? 0 },
            set: { draft?[keyPath: keyPath] = $0; touch() }
        )
    }

    /// Turning repeat on starts counting from today. Reusing the template's
    /// creation date would backfill months of periods the moment it is switched on.
    private func repeatRule(_ draft: ListTemplate) -> Binding<RepeatRule> {
        Binding(
            get: { draft.repeatRule },
            set: { rule in
                let wasOff = draft.repeatRule == .off
                draft.repeatRule = rule
                if rule == .off {
                    draft.repeatStart = nil
                    draft.lastGeneratedAt = nil
                } else if wasOff {
                    draft.repeatStart = Calendar.current.startOfDay(for: .now)
                    draft.lastGeneratedAt = nil
                }
                touch()
            }
        )
    }

    // MARK: - Lifecycle

    private func prepare() {
        guard draft == nil else { return }
        if let template {
            draft = template
            insertedHere = false
        } else {
            let created = ListTemplate(title: "")
            context.insert(created)
            draft = created
            insertedHere = true
        }
    }

    private func touch() {
        draft?.updatedAt = .now
        try? context.save()
    }

    private func finish(_ draft: ListTemplate) {
        draft.updatedAt = .now
        try? context.save()
        dismiss()
    }

    private func cancel(_ draft: ListTemplate) {
        let isBlank = draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            && draft.orderedItems.isEmpty
        if insertedHere && isBlank {
            context.delete(draft)
            try? context.save()
        }
        dismiss()
    }

    private func removeTemplate(_ draft: ListTemplate) {
        context.delete(draft)
        try? context.save()
        dismiss()
    }

    private func addItem(to draft: ListTemplate) {
        let item = TemplateItem(title: "", sortIndex: Double(draft.taskCount))
        context.insert(item)
        item.template = draft
        touch()
    }

    private func addCheck(to item: TemplateItem) {
        let check = TemplateCheck(title: "", sortIndex: Double(item.orderedChecks.count))
        context.insert(check)
        check.item = item
        touch()
    }
}
