import Foundation

struct ParsedTaskInput {
    var title: String
    var dueDate: Date?
    var endDate: Date?
    var hasTime: Bool

    init(title: String, dueDate: Date?, endDate: Date? = nil, hasTime: Bool) {
        self.title = title
        self.dueDate = dueDate
        self.endDate = endDate
        self.hasTime = hasTime
    }
}

/// Small and deliberate: it understands 今天 / 明天 / 周三 / 下午3点 / 15:30 and
/// leaves the rest of the sentence alone.
enum NaturalDateParser {

    static func parse(
        _ raw: String,
        now: Date = .now,
        calendar: Calendar = .current,
        useSystemFallback: Bool = false
    ) -> ParsedTaskInput {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return ParsedTaskInput(title: raw, dueDate: nil, hasTime: false)
        }

        // A range is two expressions joined by a connector; parse each half with the
        // rules below, then let the end inherit the start's day when it names none.
        if let parts = splitRange(text) {
            let left = parseSingle(parts.0, now: now, calendar: calendar, useSystemFallback: useSystemFallback)
            let right = parseSingle(parts.1, now: now, calendar: calendar, useSystemFallback: useSystemFallback)
            if let start = left.dueDate {
                var end = right.dueDate ?? start
                if !daysNamed(parts.1) {
                    end = calendar.date(
                        bySettingHour: calendar.component(.hour, from: end),
                        minute: calendar.component(.minute, from: end),
                        second: 0,
                        of: start
                    ) ?? end
                }
                if end <= start {
                    end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
                }
                return ParsedTaskInput(
                    title: left.title.isEmpty ? right.title : left.title,
                    dueDate: start,
                    endDate: end,
                    hasTime: left.hasTime || right.hasTime
                )
            }
        }

