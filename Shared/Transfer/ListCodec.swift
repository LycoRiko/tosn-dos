import Foundation
import SwiftData

/// A list reduced to the parts worth sharing, encoded so the result survives a
/// chat app: deflate (the titles dominate and compress well) then Base64URL
/// (no `+ / =`, so it can sit inside a URL or a message untouched).
///
/// Length is set by the task titles themselves, not by the container: keys are
/// one character, nil fields are omitted, and the JSON is written compactly.
enum ListCodec {
    static let prefix = "TOSN1:"

    struct Snapshot: Codable {
        var t: String
        var s: String?
        var c: Int?
        var i: [Item]
    }

    struct Item: Codable {
        var t: String
        /// Days from today; relative offsets stay correct however long the code
        /// sits in a chat before someone imports it.
        var d: Int?
        var m: Bool?
        var x: Bool?
        var n: String?
        var p: Int?
    }

    // MARK: - Encode

    static func encode(_ list: TodoList) -> String {
        let today = Calendar.current.startOfDay(for: .now)
        let snapshot = Snapshot(
            t: list.title,
            s: list.symbol == "list.bullet" ? nil : list.symbol,
            c: list.colorHex == 0x5E5CE6 ? nil : list.colorHex,
            i: (list.tasks ?? []).sorted { $0.sortIndex < $1.sortIndex }.map { task in
                Item(
                    t: task.title,
                    d: task.dueDate.flatMap {
                        Calendar.current.dateComponents(
                            [.day], from: today, to: Calendar.current.startOfDay(for: $0)
                        ).day
                    },
                    m: task.hasDueTime ? true : nil,
                    x: task.isCompleted ? true : nil,
                    n: task.notes.isEmpty ? nil : task.notes,
                    p: task.priorityRaw == 0 ? nil : task.priorityRaw
                )
            }
        )

        guard let json = try? JSONEncoder().encode(snapshot) else { return "" }
        let packed = (try? (json as NSData).compressed(using: .zlib) as Data) ?? json
        return prefix + base64URLEncode(packed)
    }

    // MARK: - Decode

    static func decode(_ raw: String) -> Snapshot? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        guard let data = base64URLDecode(text) else { return nil }
        let json = (try? (data as NSData).decompressed(using: .zlib) as Data) ?? data
        return try? JSONDecoder().decode(Snapshot.self, from: json)
    }

    /// Always a new list — importing never overwrites what is already there.
        @discardableResult
    static func importList(_ snapshot: Snapshot, into context: ModelContext, sortIndex: Double) -> TodoList? {
        let list = TodoList(title: snapshot.t, symbol: snapshot.s ?? "list.bullet", colorHex: snapshot.c ?? 0x5E5CE6, sortIndex: sortIndex)
        context.insert(list)

        let today = Calendar.current.startOfDay(for: .now)
        for (index, item) in snapshot.i.enumerated() {
            let due = item.d.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
            let task = TodoItem(
                title: item.t,
                notes: item.n ?? "",
                dueDate: due,
                hasDueTime: item.m ?? false,
                priority: TaskPriority(rawValue: item.p ?? 0) ?? .none,
                list: list,
                sortIndex: Double(index)
            )
            context.insert(task)
            if item.x == true { task.setCompleted(true) }
        }
        try? context.save()
        return list
    }

    // MARK: - Base64URL

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ text: String) -> Data? {
        var base = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base.count % 4
        if remainder > 0 { base += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base)
    }
}
