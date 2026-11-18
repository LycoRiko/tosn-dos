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
    /// Finished work this month, biggest list first.
    var byList: [(name: String, count: Int)] = []
    /// 24 slots, one per hour of the day.
    var byHour: [Int] = Array(repeating: 0, count: 24)
    /// Hours between creating and finishing; median is less distorted than average.
    var medianHours: Double?
    var templateFinished = 0
    var templateTotal = 0

    var onTimeRate: Double? {
        let total = onTime + late
        return total == 0 ? nil : Double(onTime) / Double(total)
    }

    var templateRate: Double? {
        templateTotal == 0 ? nil : Double(templateFinished) / Double(templateTotal)
    }
}

enum StatsService {
    static let weeks = 12

    static func snapshot(
        from tasks: [TodoItem],
        lists: [TodoList] = [],
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

        stats.byList = listBreakdown(tasks: tasks, month: thisMonth, calendar: calendar)
        stats.byHour = hourHistogram(tasks: tasks, since: horizon, calendar: calendar)
        stats.medianHours = medianFinishHours(tasks: tasks, since: horizon, calendar: calendar)

        let fromTemplates = lists.filter { $0.periodDate != nil }
        stats.templateTotal = fromTemplates.count
        stats.templateFinished = fromTemplates.filter(\.isFinished).count

        return stats
    }

    /// Only the head of the list is worth showing; the tail is noise.
    private static func listBreakdown(
        tasks: [TodoItem],
        month: DateInterval?,
        calendar: Calendar
    ) -> [(name: String, count: Int)] {
        guard let month else { return [] }
        var counts: [String: Int] = [:]
        for task in tasks {
            guard task.isCompleted, let finished = task.completedAt, month.contains(finished) else { continue }
            counts[task.list?.title ?? String(localized: "No list"), default: 0] += 1
        }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(5)
            .map { (name: $0.key, count: $0.value) }
    }

    private static func hourHistogram(tasks: [TodoItem], since: Date, calendar: Calendar) -> [Int] {
        var buckets = Array(repeating: 0, count: 24)
        for task in tasks {
            guard task.isCompleted, let finished = task.completedAt, finished >= since else { continue }
            let hour = calendar.component(.hour, from: finished)
            buckets[hour] += 1
        }
        return buckets
    }

    private static func medianFinishHours(tasks: [TodoItem], since: Date, calendar: Calendar) -> Double? {
        var hours: [Double] = []
        for task in tasks {
            guard task.isCompleted, let finished = task.completedAt, finished >= since else { continue }
            let span = finished.timeIntervalSince(task.createdAt)
            guard span > 0 else { continue }
            hours.append(span / 3600)
        }
        guard !hours.isEmpty else { return nil }
        hours.sort()
        let middle = hours.count / 2
        return hours.count.isMultiple(of: 2)
            ? (hours[middle - 1] + hours[middle]) / 2
            : hours[middle]
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
