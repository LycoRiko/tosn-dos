import SwiftUI
import SwiftData

/// What was written down on a given day, outside the template runs.
/// The previous page lists finished *lists*; this covers everything that never
/// belonged to one of those, so a day does not look emptier than it was.
struct DayTasksView: View {
    let day: Date

    @Query(sort: \TodoItem.createdAt, order: .reverse) private var tasks: [TodoItem]

    private var added: [TodoItem] {
        let calendar = Calendar.current
        return tasks.filter { task in
            calendar.isDate(task.createdAt, inSameDayAs: day)
                && !(task.list?.isFinished ?? false)
        }
    }

    var body: some View {
        List {
            if added.isEmpty {
                Section {
                    EmptyHint(
                        symbol: "tray",
                        title: String(localized: "Nothing added that day"),
                        message: String(localized: "Tasks you type on the Today screen show up here.")
                    )
                }
            } else {
                Section {
                    ForEach(added) { task in
                        row(task)
                    }
                }
            }
        }
        .groupedRows()
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 92, for: .scrollContent)
        .background(AppBackground())
        .navigationTitle(day.formatted(.dateTime.month(.abbreviated).day()))
    }

    private func row(_ task: TodoItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(task.isCompleted ? AnyShapeStyle(Theme.mint) : AnyShapeStyle(.tertiary))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title.isEmpty ? String(localized: "Untitled") : task.title)
                    .font(.subheadline)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted, color: .secondary)
                HStack(spacing: 6) {
                    if let name = task.list?.title {
                        Text(name)
                    }
                    Text(task.createdAt.formatted(date: .omitted, time: .shortened))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(task.isCompleted ? "Completed" : "Open"))
    }
}
