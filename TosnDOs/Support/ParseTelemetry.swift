import Foundation

/// DEBUG-only tallies so a parser run can be attributed: did our rules fire, or
/// did the input fall through to the system detector?
enum ParseTelemetry {
    nonisolated(unsafe) static private(set) var attempts = 0
    nonisolated(unsafe) static private(set) var resolvedByRules = 0
    nonisolated(unsafe) static private(set) var resolvedByFallback = 0
    nonisolated(unsafe) static private(set) var unresolved = 0
    nonisolated(unsafe) static private(set) var fallbackRejected = 0

    static func reset() {
        attempts = 0
        resolvedByRules = 0
        resolvedByFallback = 0
        unresolved = 0
        fallbackRejected = 0
    }

    static func recordRules() { attempts += 1; resolvedByRules += 1 }
    static func recordFallback() { resolvedByFallback += 1 }
    static func recordRejected() { fallbackRejected += 1 }
    static func recordUnresolved() { attempts += 1; unresolved += 1 }

    static var summary: String {
        "attempts \(attempts) · rules \(resolvedByRules) · fallback \(resolvedByFallback) · rejected \(fallbackRejected) · unresolved \(unresolved)"
    }
}

/// Last-resort date spotting. Deliberately narrow: a match only counts when it
/// names a month and a day, and lands within two years of now.
enum SystemDateFallback {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    static func date(in text: String, now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let detector else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, range: range)
        let twoYears = calendar.date(byAdding: .year, value: 2, to: now) ?? now
        let twoYearsBack = calendar.date(byAdding: .year, value: -2, to: now) ?? now

        for match in matches {
            guard let date = match.date, date >= twoYearsBack, date <= twoYears else { continue }
            // A bare "18:00" also matches as a date; require a real day component.
            let parts = calendar.dateComponents([.month, .day], from: date)
            guard parts.month != nil, parts.day != nil else { continue }
            return date
        }
        return nil
    }
}
