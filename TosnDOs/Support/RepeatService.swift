import Foundation
import SwiftData

/// Turns a repeating template into a real list when its period comes around.
///
/// There is no background timer on purpose: the check runs when the app opens
/// or comes back to the front, and a miss is surfaced to the user instead of
/// being quietly papered over. Skipping still marks the period as handled, so
/// the same miss is not asked about twice.
@MainActor
enum RepeatService {

    /// At most this many lists are offered in one go. Anything older is folded
    /// into "the latest is enough" — nobody wants twenty catch-up lists.
    static let maxMissed = 30

    struct Prompt: Identifiable {
        let templateUID: UUID
        let title: String
        let rule: RepeatRule
        /// The newest period already handled, nil if no list was ever made.
        let lastHandled: Date?
        /// Period starts that were missed, oldest first.
        let missed: [Date]

        var id: UUID { templateUID }
        var count: Int { missed.count }
    }

    enum Choice {
        case latest
        case all
        case skip
    }

    // MARK: - Detection

    static func nextPrompt(
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Prompt? {
        let templates = (try? context.fetch(FetchDescriptor<ListTemplate>())) ?? []
        for template in templates where template.repeatRule != .off {
            let missed = missedPeriods(for: template, now: now, calendar: calendar)
            if missed.isEmpty { continue }
            return Prompt(
                templateUID: template.uid,
                title: template.title.isEmpty ? String(localized: "Untitled") : template.title,
                rule: template.repeatRule,
                lastHandled: template.lastGeneratedAt,
                missed: missed
            )
        }
        return nil
    }

    static func missedPeriods(
        for template: ListTemplate,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Date] {
        let rule = template.repeatRule
        guard rule != .off else { return [] }

        let anchor = calendar.startOfDay(for: template.repeatStart ?? template.createdAt)
        let handled = template.lastGeneratedAt
        let starts = periodStarts(anchor: anchor, rule: rule, until: now, calendar: calendar)

        let missed = starts.filter { start in
            guard let handled else { return true }
            return start > handled
        }
        return Array(missed.suffix(maxMissed))
    }

    /// Every period start from `anchor` up to and including `end`.
    static func periodStarts(
        anchor: Date,
        rule: RepeatRule,
        until end: Date,
        calendar: Calendar = .current,
        limit: Int = 400
    ) -> [Date] {
        var result: [Date] = []
        var index = 0
        while result.count < limit {
            guard let start = periodStart(anchor: anchor, rule: rule, index: index, calendar: calendar),
                  start <= end
            else { break }
            result.append(start)
            index += 1
        }
        return result
    }

    /// The start of the `index`-th period after `anchor`. Monthly counts from
    /// the anchor's day-of-month, clamped to the last day of short months, so
    /// a list on the 31st lands on Feb 28 rather than drifting to Mar 3.
    static func periodStart(
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

    // MARK: - Resolution

    /// Creates the lists the user asked for and marks the newest missed period
    /// as handled. Every choice ends at the same `lastGeneratedAt`, which is
    /// what keeps the prompt from coming back.
    static func resolve(
        _ choice: Choice,
        for prompt: Prompt,
        in context: ModelContext,
        calendar: Calendar = .current
    ) {
        guard let template = template(uid: prompt.templateUID, in: context) else { return }
        guard let newest = prompt.missed.last else { return }

        let periods: [Date]
        switch choice {
        case .latest: periods = [newest]
        case .all: periods = prompt.missed
        case .skip: periods = []
        }

        let startsToday = UserDefaults.standard.object(forKey: PreferenceKey.templateDueToday) as? Bool ?? true
        for period in periods {
            WorkspaceService.instantiate(
                template: template,
                title: template.title,
                dueToday: startsToday,
                period: period,
                in: context
            )
        }

        template.lastGeneratedAt = newest
        WorkspaceService.save(context)
    }

    private static func template(uid: UUID, in context: ModelContext) -> ListTemplate? {
        let all = (try? context.fetch(FetchDescriptor<ListTemplate>())) ?? []
        return all.first { $0.uid == uid }
    }
}
