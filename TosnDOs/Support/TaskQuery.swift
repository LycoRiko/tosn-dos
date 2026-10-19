import Foundation

/// Filtering and grouping live in one place so every screen agrees on what
/// "today" means. Kept intentionally simple: for a personal task list the
/// cost of filtering in memory is negligible, and it avoids predicate drift
/// between platforms.
enum TaskQuery {

    /// A due date counts as "today" when it is before tomorrow's midnight, so
    /// anything overdue is rolled in. The rule itself lives in `Shared/` so the
    /// widget extension can use the same one.
    static func isDueToday(_ item: TodoItem, endOfToday: Date) -> Bool {
        TodayScope.isDue(item, endOfToday: endOfToday)
    }

    static func items(
        from all: [TodoItem],
        scope: SidebarItem,
        lists: [TodoList],
        tags: [Tag],
        search: String = "",
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [TodoItem] {
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now

        var result: [TodoItem] = all.filter { item in
            switch scope {
            case .smart(.today):
                // A parked task cannot be acted on today, so it never shows up
                // here and never reaches the hero's numbers.
                guard !item.isCompleted, !item.isWaiting else { return false }
                return isDueToday(item, endOfToday: endOfToday)
            case .smart(.upcoming):
                guard !item.isCompleted, let due = item.dueDate else { return false }
                return due >= endOfToday
            case .smart(.all):
                return !item.isCompleted
            case .smart(.completed):
                return item.isCompleted
            case .list(let uid):
                return item.list?.uid == uid
            case .tag(let uid):
                return (item.tags ?? []).contains { $0.uid == uid }
            case .templates:
                return false
            }
        }

        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed)
                    || $0.notes.localizedCaseInsensitiveContains(trimmed)
            }
        }

        _ = lists
        _ = tags
        return result
    }

    /// The numbers behind the Today hero, the Today scope and the widget.
    /// Implemented in `Shared/TodayScope` so all three read the same code.
    static func todaySnapshot(
        from all: [TodoItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TodaySnapshot {
        TodayScope.snapshot(from: all, now: now, calendar: calendar)
    }

    static func sections(
        from items: [TodoItem],
        scope: SidebarItem,
        showCompleted: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [TaskSection] {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now

        if scope.smartList == .completed {
            let done = items.filter { $0.isCompleted }
            let section = TaskSection(kind: .completed, items: sortForCompleted(done))
            return done.isEmpty ? [] : [section]
        }

        // Fill buckets first, then emit them in `Kind.displayOrder`. Adding a
        // group means adding a case and one line here — not another if-chain.
        var buckets: [TaskSection.Kind: [TodoItem]] = [:]

        for item in items {
            let kind: TaskSection.Kind
            if item.isCompleted {
                kind = .completed
            } else if item.isWaiting {
                // Checked before the date buckets: a parked task stays parked
                // even if its due date has passed.
                kind = .waiting
            } else if let due = item.dueDate {
                if item.hasDueTime ? (due < now) : (due < startOfToday) {
                    kind = .overdue
                } else if due < endOfToday {
                    kind = .today
                } else {
                    kind = .upcoming
                }
            } else {
                kind = .anytime
            }
            buckets[kind, default: []].append(item)
        }

        return TaskSection.Kind.displayOrder.compactMap { kind in
            guard let items = buckets[kind], !items.isEmpty else { return nil }
            if kind == .completed && !showCompleted { return nil }
            return TaskSection(kind: kind, items: sorted(items, for: kind))
        }
    }

    private static func sorted(_ items: [TodoItem], for kind: TaskSection.Kind) -> [TodoItem] {
        kind == .completed ? sortForCompleted(items) : sort(items)
    }

    private static func sortForCompleted(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    /// Due date first, then priority, then insertion order. This is also the
    /// reason the app has no manual sort UI: the order is always meaningful.
    static func sort(_ items: [TodoItem]) -> [TodoItem] {
        TodayScope.sort(items)
    }
}

struct TaskSection: Identifiable {
    enum Kind: String {
        case overdue, today, upcoming, anytime, waiting, completed

        /// Rendered in this order. Kept beside the cases so they cannot drift.
        /// Waiting sits after everything actionable and before Completed: you
        /// look at what you can do first, then at what you are waiting on.
        static let displayOrder: [Kind] = [.overdue, .today, .upcoming, .anytime, .waiting, .completed]

        var title: String {
            switch self {
            case .overdue: return String(localized: "Overdue")
            case .today: return String(localized: "Today")
            case .upcoming: return String(localized: "Upcoming")
            case .anytime: return String(localized: "No date")
            case .waiting: return String(localized: "Waiting")
            case .completed: return String(localized: "Completed")
            }
        }
    }

    let kind: Kind
    let items: [TodoItem]

    var id: String { kind.rawValue }
}

/// Human, locale-aware due label. Uses Foundation formatting so Chinese,
/// Japanese and English all come out right without extra work.
enum DueDateFormat {
    static func label(
        for item: TodoItem,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String? {
        guard let due = item.dueDate else { return nil }
        let startOfToday = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: due)

        if item.isCompleted && !item.hasDueTime {
            return dayText(due, relativeTo: startOfToday, calendar: calendar)
        }
        if item.hasDueTime && due < now && !item.isCompleted {
            return timeText(due)
        }
        if dueDay < startOfToday {
            return dayText(due, relativeTo: startOfToday, calendar: calendar)
        }

        let base = dayText(due, relativeTo: startOfToday, calendar: calendar)
        return item.hasDueTime ? "\(base) \(timeText(due))" : base
    }

    private static func dayText(_ date: Date, relativeTo startOfToday: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: startOfToday, to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Tomorrow")
        case -1: return String(localized: "Yesterday")
        case 2...6:
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.setLocalizedDateFormatFromTemplate("EEE")
            return formatter.string(from: date)
        default:
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private static func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// True when the label should be shown in the destructive tint.
    static func isLate(_ item: TodoItem, now: Date = .now) -> Bool {
        item.isOverdue(at: now)
    }
}

/// Deadline copy for list rows. Lives next to the task formatter so both
/// screens agree on what "today" means.
enum DeadlineFormat {
    static func label(
        for deadline: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let startOfToday = calendar.startOfDay(for: now)
        let deadlineDay = calendar.startOfDay(for: deadline)
        let days = calendar.dateComponents([.day], from: startOfToday, to: deadlineDay).day ?? 0

        switch days {
        case 0: return String(localized: "Due today")
        case 1: return String(localized: "Due tomorrow")
        case -1: return String(localized: "Due yesterday")
        default: return deadline.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    /// Two steps only: late, or nearly late. Everything else stays quiet.
    static func isUrgent(
        for deadline: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard let soon = calendar.date(byAdding: .hour, value: 24, to: now) else { return false }
        return deadline < soon
    }
}
