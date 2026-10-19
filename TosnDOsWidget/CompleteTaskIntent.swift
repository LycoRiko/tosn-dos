import AppIntents
import SwiftData
import WidgetKit

/// Tapping a task in the widget completes it immediately, without opening the
/// app. The intent opens the same App Group store the app writes to, then asks
/// WidgetKit for a fresh timeline.
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete task"
    static var description = IntentDescription("Marks a task as done.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Task")
    var taskUID: String

    init() {}

    init(taskUID: String) {
        self.taskUID = taskUID
    }

    func perform() async throws -> some IntentResult {
        let context = ModelContext(WidgetData.container)
        let items = (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []

        if let item = items.first(where: { $0.uid.uuidString == taskUID }) {
            item.setCompleted(true)
            try? context.save()
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
