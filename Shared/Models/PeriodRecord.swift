import Foundation

/// One line of a template's ledger: what happened to one period of a repeating list.
///
/// The ledger exists so "catch up the latest" and "catch up all" are not the same
/// entry, and so a period that was passed over can be told apart from one that was
/// never offered.
struct PeriodRecord: Codable, Hashable {
    enum Outcome: String, Codable {
        case generated   // a list was made for this period
        case skipped     // passed over, on purpose, never to be asked again
        case manual      // pulled by hand — not a catch-up, must not close the period
    }

    var start: Date
    var outcome: Outcome
    var recordedAt: Date

    init(start: Date, outcome: Outcome, recordedAt: Date = .now) {
        self.start = start
        self.outcome = outcome
        self.recordedAt = recordedAt
    }
}
