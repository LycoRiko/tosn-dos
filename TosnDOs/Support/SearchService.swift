import Foundation

/// Where a match was found. The raw order doubles as the tie-break when one
/// task matches in several places — a title hit is never buried by a note hit.
enum SearchField: Int, Comparable {
    case title = 0
    case list = 1
    case notes = 2
    case material = 3
    case screenshot = 4

    static func < (lhs: SearchField, rhs: SearchField) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String? {
        switch self {
        case .title: return nil
        case .list: return String(localized: "List")
        case .notes: return String(localized: "Notes")
        case .material: return String(localized: "Material")
        case .screenshot: return String(localized: "In a screenshot")
        }
    }
}

struct SearchHit: Identifiable {
    let task: TodoItem
    let field: SearchField
    /// Surrounding words for long text; nil when the title itself matched.
    let snippet: String?

    var id: UUID { task.uid }
}

/// Pure matching so the rules can be tested without a view.
enum SearchService {

    static func hits(in tasks: [TodoItem], query: String, limit: Int = 80) -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var found: [SearchHit] = []
        for task in tasks {
            guard let hit = hit(for: task, query: trimmed) else { continue }
            found.append(hit)
        }

        found.sort { lhs, rhs in
            if lhs.field != rhs.field { return lhs.field < rhs.field }
            let l = lhs.task.focusDate ?? .distantFuture
            let r = rhs.task.focusDate ?? .distantFuture
            if l != r { return l < r }
            return lhs.task.title.localizedStandardCompare(rhs.task.title) == .orderedAscending
        }

        return Array(found.prefix(limit))
    }

    static func hit(for task: TodoItem, query: String) -> SearchHit? {
        if task.title.localizedCaseInsensitiveContains(query) {
            return SearchHit(task: task, field: .title, snippet: nil)
        }
        if let listTitle = task.list?.title, listTitle.localizedCaseInsensitiveContains(query) {
            return SearchHit(task: task, field: .list, snippet: nil)
        }
        if task.notes.localizedCaseInsensitiveContains(query) {
            return SearchHit(task: task, field: .notes, snippet: snippet(in: task.notes, around: query))
        }
        for evidence in task.orderedEvidences {
            if evidence.text.localizedCaseInsensitiveContains(query) {
                let field: SearchField = evidence.kind == .image ? .screenshot : .material
                return SearchHit(task: task, field: field, snippet: snippet(in: evidence.text, around: query))
            }
            if evidence.ocrText.localizedCaseInsensitiveContains(query) {
                return SearchHit(
                    task: task,
                    field: .screenshot,
                    snippet: snippet(in: evidence.ocrText, around: query)
                )
            }
        }
        return nil
    }

    /// A window of text around the first match, so the row can show why it hit.
    static func snippet(in text: String, around query: String, width: Int = 26) -> String? {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let range = flat.range(of: query, options: .caseInsensitive)
        else { return flat.isEmpty ? nil : String(flat.prefix(width * 2)) }

        let start = flat.index(range.lowerBound, offsetBy: -width, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(range.upperBound, offsetBy: width, limitedBy: flat.endIndex) ?? flat.endIndex
        var piece = String(flat[start..<end])
        if start > flat.startIndex { piece = "…" + piece }
        if end < flat.endIndex { piece += "…" }
        return piece
    }
}
