import Foundation

/// Period arithmetic for repeating templates, kept free of SwiftData so it can be
/// tested without a store. `RepeatService` is the model-aware wrapper around it.
enum RepeatSchedule {

    /// Every period start from `anchor` up to and including `end`.
    static func starts(
        anchor: Date,
        rule: RepeatRule,
        until end: Date,
        calendar: Calendar = .current,
        limit: Int = 400
    ) -> [Date] {
        var result: [Date] = []
        var index = 0
        while result.count < limit {
            guard let start = start(anchor: anchor, rule: rule, index: index, calendar: calendar),
                  start <= end
            else { break }
            result.append(start)
            index += 1
        }
        return result
    }

    /// The start of the `index`-th period after `anchor`. Monthly counts from the
    /// anchor's day-of-month, clamped to the last day of short months, so a list on
    /// the 31st lands on Feb 28 rather than drifting to Mar 3.
    static func start(
        anchor: Date,
        rule: RepeatRule,
        index: Int,
        calendar: Calendar = .current
    ) -> Date? {
        switch rule {
        case .off:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: index, to: anchor)
        case .weekly:
            return calendar.date(byAdding: .day, value: index * 7, to: anchor)
        case .monthly:
            let parts = calendar.dateComponents([.year, .month, .day], from: anchor)
            guard let year = parts.year, let month = parts.month else { return nil }
            let anchorDay = parts.day ?? 1
            guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let target = calendar.date(byAdding: .month, value: index, to: firstOfMonth)
            else { return nil }
            let daysInMonth = calendar.range(of: .day, in: .month, for: target)?.count ?? 28
            return calendar.date(byAdding: .day, value: min(anchorDay, daysInMonth) - 1, to: target)
        }
    }

    /// The last period that has already begun.
    static func currentStart(
        anchor: Date,
        rule: RepeatRule,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        var latest: Date?
        var index = 0
        while index < 400,
              let start = start(anchor: anchor, rule: rule, index: index, calendar: calendar),
              start <= now {
            latest = start
            index += 1
        }
        return latest
    }

    /// Periods the template has not dealt with.
    ///
    /// The horizon is the newest period already settled. The ledger carries it per
    /// period; `lastGeneratedAt` covers templates written before the ledger existed,
    /// and keeps their older periods from resurfacing. Manual pulls never settle one.
    static func missedStarts(
        anchor: Date,
        rule: RepeatRule,
        log: [PeriodRecord],
        lastGeneratedAt: Date?,
        now: Date = .now,
        calendar: Calendar = .current,
        limit: Int
    ) -> [Date] {
        let settled = log.filter { $0.outcome != .manual }.map(\.start).max()
        let horizon = Swift.max(lastGeneratedAt ?? .distantPast, settled ?? .distantPast)
        let missed = starts(anchor: anchor, rule: rule, until: now, calendar: calendar)
            .filter { $0 > horizon }
        return Array(missed.suffix(limit))
    }

    /// The trail a choice leaves: periods taken become lists, the rest are skipped.
    /// Keeping this separate is what makes "latest" and "all" leave different records.
    static func ledger(for missed: [Date], taking taken: [Date]) -> [PeriodRecord] {
        let chosen = Set(taken)
        return missed.map {
            PeriodRecord(start: $0, outcome: chosen.contains($0) ? .generated : .skipped)
        }
    }
}
