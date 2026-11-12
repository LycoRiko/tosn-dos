#if DEBUG
import Foundation
import SwiftData

/// Temporary: seeds a repeating template with a ledger so the History block can be
/// looked at without waiting a few weeks for real periods to pass.
enum LedgerDemo {
    /// The template seeded last, so a preview can jump straight at it.
    nonisolated(unsafe) static var lastSeededUID: UUID?

    @MainActor
    static func seed(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ListTemplate>())) ?? []
        // Start clean each run: a stale copy would still owe periods and pop the prompt.
        for stale in existing where stale.title == "Weekly review" {
            context.delete(stale)
        }

        let calendar = Calendar.current
        let anchor = calendar.date(byAdding: .weekOfYear, value: -3, to: calendar.startOfDay(for: .now)) ?? .now

        let template = ListTemplate(title: "Weekly review")
        template.repeatRuleRaw = RepeatRule.weekly.rawValue
        template.repeatStart = anchor
        template.periodLog = [
            PeriodRecord(start: anchor, outcome: .generated),
            PeriodRecord(start: calendar.date(byAdding: .weekOfYear, value: 1, to: anchor) ?? anchor, outcome: .skipped),
            PeriodRecord(start: calendar.date(byAdding: .weekOfYear, value: 2, to: anchor) ?? anchor, outcome: .manual)
        ]
        context.insert(template)

        let item = TemplateItem(title: "Clear the inbox", sortIndex: 0)
        item.template = template
        context.insert(item)

        template.lastGeneratedAt = .now          // no prompt for the demo
        try? context.save()
        lastSeededUID = template.uid
    }
}
#endif
