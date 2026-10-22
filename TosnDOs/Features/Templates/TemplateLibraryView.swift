import SwiftUI
import SwiftData

/// The template shelf. A template is never mixed into normal lists —
/// it only becomes a list when the user pulls it in.
struct TemplateLibraryView: View {
    var onSelect: ((ListTemplate) -> Void)?

    @Query(sort: \ListTemplate.updatedAt, order: .reverse) private var templates: [ListTemplate]
    @Environment(\.modelContext) private var context

    @State private var editorTemplate: ListTemplate?
    @State private var showsNewEditor = false

    private let columns = [GridItem(.adaptive(minimum: 148), spacing: 12)]

    var body: some View {
        List {
            if templates.isEmpty {
                Section {
                    EmptyHint(
                        symbol: "square.on.square.dashed",
                        title: String(localized: "No templates yet"),
                        message: String(localized: "Write a checklist once, then pull a fresh copy whenever you need it.")
                    )
                    Button {
                        showsNewEditor = true
                    } label: {
                        Text("New template")
                    }
                }
            } else {
                Section {
                    ForEach(templates) { template in
                        card(template)
                            .listRowInsets(EdgeInsets(top: 4, leading: Theme.pagePadding, bottom: 4, trailing: Theme.pagePadding))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    editorTemplate = template
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    WorkspaceService.delete(template, in: context)
                                } label: {
                                    Label("Delete template", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { offsets in
                        for index in offsets where index < templates.count {
                            WorkspaceService.delete(templates[index], in: context)
                        }
                    }

                    Button {
                        showsNewEditor = true
                    } label: {
                        Label("New template", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Templates")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsNewEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("New template"))
            }
        }
        .sheet(isPresented: $showsNewEditor) {
            NavigationStack {
                TemplateEditorView(template: nil)
            }
        }
        .sheet(item: $editorTemplate) { template in
            NavigationStack {
                TemplateEditorView(template: template)
            }
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private func card(_ template: ListTemplate) -> some View {
        let content = compactRow(template)
            .contextMenu {
                Button {
                    editorTemplate = template
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button {
                    _ = WorkspaceService.duplicate(template: template, in: context)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Divider()
                Button(role: .destructive) {
                    WorkspaceService.delete(template, in: context)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

        if let onSelect {
            Button { onSelect(template) } label: { content }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: TemplateRoute.template(template.uid)) {
                content
            }
            .buttonStyle(.plain)
        }
    }

    /// A full-width row rather than the grid card: a 148pt card stretched to
    /// screen width grows into a lot of empty tile.
    private func compactRow(_ template: ListTemplate) -> some View {
        HStack(spacing: 12) {
            ListGlyph(symbol: template.symbol, color: ListPalette.color(template.colorHex), size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title)
                    .font(.subheadline)
                HStack(spacing: 6) {
                    MetaChip(icon: "list.bullet", text: "\(template.taskCount)")
                    MetaChip(icon: "checkmark.square", text: "\(template.checkCount)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var newCard: some View {
        Button {
            showsNewEditor = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Text("New template")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 124)
            .background {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(0.12),
                        style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

struct TemplateCard: View {
    let template: ListTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ListGlyph(symbol: template.symbol, color: ListPalette.color(template.colorHex), size: 32)

            Text(template.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text("\(template.taskCount)")
                    .monospacedDigit()
                Text("tasks")
                if template.checkCount > 0 {
                    Text("·")
                    Text("\(template.checkCount)")
                        .monospacedDigit()
                    Text("checks")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 124)
        .glassCard(radius: Theme.radius, padding: 14)
    }
}
