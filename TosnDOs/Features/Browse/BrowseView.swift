import SwiftUI
import SwiftData

/// Your own containers, and nothing else. Lists you made, templates you wrote,
/// tags you used. No suggested views, no "for you" rows.
struct BrowseView: View {
    @Query(sort: \TodoList.sortIndex) private var lists: [TodoList]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \ListTemplate.updatedAt, order: .reverse) private var templates: [ListTemplate]

    @Environment(\.modelContext) private var context
    @State private var newListSheet = false
    @State private var newTemplateSheet = false

    var body: some View {
        NavigationStack {
            List {
                listsSection
                previousSection
                templatesSection

                if !tags.isEmpty {
                    Section {
                        ForEach(tags) { tag in
                            NavigationLink(value: SidebarItem.tag(tag.uid)) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(ListPalette.color(tag.colorHex))
                                        .frame(width: 8, height: 8)
                                    Text(tag.name)
                                        .font(.subheadline)
                                    Spacer()
                                    CountBadge(value: (tag.items ?? []).filter { !$0.isCompleted }.count)
                                }
                            }
                        }
                    } header: {
                        SectionHeader(title: String(localized: "Tags"))
                    }
                }
            }
            .groupedRows()
            .scrollContentBackground(.hidden)
            // The floating tab bar covers the last section otherwise.
            .contentMargins(.bottom, 92, for: .scrollContent)
            .background(AppBackground())
            .navigationTitle("Browse")
            .navigationDestination(for: SidebarItem.self) { item in
                TaskListView(scope: item, selection: .constant(nil))
            }
            .navigationDestination(for: TemplateRoute.self) { route in
                switch route {
                case .library:
                    TemplateLibraryView()
                case .template(let uid):
                    TemplateDetailView(templateUID: uid)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newListSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("New list"))
                }
            }
            .sheet(isPresented: $newListSheet) {
                NavigationStack {
                    ListEditorView(list: nil)
                }
            }
            .sheet(isPresented: $newTemplateSheet) {
                NavigationStack {
                    TemplateEditorView(template: nil)
                }
            }
        }
    }

    // MARK: - Lists

    private var activeLists: [TodoList] {
        lists.filter { !$0.isFinished }
    }

    private var previousLists: [TodoList] {
        lists
            .filter(\.isFinished)
            .sorted { ($0.lastCompletedAt ?? .distantPast) > ($1.lastCompletedAt ?? .distantPast) }
    }

    /// Which run this was, and how long it took — the two things you want to
    /// know from a finished list without opening it.
    private var listsSection: some View {
        Section {
            if activeLists.isEmpty && lists.isEmpty {
                EmptyHint(
                    symbol: "square.stack",
                    title: String(localized: "No lists yet"),
                    message: String(localized: "Lists hold the tasks that belong together. Create one, or start from a template.")
                )
            }

            ForEach(activeLists) { list in
                NavigationLink(value: SidebarItem.list(list.uid)) {
                    listRow(list)
                }
                .contextMenu {
                    Button {
                        WorkspaceService.saveAsTemplate(from: list, in: context)
                    } label: {
                        Label("Save as template", systemImage: "square.on.square.dashed")
                    }
                    Divider()
                    Button(role: .destructive) {
                        WorkspaceService.delete(list, in: context)
                    } label: {
                        Label("Delete list", systemImage: "trash")
                    }
                }
            }

            Button {
                newListSheet = true
            } label: {
                Label {
                    Text("New list")
                } icon: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                .font(.subheadline.weight(.medium))
            }
        } header: {
            SectionHeader(title: String(localized: "My lists"), count: activeLists.count)
        }
    }

    private var previousSection: some View {
        Section {
            NavigationLink {
                PreviousListsView()
            } label: {
                HStack(spacing: 12) {
                    ListGlyph(symbol: "checkmark.circle", color: Palette.mint, size: 28)
                    Text("Previous ToDos")
                        .font(.subheadline)
                    Spacer()
                    CountBadge(value: previousLists.count)
                }
            }
        }
    }

    // MARK: - Templates

    private var templatesSection: some View {
        Section {
            ForEach(templates.prefix(3)) { template in
                NavigationLink(value: TemplateRoute.template(template.uid)) {
                    templateRow(template)
                }
            }

            NavigationLink(value: TemplateRoute.library) {
                Label {
                    Text("Template library")
                } icon: {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(Theme.accent)
                }
                .font(.subheadline.weight(.medium))
            }

            Button {
                newTemplateSheet = true
            } label: {
                Label {
                    Text("New template")
                } icon: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.mint)
                }
                .font(.subheadline.weight(.medium))
            }
        } header: {
            SectionHeader(title: String(localized: "Templates"), count: templates.count)
        } footer: {
            Text("A template is a list you can pull into your workspace again and again — with its checklist already written.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Rows

    private func listRow(_ list: TodoList) -> some View {
        HStack(spacing: 12) {
            ListGlyph(symbol: list.symbol, color: ListPalette.color(list.colorHex))
            VStack(alignment: .leading, spacing: 1) {
                Text(list.title)
                    .font(.subheadline)
                if list.isFinished {
                    Text("All done")
                        .font(.caption2)
                        .foregroundStyle(Theme.mint)
                } else if let period = list.periodDate {
                    Text(period.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            DeadlineBadge(list: list)
            CountBadge(value: list.openTaskCount)
        }
    }

    private func templateRow(_ template: ListTemplate) -> some View {
        HStack(spacing: 12) {
            ListGlyph(symbol: template.symbol, color: ListPalette.color(template.colorHex), size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(template.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(template.taskCount) · \(template.checkCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// Navigation value for the template section.
enum TemplateRoute: Hashable {
    case library
    case template(UUID)
}

/// Template library presented on its own, e.g. from the empty home screen.
struct TemplateLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TemplateLibraryView()
                .navigationDestination(for: TemplateRoute.self) { route in
                    switch route {
                    case .library:
                        TemplateLibraryView()
                    case .template(let uid):
                        TemplateDetailView(templateUID: uid)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
