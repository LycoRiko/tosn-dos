import SwiftUI
import SwiftData

/// Everything finished, grouped by the day it was finished — plus, under each
/// day, what was typed in by hand that day. Kept out of Browse: at three entries
/// it was a nice list, at thirty it was the whole page.
struct PreviousListsView: View {
    @Query private var lists: [TodoList]
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var tasks: [TodoItem]

    private struct Group: Identifiable {
        let day: Date
        let lists: [TodoList]
        let added: [TodoItem]
        var id: Date { day }
    }

    private var finished: [TodoList] {
        lists
            .filter(\.isFinished)
            .sorted { ($0.completedAt ?? $0.lastCompletedAt ?? .distantPast) > ($1.completedAt ?? $1.lastCompletedAt ?? .distantPast) }
    }

    /// Tasks typed on the Today screen, which never belong to a finished list.
    private var added: [TodoItem] {
        tasks.filter { !($0.list?.isFinished ?? false) }
    }

    private var groups: [Group] {
        let calendar = Calendar.current
        var days = Set(finished.map { calendar.startOfDay(for: $0.completedAt ?? $0.createdAt) })
        for task in added {
            days.insert(calendar.startOfDay(for: task.createdAt))
        }

        return days.sorted(by: >).map { day in
            Group(
                day: day,
                lists: finished.filter { calendar.startOfDay(for: $0.completedAt ?? $0.createdAt) == day },
                added: added.filter { calendar.isDate($0.createdAt, inSameDayAs: day) }
            )
        }
    }

    var body: some View {
        List {
            if groups.isEmpty {
                Section {
                    EmptyHint(
                        symbol: "checkmark.circle",
                        title: String(localized: "Nothing checked off yet"),
                        message: String(localized: "When every task in a list is done, the list moves here so you can look back at it.")
                    )
                }
            } else {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.lists) { list in
                            row(list)
                        }
                        if !group.added.isEmpty {
                            NavigationLink {
                                DayTasksView(day: group.day)
                            } label: {
                                HStack(spacing: 12) {
                                    ListGlyph(symbol: "square.and.pencil", color: Theme.accent, size: 28)
                                    Text("Added that day")
                                        .font(.subheadline)
                                    Spacer()
                                    CountBadge(value: group.added.count)
                                }
                            }
                        }
                    } header: {
                        Text(dayTitle(group.day))
                    }
                }
            }
        }
        .groupedRows()
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 92, for: .scrollContent)
        .background(AppBackground())
        .navigationTitle("Previous ToDos")
    }

    private func row(_ list: TodoList) -> some View {
        NavigationLink(value: SidebarItem.list(list.uid)) {
            HStack(spacing: 12) {
                ListGlyph(symbol: "checkmark", color: Palette.mint, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(list.title)
                        .font(.subheadline)
                    if let detail = subtitle(list) {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                CountBadge(value: list.tasks?.count ?? 0)
            }
        }
    }

    /// The header already carries the day, so this line holds only the template
    /// name (what tells two runs apart) and time spent.
    private func subtitle(_ list: TodoList) -> String? {
        var parts: [String] = []
        if !list.sourceTemplateName.isEmpty { parts.append(list.sourceTemplateName) }
        if let seconds = list.workedDuration, seconds >= 60 {
            parts.append(DurationFormat.short(seconds))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.month(.abbreviated).day())
    }
}