        return parseSingle(text, now: now, calendar: calendar, useSystemFallback: useSystemFallback)
    }

    /// `useSystemFallback` stays off by default: it exists so the measurement can
    /// tell us whether a fallback would even help.
    private static func parseSingle(
        _ raw: String,
        now: Date,
        calendar: Calendar,
        useSystemFallback: Bool = false
    ) -> ParsedTaskInput {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return ParsedTaskInput(title: raw, dueDate: nil, hasTime: false)
        }

        var hour: Int?
        var minute = 0
        var impliedEvening = false
        var explicitPeriod: String?

        // 1. Explicit clock time: 15:30 / 3:30pm
        if let result = firstMatch(#"(上午|下午|晚上|中午|早上|凌晨|傍晚)?\s*(\d{1,2})\s*[:：]\s*(\d{2})\s*(am|pm)?"#, in: text) {
            let period = capture(1, result, text)
            explicitPeriod = period
            hour = Int(capture(2, result, text) ?? "")
            minute = Int(capture(3, result, text) ?? "") ?? 0
            hour = adjustedHour(hour, period: period, bareIsAfternoon: false)
            let suffix = (capture(4, result, text) ?? "").lowercased()
            if !suffix.isEmpty { hour = adjustedForMeridiem(hour, suffix: suffix) }
            text = removing(result.range, from: text)
        }
        // Spoken clock time: 下午3点 / 8点半 / 7点15分
        else if let result = firstMatch(#"(上午|下午|晚上|中午|早上|凌晨|傍晚)?\s*(\d{1,2}|[一二两三四五六七八九十]{1,3})\s*点\s*(半|\d{1,2}\s*分|[一二两三四五六七八九十]{1,3}\s*分)?"#, in: text) {
            let period = capture(1, result, text)
            explicitPeriod = period
            hour = hourValue(capture(2, result, text) ?? "")
            let tail = capture(3, result, text) ?? ""
            if tail.contains("半") {
                minute = 30
            } else if tail.contains("分") {
                let digits = tail.replacingOccurrences(of: "分", with: "")
                    .trimmingCharacters(in: .whitespaces)
                minute = hourValue(digits) ?? 0
            }
            hour = adjustedHour(hour, period: period, bareIsAfternoon: true)
            text = removing(result.range, from: text)
        }
        // English bare hour: 8pm
        else if let result = firstMatch(#"(\d{1,2})\s*(am|pm)"#, in: text) {
            hour = Int(capture(1, result, text) ?? "")
            hour = adjustedForMeridiem(hour, suffix: (capture(2, result, text) ?? "").lowercased())
            text = removing(result.range, from: text)
        }

        // 3. Day expression
        var dayOffset: Int?
        var weekdayTarget: Int?
        var weekShift = 0
        var fixedDay: Date?

        let dayKeywords: [(String, Int)] = [
            ("day after tomorrow", 2), ("大后天", 3), ("后天", 2),
            ("明天", 1), ("明日", 1), ("明早", 1), ("明晚", 1), ("tomorrow", 1),
            ("今天", 0), ("today", 0), ("今日", 0), ("今晚", 0), ("tonight", 0)
        ]

        // The earliest mention wins, and the longer keyword wins a tie: a range like
        // "今天18:00到明天10:00" must not read 明天 as the start.
        var earliest: (keyword: String, offset: Int, at: Int, length: Int)?
        for (keyword, offset) in dayKeywords {
            guard let found = text.range(of: keyword, options: .caseInsensitive) else { continue }
            let at = text.distance(from: text.startIndex, to: found.lowerBound)
            if earliest == nil || at < earliest!.at || (at == earliest!.at && keyword.count > earliest!.length) {
                earliest = (keyword, offset, at, keyword.count)
            }
        }
        if let match = earliest {
            dayOffset = match.offset
            if ["今晚", "明晚", "tonight"].contains(match.keyword) { impliedEvening = true }
            text = text.replacingOccurrences(of: match.keyword, with: "", options: .caseInsensitive)
        }

        if dayOffset == nil, text.contains("周末") {
            weekdayTarget = 7
            text = text.replacingOccurrences(of: "周末", with: "")
        }

        if dayOffset == nil, weekdayTarget == nil, let result = firstMatch(#"(下下|下|本|这)?\s*(?:周|星期|礼拜)\s*([一二三四五六日天])"#, in: text) {
            let prefix = capture(1, result, text) ?? ""
            let dayChar = capture(2, result, text) ?? ""
            weekdayTarget = weekdayNumber(dayChar)
            switch prefix {
            case "下下周", "下下": weekShift = 2
            case "下周", "下": weekShift = 1
            case "本周", "这周", "本", "这": weekShift = -1
            default: weekShift = 0
            }
            text = removing(result.range, from: text)
        }

        if dayOffset == nil, weekdayTarget == nil,
           let result = firstMatch(#"(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?"#, in: text) {
            if let month = Int(capture(1, result, text) ?? ""),
               let day = Int(capture(2, result, text) ?? "") {
                var comps = calendar.dateComponents([.year], from: now)
                comps.month = month
                comps.day = day
                comps.hour = 0
                comps.minute = 0
                if var candidate = calendar.date(from: comps) {
                    if candidate < calendar.startOfDay(for: now) {
                        comps.year = (comps.year ?? 0) + 1
                        candidate = calendar.date(from: comps) ?? candidate
                    }
                    fixedDay = candidate
                }
            }
            text = removing(result.range, from: text)
        }

        if dayOffset == nil, weekdayTarget == nil, fixedDay == nil,
           let result = firstMatch(#"(\d{4})-(\d{1,2})-(\d{1,2})"#, in: text) {
            if let year = Int(capture(1, result, text) ?? ""),
               let month = Int(capture(2, result, text) ?? ""),
               let day = Int(capture(3, result, text) ?? "") {
                var comps = DateComponents()
                comps.year = year
                comps.month = month
                comps.day = day
                comps.hour = 0
                comps.minute = 0
                fixedDay = calendar.date(from: comps)
            }
            text = removing(result.range, from: text)
        }

        if dayOffset == nil, weekdayTarget == nil, fixedDay == nil,
           let result = firstMatch(#"(\d{1,2})/(\d{1,2})"#, in: text) {
            if let month = Int(capture(1, result, text) ?? ""), let day = Int(capture(2, result, text) ?? "") {
                var comps = calendar.dateComponents([.year], from: now)
                comps.month = month
                comps.day = day
                comps.hour = 0
                comps.minute = 0
                if var candidate = calendar.date(from: comps) {
                    if candidate < calendar.startOfDay(for: now) {
                        comps.year = (comps.year ?? 0) + 1
                        candidate = calendar.date(from: comps) ?? candidate
                    }
                    fixedDay = candidate
                }
            }
            text = removing(result.range, from: text)
        }

        if dayOffset == nil, weekdayTarget == nil, fixedDay == nil,
           let result = firstMatch(#"(?i)\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})\b"#, in: text) {
            let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                          "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
            if let key = capture(1, result, text)?.lowercased(),
               let month = months[key],
               let day = Int(capture(2, result, text) ?? "") {
                fixedDay = upcomingMonthDay(month, day, now: now, calendar: calendar)
            }
            text = removing(result.range, from: text)
        }

        // Spans counted from today: 三天后 / 半个月后 / 两周后.
        if dayOffset == nil, weekdayTarget == nil, fixedDay == nil,
           let result = firstMatch(#"(半|[一二三四五六七八九十]|\d{1,2})\s*个?\s*(天|日|周|星期|月)\s*(?:之?后|以后)"#, in: text) {
            let amount = chineseNumber(capture(1, result, text) ?? "") ?? 0
            let unit = capture(2, result, text) ?? "天"
            let days: Double
            switch unit {
            case "周", "星期": days = amount * 7
            case "月": days = amount * 30
            default: days = amount
            }
            fixedDay = calendar.date(byAdding: .day, value: Int(days.rounded()),
                                     to: calendar.startOfDay(for: now))
            text = removing(result.range, from: text)
        }

        if dayOffset == nil, weekdayTarget == nil, fixedDay == nil, text.contains("月底") {
            if let month = calendar.dateInterval(of: .month, for: now) {
                fixedDay = calendar.date(byAdding: .day, value: -1, to: month.end)
            }
            text = text.replacingOccurrences(of: "月底", with: "")
        }

        // Offsets from the current time, so the hour moves too: "in 2 hours".
        if hour == nil, let result = firstMatch(#"in\s+(\d{1,2})\s*(?:hours?|hrs?|h)\b"#, in: text) {
            let hours = Int(capture(1, result, text) ?? "") ?? 0
            let target = calendar.date(byAdding: .hour, value: hours, to: now) ?? now
            hour = calendar.component(.hour, from: target)
            fixedDay = calendar.startOfDay(for: target)
            text = removing(result.range, from: text)
        }

        // 4. Compose the date
        var dueDate: Date?
        var hasTime = hour != nil

        if var hour {
            // "今晚8点" carries its period in the day word, not in front of the hour.
            let period = explicitPeriod ?? ""
            if impliedEvening, period.isEmpty, hour < 12 { hour += 12 }

            var base = calendar.startOfDay(for: now)
            if let offset = dayOffset {
                base = calendar.date(byAdding: .day, value: offset, to: base) ?? base
            } else if let weekday = weekdayTarget {
                base = dateFor(weekday: weekday, weekShift: weekShift, from: now, calendar: calendar)
            } else if let fixedDay {
                base = fixedDay
            }
            dueDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)
        } else if impliedEvening {
            let base = calendar.startOfDay(for: now)
            dueDate = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: base)
            hasTime = true
        } else if let dayOffset {
            let base = calendar.startOfDay(for: now)
            dueDate = calendar.date(byAdding: .day, value: dayOffset, to: base)
        } else if let weekday = weekdayTarget {
            dueDate = dateFor(weekday: weekday, weekShift: weekShift, from: now, calendar: calendar)
        } else if let fixedDay {
            dueDate = fixedDay
        }

        let title = cleaned(text, fallback: raw)
        if dueDate != nil {
            ParseTelemetry.recordRules()
        } else if useSystemFallback, let found = SystemDateFallback.date(in: raw, now: now, calendar: calendar) {
            ParseTelemetry.recordFallback()
            return ParsedTaskInput(title: title, dueDate: found, hasTime: true)
        } else {
            if useSystemFallback { ParseTelemetry.recordRejected() }
            ParseTelemetry.recordUnresolved()
        }
        return ParsedTaskInput(title: title, dueDate: dueDate, hasTime: hasTime)
    }

    // MARK: - Ranges

    /// Dates are never split: a hyphen only counts when both sides end and start
    /// with a clock time, so `2026-11-13` stays whole.
    private static func splitRange(_ text: String) -> (String, String)? {
        let connectors = ["一直到", "直到", "到", "至", "～", "~", "—", "–", "-",
                          " to ", " until ", " till ", " through "]
        for connector in connectors {
            guard var range = text.range(of: connector) else { continue }
            let left = String(text[text.startIndex..<range.lowerBound])
            let right = String(text[range.upperBound...])
            guard looksLikeTime(left), looksLikeTime(right) else { continue }
            if connector != "-" {
                // nothing to validate
            } else {
                // 2026-11-13 carries hyphens of its own, so try each one.
                var candidate = range
                var accepted = false
                while true {
                    let l = String(text[text.startIndex..<candidate.lowerBound])
                    let r = String(text[candidate.upperBound...])
                    let clock = endsWithClockTime(l) && startsWithClockTime(r)
                    let spoken = l.range(of: #"\d{1,2}\s*点"#, options: .regularExpression) != nil
                        && r.range(of: #"\d{1,2}\s*点"#, options: .regularExpression) != nil
                    // "今天18:00-明天10:00" joins two day words, not two clock times.
                    let dayEdge = (endsWithClockTime(l) || endsWithDayWord(l))
                        && (startsWithClockTime(r) || startsWithDayWord(r))
                    if clock || spoken || dayEdge { range = candidate; accepted = true; break }
                    guard let next = text.range(of: connector, range: candidate.upperBound..<text.endIndex) else { break }
                    candidate = next
                }
                guard accepted else { continue }
            }
            return (String(text[text.startIndex..<range.lowerBound]),
                    String(text[range.upperBound...]))
        }
        return nil
    }

    /// Guards against `到底`, `迟到` and `todo`: the side has to name a time or a day.
    private static func looksLikeTime(_ fragment: String) -> Bool {
        if fragment.range(of: #"\d"#, options: .regularExpression) != nil { return true }
        let days = ["今天", "明天", "后天", "明早", "明晚", "今晚", "次日", "第二天", "周末", "tomorrow", "tonight"]
        return days.contains { fragment.localizedCaseInsensitiveContains($0) }
    }

    private static func endsWithClockTime(_ text: String) -> Bool {
        text.range(of: #"\d{1,2}[:：]\d{2}\s*$"#, options: .regularExpression) != nil
    }

    private static func startsWithClockTime(_ text: String) -> Bool {
        text.range(of: #"^\s*\d{1,2}[:：]\d{2}"#, options: .regularExpression) != nil
    }

    private static let dayWords = [
        "今天", "今日", "明天", "明日", "明早", "明晚", "今晚", "后天", "大后天",
        "tomorrow", "today", "tonight"
    ]

    private static func endsWithDayWord(_ text: String) -> Bool {
        dayWords.contains { text.hasSuffix($0) }
    }

    private static func startsWithDayWord(_ text: String) -> Bool {
        let head = text.trimmingCharacters(in: .whitespaces)
        return dayWords.contains { head.hasPrefix($0) }
    }

    private static func daysNamed(_ text: String) -> Bool {
        let markers = ["今天", "明天", "后天", "大后天", "明早", "明晚", "今晚", "次日", "第二天",
                       "周", "星期", "礼拜", "周末", "月", "/", "tomorrow", "tonight", "next"]
        return markers.contains { text.localizedCaseInsensitiveContains($0) }
    }

    // MARK: - Helpers

    private static func adjustedHour(_ hour: Int?, period: String?, bareIsAfternoon: Bool) -> Int? {
        guard var hour else { return nil }
        switch period {
        case "下午", "晚上", "傍晚":
            if hour < 12 { hour += 12 }
        case "中午":
            if hour < 11 { hour += 12 }
        case "凌晨":
            if hour == 12 { hour = 0 }
        default:
            // Only a spoken "3点" leans afternoon; "03:00" is taken literally.
            if bareIsAfternoon, hour < 7 { hour += 12 }
        }
        return min(max(hour, 0), 23)
    }

    /// A month/day with no year rolls forward when it has already passed.
    private static func upcomingMonthDay(_ month: Int, _ day: Int, now: Date, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.year], from: now)
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        guard var candidate = calendar.date(from: comps) else { return nil }
        if candidate < calendar.startOfDay(for: now) {
            comps.year = (comps.year ?? 0) + 1
            candidate = calendar.date(from: comps) ?? candidate
        }
        return candidate
    }

    /// 一 … 十 plus 半, which is all a spoken clock or a relative span needs.
    private static func chineseNumber(_ text: String) -> Double? {
        let map: [Character: Double] = [
            "一": 1, "两": 2, "二": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        if text == "半" { return 0.5 }
        if let value = Double(text) { return value }
        if text == "十" { return 10 }
        if text.hasPrefix("十") {
            let rest = text.dropFirst()
            return rest.isEmpty ? 10 : 10 + (map[rest.first!] ?? 0)
        }
        if text.hasSuffix("十") {
            let head = text.dropLast()
            return head.isEmpty ? 10 : (map[head.first!] ?? 0) * 10
        }
        if text.count == 1, let character = text.first { return map[character] }
        return nil
    }

    private static func hourValue(_ text: String) -> Int? {
        if let value = Int(text) { return value }
        return chineseNumber(text).map { Int($0) }
    }

    private static func adjustedForMeridiem(_ hour: Int?, suffix: String) -> Int? {
        guard let hour else { return nil }
        switch suffix {
        case "pm": return hour == 12 ? 12 : (hour < 12 ? hour + 12 : hour)
        case "am": return hour == 12 ? 0 : hour
        default: return hour
        }
    }

    private static func weekdayNumber(_ character: String) -> Int? {
        switch character {
        case "一": return 2
        case "二": return 3
        case "三": return 4
        case "四": return 5
        case "五": return 6
        case "六": return 7
        case "日", "天": return 1
        default: return nil
        }
    }

    /// `weekShift` follows the Chinese week: 0 means the nearest occurrence, 1 the
    /// next calendar week, 2 the one after, and -1 pins it inside this week even if
    /// that day has already passed. Weeks start on Monday.
    private static func dateFor(weekday: Int, weekShift: Int, from now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let currentWeekday = calendar.component(.weekday, from: today)   // 1 = Sunday
        let mondayOffset = (currentWeekday + 5) % 7                      // Sunday → 6, Monday → 0
        let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: today) ?? today
        let targetOffset = (weekday + 5) % 7

        var target = calendar.date(byAdding: .day, value: targetOffset, to: monday) ?? today
        if weekShift > 0 {
            target = calendar.date(byAdding: .day, value: 7 * weekShift, to: target) ?? target
        } else if weekShift == 0, target < today {
            target = calendar.date(byAdding: .day, value: 7, to: target) ?? target
        }
        return target
    }

    private static func cleaned(_ text: String, fallback: String) -> String {
        let trimmed = text
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "，,、.。;；:：-—"))
            .trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? fallback.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range)
    }

    private static func capture(_ index: Int, _ result: NSTextCheckingResult, _ text: String) -> String? {
        guard index < result.numberOfRanges,
              let range = Range(result.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    private static func removing(_ range: NSRange, from text: String) -> String {
        guard let swiftRange = Range(range, in: text) else { return text }
        return text.replacingCharacters(in: swiftRange, with: "")
    }
}
