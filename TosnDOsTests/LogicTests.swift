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


    /// 特殊写法单独断言：这类靠组合生成覆盖不到。
    @Test func specialDateParsing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        // 2026-11-12 是星期四
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 10, minute: 0))!

        func offset(_ date: Date?) -> Int? {
            guard let date else { return nil }
            return calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day
        }

        // 周末 = 本周六
        let weekend = NaturalDateParser.parse("周末 10:00 买菜", now: now, calendar: calendar)
        #expect(offset(weekend.dueDate) == 2)
        #expect(calendar.component(.hour, from: weekend.dueDate ?? now) == 10)

        // 周X / 下周X
        #expect(offset(NaturalDateParser.parse("周五 14:00 复盘", now: now, calendar: calendar).dueDate) == 1)
        #expect(offset(NaturalDateParser.parse("下周三 9:00 面试", now: now, calendar: calendar).dueDate) == 6)

        // 11/15 与 11月15日 等价
        let slash = NaturalDateParser.parse("11/15 20:00 直播", now: now, calendar: calendar)
        #expect(offset(slash.dueDate) == 3)
        let spoken = NaturalDateParser.parse("11月15日 20:00 直播", now: now, calendar: calendar)
        #expect(offset(spoken.dueDate) == 3)

        // 跨年的月日：10月20日 已经过去 → 落到明年
        let past = NaturalDateParser.parse("10月20日 开会", now: now, calendar: calendar)
        #expect(calendar.component(.year, from: past.dueDate ?? now) == 2027)

        // 没有任何日期词 → 不应解析出时间
        let plain = NaturalDateParser.parse("买咖啡", now: now, calendar: calendar)
        #expect(plain.dueDate == nil)
        #expect(plain.title == "买咖啡")

        // 多个时间：取第一个，其余留在标题里
        let multi = NaturalDateParser.parse("3点和5点开会", now: now, calendar: calendar)
        #expect(calendar.component(.hour, from: multi.dueDate ?? now) == 15)

        // 误判防护：日期里的连字符不该被当成区间
        let dated = NaturalDateParser.parse("2026-11-13 10:00-12:00 培训", now: now, calendar: calendar)
        #expect(offset(dated.dueDate) == 1)
        #expect(dated.endDate != nil)
        #expect(calendar.component(.hour, from: dated.endDate ?? now) == 12)

        // 误判防护：到底 / 迟到 不含时间语义
        #expect(NaturalDateParser.parse("到底要不要去", now: now, calendar: calendar).dueDate == nil)
        #expect(NaturalDateParser.parse("迟到了要罚钱", now: now, calendar: calendar).dueDate == nil)
    }


    // MARK: - 跨天归属

    /// A range shows on every day it touches but counts only where it ends.
    @Test func rangeCountsOnlyOnItsLastDay() throws {
        let container = try memoryContainer()
        let context = ModelContext(container)
        let list = TodoList(title: "Shift")
        context.insert(list)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 10))!

        // 18:00 today → 02:00 tomorrow: visible today, counted tomorrow.
        let ahead = TodoItem(title: "night shift", dueDate: now, hasDueTime: true, list: list, sortIndex: 0)
        ahead.dueDate = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now)
        ahead.endDate = calendar.date(byAdding: .day, value: 1,
                                      to: calendar.date(bySettingHour: 2, minute: 0, second: 0, of: now)!)

        // 22:00 yesterday → 02:00 today: visible today, counted today.
        let ended = TodoItem(title: "last night", dueDate: now, hasDueTime: true, list: list, sortIndex: 1)
        ended.dueDate = calendar.date(byAdding: .day, value: -1,
                                      to: calendar.date(bySettingHour: 22, minute: 0, second: 0, of: now)!)
        ended.endDate = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: now)
        try context.save()

        let snapshot = TodayScope.snapshot(from: [ahead, ended], now: now, calendar: calendar)
        #expect(snapshot.open.count == 2, "both are visible today")
        #expect(snapshot.total == 1, "only the one ending today is counted")
    }




    // MARK: - 大清单

    /// Nothing here was ever measured. A loose bound only: it catches a change that
    /// turns filtering quadratic, not a 10% regression.
    @Test func aLargeListStaysResponsive() throws {
        let container = try memoryContainer()
        let context = ModelContext(container)
        let list = TodoList(title: "Big")
        context.insert(list)

        let now = Date()
        for index in 0..<500 {
            let task = TodoItem(
                title: "task \(index)",
                dueDate: now.addingTimeInterval(Double(index) * 60),
                hasDueTime: true,
                list: list,
                sortIndex: Double(index)
            )
            context.insert(task)
        }
        try context.save()

        let all = try context.fetch(FetchDescriptor<TodoItem>())

        let snapshotStart = Date()
        let snapshot = TodayScope.snapshot(from: all, now: now)
        let snapshotCost = Date().timeIntervalSince(snapshotStart)

        let queryStart = Date()
        let todays = TaskQuery.items(from: all, scope: .smart(.today), lists: [], tags: [])
        let queryCost = Date().timeIntervalSince(queryStart)

        print(String(format: "perf · 500 tasks · snapshot %.1f ms · query %.1f ms · %d open",
                     snapshotCost * 1000, queryCost * 1000, todays.count))
        #expect(snapshot.total > 0)
        #expect(snapshotCost < 0.5, "snapshot must not crawl on a big list")
        #expect(queryCost < 0.5, "filtering must not crawl on a big list")
    }

    // MARK: - 重复模板账本

    private func scheduleCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return calendar
    }

    /// Noon on 2026-11-12, so day arithmetic never straddles midnight.
    private func scheduleBase(_ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!
    }

    private func day(_ offset: Int, from base: Date, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: offset, to: base)!
    }

    @Test func latestAndAllLeaveDifferentLedgers() {
        let calendar = scheduleCalendar()
        let base = scheduleBase(calendar)
        let missed = (0..<3).map { day($0, from: base, calendar) }

        let latest = RepeatSchedule.ledger(for: missed, taking: [missed[2]])
        #expect(latest.map(\.outcome) == [.skipped, .skipped, .generated])

        let all = RepeatSchedule.ledger(for: missed, taking: missed)
        #expect(all.allSatisfy { $0.outcome == .generated })

        let skip = RepeatSchedule.ledger(for: missed, taking: [])
        #expect(skip.allSatisfy { $0.outcome == .skipped })
    }

    @Test func aManualPullDoesNotCloseAPeriod() {
        let calendar = scheduleCalendar()
        let base = scheduleBase(calendar)
        let log = [PeriodRecord(start: base, outcome: .manual)]

        let missed = RepeatSchedule.missedStarts(
            anchor: base, rule: .daily, log: log, lastGeneratedAt: nil,
            now: day(2, from: base, calendar), calendar: calendar, limit: 30
        )
        #expect(missed.count == 3, "the period is logged but still offered")
    }

    @Test func skippedPeriodsAreNotOfferedAgain() {
        let calendar = scheduleCalendar()
        let base = scheduleBase(calendar)
        let log = [
            PeriodRecord(start: base, outcome: .skipped),
            PeriodRecord(start: day(1, from: base, calendar), outcome: .skipped)
        ]

        let missed = RepeatSchedule.missedStarts(
            anchor: base, rule: .daily, log: log, lastGeneratedAt: nil,
            now: day(2, from: base, calendar), calendar: calendar, limit: 30
        )
        #expect(missed == [day(2, from: base, calendar)])
    }

    @Test func legacyTemplateFallsBackToItsLastGeneratedDate() {
        let calendar = scheduleCalendar()
        let base = scheduleBase(calendar)

        let missed = RepeatSchedule.missedStarts(
            anchor: base, rule: .daily, log: [], lastGeneratedAt: day(1, from: base, calendar),
            now: day(2, from: base, calendar), calendar: calendar, limit: 30
        )
        #expect(missed == [day(2, from: base, calendar)], "older periods stay settled")
    }

    @Test func monthlyPeriodsClampToShortMonths() {
        let calendar = scheduleCalendar()
        let january31 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 12))!
        let february = RepeatSchedule.start(anchor: january31, rule: .monthly, index: 1, calendar: calendar)!
        #expect(calendar.component(.month, from: february) == 2)
        #expect(calendar.component(.day, from: february) == 28)
    }


    /// The ledger is a new attribute; this proves SwiftData round-trips it and that a
    /// template written before the ledger existed still reads as nil.
    @Test func periodLedgerSurvivesARoundTrip() throws {
        let container = try memoryContainer()
        let context = ModelContext(container)
        let calendar = scheduleCalendar()
        let base = scheduleBase(calendar)

        let template = ListTemplate(title: "Daily")
        template.repeatRuleRaw = RepeatRule.daily.rawValue
        template.repeatStart = base
        template.periodLog = [
            PeriodRecord(start: base, outcome: .generated),
            PeriodRecord(start: day(1, from: base, calendar), outcome: .skipped)
        ]
        context.insert(template)

        let legacy = ListTemplate(title: "Old")
        context.insert(legacy)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ListTemplate>())
        let stored = fetched.first { $0.title == "Daily" }
        #expect(stored?.periodLog?.count == 2)
        #expect(stored?.periodLog?.map(\.outcome) == [.generated, .skipped])
        #expect(fetched.first { $0.title == "Old" }?.periodLog == nil, "no ledger is the old state")
    }

    // MARK: - 时间合并迁移

    @Test func migrationMovesALoneDeadlineIntoTheDueDate() throws {
        UserDefaults.standard.set(0, forKey: "data.version")
        let context = ModelContext(try memoryContainer())
        let deadline = date(18)

        let task = TodoItem(title: "old", list: nil, sortIndex: 0)
        task.deadline = deadline
        task.deadlineReminderEnabled = true
        task.deadlineLeadMinutes = 30
        context.insert(task)
        try context.save()

        TimeMerge.runIfNeeded(context)

        #expect(task.dueDate == deadline, "the single time becomes the due date")
        #expect(task.hasDueTime)
        #expect(task.endReminderEnabled, "the old reminder becomes the end reminder")
        #expect(task.endReminderLeadMinutes == 30)
        #expect(task.endDate == nil, "one time stays single-mode")
        #expect(task.deadline == nil, "the legacy field is emptied")
        #expect(UserDefaults.standard.integer(forKey: "data.version") == TimeMerge.current)
    }

    @Test func migrationTurnsTwoTimesIntoARange() throws {
        UserDefaults.standard.set(0, forKey: "data.version")
        let context = ModelContext(try memoryContainer())
        let due = date(10)
        let deadline = date(18)

        let task = TodoItem(title: "both", dueDate: due, hasDueTime: true, list: nil, sortIndex: 0)
        task.deadline = deadline
        task.deadlineReminderEnabled = true
        task.deadlineLeadMinutes = 15
        context.insert(task)
        try context.save()

        TimeMerge.runIfNeeded(context)

        #expect(task.dueDate == due, "the plan time is untouched")
        #expect(task.endDate == deadline, "the deadline becomes the end of the range")
        #expect(task.startReminderEnabled)
        #expect(task.startReminderLeadMinutes == 15)
    }

    @Test func migrationRunsOnlyOnce() throws {
        let context = ModelContext(try memoryContainer())
        let task = TodoItem(title: "already", list: nil, sortIndex: 0)
        context.insert(task)
        try context.save()

        UserDefaults.standard.set(TimeMerge.current, forKey: "data.version")
        task.deadline = date(18)
        TimeMerge.runIfNeeded(context)

        #expect(task.deadline != nil, "a stamped version means no second pass")
        UserDefaults.standard.set(0, forKey: "data.version")
    }

    // MARK: - 双提醒的时刻

    @Test func reminderFiresTheLeadBeforeItsAnchor() {
        let deadline = date(18)
        #expect(NotificationService.fireDate(anchor: deadline, leadMinutes: 60)
                == deadline.addingTimeInterval(-3600))
        #expect(NotificationService.fireDate(anchor: nil, leadMinutes: 60) == nil)
    }

    @Test func startReminderNeverLandsAfterTheRangeEnds() {
        // A reversed range can exist after a bad migration; the reminder must not.
        let start = date(10)
        let end = date(9)
        #expect(NotificationService.startFireDate(start: start, leadMinutes: 0, end: end)
                == end.addingTimeInterval(-60))
    }

    @Test func startReminderKeepsItsLeadOnASaneRange() {
        let start = date(10)
        let end = date(18)
        #expect(NotificationService.startFireDate(start: start, leadMinutes: 60, end: end)
                == start.addingTimeInterval(-3600))
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