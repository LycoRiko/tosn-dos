import WidgetKit
import SwiftUI
import SwiftData

// MARK: - Entry

/// A widget entry carries value types only — never SwiftData models, which are
/// bound to the context that fetched them.
struct TodayEntry: TimelineEntry {
    let date: Date
    let remaining: Int
    let done: Int
    let tasks: [WidgetTask]

    var progress: Double {
        let total = remaining + done
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    static let placeholder = TodayEntry(
        date: .now,
        remaining: 3,
        done: 2,
        tasks: [
            WidgetTask(id: "1", title: String(localized: "Review the design handoff"), isDone: false, isLate: false),
            WidgetTask(id: "2", title: String(localized: "Reply to the planning thread"), isDone: false, isLate: true),
            WidgetTask(id: "3", title: String(localized: "Buy coffee beans"), isDone: true, isLate: false)
        ]
    )
}

struct WidgetTask: Identifiable, Hashable {
    let id: String
    let title: String
    let isDone: Bool
    let isLate: Bool
}

// MARK: - Provider

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? .placeholder : WidgetData.todayEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = WidgetData.todayEntry()
        // Refresh at the next midnight, and no later than 30 minutes out so the
        // count still tracks completions made on another device.
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        let halfHour = Date.now.addingTimeInterval(30 * 60)
        let next = min(midnight, halfHour)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Data

enum WidgetData {
    static let container: ModelContainer = SharedStore.boot().container

    static func todayEntry() -> TodayEntry {
        let context = ModelContext(container)
        guard let all = try? context.fetch(FetchDescriptor<TodoItem>()) else {
            return TodayEntry(date: .now, remaining: 0, done: 0, tasks: [])
        }

        // Same rule as the app's Today screen; see Shared/TodayScope.swift.
        let snapshot = TodayScope.snapshot(from: all)

        let snapshots = snapshot.open.prefix(6).map { item in
            WidgetTask(
                id: item.uid.uuidString,
                title: item.title.isEmpty ? String(localized: "Untitled") : item.title,
                isDone: false,
                isLate: item.isOverdue(at: .now)
            )
        }

        return TodayEntry(
            date: .now,
            remaining: snapshot.remaining,
            done: snapshot.done,
            tasks: Array(snapshots)
        )
    }
}

// MARK: - Widget

struct TodayWidget: Widget {
    let kind = "TodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "tosndos://today"))
        }
        .configurationDisplayName(Text("Today"))
        .description(Text("What is left today, and one tap to check it off."))
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        return [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        return [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

@main
struct TosnDOsWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}
