import Foundation

struct ParsedTaskInput {
    var title: String
    var dueDate: Date?
    var hasTime: Bool
}

/// A deliberately small natural-date parser for the quick-add field.
///
/// It understands the handful of expressions people actually type in a todo
/// app — 今天 / 明天 / 后天 / 周三 / 下周一 / 10月20日 / 下午3点 / 15:30 —
/// and leaves everything else alone. No AI, no surprises, no rewriting of the
/// user's sentence beyond removing the words it consumed.
enum NaturalDateParser {

    static func parse(_ raw: String, now: Date = .now, calendar: Calendar = .current) -> ParsedTaskInput {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return ParsedTaskInput(title: raw, dueDate: nil, hasTime: false)
        }

        var hour: Int?
        var minute = 0
        var impliedEvening = false

        // 1. Explicit clock time: 15:30
        if let result = firstMatch(#"(上午|下午|晚上|中午|早上|凌晨|傍晚)?\s*(\d{1,2})\s*[:：]\s*(\d{2})"#, in: text) {
            let period = capture(1, result, text)
            hour = Int(capture(2, result, text) ?? "")
            minute = Int(capture(3, result, text) ?? "") ?? 0
            hour = adjustedHour(hour, period: period)
            text = removing(result.range, from: text)
        }
        // 2. Spoken clock time: 下午3点 / 8点半 / 7点15分
        else if let result = firstMatch(#"(上午|下午|晚上|中午|早上|凌晨|傍晚)?\s*(\d{1,2})\s*点\s*(半|\d{1,2}\s*分)?"#, in: text) {
            let period = capture(1, result, text)
            hour = Int(capture(2, result, text) ?? "")
            let tail = capture(3, result, text) ?? ""
            if tail.contains("半") {
                minute = 30
            } else if let value = Int(tail.replacingOccurrences(of: "分", with: "").trimmingCharacters(in: .whitespaces)) {
                minute = value
            }
            hour = adjustedHour(hour, period: period)
            text = removing(result.range, from: text)
        }

        // 3. Day expression
        var dayOffset: Int?
        var weekdayTarget: Int?
        var nextWeek = false
        var fixedDay: Date?

        let dayKeywords: [(String, Int)] = [
            ("大后天", 3), ("后天", 2), ("明天", 1), ("明日", 1),
            ("今天", 0), ("今日", 0), ("今晚", 0)
        ]

        for (keyword, offset) in dayKeywords {
            if text.contains(keyword) {
                dayOffset = offset
                if keyword == "今晚" { impliedEvening = true }
                text = text.replacingOccurrences(of: keyword, with: "")
                break
            }
        }

        if dayOffset == nil, let result = firstMatch(#"(下下|下)?\s*(?:周|星期|礼拜)\s*([一二三四五六日天])"#, in: text) {
            let prefix = capture(1, result, text) ?? ""
            let dayChar = capture(2, result, text) ?? ""
            weekdayTarget = weekdayNumber(dayChar)
            nextWeek = !prefix.isEmpty
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

        // 4. Compose the date
        var dueDate: Date?
        var hasTime = hour != nil

        if let hour {
            var base = calendar.startOfDay(for: now)
            if let offset = dayOffset {
                base = calendar.date(byAdding: .day, value: offset, to: base) ?? base
            } else if let weekday = weekdayTarget {
                base = dateFor(weekday: weekday, nextWeek: nextWeek, from: now, calendar: calendar)
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
            dueDate = dateFor(weekday: weekday, nextWeek: nextWeek, from: now, calendar: calendar)
        } else if let fixedDay {
            dueDate = fixedDay
        }

        let title = cleaned(text, fallback: raw)
        return ParsedTaskInput(title: title, dueDate: dueDate, hasTime: hasTime)
    }

    // MARK: - Helpers

    private static func adjustedHour(_ hour: Int?, period: String?) -> Int? {
        guard var hour else { return nil }
        switch period {
        case "下午", "晚上", "傍晚":
            if hour < 12 { hour += 12 }
        case "中午":
            if hour < 11 { hour += 12 }
        case "凌晨":
            if hour == 12 { hour = 0 }
        default:
            break
        }
        return min(max(hour, 0), 23)
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

    private static func dateFor(weekday: Int, nextWeek: Bool, from now: Date, calendar: Calendar) -> Date {
        let current = calendar.component(.weekday, from: now)
        var delta = (weekday - current + 7) % 7
        if nextWeek { delta += 7 }
        let base = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: delta, to: base) ?? base
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
