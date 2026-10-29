import Foundation
import Observation

/// 截图解析出来、还没确认的草稿。Intent 写、界面读，都在同一个进程里，
/// 所以不需要 App Group 也不落盘。
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
