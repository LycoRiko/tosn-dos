import SwiftUI
import SwiftData

/// Template preview. Read-only by design: you inspect the checklist, then
/// pull it into the workspace with one tap.
struct TemplateDetailView: View {
    let templateUID: UUID

    @Query private var templates: [ListTemplate]
    @Environment(\.modelContext) private var context

    @State private var showsInstantiate = false

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
        .background(AppBackground())
        .navigationTitle(template?.title ?? String(localized: "Template"))
        .toolbar {
            if let template {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showsInstantiate = true
                    } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    .accessibilityLabel(Text("Add to workspace"))
                }
            }
        }
        .sheet(isPresented: $showsInstantiate) {
            if let template {
                TemplateInstantiateSheet(template: template)
            }
        }
    }

    private func content(_ template: ListTemplate) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(template)

                if template.orderedItems.isEmpty {
                    EmptyHint(
                        symbol: "square.and.pencil",
                        title: String(localized: "Nothing written yet"),
                        message: String(localized: "Add tasks and checks to this template.")
                    )
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(template.orderedItems) { item in
                            itemBlock(item)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 96)
        }
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

    private func itemBlock(_ item: TemplateItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "circle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.tertiary)
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                if item.priority != .none {
                    Circle()
                        .fill(item.priority.color)
                        .frame(width: 5, height: 5)
                }
            }

            if !item.note.isEmpty {
                Text(item.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }

            if !item.orderedChecks.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(item.orderedChecks) { check in
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark.square")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                            Text(check.title)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 2)
    }
}
