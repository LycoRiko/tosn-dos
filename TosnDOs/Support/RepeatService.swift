import Foundation
import SwiftData

/// No background timer: the check runs on open or on return to the front, and a miss
/// is surfaced rather than papered over.
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
        let anchor = calendar.startOfDay(for: template.repeatStart ?? template.createdAt)
        return RepeatSchedule.missedStarts(
            anchor: anchor,
            rule: template.repeatRule,
            log: template.periodLog ?? [],
            lastGeneratedAt: template.lastGeneratedAt,
            now: now,
            calendar: calendar,
            limit: maxMissed
        )
    }

    static func periodStarts(
        anchor: Date,
        rule: RepeatRule,
        until end: Date,
        calendar: Calendar = .current,
        limit: Int = 400
    ) -> [Date] {
        RepeatSchedule.starts(anchor: anchor, rule: rule, until: end, calendar: calendar, limit: limit)
    }

    static func periodStart(
        anchor: Date,
        rule: RepeatRule,
        index: Int,
        calendar: Calendar = .current
    ) -> Date? {
        RepeatSchedule.start(anchor: anchor, rule: rule, index: index, calendar: calendar)
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

        // One record per offered period, so "the latest" and "all" leave different
        // trails: what was made, and what was waved through.
        append(RepeatSchedule.ledger(for: prompt.missed, taking: periods), to: template)

        template.lastGeneratedAt = newest
        WorkspaceService.save(context)
    }

    /// A list pulled by hand is not a catch-up. It goes into the ledger so it can be
    /// seen, but `missedPeriods` never counts it as handled.
    static func noteManualPull(
        for template: ListTemplate,
        at now: Date = .now,
        calendar: Calendar = .current
    ) {
        guard let start = currentPeriodStart(for: template, now: now, calendar: calendar) else { return }
        append([PeriodRecord(start: start, outcome: .manual)], to: template)
    }

    /// The last period that has already begun.
    static func currentPeriodStart(
        for template: ListTemplate,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        let anchor = calendar.startOfDay(for: template.repeatStart ?? template.createdAt)
        return RepeatSchedule.currentStart(anchor: anchor, rule: template.repeatRule,
                                           now: now, calendar: calendar)
    }

    /// Keeps the ledger bounded: a daily template would otherwise grow it forever.
    private static func append(_ records: [PeriodRecord], to template: ListTemplate) {
        guard !records.isEmpty else { return }
        var log = template.periodLog ?? []
        log.append(contentsOf: records)
        if log.count > maxLog { log = Array(log.suffix(maxLog)) }
        template.periodLog = log
    }

    private static let maxLog = 400

    private static func template(uid: UUID, in context: ModelContext) -> ListTemplate? {
        let all = (try? context.fetch(FetchDescriptor<ListTemplate>())) ?? []
        return all.first { $0.uid == uid }
    }
}
