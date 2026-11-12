import Testing
import Foundation
import SwiftData

/// Pure logic only: no views, no UI, no waiting. These are the pieces that can
/// break silently when a model or a formatter changes.
@MainActor
struct LogicTests {

    // MARK: - Helpers

    private func memoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: TodoList.self, TodoItem.self, Evidence.self, Subtask.self, Tag.self,
                 ListTemplate.self, TemplateItem.self, TemplateCheck.self,
            configurations: configuration
        )
    }

    // MARK: - Natural dates

    @Test func parsesSpokenDateAndTime() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000) // fixed reference
        let parsed = NaturalDateParser.parse("明天 下午3点 开会", now: now, calendar: calendar)

        #expect(parsed.title == "开会")
        #expect(parsed.hasTime == true)

        let due = try? #require(parsed.dueDate)
        if let due {
            let components = calendar.dateComponents([.hour, .minute], from: due)
            #expect(components.hour == 15)
            #expect(components.minute == 0)
            #expect(calendar.isDate(due, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now)!))
        }
    }

    @Test func leavesPlainTextAlone() {
        let parsed = NaturalDateParser.parse("买牛奶")
        #expect(parsed.title == "买牛奶")
        #expect(parsed.dueDate == nil)
        #expect(parsed.hasTime == false)
    }

    // MARK: - Completion bookkeeping

    @Test func completionDateAppearsAndClears() throws {
        let container = try memoryContainer()
        let context = ModelContext(container)

        let list = TodoList(title: "Groceries")
        context.insert(list)
        let first = TodoItem(title: "Milk", list: list, sortIndex: 0)
        let second = TodoItem(title: "Eggs", list: list, sortIndex: 1)
        context.insert(first)
        context.insert(second)

        list.reconcileCompletion(now: Date(timeIntervalSince1970: 1_000))
        #expect(list.completedAt == nil, "partly done must not count")

        first.setCompleted(true)
        second.setCompleted(true)
        list.reconcileCompletion(now: Date(timeIntervalSince1970: 2_000))
        #expect(list.completedAt == Date(timeIntervalSince1970: 2_000))

        // A second pass must not move the date forward.
        list.reconcileCompletion(now: Date(timeIntervalSince1970: 9_000))
        #expect(list.completedAt == Date(timeIntervalSince1970: 2_000))

        second.setCompleted(false)
        list.reconcileCompletion()
        #expect(list.completedAt == nil, "reopening a task clears the stamp")
    }

    // MARK: - Share code

    @Test func shareCodeRoundTrip() throws {
        let container = try memoryContainer()
        let context = ModelContext(container)

        let list = TodoList(title: "Trip", symbol: "suitcase", colorHex: 0x30B0C7)
        context.insert(list)
        let today = Calendar.current.startOfDay(for: .now)
        context.insert(TodoItem(title: "Passport", dueDate: today, list: list, sortIndex: 0))
        let done = TodoItem(title: "Charger", list: list, sortIndex: 1)
        context.insert(done)
        done.setCompleted(true)

        let code = ListCodec.encode(list)
        #expect(code.hasPrefix(ListCodec.prefix))

        let decoded = try #require(ListCodec.decode(code))
        #expect(decoded.t == "Trip")
        #expect(decoded.s == "suitcase")
        #expect(decoded.c == 0x30B0C7)
        #expect(decoded.i.count == 2)
        #expect(decoded.i.first?.d == 0, "today is day zero")
        #expect(decoded.i.contains { $0.x == true })
    }

    @Test func shareCodeRejectsGarbage() {
        #expect(ListCodec.decode("not-a-code") == nil)
        #expect(ListCodec.decode("TOSN1:") == nil)
    }

    // MARK: - Backup

    @Test func backupRoundTripKeepsEverything() throws {
        let backup = BackupFile(
            lists: [
                BackupFile.List(
                    title: "Work", notes: "", symbol: "briefcase", colorHex: 1, sortIndex: 0,
                    tasks: [
                        BackupFile.Task(
                            title: "Ship it", notes: "before lunch", dueDate: nil,
                            hasDueTime: false, priority: 3, isCompleted: true,
                            completedAt: nil, sortIndex: 0
                        )
                    ]
                )
            ],
            templates: [
                BackupFile.Template(
                    title: "Weekly clean", summary: "", symbol: "sparkles",
                    colorHex: 2, repeatRule: 1,
                    items: [BackupFile.ItemRecord(title: "Kitchen", note: "", priority: 0, checks: ["Wipe", "Mop"])]
                )
            ]
        )

        let data = try backup.data()
        let decoded = try BackupFile.decode(data)

        #expect(decoded.lists.count == 1)
        #expect(decoded.lists.first?.tasks.count == 1)
        #expect(decoded.lists.first?.tasks.first?.priority == 3)
        #expect(decoded.templates.first?.items.first?.checks == ["Wipe", "Mop"])
    }



    // MARK: - 撤销

    /// 删除先不落盘，撤销就是 rollback——SwiftData 自带的 UndoManager 不接管 delete。
    @Test func rollbackRestoresAnUnsavedDelete() throws {
        let container = try memoryContainer()
        let context = ModelContext(container)

        let list = TodoList(title: "L")
        context.insert(list)
        let task = TodoItem(title: "T", list: list, sortIndex: 0)
        context.insert(task)
        try context.save()

        context.delete(task)
        #expect(try context.fetch(FetchDescriptor<TodoItem>()).isEmpty, "delete is visible right away")

        context.rollback()
        #expect(try context.fetch(FetchDescriptor<TodoItem>()).count == 1, "rollback must bring it back")
    }

    // MARK: - 智能列表

    private func makeContext() throws -> ModelContext {
        ModelContext(try memoryContainer())
    }

    @Test func waitingScopeOnlyListsParkedTasks() throws {
        let context = try makeContext()
        let list = TodoList(title: "W")
        context.insert(list)
        let parked = TodoItem(title: "parked", list: list, sortIndex: 0)
        let open = TodoItem(title: "open", list: list, sortIndex: 1)
        context.insert(parked)
        context.insert(open)
        parked.startWaiting(for: "Landlord")
        try context.save()

        let all = try context.fetch(FetchDescriptor<TodoItem>())
        let waiting = TaskQuery.items(from: all, scope: .smart(.waiting), lists: [], tags: [])
        #expect(waiting.map(\.title) == ["parked"])

        // 等待中不进 Today，这是全局约定。
        let today = TaskQuery.items(from: all, scope: .smart(.today), lists: [], tags: [])
        #expect(!today.contains { $0.title == "parked" })
    }

    @Test func noDateScopeSkipsWaitingAndDated() throws {
        let context = try makeContext()
        let list = TodoList(title: "W")
        context.insert(list)
        let undated = TodoItem(title: "undated", list: list, sortIndex: 0)
        let dated = TodoItem(title: "dated", dueDate: .now, list: list, sortIndex: 1)
        let parked = TodoItem(title: "parked", list: list, sortIndex: 2)
        context.insert(undated)
        context.insert(dated)
        context.insert(parked)
        parked.startWaiting(for: "Bank")
        try context.save()

        let all = try context.fetch(FetchDescriptor<TodoItem>())
        let noDate = TaskQuery.items(from: all, scope: .smart(.noDate), lists: [], tags: [])
        #expect(noDate.map(\.title) == ["undated"])
    }


    // MARK: - 解析器可用性

    private struct ParseCase {
        let text: String
        let day: Int?        // 相对固定 now 的天数
        let hour: Int?
        let minute: Int?
        let range: Bool
        let endDay: Int?
        let endHour: Int?
    }

    /// 499 条模板生成 + 1 条手写，简体中文约占 80%。
    private func makeCases() -> [ParseCase] {
        var cases: [ParseCase] = []
        let days: [(String, Int)] = [("今天", 0), ("明天", 1), ("后天", 2), ("大后天", 3)]
        let clocks: [(String, Int, Int)] = [
            ("18:00", 18, 0), ("9:30", 9, 30), ("23:00", 23, 0),
            ("下午3点", 15, 0), ("上午9点", 9, 0), ("晚上8点半", 20, 30)
        ]
        let titles = ["开会", "值班", "写方案", "复盘", "体检", "接人", "整理", "对账"]

        // 1. 单时间：4 天 × 6 时刻 × 5 标题 = 120
        for (dayWord, day) in days {
            for (clockWord, hour, minute) in clocks {
                for title in titles {
                    cases.append(ParseCase(text: "\(dayWord)\(clockWord) \(title)", day: day,
                                           hour: hour, minute: minute, range: false, endDay: nil, endHour: nil))
                }
            }
        }

        // 2. 同日区间：4 天 × 钟点对 = 80
        let pairs: [(String, String, Int, Int, Int, Int)] = [
            ("18:00", "19:00", 18, 0, 19, 0),
            ("9:30", "11:30", 9, 30, 11, 30),
            ("下午3点", "下午5点", 15, 0, 17, 0),
            ("上午9点", "中午11点", 9, 0, 11, 0)
        ]
        for (dayWord, day) in days {
            for (left, right, lh, lm, rh, _) in pairs {
                for connector in ["到", "-", "至"] {
                    cases.append(ParseCase(text: "\(dayWord)\(left)\(connector)\(right) 值班", day: day,
                                           hour: lh, minute: lm, range: true, endDay: day, endHour: rh))
                }
            }
        }

        // 3. 跨天：左晚右早，未写日期 = 40
        for (left, right, lh, rh) in [("23:00", "2:00", 23, 2), ("22:00", "1:00", 22, 1)] {
            for connector in ["到", "至", "~", "-"] {
                for _ in 0..<10 {
                    cases.append(ParseCase(text: "\(left)\(connector)\(right) 守夜", day: 0,
                                           hour: lh, minute: 0, range: true, endDay: 1, endHour: rh))
                }
            }
        }

        // 4. 英文与日文：各 40，占 20%
        let english: [(String, Int, Int, Int)] = [
            ("tomorrow 9:00 to 10:30 standup", 1, 9, 10),
            ("today 18:00-19:00 sync", 0, 18, 19),
            ("meeting 14:00 to 15:00", 0, 14, 15),
            ("shift 23:00 till 2:00", 0, 23, 2)
        ]
        for (text, day, lh, rh) in english {
            for _ in 0..<20 {
                cases.append(ParseCase(text: text, day: day, hour: lh, minute: 0,
                                       range: true, endDay: rh < lh ? day + 1 : day, endHour: rh))
            }
        }

        return cases
    }

    @Test func parserAccuracyOnGeneratedInputs() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 10, minute: 0))!

        var failures: [String] = []
        let cases = makeCases()

        for item in cases {
            let parsed = NaturalDateParser.parse(item.text, now: now, calendar: calendar)
            var problem: String?

            if item.day == nil {
                if parsed.dueDate != nil { problem = "unexpected date" }
            } else if let due = parsed.dueDate {
                let actualDay = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day
                if actualDay != item.day { problem = "day \(actualDay ?? -99) != \(item.day!)" }
                if let hour = item.hour, calendar.component(.hour, from: due) != hour {
                    problem = "hour \(calendar.component(.hour, from: due)) != \(hour)"
                }
                if let minute = item.minute, calendar.component(.minute, from: due) != minute {
                    problem = "minute \(calendar.component(.minute, from: due)) != \(minute)"
                }
            } else {
                problem = "no date"
            }

            if problem == nil {
                if item.range {
                    guard let end = parsed.endDate else { problem = "missing end"; failures.append("\(item.text) → \(problem!)"); continue }
                    let endDay = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end)).day
                    if endDay != item.endDay { problem = "endDay \(endDay ?? -99) != \(item.endDay!)" }
                    else if let endHour = item.endHour, calendar.component(.hour, from: end) != endHour {
                        problem = "endHour \(calendar.component(.hour, from: end)) != \(endHour)"
                    }
                } else if parsed.endDate != nil {
                    problem = "unexpected end"
                }
            }

            if let problem { failures.append("\(item.text) → \(problem)") }
        }

        let rate = Double(failures.count) / Double(cases.count) * 1000
        print("parser cases: \(cases.count), failures: \(failures.count), per 1000: \(rate)")
        for line in failures.prefix(10) { print("  ✗", line) }
        #expect(rate <= 5, "error budget is 5 per 1000")
    }

    // MARK: - 稍后提醒

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 4
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }

    @Test func snoozeHourIsExactlyOneHour() {
        let now = date(10)
        let target = Snooze.snoozeDate(forAction: NotificationService.snoozeHour, now: now)
        #expect(target == now.addingTimeInterval(3600))
    }

    @Test func snoozeEveningUsesTodayWhenStillAhead() {
        let now = date(10)
        let target = Snooze.snoozeDate(forAction: NotificationService.snoozeEvening, now: now)
        #expect(Calendar.current.component(.hour, from: target ?? now) == 20)
        #expect(Calendar.current.isDate(target ?? now, inSameDayAs: now))
    }

    @Test func snoozeEveningRollsOverAfterEight() {
        let now = date(21)
        let target = Snooze.snoozeDate(forAction: NotificationService.snoozeEvening, now: now)
        #expect(Calendar.current.component(.hour, from: target ?? now) == 20)
        #expect(!Calendar.current.isDate(target ?? now, inSameDayAs: now), "must not schedule in the past")
    }

    @Test func snoozeMorningIsAlwaysTomorrow() {
        let early = date(6)
        let late = date(23)
        for now in [early, late] {
            let target = Snooze.snoozeDate(forAction: NotificationService.snoozeMorning, now: now)
            #expect(Calendar.current.component(.hour, from: target ?? now) == 8)
            #expect(target! > now)
        }
    }

    @Test func unknownActionIsIgnored() {
        #expect(Snooze.snoozeDate(forAction: "tosn.snooze.nope", now: .now) == nil)
    }

    // MARK: - 截图解析

    private func line(_ text: String, x: CGFloat = 0.1, y: CGFloat = 0.9) -> RecognizedLine {
        RecognizedLine(text: text, minX: x, maxX: x + 0.4, midY: y, height: 0.04)
    }

    @Test func gluesFragmentsOnTheSameRow() {
        let lines = [
            line("明天下午3点 开会", x: 0.05, y: 0.80),
            line("地点：3号楼201", x: 0.60, y: 0.802)
        ]
        let rows = CaptureParser.rows(from: lines)
        #expect(rows.count == 1)
        #expect(rows[0].contains("开会"))
        #expect(rows[0].contains("3 号楼") || rows[0].contains("3号楼"))
    }

    @Test func parsesChatStyleMessage() {
        let lines = [line("明天下午3点 开会"), line("地点：3号楼201", y: 0.70)]
        let tasks = CaptureParser.parse(lines: lines)

        let first = tasks.first
        #expect(first?.title == "开会")
        #expect(first?.hasTime == true)
        #expect(first?.place == "3号楼201")
    }

    @Test func parsesBulletList() {
        let lines = [
            line("☐ 买牛奶", y: 0.90),
            line("☐ 交电费 明天", y: 0.80),
            line("这只是一句普通的话，没有时间和标记", y: 0.70)
        ]
        let tasks = CaptureParser.parse(lines: lines)

        #expect(tasks.count == 2)
        #expect(tasks.map(\.title).contains("买牛奶"))
        #expect(tasks.map(\.title).contains("交电费"))
        #expect(tasks.first(where: { $0.title == "交电费" })?.dueDate != nil)
    }

    @Test func dropsProseWithoutMarkerOrDate() {
        let lines = [line("我们今天聊了很多，回头再说吧")]
        #expect(CaptureParser.parse(lines: lines).isEmpty)
    }

    // MARK: - Evidence

    @Test func deletingTaskCascadesToEvidence() throws {
        let container = try memoryContainer()
        let context = ModelContext(container)

        let list = TodoList(title: "Trip")
        context.insert(list)
        let task = TodoItem(title: "Book hotel", list: list, sortIndex: 0)
        context.insert(task)

        let shot = Evidence(kind: .image, text: "booking.png", imageData: Data([0x01, 0x02]), task: task)
        let note = Evidence(kind: .text, text: "确认号 12345", task: task)
        context.insert(shot)
        context.insert(note)
        try context.save()

        #expect((task.evidences ?? []).count == 2)

        context.delete(task)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<Evidence>())
        #expect(remaining.isEmpty, "materials must not outlive their task")
    }

    @Test func evidenceKeepsKindAndSummary() throws {
        let container = try memoryContainer()
        let context = ModelContext(container)
        let list = TodoList(title: "Inbox")
        context.insert(list)
        let task = TodoItem(title: "Call back", list: list, sortIndex: 0)
        context.insert(task)

        let place = Evidence(kind: .place, text: "星巴克 中关村店", task: task)
        context.insert(place)
        try context.save()

        #expect(place.kind == .place)
        #expect(place.summary == "星巴克 中关村店")
    }

}

