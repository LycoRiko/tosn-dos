import Foundation

/// Everything the statistics page shows, computed from what is already stored.
/// No counters are kept on the model: a wrong counter is worse than a recount.
struct StatsSnapshot {
    var monthDone = 0
    var previousMonthDone = 0
    /// `[week][weekday]`, oldest week first — 12 columns of 7.
    var heatmap: [[Int]] = Array(repeating: Array(repeating: 0, count: 7), count: 12)
    var currentStreak = 0
    var longestStreak = 0
    var onTime = 0
    var late = 0

    var onTimeRate: Double? {
        let total = onTime + late
        return total == 0 ? nil : Double(onTime) / Double(total)
    }
}

enum StatsService {
    static let weeks = 12

    static func snapshot(
        from tasks: [TodoItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> StatsSnapshot {
        var stats = StatsSnapshot()
        let startOfToday = calendar.startOfDay(for: now)

        // Only finished work counts; an open task is not an outcome.
        let doneDates: [Date] = tasks.compactMap { task in
            task.isCompleted ? task.completedAt : nil
        }

        var perDay: [Date: Int] = [:]
        for date in doneDates {
            perDay[calendar.startOfDay(for: date), default: 0] += 1
        }

        let thisMonth = calendar.dateInterval(of: .month, for: now)
        let lastMonth = calendar.date(
            byAdding: .month,
            value: -1,
            to: thisMonth?.start ?? now
        ).flatMap { calendar.dateInterval(of: .month, for: $0) }

        for date in doneDates {
            if let thisMonth, thisMonth.contains(date) { stats.monthDone += 1 }
            if let lastMonth, lastMonth.contains(date) { stats.previousMonthDone += 1 }
        }

        stats.currentStreak = streak(perDay: perDay, endingAt: startOfToday, calendar: calendar)
        stats.longestStreak = longestStreak(perDay: perDay, calendar: calendar)
        stats.heatmap = heatmap(perDay: perDay, endingAt: startOfToday, calendar: calendar)

        let horizon = calendar.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday
        for task in tasks {
            guard task.isCompleted, let finished = task.completedAt, finished >= horizon else { continue }
            guard let deadline = task.focusDate else { continue }
            if finished <= deadline {
                stats.onTime += 1
            } else {
                stats.late += 1
            }
        }

        return stats
    }

    /// Today does not break a streak until it is over — an empty morning is not
    /// a failure.
    private static func streak(perDay: [Date: Int], endingAt today: Date, calendar: Calendar) -> Int {
        var cursor = today
        if perDay[cursor] == nil {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while (perDay[cursor] ?? 0) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private static func longestStreak(perDay: [Date: Int], calendar: Calendar) -> Int {
        let days = perDay.filter { $0.value > 0 }.keys.sorted()
        var best = 0
        var run = 0
        var previous: Date?

        for day in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// Column = week (oldest first), row = weekday, so the grid reads like a
    /// calendar when you look at the last column.
    private static func heatmap(perDay: [Date: Int], endingAt today: Date, calendar: Calendar) -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 7), count: weeks)

        // Anchor on the start of the week containing today, then walk back.
        let weekday = calendar.component(.weekday, from: today)
        let daysIntoWeek = (weekday - calendar.firstWeekday + 7) % 7
        guard let weekStart = calendar.date(byAdding: .day, value: -daysIntoWeek, to: today) else {
            return grid
        }

        for column in 0..<weeks {
            guard let columnStart = calendar.date(byAdding: .weekOfYear, value: column - (weeks - 1), to: weekStart) else {
                continue
            }
            for row in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: row, to: columnStart) else { continue }
                if day > today { continue }
                grid[column][row] = perDay[day] ?? 0
            }
        }
        return grid
    }
}
