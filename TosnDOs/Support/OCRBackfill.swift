import Foundation
import SwiftData

/// Screenshots taken before OCR text was stored have nothing to search. Fill a
/// few per launch, off the main thread, so old material becomes findable
/// without a migration that blocks startup.
@MainActor
enum OCRBackfill {
    private static let perLaunch = 12
    private static var hasRun = false

    static func runIfNeeded(context: ModelContext) {
        guard !hasRun else { return }
        hasRun = true

        let imageKind = EvidenceKind.image.rawValue
        var descriptor = FetchDescriptor<Evidence>(
            predicate: #Predicate { $0.kindRaw == imageKind && $0.ocrText.isEmpty },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = perLaunch

        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        Task {
            for evidence in pending {
                guard let data = evidence.imageData else { continue }
                let lines = await TextRecognizer.lines(from: data)
                guard !lines.isEmpty else { continue }
                evidence.ocrText = lines.map(\.text).joined(separator: "\n")
            }
            try? context.save()
            SpotlightIndexer.indexAll(in: context)
        }
    }
}