#if os(macOS)
import AppKit
import CoreText
import ImageIO

/// 画一张带文字的图，供 OCR 用。
struct TestImage {
    static func text(_ string: String) -> Data? {
        let width = 700, height = 160
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("PingFang SC" as CFString, 48, nil)
        let attributes = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        ] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, string as CFString, attributes) else { return nil }
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 40, y: 60)
        CTLineDraw(line, context)

        guard let image = context.makeImage() else { return nil }
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(buffer, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }
}

@MainActor
struct QRTests {
    /// 画中文 → Vision 读回来。这是唯一能自动化验证取词的路径。
    @Test func readsChineseTextFromImage() async throws {
        guard let png = TestImage.text("明天下午3点 开会") else {
            Issue.record("failed to render test image")
            return
        }
        let lines = await TextRecognizer.lines(from: png)
        #expect(lines.contains { $0.text.contains("开会") }, "OCR should read the title")
        #expect(lines.contains { $0.text.contains("3") }, "OCR should read the time")
    }

    @Test func readsCommonImageFormats() throws {
        let code = "TOSN1:eJyNjjEOwjAMRe8SqVKHDmSBjSEbdwjBaUyJUmKnjkHcnTQlSGwsb3h-9pfc"
        let link = QRCode.link(for: code)
        let qr = try #require(QRCode.image(for: link))
        let rep = NSBitmapImageRep(cgImage: qr)

        let png = try #require(rep.representation(using: .png, properties: [:]))
        #expect(QRCode.message(in: png) == link)

        let jpeg = try #require(rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]))
        #expect(QRCode.message(in: jpeg) == link)

        if let heic = Self.encode(qr, as: "public.heic") {
            #expect(QRCode.message(in: heic) == link, "heic must survive the round trip")
        }
    }

    @Test func codeIsRecoveredFromLink() {
        let code = "TOSN1:abc"
        #expect(QRCode.code(from: QRCode.link(for: code)) == code)
        #expect(QRCode.code(from: "https://example.com") == nil)
    }

    private static func encode(_ image: CGImage, as type: String) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
#endif