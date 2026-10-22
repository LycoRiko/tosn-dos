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
            for: TodoList.self, TodoItem.self, Subtask.self, Tag.self,
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
}
