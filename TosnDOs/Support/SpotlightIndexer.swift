import Foundation
import SwiftData

#if os(iOS)
import CoreSpotlight
import UniformTypeIdentifiers

/// System search. Rebuilt as a whole rather than patched per edit: the library
/// is small, and one code path cannot drift out of sync with the store.
@MainActor
enum SpotlightIndexer {
    static let domain = "tosndos.tasks"

    static func indexAll(in context: ModelContext) {
        let descriptor = FetchDescriptor<TodoItem>()
        guard let tasks = try? context.fetch(descriptor) else { return }

        let items = tasks.map(searchableItem(for:))
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            guard !items.isEmpty else { return }
            index.indexSearchableItems(items)
        }
    }

    static func remove(uid: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [uid.uuidString])
    }

    private static func searchableItem(for task: TodoItem) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = task.title
        attributes.contentDescription = summary(for: task)
        attributes.keywords = [task.list?.title].compactMap { $0 } + (task.tags ?? []).map(\.name)
        attributes.contentURL = URL(string: "tosndos://task/\(task.uid.uuidString)")
        return CSSearchableItem(
            uniqueIdentifier: task.uid.uuidString,
            domainIdentifier: domain,
            attributeSet: attributes
        )
    }

    /// Everything a person might remember about the task, screenshots included.
    private static func summary(for task: TodoItem) -> String {
        var parts: [String] = []
        if !task.notes.isEmpty { parts.append(task.notes) }
        if let list = task.list?.title { parts.append(list) }
        for evidence in task.orderedEvidences {
            if !evidence.text.isEmpty, evidence.kind != .image { parts.append(evidence.text) }
            if !evidence.ocrText.isEmpty { parts.append(evidence.ocrText) }
        }
        return parts.joined(separator: " · ")
    }
}

#else

/// The Mac has no `tosndos://task/...` handler yet, and indexing results that
/// cannot be opened is worse than not indexing at all.
@MainActor
enum SpotlightIndexer {
    static func indexAll(in context: ModelContext) {}
    static func remove(uid: UUID) {}
}

#endif
