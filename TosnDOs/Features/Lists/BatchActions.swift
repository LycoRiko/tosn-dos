import SwiftUI
import SwiftData

/// The bar that replaces quick-add while a selection is active. Four verbs is
/// the whole vocabulary: when, where, done, gone.
struct BatchActionBar: View {
    var count: Int
    var onDate: () -> Void
    var onMove: () -> Void
    var onComplete: () -> Void
    var onDelete: () -> Void

    private var isEnabled: Bool { count > 0 }

    private var status: String {
        count == 0
            ? String(localized: "Select tasks")
            : String(localized: "\(count) selected")
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(status)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)

            Spacer(minLength: 0)

            item("calendar", "Date", action: onDate)
            item("folder", "Move", action: onMove)
            item("checkmark.circle", "Complete", action: onComplete)
            item("trash", "Delete", destructive: true, action: onDelete)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassPill()
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 8)
        .opacity(isEnabled ? 1 : 0.45)
        .allowsHitTesting(isEnabled)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: count)
        .accessibilityElement(children: .contain)
    }

    private func item(
        _ symbol: String,
        _ title: LocalizedStringKey,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 42, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(destructive ? Color.red : Theme.accent)
        .accessibilityLabel(Text(title))
    }
}

/// Batch date: one day for the whole selection. Ranges collapse to a single
/// deadline because a shared start would leave their ends pointing backwards.
struct BatchDateSheet: View {
    var count: Int
    var onApply: (Date, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()
    @State private var withTime = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $day, displayedComponents: .date)
                Toggle("Include a time", isOn: $withTime)
                if withTime {
                    DatePicker("Time", selection: $day, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("Move \(count) to a date")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(day, withTime)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .compactSheetDetents()
    }
}

/// Batch move: pick a destination list, newest tasks land at the end.
struct BatchMoveSheet: View {
    var count: Int
    var lists: [TodoList]
    var currentListUID: UUID?
    var onPick: (TodoList) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(lists) { list in
                    Button {
                        onPick(list)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ListGlyph(symbol: list.symbol, color: ListPalette.color(list.colorHex))
                            Text(list.title).font(.subheadline)
                            Spacer()
                            if list.uid == currentListUID {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Move \(count) to a list")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .compactSheetDetents()
    }
}
