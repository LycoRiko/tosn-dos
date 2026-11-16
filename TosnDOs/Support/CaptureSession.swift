import Foundation
import Observation

/// In-process handoff from the intent to the review sheet; never persisted.
@Observable
final class CaptureSession {
    static let shared = CaptureSession()

    struct Draft: Identifiable {
        let id = UUID()
        var tasks: [CapturedTask]
        var imageData: Data?
        /// Joined OCR lines, stored with the screenshot so search can find it.
        var ocrText: String = ""
    }

    var draft: Draft?

    private init() {}

    func clear() {
        draft = nil
    }
}
