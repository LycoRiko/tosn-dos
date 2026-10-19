import Foundation

/// The single definition of "today" for the app and the widget extension.
///
/// It lives in `Shared/` on purpose: `TaskQuery` depends on navigation types
/// that only the app target compiles, so the widget cannot import it. Keeping
/// the rule here is what stops the Today screen and the widget from drifting
/// into two different sets of numbers.
enum TodayScope {

    /// A due date belongs to today when it falls before tomorrow's midnight,
    /// so anything overdue is rolled in.
    static func isDue(_ item: TodoItem, endOfToday: Date) -> Bool {
        guard let due = item.dueDate else { return false }
        return due < endOfToday
    }

    static func endOfToday(_ now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    }

    /// Due date first, then priority, then insertion order. Both the hero and
    /// the widget read the order from here.
    static func sort(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { lhs, rhs in
            let l = lhs.dueDate ?? .distantFuture
            let r = rhs.dueDate ?? .distantFuture
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
