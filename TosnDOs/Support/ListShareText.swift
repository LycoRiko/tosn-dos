import Foundation

/// Turns a list into plain text people can paste into a message.
///
/// The shape is deliberately strict — two leading lines, then `[x]` / `[ ]`
/// marks, sub-items indented with four spaces — because the share code planned
/// later will parse the same structure. Anything that changes here should stay
/// parseable: no prose, no trailing decoration.
enum ListShareText {

    static func make(for list: TodoList) -> String {
        var lines: [String] = []

        var header = list.title.isEmpty ? String(localized: "Untitled") : list.title
        if let stamp = dateStamp(for: list) {
            header += " · " + stamp
        }
        lines.append(header)
        lines.append(summaryLine(for: list))
        lines.append("")

        for task in list.orderedTasks {
            lines.append(mark(task.isCompleted) + " " + title(of: task))
            for check in task.orderedSubtasks {
                lines.append("    " + mark(check.isDone) + " " + title(of: check))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func mark(_ done: Bool) -> String {
        done ? "[x]" : "[ ]"
    }

    private static func title(of task: TodoItem) -> String {
        task.title.isEmpty ? String(localized: "Untitled") : task.title
    }

    private static func title(of check: Subtask) -> String {
        check.title.isEmpty ? String(localized: "Untitled") : check.title
    }

    /// The repeating period when there is one — it identifies the list better
    /// than "the day it was created".
    private static func dateStamp(for list: TodoList) -> String? {
        let date = list.periodDate ?? list.createdAt
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private static func summaryLine(for list: TodoList) -> String {
        let total = list.actionableTasks.count
        let done = list.doneTaskCount
        var line = String(localized: "\(done) of \(total) done")
        if let seconds = list.workedDuration {
            line += " · " + DurationFormat.short(seconds)
        }
        return line
    }
}
