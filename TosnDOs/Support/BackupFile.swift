import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Full backup file. Carries every field plus a schema number.
/// The bytes stay JSON; only the extension is ours, so a double-click opens the
/// app and nobody has to guess whether it is safe to edit.
extension BackupFile {
    /// Declared in Info.plist so the system picker accepts only this and .json.
    static var contentType: UTType { UTType(filenameExtension: "tndbackup") ?? .json }
}

struct BackupFile: Codable {
    var schema: Int = 1
    var exportedAt: Date = .now
    var lists: [List]
    var templates: [Template]

    struct List: Codable {
        var title: String
        var notes: String
        var symbol: String
        var colorHex: Int
        var sortIndex: Double
        var tasks: [Task]
    }

    struct Task: Codable {
        var title: String
        var notes: String
        var dueDate: Date?
        var hasDueTime: Bool
        var priority: Int
        var isCompleted: Bool
        var completedAt: Date?
        var sortIndex: Double
    }

    struct Template: Codable {
        var title: String
        var summary: String
        var symbol: String
        var colorHex: Int
        var repeatRule: Int
        var items: [ItemRecord]
    }

    struct ItemRecord: Codable {
        var title: String
        var note: String
        var priority: Int
        var checks: [String]
    }

    // MARK: - Export

    static func capture(from context: ModelContext) -> BackupFile {
        let lists = ((try? context.fetch(FetchDescriptor<TodoList>())) ?? [])
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { list in
                List(
                    title: list.title,
                    notes: list.notes,
                    symbol: list.symbol,
                    colorHex: list.colorHex,
                    sortIndex: list.sortIndex,
                    tasks: (list.tasks ?? []).sorted { $0.sortIndex < $1.sortIndex }.map { task in
                        Task(
                            title: task.title,
                            notes: task.notes,
                            dueDate: task.dueDate,
                            hasDueTime: task.hasDueTime,
                            priority: task.priorityRaw,
                            isCompleted: task.isCompleted,
                            completedAt: task.completedAt,
                            sortIndex: task.sortIndex
                        )
                    }
                )
            }

        let templates = ((try? context.fetch(FetchDescriptor<ListTemplate>())) ?? [])
            .map { template in
                Template(
                    title: template.title,
                    summary: template.summary,
                    symbol: template.symbol,
                    colorHex: template.colorHex,
                    repeatRule: template.repeatRuleRaw,
                    items: template.orderedItems.map { item in
                        ItemRecord(
                            title: item.title,
                            note: item.note,
                            priority: item.priorityRaw,
                            checks: item.orderedChecks.map(\.title)
                        )
                    }
                )
            }

        return BackupFile(lists: lists, templates: templates)
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: data)
    }

    // MARK: - Import

    enum Mode {
        /// Everything in the file is added; existing lists are untouched.
        case merge
        /// Existing lists and templates are deleted first.
        case replace
    }

    @discardableResult
    func restore(into context: ModelContext, mode: Mode) -> (lists: Int, templates: Int) {
        if mode == .replace {
            for list in (try? context.fetch(FetchDescriptor<TodoList>())) ?? [] {
                context.delete(list)
            }
            for template in (try? context.fetch(FetchDescriptor<ListTemplate>())) ?? [] {
                context.delete(template)
            }
        }

        for list in lists {
            let target = TodoList(
                title: list.title,
                symbol: list.symbol,
                colorHex: list.colorHex,
                notes: list.notes,
                sortIndex: list.sortIndex
            )
            context.insert(target)
            for task in list.tasks {
                let item = TodoItem(
                    title: task.title,
                    notes: task.notes,
                    dueDate: task.dueDate,
                    hasDueTime: task.hasDueTime,
                    priority: TaskPriority(rawValue: task.priority) ?? .none,
                    list: target,
                    sortIndex: task.sortIndex
                )
                context.insert(item)
                if task.isCompleted {
                    item.setCompleted(true)
                    item.completedAt = task.completedAt ?? .now
                }
            }
            target.reconcileCompletion()
        }

        for template in templates {
            let created = ListTemplate(
                title: template.title,
                summary: template.summary,
                symbol: template.symbol,
                colorHex: template.colorHex
            )
            created.repeatRuleRaw = template.repeatRule
            context.insert(created)
            for (index, item) in template.items.enumerated() {
                let entry = TemplateItem(
                    title: item.title,
                    note: item.note,
                    priority: TaskPriority(rawValue: item.priority) ?? .none,
                    sortIndex: Double(index)
                )
                context.insert(entry)
                entry.template = created
                for (checkIndex, title) in item.checks.enumerated() {
                    let check = TemplateCheck(title: title, sortIndex: Double(checkIndex))
                    context.insert(check)
                    check.item = entry
                }
            }
        }

        try? context.save()
        return (lists.count, templates.count)
    }
}

/// Thin file wrapper so the backup can go through the system file picker.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
