import Foundation
import SwiftData

/// Every mutation that touches more than one record type goes through here.
/// Views stay declarative; the rules for "what a template becomes" live in
/// exactly one place.
@MainActor
enum WorkspaceService {

    // MARK: Lists

    static func createList(
        title: String,
        symbol: String = "list.bullet",
        colorHex: Int = 0x5E5CE6,
        in context: ModelContext
    ) -> TodoList {
        let list = TodoList(title: title, symbol: symbol, colorHex: colorHex, sortIndex: nextListIndex(in: context))
        context.insert(list)
        save(context)
        return list
    }

    static func nextListIndex(in context: ModelContext) -> Double {
        let lists = (try? context.fetch(FetchDescriptor<TodoList>())) ?? []
        return (lists.map(\.sortIndex).max() ?? 0) + 1
    }

    static func nextTaskIndex(in list: TodoList?) -> Double {
        let tasks = list?.tasks ?? []
        return (tasks.map(\.sortIndex).max() ?? 0) + 1
    }

    // MARK: Templates → Workspace

    /// Turns a blueprint into a real list. The template itself is never
    /// modified except for usage metadata, so the same checklist can be
    /// pulled as many times as needed.
    ///
    /// `period` is set for repeating templates: it records which run of the
    /// checklist this is, and doubles as the due day so a catch-up list from
    /// last week still reads as last week's.
    @discardableResult
    static func instantiate(
        template: ListTemplate,
        title: String,
        dueToday: Bool,
        period: Date? = nil,
        in context: ModelContext
    ) -> TodoList {
        let list = TodoList(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? template.title : title,
            symbol: template.symbol,
            colorHex: template.colorHex,
            notes: template.summary,
            sortIndex: nextListIndex(in: context)
        )
        list.periodDate = period
        list.sourceTemplateName = template.title
        context.insert(list)

        let startOfToday = Calendar.current.startOfDay(for: .now)
        let dueDay = period.map { Calendar.current.startOfDay(for: $0) } ?? startOfToday
        for (taskIndex, blueprint) in template.orderedItems.enumerated() {
            let task = TodoItem(
                title: blueprint.title,
                notes: blueprint.note,
                dueDate: dueToday ? dueDay : nil,
                hasDueTime: false,
                priority: blueprint.priority,
                list: list,
                sortIndex: Double(taskIndex)
            )
            context.insert(task)

            for (checkIndex, check) in blueprint.orderedChecks.enumerated() {
                let subtask = Subtask(title: check.title, isDone: false, sortIndex: Double(checkIndex))
                context.insert(subtask)
                subtask.parent = task
            }
        }

        list.reconcileCompletion()
        template.usageCount += 1
        template.lastUsedAt = .now
        save(context)
        return list
    }

    // MARK: Workspace → Templates

    /// Captures the *shape* of an existing list, not its completion state.
    @discardableResult
    static func saveAsTemplate(from list: TodoList, in context: ModelContext) -> ListTemplate {
        let template = ListTemplate(
            title: list.title,
            summary: list.notes,
            symbol: list.symbol,
            colorHex: list.colorHex
        )
        context.insert(template)

        for (taskIndex, task) in list.orderedTasks.enumerated() {
            let item = TemplateItem(
                title: task.title,
                note: task.notes,
                priority: task.priority,
                sortIndex: Double(taskIndex)
            )
            context.insert(item)
            item.template = template

            for (checkIndex, subtask) in task.orderedSubtasks.enumerated() {
                let check = TemplateCheck(title: subtask.title, sortIndex: Double(checkIndex))
                context.insert(check)
                check.item = item
            }
        }

        save(context)
        return template
    }

    static func duplicate(template: ListTemplate, in context: ModelContext) -> ListTemplate {
        let copy = ListTemplate(
            title: "\(template.title) \(String(localized: "copy"))",
            summary: template.summary,
            symbol: template.symbol,
            colorHex: template.colorHex
        )
        context.insert(copy)
        for (index, item) in template.orderedItems.enumerated() {
            let newItem = TemplateItem(
                title: item.title,
                note: item.note,
                priority: item.priority,
                sortIndex: Double(index)
            )
            context.insert(newItem)
            newItem.template = copy
            for (checkIndex, check) in item.orderedChecks.enumerated() {
                let newCheck = TemplateCheck(title: check.title, sortIndex: Double(checkIndex))
                context.insert(newCheck)
                newCheck.item = newItem
            }
        }
        save(context)
        return copy
    }

    // MARK: Delete

    static func delete(_ task: TodoItem, in context: ModelContext) {
        let owner = task.list
        NotificationService.cancel(task)
        context.delete(task)
        // Removing the last open task is a completion in every way the UI cares about.
        owner?.reconcileCompletion()
        save(context)
    }

    static func delete(_ list: TodoList, in context: ModelContext) {
        NotificationService.cancel(list)
        context.delete(list)
        save(context)
    }

    static func delete(_ template: ListTemplate, in context: ModelContext) {
        context.delete(template)
        save(context)
    }

    static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            assertionFailure("Save failed: \(error)")
        }
    }
}
