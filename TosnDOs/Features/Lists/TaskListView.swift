import SwiftUI
import SwiftData
#if os(macOS)
import UniformTypeIdentifiers
#endif

/// The single task list renderer, used by the iPhone tabs and the Mac
/// content column. Both platforms share the rows, the grouping and the
/// quick-add bar; only the tap behaviour differs.
struct TaskListView: View {
    let scope: SidebarItem
    @Binding var selection: TodoItem?

    @Query(sort: \TodoItem.sortIndex) private var allTasks: [TodoItem]
    @Query(sort: \TodoList.sortIndex) private var lists: [TodoList]
    @Query(sort: \Tag.name) private var tags: [Tag]

    @AppStorage(PreferenceKey.showCompleted) private var showCompleted = true
    @AppStorage(BackgroundKey.imageName) private var globalBackground = ""
    @Environment(\.modelContext) private var context

    @State private var search = ""
    @State private var editingTask: TodoItem?
    @State private var showsNewList = false
    @State private var showsTemplates = false
    @State private var showsQR = false
    #if os(macOS)
    @State private var isDropTargeted = false
    #endif

    // MARK: - Derived state

    private var currentList: TodoList? {
        guard let uid = scope.listUID else { return nil }
        return lists.first { $0.uid == uid }
    }

    private var currentTag: Tag? {
        guard let uid = scope.tagUID else { return nil }
        return tags.first { $0.uid == uid }
    }

    private var title: String {
        if let smart = scope.smartList { return smart.title }
        if let list = currentList { return list.title }
        if let tag = currentTag { return tag.name }
        return String(localized: "Templates")
    }

    private var showsListName: Bool {
        scope.listUID == nil
    }

    private var filtered: [TodoItem] {
        TaskQuery.items(from: allTasks, scope: scope, lists: lists, tags: tags, search: search)
    }

    private var sections: [TaskSection] {
        TaskQuery.sections(from: filtered, scope: scope, showCompleted: showCompleted)
    }

    private var targetList: TodoList? { currentList }

    private var defaultDue: Date? {
        scope.smartList == .today ? Calendar.current.startOfDay(for: .now) : nil
    }

    private var photoBackground: Bool {
        let listName = currentList?.backgroundImageName ?? ""
        return listName.isEmpty ? !globalBackground.isEmpty : true
    }

    private var isEmptyWorkspace: Bool {
        allTasks.isEmpty && lists.isEmpty
    }

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        List {
            if scope.smartList == .today, !isSearching {
                Section {
                    TodayHero(
                        remaining: todaySnapshot.remaining,
                        done: todaySnapshot.done,
                        progress: todaySnapshot.progress
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: Theme.pagePadding, bottom: 10, trailing: Theme.pagePadding))
            }

            if let list = currentList, !(list.tasks ?? []).isEmpty, !isSearching {
                Section {
                    listSummary(list)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: Theme.pagePadding, bottom: 8, trailing: Theme.pagePadding))
            }

