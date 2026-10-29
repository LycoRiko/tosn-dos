import AppIntents
import Foundation

/// 快捷指令的入口：接收一张截图，在本机 OCR + 抽条，然后把 App 叫到前台确认。
/// 全程不联网；截图只留在内存里，直到确认面板关掉。
struct AddTasksFromScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Add tasks from a screenshot"
    static var description = IntentDescription("Reads a screenshot on this device and asks you to confirm what to add.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Screenshot")
    var screenshot: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let data = screenshot.data
        let lines = await TextRecognizer.lines(from: data)
        let tasks = CaptureParser.parse(lines: lines)
        CaptureSession.shared.draft = CaptureSession.Draft(tasks: tasks, imageData: data)

        if tasks.isEmpty {
            return .result(dialog: "没有识别到待办事项。")
        }
        return .result(dialog: "找到 \(tasks.count) 条，请确认。")
    }
}
