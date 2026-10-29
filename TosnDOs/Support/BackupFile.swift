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

/// 备份时证据怎么处理。默认只带文字：截图会让文件从 KB 涨到几十 MB。
enum BackupEvidenceScope: Int, CaseIterable, Identifiable {
    case none = 0
    case textOnly = 1
    case all = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return String(localized: "No materials")
        case .textOnly: return String(localized: "Text only")
        case .all: return String(localized: "All materials")
        }
    }
}

struct BackupFile: Codable {
    var schema: Int = 2
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
        /// 缺省代表这份备份里没有材料（旧文件或用户选了「不备份」）。
        var evidences: [EvidenceRecord]?
    }

    struct EvidenceRecord: Codable {
        var kind: Int
        var text: String
        var createdAt: Date
        /// 只有选了「全部材料 + 不优化」时才是原图；其余情况是压缩后的 JPEG。
        var image: Data?
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

    static func capture(
        from context: ModelContext,
        evidenceScope: BackupEvidenceScope = .textOnly,
        optimizeImages: Bool = true
    ) -> BackupFile {
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
                            sortIndex: task.sortIndex,
                            evidences: evidenceScope == .none ? nil : task.orderedEvidences.map { evidence in
                                EvidenceRecord(
                                    kind: evidence.kindRaw,
                                    text: evidence.text,
                                    createdAt: evidence.createdAt,
                                    image: evidenceScope == .all
                                        ? (optimizeImages ? ImageShrink.jpeg(evidence.imageData) : evidence.imageData)
                                        : nil
                                )
                            }
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
                for record in task.evidences ?? [] {
                    let evidence = Evidence(
                        kind: EvidenceKind(rawValue: record.kind) ?? .text,
                        text: record.text,
                        imageData: record.image,
                        task: item
                    )
                    evidence.createdAt = record.createdAt
                    context.insert(evidence)
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

/// 备份里的图片压缩：长边 1600、JPEG 0.8。只走 ImageIO/CoreImage，两端通用。
enum ImageShrink {
    static func jpeg(_ data: Data?, longEdge: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, longEdge / max(width, height))

        var output = image
        if scale < 1 {
            let ciImage = CIImage(cgImage: image)
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            output = CIContext().createCGImage(ciImage, from: ciImage.extent) ?? image
        }

        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(buffer, "public.jpeg" as CFString, 1, nil) else {
            return data
        }
        CGImageDestinationAddImage(destination, output, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return data }
        return buffer as Data
    }
}