            if sections.isEmpty {
                Section {
                    VStack(spacing: 4) {
                        EmptyHint(
                            symbol: isSearching ? "magnifyingglass" : emptySymbol,
                            title: isSearching ? String(localized: "No matches") : emptyTitle,
                            message: isSearching ? String(localized: "Try a different word.") : emptyMessage
                        )
                        if isEmptyWorkspace && !isSearching {
                            VStack(spacing: 2) {
                                Button("New list") { showsNewList = true }
                                    .buttonStyle(PrimaryActionStyle())
                                Button("Start from a template") { showsTemplates = true }
                                    .buttonStyle(QuietActionStyle())
                            }
                            .padding(.horizontal, 28)
                            .padding(.bottom, 16)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { task in
                            row(task)
                        }
                    } header: {
                        SectionHeader(title: section.kind.title, count: section.items.count)
                            .padding(.top, 6)
                    }
                }
            }

            Color.clear
                .frame(height: 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // On iPad the rows stretched edge to edge, which left a lot of dead space
        // and very long lines. Cap the column, then let it centre.
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(AppBackground(setting: currentList?.backgroundSetting))
        .environment(\.photoBackground, photoBackground)
        .navigationTitle(title)
        .toolbar {
            if let list = currentList {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ShareLink(item: ListShareText.make(for: list)) {
                            Label("Share as text", systemImage: "square.and.arrow.up")
                        }
                        // QR only: the bare base64 string was too long to paste
                        // anywhere, and the camera path needs no paste at all.
                        Button {
                            showsQR = true
                        } label: {
                            Label("Show QR code", systemImage: "qrcode")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(Text("More"))
                }
            }
        }
        .searchable(text: $search, prompt: Text("Search tasks"))
        #if os(macOS)
        // Dragging a QR image in is the Mac's answer to scanning: no camera,
        // no permission, and Core Image does the decoding.
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 3)
                        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Label("Drop a QR image or a backup", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                }
                .padding(12)
                .allowsHitTesting(false)
            }
        }
        #endif
        .sheet(isPresented: $showsQR) {
            if let list = currentList {
                QRSheet(title: list.title, code: ListCodec.encode(list))
                    .compactSheetDetents()
            }
        }
        #if os(iOS)
        .modifier(KeyboardDismissScroll())
        .dismissKeyboardOnTap()
        #endif
        .safeAreaInset(edge: .bottom, spacing: 0) {
            QuickAddBar(targetList: targetList, defaultDue: defaultDue)
        }
        .sheet(item: $editingTask) { task in
            NavigationStack {
                TaskEditorView(task: task)
            }
        }
        .sheet(isPresented: $showsNewList) {
            NavigationStack {
                ListEditorView(list: nil)
            }
        }
        .sheet(isPresented: $showsTemplates) {
            TemplateLibrarySheet()
        }
    }

    // MARK: - Rows

    #if os(macOS)
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard
                    let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil),
                    let contents = try? Data(contentsOf: url)
                else { return }
                let name = url.lastPathComponent
                Task { @MainActor in importPayload(contents, fileName: name) }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in importPayload(data, fileName: "") }
            }
            return true
        }
        return false
    }

    /// One drop target, two formats: a backup JSON restores the whole workspace,
    /// an image is read as a QR. The JSON check comes first — a backup is never
    /// a valid QR, while a QR screenshot is never valid JSON.
    @MainActor
    private func importPayload(_ data: Data, fileName: String) {
        if fileName.lowercased().hasSuffix(".json"), let backup = try? BackupFile.decode(data) {
            backup.restore(into: context, mode: .merge)
            return
        }

        guard
            let message = QRCode.message(in: data),
            let code = QRCode.code(from: message),
            let snapshot = ListCodec.decode(code)
        else { return }

        let existing = (try? context.fetch(FetchDescriptor<TodoList>())) ?? []
        let next = (existing.map(\.sortIndex).max() ?? 0) + 1
        ListCodec.importList(snapshot, into: context, sortIndex: next)
    }
    #endif

    private func row(_ task: TodoItem) -> some View {
        TaskRow(task: task, showsListName: showsListName)
            .listRowInsets(EdgeInsets(top: 0, leading: Theme.pagePadding, bottom: 0, trailing: Theme.pagePadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .tag(task)
            .contentShape(Rectangle())
            .onTapGesture { open(task) }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    open(task)
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }

                Button(role: .destructive) {
                    WorkspaceService.delete(task, in: context)
                } label: {
                    Label("Delete task", systemImage: "trash")
                }
            }
            .contextMenu {
                Button {
                    toggleCompletion(task)
                } label: {
                    Label(task.isCompleted ? "Reopen" : "Complete", systemImage: "checkmark.circle")
                }
                Button {
                    moveToTomorrow(task)
                } label: {
                    Label("Move to tomorrow", systemImage: "sunrise")
                }
                Divider()
                Button(role: .destructive) {
                    WorkspaceService.delete(task, in: context)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private func listSummary(_ list: TodoList) -> some View {
        HStack(spacing: 12) {
            ProgressRing(progress: list.progress, size: 38, lineWidth: 4.5, showsLabel: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(summaryLine(list))
                    .font(.subheadline.weight(.medium))
                if list.waitingCount > 0 {
                    Text("\(list.waitingCount) waiting")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !list.notes.isEmpty {
                    Text(list.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            DeadlineBadge(list: list)
        }
        .padding(.vertical, 4)
    }

    private func summaryLine(_ list: TodoList) -> String {
        if list.isFinished { return String(localized: "All done") }
        return String(localized: "\(list.doneTaskCount) of \(list.actionableTasks.count) done")
    }

    // MARK: - Today numbers

    /// Shared with the widget so the hero and the home screen always agree.
    private var todaySnapshot: TodaySnapshot {
        TaskQuery.todaySnapshot(from: allTasks)
    }

    // MARK: - Empty copy

    private var emptySymbol: String {
        if let smart = scope.smartList {
            switch smart {
            case .today: return "sun.max"
            case .upcoming: return "calendar"
            case .all: return "square.stack.3d.up"
            case .completed: return "checkmark.circle"
            }
        }
        return "checklist"
    }

    private var emptyTitle: String {
        if let smart = scope.smartList {
            switch smart {
            // The hero card above already says "Nothing due today"; repeating it here reads as a stutter.
            case .today: return String(localized: "No open tasks")
            case .upcoming: return String(localized: "Nothing scheduled")
            case .all: return String(localized: "No open tasks")
            case .completed: return String(localized: "Nothing completed yet")
            }
        }
        return String(localized: "This list is empty")
    }

    private var emptyMessage: String {
        if let smart = scope.smartList, smart == .completed {
            return String(localized: "Finished tasks collect here.")
        }
        return String(localized: "Type below to add the first one.")
    }

    // MARK: - Actions

    private func open(_ task: TodoItem) {
        #if os(macOS)
        selection = task
        #else
        editingTask = task
        #endif
    }

    private func toggleCompletion(_ task: TodoItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            task.setCompleted(!task.isCompleted)
        }
        try? context.save()
    }

    private func moveToTomorrow(_ task: TodoItem) {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            task.dueDate = base
            task.hasDueTime = false
        }
        try? context.save()
    }
}
