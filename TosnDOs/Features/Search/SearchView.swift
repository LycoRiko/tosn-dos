import SwiftUI
import SwiftData

/// One search surface for the whole library. Both entry points open this same
/// sheet so there is only one set of ranking rules to reason about.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TodoItem.sortIndex) private var allTasks: [TodoItem]
    @Query(sort: \TodoList.sortIndex) private var lists: [TodoList]
    @Query(sort: \ListTemplate.updatedAt, order: .reverse) private var templates: [ListTemplate]

    @State private var query = ""
    @FocusState private var focused: Bool
    @State private var openTask: TodoItem?
    @State private var openList: TodoList?
    @State private var openTemplate: TemplateRef?

    private var taskHits: [SearchHit] {
        SearchService.hits(in: allTasks, query: query)
    }

    private var listHits: [TodoList] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return lists.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private var templateHits: [ListTemplate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return templates.filter { template in
            template.title.localizedCaseInsensitiveContains(trimmed)
                || (template.items ?? []).contains { $0.title.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isEmpty: Bool {
        taskHits.isEmpty && listHits.isEmpty && templateHits.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if !isSearching {
                    Section {
                        EmptyHint(
                            symbol: "magnifyingglass",
                            title: String(localized: "Search everything"),
                            message: String(localized: "Tasks, notes, lists and words inside screenshots.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else if isEmpty {
                    Section {
                        EmptyHint(
                            symbol: "magnifyingglass",
                            title: String(localized: "No matches"),
                            message: String(localized: "Try a different word.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    if !taskHits.isEmpty {
                        Section {
                            ForEach(taskHits) { hit in
                                taskRow(hit)
                            }
                        } header: {
                            SectionHeader(title: String(localized: "Tasks"), count: taskHits.count)
                        }
                    }

                    if !listHits.isEmpty {
                        Section {
                            ForEach(listHits) { list in
                                Button {
                                    openList = list
                                } label: {
                                    HStack(spacing: 12) {
                                        ListGlyph(symbol: list.symbol, color: ListPalette.color(list.colorHex))
                                        Text(list.title).font(.subheadline)
                                        Spacer()
                                        CountBadge(value: list.openTaskCount)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            SectionHeader(title: String(localized: "Lists"), count: listHits.count)
                        }
                    }

                    if !templateHits.isEmpty {
                        Section {
                            ForEach(templateHits) { template in
                                Button {
                                    openTemplate = TemplateRef(uid: template.uid)
                                } label: {
                                    HStack(spacing: 12) {
                                        ListGlyph(symbol: "square.on.square", color: Theme.accent)
                                        Text(template.title).font(.subheadline)
                                        Spacer()
                                        Text("\(template.items?.count ?? 0)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            SectionHeader(title: String(localized: "Templates"), count: templateHits.count)
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                prompt: Text("Search tasks, lists and screenshots")
            )
            .searchFocused($focused)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                // The drawer animates in; focusing before it settles is ignored.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
            }
        }
        .sheet(item: $openTask) { task in
            TaskEditorView(task: task)
        }
        .sheet(item: $openList) { list in
            SearchListSheet(listUID: list.uid)
        }
        .sheet(item: $openTemplate) { ref in
            NavigationStack {
                TemplateDetailView(templateUID: ref.uid)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { openTemplate = nil }
                        }
                    }
            }
        }
    }

    private func taskRow(_ hit: SearchHit) -> some View {
        Button {
            openTask = hit.task
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(hit.task.title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(hit.task.isCompleted ? .secondary : .primary)

                    if hit.task.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.mint)
                    }

                    Spacer(minLength: 6)

                    if let label = hit.field.label {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let meta = meta(for: hit.task) {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let snippet = hit.snippet {
                    Text(snippet)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func meta(for task: TodoItem) -> String? {
        var parts: [String] = []
        if let list = task.list?.title { parts.append(list) }
        if let due = DueDateFormat.label(for: task) { parts.append(due) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A list opened from the results keeps its own stack so the search stays behind it.
private struct SearchListSheet: View {
    let listUID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TaskListView(scope: .list(listUID), selection: .constant(nil))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private struct TemplateRef: Identifiable {
    let uid: UUID
    var id: UUID { uid }
}
