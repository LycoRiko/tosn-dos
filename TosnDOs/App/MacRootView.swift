#if os(macOS)
import SwiftUI
import SwiftData

/// Mac shell: sidebar → list → detail, like Mail and Reminders.
struct MacRootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TodoList.sortIndex) private var lists: [TodoList]
    @Query(sort: \Tag.name) private var tags: [Tag]
    @Query(sort: \ListTemplate.updatedAt, order: .reverse) private var templates: [ListTemplate]

    @State private var selection: SidebarItem? = .smart(.today)
    @State private var selectedTask: TodoItem?
    @State private var selectedTemplateUID: UUID?
    @State private var showsNewList = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 300)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 560)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: primaryAction) {
                            Image(systemName: "plus")
                        }
                        .keyboardShortcut("n", modifiers: .command)
                        .help(Text(isTemplateScope ? "New template" : "New task"))
                    }
                }
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 560)
        }
        .onChange(of: selection) { _, _ in
            selectedTask = nil
        }
        .sheet(isPresented: $showsNewList) {
            NavigationStack {
                ListEditorView(list: nil)
            }
            .frame(width: 560)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label(SmartList.today.title, systemImage: SmartList.today.symbol)
                    .tag(SidebarItem.smart(.today))
            }

            Section {
                ForEach(lists.filter { !$0.isFinished }) { list in
                    HStack(spacing: 8) {
                        Image(systemName: list.symbol)
                            .foregroundStyle(ListPalette.color(list.colorHex))
                            .frame(width: 16)
                        Text(list.title)
                        Spacer(minLength: 4)
                        if list.openTaskCount > 0 {
                            Text("\(list.openTaskCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .tag(SidebarItem.list(list.uid))
                    .contextMenu {
                        Button {
                            WorkspaceService.saveAsTemplate(from: list, in: context)
                        } label: {
                            Label("Save as template", systemImage: "square.on.square.dashed")
                        }
                        Divider()
                        Button(role: .destructive) {
                            if selection == .list(list.uid) { selection = .smart(.today) }
                            WorkspaceService.delete(list, in: context)
                        } label: {
                            Label("Delete list", systemImage: "trash")
                        }
                    }
                }

                Button {
                    showsNewList = true
                } label: {
                    Label("New list", systemImage: "plus")
                }
                .buttonStyle(.plain)
            } header: {
                Text("My lists")
            }

            // Same page as iOS: the finished lists live behind one entry instead
            // of filling the sidebar once there are a few dozen of them.
            if !lists.filter(\.isFinished).isEmpty {
                Section {
                    NavigationLink {
                        PreviousListsView()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(Palette.mint)
                                .frame(width: 16)
                            Text("Previous ToDos")
                            Spacer(minLength: 4)
                            Text("\(lists.filter(\.isFinished).count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section {
                Label("Template library", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.templates)
            } header: {
                Text("Templates")
            }

            if !tags.isEmpty {
                Section {
                    ForEach(tags) { tag in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(ListPalette.color(tag.colorHex))
                                .frame(width: 7, height: 7)
                            Text(tag.name)
                        }
                        .tag(SidebarItem.tag(tag.uid))
                    }
                } header: {
                    Text("Tags")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Tos'n DOs")
    }

    // MARK: - Content

    private var isTemplateScope: Bool {
        selection == .templates
    }

    @ViewBuilder
    private var content: some View {
        if isTemplateScope {
            TemplateLibraryView { template in
                selectedTemplateUID = template.uid
            }
        } else if selection == nil || selection == .smart(.today) {
            HomeView(selection: $selectedTask)
        } else {
            TaskListView(
                scope: selection ?? .smart(.today),
                selection: $selectedTask
            )
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if isTemplateScope {
            if let uid = selectedTemplateUID {
                NavigationStack {
                    TemplateDetailView(templateUID: uid)
                }
            } else {
                placeholder(
                    symbol: "square.on.square.dashed",
                    title: String(localized: "No template selected"),
                    message: String(localized: "Pick a template to preview its checklist.")
                )
            }
        } else if let task = selectedTask {
            NavigationStack {
                TaskEditorView(task: task) {
                    selectedTask = nil
                }
            }
        } else {
            placeholder(
                symbol: "square.dashed",
                title: String(localized: "No task selected"),
                message: String(localized: "Pick a task to see its details.")
            )
        }
    }

    private func placeholder(symbol: String, title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
        .background(AppBackground())
    }

    // MARK: - Actions

    private func primaryAction() {
        if isTemplateScope {
            // Creating from the content column is handled inside the library.
            return
        }
        addTask()
    }

    private func addTask() {
        let scope = selection ?? .smart(.today)
        let list = lists.first { $0.uid == scope.listUID }
        let due: Date? = scope.smartList == .today ? Calendar.current.startOfDay(for: .now) : nil

        let task = TodoItem(
            title: "",
            dueDate: due,
            priority: .none,
            list: list,
            sortIndex: WorkspaceService.nextTaskIndex(in: list)
        )
        context.insert(task)
        try? context.save()
        selectedTask = task
    }
}
#endif
