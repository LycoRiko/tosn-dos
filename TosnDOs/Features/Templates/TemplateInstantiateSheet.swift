import SwiftUI
import SwiftData

/// Pulling a template into the workspace.
///
/// The only two decisions are "what should this copy be called" and "does it
/// start today", because those are the only two things the app cannot guess.
struct TemplateInstantiateSheet: View {
    let template: ListTemplate
    var onCreated: ((TodoList) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PreferenceKey.templateDueToday) private var startToday = true

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("List name", text: $name)
                        .font(.body.weight(.medium))
                } footer: {
                    Text("A new list is created in your workspace. The template itself stays untouched.")
                        .font(.footnote)
                }

                Section {
                    Toggle(isOn: $startToday) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Start today")
                            Text("Every task gets today's date")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    ForEach(template.orderedItems.prefix(6)) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                            Text(item.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            if !item.orderedChecks.isEmpty {
                                Text("\(item.orderedChecks.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    if template.taskCount > 6 {
                        Text("and \(template.taskCount - 6) more")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    SectionHeader(title: String(localized: "Will be created"), count: template.taskCount)
                }
            }
            .groupedRows()
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Add to workspace")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { create() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if name.isEmpty { name = template.title }
            }
        }
        .compactSheetDetents()
    }

    private func create() {
        let list = WorkspaceService.instantiate(
            template: template,
            title: name,
            dueToday: startToday,
            in: context
        )
        onCreated?(list)
        dismiss()
    }
}
