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
    }

    var draft: Draft?

    private init() {}

    func clear() {
        draft = nil
    }
}
