import Testing
import Foundation

/// Generated corpus for the quick-add parser. Every sample carries what it should
/// produce, so a regression names the input instead of only shifting a percentage.
///
/// Two tiers:
/// - `core`  — forms we claim to support. Held to the 5-per-1000 error budget.
/// - `probe` — forms we have not implemented yet. Never fails the build; measured so
///   the value of a system-detector fallback can be compared against the cost of
///   simply writing another rule.
@MainActor
struct ParserCorpusTests {

    private struct Sample {
        let text: String
        /// nil means the input carries no date and must stay undated.
        var day: Int?
        var hour: Int?
        var minute: Int?
        var endDay: Int?
        var endHour: Int?
        var probe = false
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return calendar
    }

    /// Thursday, 2026-11-12, 10:00 local.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 10, minute: 0))!
    }

    // MARK: - Vocabulary

    private let days: [(String, Int)] = [
        ("今天", 0), ("今日", 0), ("明天", 1), ("明日", 1), ("后天", 2), ("大后天", 3)
    ]

    private let clocks: [(String, Int, Int)] = [
        ("18:00", 18, 0), ("9:30", 9, 30), ("23:00", 23, 0), ("07:15", 7, 15),
        ("12:00", 12, 0), ("15:45", 15, 45), ("10:20", 10, 20), ("17:00", 17, 0),
        ("下午3点", 15, 0), ("上午9点", 9, 0), ("晚上8点半", 20, 30), ("下午5点", 17, 0),
        ("早上7点", 7, 0), ("中午12点", 12, 0), ("晚上10点", 22, 0), ("下午1点", 13, 0)
    ]

    private let shortClocks: [(String, Int, Int)] = [
        ("20:00", 20, 0), ("09:00", 9, 0), ("15:30", 15, 30), ("10:00", 10, 0), ("18:00", 18, 0)
    ]

    private let titles: [String] = [
        "开会", "值班", "写方案", "复盘", "体检", "接人", "整理", "对账",
        "寄件", "还书", "交房租", "取快递", "回邮件", "跑步", "买菜", "面试",
        "培训", "直播", "看牙", "修车", "交周报", "开评审会", "给物业打电话", "收拾行李",
        "送孩子上学", "取体检报告", "约牙医", "续签合同", "停车缴费", "买猫粮",
        "复盘上周数据", "改简历", "回访客户", "交报销单", "订机票", "洗衣服",
        "健身", "读书", "记账", "遛狗"
    ]

    // MARK: - Corpus

    private func coreSamples() -> [Sample] {
        var out: [Sample] = []

        // 1. Day word, clock, title — the shape people actually type.
        for (dayWord, offset) in days {
            for (clock, hour, minute) in clocks {
                for title in titles {
                    out.append(Sample(text: "\(dayWord)\(clock) \(title)",
                                      day: offset, hour: hour, minute: minute))
                }
            }
        }
        // 6 × 16 × 40 = 3840

        // 2. Clock with no day word: it means today.
        for (clock, hour, minute) in clocks {
            for title in titles {
                out.append(Sample(text: "\(clock) \(title)", day: 0, hour: hour, minute: minute))
            }
        }
        // 640

        // 3. Day word with no clock: a date, no time.
        for (dayWord, offset) in days {
            for title in titles {
                out.append(Sample(text: "\(dayWord) \(title)", day: offset))
            }
        }
        // 240

        // 4. Same-day range.
        let pairs: [(String, String, Int, Int, Int)] = [
            ("18:00", "19:00", 18, 0, 19),
            ("9:30", "11:30", 9, 30, 11),
            ("下午3点", "下午5点", 15, 0, 17),
            ("上午9点", "中午11点", 9, 0, 11),
            ("晚上7点", "晚上9点", 19, 0, 21),
            ("18:00", "18:30", 18, 0, 18)
        ]
        for (dayWord, offset) in days {
            for (left, right, hour, minute, endHour) in pairs {
                for connector in ["到", "-", "至"] {
                    for title in titles.prefix(10) {
                        out.append(Sample(text: "\(dayWord)\(left)\(connector)\(right) \(title)",
                                          day: offset, hour: hour, minute: minute,
                                          endDay: offset, endHour: endHour))
                    }
                }
            }
        }
        // 6 × 6 × 3 × 10 = 1080

        // 5. Range that crosses midnight: the end rolls to the next day.
        let overnight: [(String, String, Int, Int, Int)] = [
            ("23:00", "2:00", 23, 0, 2), ("22:00", "1:00", 22, 0, 1),
            ("23:30", "6:00", 23, 30, 6), ("19:00", "3:00", 19, 0, 3)
        ]
        for (start, end, hour, minute, endHour) in overnight {
            for connector in ["到", "至", "~", "-"] {
                for (dayWord, offset) in days.prefix(4) {
                    for title in titles.prefix(10) {
                        out.append(Sample(text: "\(dayWord)\(start)\(connector)\(end) \(title)",
                                          day: offset, hour: hour, minute: minute,
                                          endDay: offset + 1, endHour: endHour))
                    }
                }
            }
        }
        // 4 × 4 × 4 × 10 = 640

        // 6. Range whose end names its own day.
        let explicitEnds: [(String, Int, String, Int)] = [
            ("今天", 0, "明天", 1), ("今天", 0, "后天", 2), ("明天", 1, "后天", 2),
            ("明天", 1, "大后天", 3), ("后天", 2, "大后天", 3)
        ]
        for (startWord, startOffset, endWord, endOffset) in explicitEnds {
            for connector in ["到", "至", "-"] {
                for title in titles.prefix(10) {
                    out.append(Sample(text: "\(startWord)18:00\(connector)\(endWord)10:00 \(title)",
                                      day: startOffset, hour: 18, minute: 0,
                                      endDay: endOffset, endHour: 10))
                }
            }
        }
        // 5 × 3 × 10 = 150

        // 7. Absolute dates.
        let fixedDays: [(String, Int)] = [
            ("11月15日", 3), ("11月20日", 8), ("12月1日", 19),
            ("12月25日", 43), ("2026-11-18", 6), ("11/25", 13)
        ]
        for (dateWord, offset) in fixedDays {
            for (clock, hour, minute) in shortClocks {
                for title in titles.prefix(8) {
                    out.append(Sample(text: "\(dateWord) \(clock) \(title)",
                                      day: offset, hour: hour, minute: minute))
                }
            }
        }
        // 6 × 5 × 8 = 240

        // 8. Weekday names resolve to the next occurrence.
        let weekdays: [(String, Int)] = [
            ("周一", 4), ("周二", 5), ("周三", 6), ("周四", 0),
            ("周五", 1), ("周六", 2), ("周日", 3)
        ]
        for (weekday, offset) in weekdays {
            for (clock, hour, minute) in shortClocks {
                for title in titles.prefix(8) {
                    out.append(Sample(text: "\(weekday)\(clock) \(title)",
                                      day: offset, hour: hour, minute: minute))
                }
            }
        }
        // 7 × 5 × 8 = 280

        // 9. 周末.
        for (clock, hour, minute) in shortClocks {
            for title in titles.prefix(8) {
                out.append(Sample(text: "周末\(clock) \(title)", day: 2, hour: hour, minute: minute))
            }
        }
        // 40

        // 10. The same range written with a leading 从.
        for (startWord, startOffset, endWord, endOffset) in explicitEnds {
            for title in titles.prefix(8) {
                out.append(Sample(text: "从\(startWord)18:00到\(endWord)10:00 \(title)",
                                  day: startOffset, hour: 18, minute: 0,
                                  endDay: endOffset, endHour: 10))
            }
        }
        // 40

        // 11. English.
        let english: [Sample] = [
            Sample(text: "standup tomorrow 9:00", day: 1, hour: 9, minute: 0),
            Sample(text: "call today 16:30", day: 0, hour: 16, minute: 30),
            Sample(text: "meeting 14:00 to 15:00", day: 0, hour: 14, minute: 0, endDay: 0, endHour: 15),
            Sample(text: "today 18:00-19:00 sync", day: 0, hour: 18, minute: 0, endDay: 0, endHour: 19),
            Sample(text: "tomorrow 9:00 to 10:30 standup", day: 1, hour: 9, minute: 0, endDay: 1, endHour: 10),
            Sample(text: "shift 23:00 till 2:00", day: 0, hour: 23, minute: 0, endDay: 1, endHour: 2),
            Sample(text: "review tomorrow 14:00 to 16:00", day: 1, hour: 14, minute: 0, endDay: 1, endHour: 16)
        ]
        for sample in english {
            for _ in 0..<10 { out.append(sample) }
        }
        // 70

        // 12. Title first, time at the end — the time has to be stripped from the tail.
        for (dayWord, offset) in days {
            for (clock, hour, minute) in clocks {
                for title in titles.prefix(30) {
                    out.append(Sample(text: "\(title) \(dayWord)\(clock)",
                                      day: offset, hour: hour, minute: minute))
                }
            }
        }
        // 6 × 16 × 30 = 2880

        return out
    }

    /// Forms we know are not implemented. Kept unambiguous so a rescue can be judged.
    private func probeSamples() -> [Sample] {
        [
            Sample(text: "今晚8点 吃饭", day: 0, hour: 20, probe: true),
            Sample(text: "明早8点 送孩子上学", day: 1, hour: 8, probe: true),
            Sample(text: "今晚八点 吃饭", day: 0, hour: 20, probe: true),
            Sample(text: "下午三点半 开会", day: 0, hour: 15, minute: 30, probe: true),
            Sample(text: "12月1号 交房租", day: 19, probe: true),
            Sample(text: "2026年12月1日 开会", day: 19, probe: true),
            Sample(text: "月底 结账", day: 18, probe: true),
            Sample(text: "三天后 回访客户", day: 3, probe: true),
            Sample(text: "半个月后 复查", day: 15, probe: true),
            Sample(text: "下周五下午3点 面试", day: 8, hour: 15, probe: true),
            Sample(text: "本周日 10:00 打球", day: 3, hour: 10, probe: true),
            Sample(text: "下周三 9:00 面试", day: 6, hour: 9, probe: true),
            Sample(text: "明天早上8点 送孩子上学", day: 1, hour: 8, probe: true),
            Sample(text: "tomorrow morning 9am standup", day: 1, hour: 9, probe: true),
            Sample(text: "Dec 1 rent", day: 19, probe: true),
            Sample(text: "tonight 8pm dinner", day: 0, hour: 20, probe: true),
            Sample(text: "in 2 hours call back", day: 0, hour: 12, probe: true),
            // False-positive bait: none of these carry a date.
            Sample(text: "买牛奶", probe: true),
            Sample(text: "PR #42 review", probe: true),
            Sample(text: "2026 年度总结", probe: true),
            Sample(text: "价格 3.5 元", probe: true)
        ]
    }

    // MARK: - Scoring

    private func mismatch(_ sample: Sample, _ parsed: ParsedTaskInput) -> String? {
        let calendar = calendar
        let now = now

        if sample.day == nil {
            return parsed.dueDate == nil ? nil : "unexpected date"
        }
        guard let due = parsed.dueDate else { return "no date" }

        let day = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                          to: calendar.startOfDay(for: due)).day
        if day != sample.day { return "day \(day ?? -99) != \(sample.day!)" }
        if let hour = sample.hour, calendar.component(.hour, from: due) != hour {
            return "hour \(calendar.component(.hour, from: due)) != \(hour)"
        }
        if let minute = sample.minute, calendar.component(.minute, from: due) != minute {
            return "minute \(calendar.component(.minute, from: due)) != \(minute)"
        }

        if let endDay = sample.endDay {
            guard let end = parsed.endDate else { return "missing end" }
            let actual = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                                 to: calendar.startOfDay(for: end)).day
            if actual != endDay { return "endDay \(actual ?? -99) != \(endDay)" }
            if let endHour = sample.endHour, calendar.component(.hour, from: end) != endHour {
                return "endHour \(calendar.component(.hour, from: end)) != \(endHour)"
            }
        } else if parsed.endDate != nil {
            return "unexpected end"
        }
        return nil
    }

    // MARK: - Tests

    /// The budget the user set: at most 5 wrong in 1000 inputs, rules only.
    @Test func rulesMeetTheErrorBudget() throws {
        let samples = coreSamples()
        var failures: [(text: String, problem: String)] = []

        for sample in samples {
            let parsed = NaturalDateParser.parse(sample.text, now: now, calendar: calendar)
            if let problem = mismatch(sample, parsed) {
                failures.append((sample.text, problem))
            }
        }

        let perThousand = Double(failures.count) / Double(samples.count) * 1000
        print("core: \(samples.count) samples, \(failures.count) wrong, \(String(format: "%.2f", perThousand)) per 1000")

        // Grouped, because 40 titles × one bad shape reads as 40 failures.
        var grouped: [String: [String]] = [:]
        for failure in failures {
            let shape = failure.problem.components(separatedBy: " != ").first ?? failure.problem
            grouped[shape, default: []].append(failure.text)
        }
        for (shape, texts) in grouped.sorted(by: { $0.value.count > $1.value.count }).prefix(15) {
            print("  ✗ ×\(texts.count) [\(shape)] \(texts.prefix(2).joined(separator: " / "))")
        }

        #expect(perThousand <= 5, "budget is 5 per 1000")
    }

    /// Attribution for the fallback question: how much would a system detector
    /// actually add, and how much would it get wrong?
    ///
    /// The detector only ever runs when the rules return nothing, so its addressable
    /// surface is the "rules said nothing" bucket — not the "rules were wrong" one.
    @Test func systemFallbackAttribution() throws {
        let samples = coreSamples() + probeSamples()
        var solvedByRules = 0
        var rulesWrong = 0
        var rescued = 0
        var detectorWrong = 0
        var unresolved: [String] = []
        var rescuedLines: [String] = []
        var wrongLines: [String] = []
        var probeWrongLines: [String] = []

        for sample in samples {
            let rules = NaturalDateParser.parse(sample.text, now: now, calendar: calendar)
            let withFallback = NaturalDateParser.parse(sample.text, now: now, calendar: calendar,
                                                       useSystemFallback: true)

            if mismatch(sample, rules) == nil {
                solvedByRules += 1
                continue
            }
            if rules.dueDate != nil {
                // A wrong answer is not something a fallback can reach.
                rulesWrong += 1
                if sample.probe {
                    probeWrongLines.append("probe: \(sample.text) → \(mismatch(sample, rules) ?? "")")
                }
                continue
            }
            if mismatch(sample, withFallback) == nil {
                rescued += 1
                rescuedLines.append("rescued: \(sample.text)")
            } else if withFallback.dueDate != nil {
                detectorWrong += 1
                wrongLines.append("wrong: \(sample.text) → \(mismatch(sample, withFallback) ?? "")")
            } else {
                unresolved.append(sample.text)
            }
        }

        let total = samples.count
        func pct(_ n: Int) -> String { String(format: "%.2f%%", Double(n) / Double(total) * 100) }

        print("""
        fallback study · \(total) samples
          solved by rules        \(solvedByRules) (\(pct(solvedByRules)))
          wrong, unreachable     \(rulesWrong) (\(pct(rulesWrong)))
          no date from rules     \(total - solvedByRules - rulesWrong)
            ├ rescued by detector \(rescued) (\(pct(rescued)))
            ├ detector wrong      \(detectorWrong) (\(pct(detectorWrong)))
            └ left unresolved     \(unresolved.count) (\(pct(unresolved.count)))
        """)
        for line in probeWrongLines.prefix(12) { print("  ~", line) }
        for line in rescuedLines.prefix(12) { print("  +", line) }
        for line in wrongLines.prefix(12) { print("  !", line) }
        for line in unresolved.prefix(12) { print("  ·", line) }

        #expect(rescued + detectorWrong == total - solvedByRules - rulesWrong - unresolved.count,
                "every rules-nil case lands in exactly one bucket")
    }

    /// Asked directly, because the attribution test can never reach the detector
    /// when the rules correctly say "no date" — that short-circuit hides false positives.
    @Test func detectorFalsePositives() throws {
        let bait = [
            "买牛奶", "PR #42 review", "价格 3.5 元", "买了3个苹果",
            "2026 年度总结", "8 楼开会", "Wi-Fi 密码 12345678", "第5章",
            "给3个人回消息", "周三之前要交"      // last one may legitimately parse
        ]
        var hits: [String] = []
        for text in bait {
            if let found = SystemDateFallback.date(in: text, now: now, calendar: calendar) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                hits.append("\(text) → \(formatter.string(from: found))")
            }
        }
        print("detector false positives: \(hits.count)/\(bait.count)")
        for line in hits { print("  !", line) }

        #expect(!hits.contains { $0.hasPrefix("买牛奶") })
        #expect(!hits.contains { $0.hasPrefix("PR #42") })
        #expect(!hits.contains { $0.hasPrefix("2026 年度总结") })
    }

    /// The four shapes nothing handles yet, listed so the next rule has a target.
    @Test func knownGaps() throws {
        let gaps = ["月底 结账", "三天后 回访客户", "半个月后 复查", "in 2 hours call back"]
        for text in gaps {
            let parsed = NaturalDateParser.parse(text, now: now, calendar: calendar)
            print("gap: \(text) → due \(parsed.dueDate == nil ? "nil" : "set"), title \(parsed.title)")
        }
    }
}
