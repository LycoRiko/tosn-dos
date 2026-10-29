#if os(iOS)
import AppIntents
import SwiftData
import UIKit

/// Add a task from Siri, Spotlight, or the Action Button.
/// Runs in-process against the app's own store.
struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a task"
    static var description = IntentDescription("Adds a task, understanding dates like “tomorrow 3pm”.")
    static var openAppWhenRun = false

    @Parameter(title: "Task", requestValueDialog: "What should I add?")
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "Nothing to add.")
        }

        let context = ModelContext(AppContainer.boot.container)
        let parsed = NaturalDateParser.parse(trimmed)
        let task = TodoItem(
            title: parsed.title,
            dueDate: parsed.dueDate,
            hasDueTime: parsed.hasTime,
            sortIndex: WorkspaceService.nextTaskIndex(in: nil)
        )
        context.insert(task)
        try context.save()

        return .result(dialog: "Added \(task.title).")
    }
}

/// Completes the first open task whose title matches. A substring is enough
/// here; a real picker would need an AppEntity.
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete a task"
    static var description = IntentDescription("Marks the matching open task as done.")
    static var openAppWhenRun = false

    @Parameter(title: "Task name")
    var name: String

    init() {}

    init(name: String) {
        self.name = name
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(AppContainer.boot.container)
        let open = try context.fetch(
            FetchDescriptor<TodoItem>(predicate: #Predicate { !$0.isCompleted })
        )
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = open.first(where: {
            $0.title.localizedCaseInsensitiveContains(needle)
        }) else {
            return .result(dialog: "No open task matches \(needle).")
        }

        match.setCompleted(true)
        try context.save()
        return .result(dialog: "Completed \(match.title).")
    }
}

struct OpenTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Today"
    static var description = IntentDescription("Opens the app on today's list.")
    static var openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = URL(string: "tosndos://today") {
            await UIApplication.shared.open(url)
        }
        return .result()
    }
}

struct TosnShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: ["Add a task in \(.applicationName)"],
            shortTitle: "Add task",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: AddTasksFromScreenshotIntent(),
            phrases: ["Add tasks from a screenshot in \(.applicationName)"],
            shortTitle: "From screenshot",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: ["Complete a task in \(.applicationName)"],
            shortTitle: "Complete task",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: OpenTodayIntent(),
            phrases: ["Open today in \(.applicationName)"],
            shortTitle: "Open Today",
            systemImageName: "sun.max"
        )
    }
}
#endif
