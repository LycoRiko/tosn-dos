import Foundation

/// Lives in `Shared/` because the widget cannot import the app's navigation types.
enum TodayScope {

    /// A due date belongs to today when it falls before tomorrow's midnight,
    /// so anything overdue is rolled in.
    static func isDue(_ item: TodoItem, endOfToday: Date) -> Bool {
        // A range shows on every day it touches, so a shift running into tomorrow
        // does not vanish at midnight.
        if let end = item.endDate, let start = item.dueDate {
            let startOfToday = endOfToday.addingTimeInterval(-86_400)
            return start < endOfToday && end >= startOfToday
        }
        guard let due = item.focusDate else { return false }
        return due < endOfToday
    }

    static func endOfToday(_ now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    }

    /// Due date first, then priority, then insertion order. Both the hero and
    /// the widget read the order from here.
    static func sort(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { lhs, rhs in
            let l = lhs.focusDate ?? .distantFuture
            let r = rhs.focusDate ?? .distantFuture
            if l != r { return l < r }
            if lhs.priorityRaw != rhs.priorityRaw { return lhs.priorityRaw > rhs.priorityRaw }
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.createdAt < rhs.createdAt
        }
    }

    static func snapshot(
        from all: [TodoItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TodaySnapshot {
        let end = endOfToday(now, calendar: calendar)
        let todays = all.filter { !$0.isWaiting && isDue($0, endOfToday: end) }
        let done = todays.reduce(0) { $0 + ($1.isCompleted ? 1 : 0) }
        return TodaySnapshot(done: done, total: todays.count, open: sort(todays.filter { !$0.isCompleted }))
    }
}

/// Everything "today" means, computed once. `total` deliberately includes
/// completed tasks: the hero shows progress, not just what is left.
struct TodaySnapshot {
    let done: Int
    let total: Int
    /// Open tasks due today or earlier, already sorted.
    let open: [TodoItem]

    var remaining: Int { total - done }

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }
}
