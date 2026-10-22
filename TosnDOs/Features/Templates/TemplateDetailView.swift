import SwiftUI
import SwiftData

/// Template preview. Read-only by design: you inspect the checklist, then
/// pull it into the workspace with one tap.
struct TemplateDetailView: View {
    let templateUID: UUID

    @Query private var templates: [ListTemplate]
    @Environment(\.modelContext) private var context

    @State private var showsInstantiate = false
    @State private var showsEditor = false
    @State private var editingItem: TemplateItem?
    @FocusState private var focusedItem: UUID?

    private var template: ListTemplate? {
        templates.first { $0.uid == templateUID }
    }

    var body: some View {
        Group {
            if let template {
                content(template)
            } else {
                EmptyHint(
                    symbol: "questionmark.folder",
                    title: String(localized: "Template not found"),
                    message: String(localized: "It may have been deleted.")
                )
            }
        }
        // A row the user tapped but never filled in should not survive: it reads
        // as a stray bullet and would be copied into every new list.
        .onChange(of: focusedItem) { previous, _ in
            pruneIfEmpty(previous)
        }
        .background(AppBackground())
        .navigationTitle(template?.title ?? String(localized: "Template"))
        .toolbar {
            if template != nil {
                // Editing used to live only behind the library's context menu,
                // which left the detail screen with two identical "add to
                // workspace" buttons and no way to put tasks in the template.
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsEditor = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(Text("Edit"))
                }
            }
        }
        .sheet(isPresented: $showsEditor) {
            if let template {
                NavigationStack {
                    TemplateEditorView(template: template)
                }
            }
        }
        .sheet(item: $editingItem) { item in
            TemplateItemSheet(item: item)
        }
        .sheet(isPresented: $showsInstantiate) {
            if let template {
                TemplateInstantiateSheet(template: template)
            }
        }
    }

    private func content(_ template: ListTemplate) -> some View {
        // A List, not a ScrollView: swipe-to-delete is the expected way to
        // remove a row, and only List gives it for free (with VoiceOver support).
        List {
            header(template)
                .rowChrome()

            if template.orderedItems.isEmpty {
                EmptyHint(
                    symbol: "square.and.pencil",
                    title: String(localized: "Nothing written yet"),
                    message: String(localized: "Add tasks and checks to this template.")
                )
                .rowChrome()
            } else {
                ForEach(template.orderedItems) { item in
                    itemBlock(item, in: template)
                        .rowChrome()
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                editingItem = item
                            } label: {
                                Label("Settings", systemImage: "slider.horizontal.3")
                            }

                            Button(role: .destructive) {
                                context.delete(item)
                                touch(template)
                            } label: {
                                Label("Delete task", systemImage: "trash")
                            }
                        }
                }
            }

            addTaskButton(template)
                .rowChrome()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        #if os(iOS)
        .modifier(KeyboardDismissScroll())
        #endif
        .safeAreaInset(edge: .bottom) {
            Button {
                showsInstantiate = true
            } label: {
                Label("Add to workspace", systemImage: "plus")
            }
            .buttonStyle(PrimaryActionStyle())
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial.opacity(0.001))
        }
    }

    private func header(_ template: ListTemplate) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ListGlyph(symbol: template.symbol, color: ListPalette.color(template.colorHex), size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                        .font(.title3.weight(.bold))
                    if !template.summary.isEmpty {
                        Text(template.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 18) {
                stat(value: "\(template.taskCount)", label: String(localized: "tasks"))
                stat(value: "\(template.checkCount)", label: String(localized: "checks"))
                stat(value: "\(template.usageCount)", label: String(localized: "uses"))
                Spacer(minLength: 0)
            }
        }
        .glassCard(radius: Theme.radius, padding: 18)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func itemBlock(_ item: TemplateItem, in template: ListTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        if item.priority == .high {
                            Image(systemName: "exclamationmark.2")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(TaskPriority.high.color)
                                .accessibilityHidden(true)
                        }
                        TextField("Task name", text: Binding(
                            get: { item.title },
                            set: { item.title = $0; touch(template) }
                        ))
                        .font(.subheadline.weight(.medium))
                        .focused($focusedItem, equals: item.uid)
                        .submitLabel(.next)
                        .onSubmit { addItem(to: template) }
                    }

                    if !item.note.isEmpty || !item.orderedChecks.isEmpty {
                        HStack(spacing: 6) {
                            if !item.orderedChecks.isEmpty {
                                MetaChip(icon: "checklist", text: "\(item.orderedChecks.count)")
                            }
                            if !item.note.isEmpty {
                                Text(item.note)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                editingItem = item
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive) {
                context.delete(item)
                touch(template)
            } label: {
                Label("Delete task", systemImage: "trash")
            }
        }
    }

    private func addTaskButton(_ template: ListTemplate) -> some View {
        Button {
            addItem(to: template)
        } label: {
            Label("Add task", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.medium))
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
    }

    /// Adding happens on this screen: the pencil is for the template's own
    /// properties, and making people open it to type a task was a dead end.
    private func addItem(to template: ListTemplate) {
        // Returning on an untouched row should not stack a second empty one.
        if let current = focusedItem,
           let existing = template.orderedItems.first(where: { $0.uid == current }),
           existing.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            focusedItem = existing.uid
            return
        }

        let item = TemplateItem(title: "", sortIndex: Double(template.taskCount))
        context.insert(item)
        item.template = template
        touch(template)
        focusedItem = item.uid
    }

    private func pruneIfEmpty(_ uid: UUID?) {
        guard let uid, let template,
              let item = template.orderedItems.first(where: { $0.uid == uid }),
              item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        context.delete(item)
        touch(template)
    }

    private func touch(_ template: ListTemplate) {
        template.updatedAt = .now
        try? context.save()
    }
}

private extension View {
    /// These rows are layout containers, not table cells: no separator, no
    /// background, page padding instead of the default inset.
    func rowChrome() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: Theme.pagePadding, bottom: 6, trailing: Theme.pagePadding))
    }
}
