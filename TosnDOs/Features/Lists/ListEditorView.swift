import SwiftUI
import SwiftData

/// Create or rename a list. Symbol and color are the only decoration the app
/// allows, which keeps lists recognisable without turning them into artwork.
struct ListEditorView: View {
    var list: TodoList?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var title = ""
    @State private var notes = ""
    @State private var symbol = "list.bullet"
    @State private var colorHex = ListPalette.colors[0]
    @State private var colorValue = ListPalette.color(ListPalette.colors[0])
    @State private var showsAllIcons = false
    @State private var background = BackgroundSetting.plain
    @State private var hasDeadline = false
    @State private var deadline = Date.now.addingTimeInterval(86_400)
    @State private var remindBeforeDeadline = false
    @State private var leadMinutes = 1440

    private var isNew: Bool { list == nil }

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 10)]

    /// Two rows up front; the rest stays behind a disclosure so the sheet does
    /// not open as a wall of symbols.
    private var visibleSymbols: [String] {
        showsAllIcons ? ListSymbols.all : Array(ListSymbols.all.prefix(12))
    }

    var body: some View {
        List {
            Section {
                TextField("List name", text: $title)
                    .font(.body.weight(.medium))
                TextField("Description (optional)", text: $notes, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(1...3)
            }

            Section {
                Toggle("Deadline", isOn: $hasDeadline.animation())

                if hasDeadline {
                    DatePicker("Date", selection: $deadline)
                    Toggle("Remind me before this deadline", isOn: $remindBeforeDeadline.animation())

                    if remindBeforeDeadline {
                        Picker("Notify", selection: $leadMinutes) {
                            ForEach(NotificationService.leadChoices, id: \.self) { minutes in
                                Text(NotificationService.title(forLead: minutes)).tag(minutes)
                            }
                        }
                    }
                }
            } header: {
                Text("Deadline")
            } footer: {
                Text("A deadline belongs to this list, not to a single task.")
                    .font(.footnote)
            }

            Section {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(visibleSymbols, id: \.self) { name in
                        Button {
                            symbol = name
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(symbol == name ? Color.white : Color.primary.opacity(0.75))
                                .frame(width: 40, height: 40)
                                .background(
                                    symbol == name ? AnyShapeStyle(ListPalette.color(colorHex)) : AnyShapeStyle(Color.primary.opacity(0.06)),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(name))
                        .accessibilityAddTraits(symbol == name ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)

                if ListSymbols.all.count > visibleSymbols.count || showsAllIcons {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            showsAllIcons.toggle()
                        }
                    } label: {
                        Text(showsAllIcons ? "Show less" : "More icons")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
            } header: {
                Text("Icon")
            }

            Section {
                ColorPicker(selection: $colorValue, supportsOpacity: false) {
                    Text("List color")
                }
                .onChange(of: colorValue) { _, newValue in
                    colorHex = newValue.hexInt
                }
            } header: {
                Text("Color")
            }

            Section {
                BackgroundPicker(setting: $background)
            } header: {
                Text("Background")
            } footer: {
                Text("Only this list uses this photo. Without one it follows the app background.")
                    .font(.footnote)
            }
        }
        .groupedRows()
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        // A `List` is flexible, and a macOS sheet sizes itself from its content:
        // without a floor the list measures zero and the sheet opens empty.
        .frame(minHeight: 540)
        .navigationTitle(isNew ? "New list" : "Edit list")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard let list else { return }
            title = list.title
            notes = list.notes
            symbol = list.symbol
            colorHex = list.colorHex
            colorValue = ListPalette.color(list.colorHex)
            background = list.backgroundSetting
            hasDeadline = list.deadline != nil
            deadline = list.deadline ?? Date.now.addingTimeInterval(86_400)
            remindBeforeDeadline = list.deadlineReminderEnabled
            leadMinutes = list.deadlineLeadMinutes
        }
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let target: TodoList
        if let list {
            list.title = name
            list.notes = notes
            list.symbol = symbol
            list.colorHex = colorHex
            list.applyBackground(background)
            target = list
        } else {
            target = WorkspaceService.createList(title: name, symbol: symbol, colorHex: colorHex, in: context)
            target.applyBackground(background)
        }

        target.deadline = hasDeadline ? deadline : nil
        target.deadlineReminderEnabled = hasDeadline && remindBeforeDeadline
        target.deadlineLeadMinutes = leadMinutes
        try? context.save()

        Task { await NotificationService.apply(target) }
        dismiss()
    }
}
