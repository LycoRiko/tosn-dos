import SwiftUI
import SwiftData

/// Today, on a 40mm screen. One row per task, one tap to finish it.
///
/// The numbers come from `TodayScope`, the same code the phone and the widget
/// use, so the watch can never disagree with them about what "today" means.
struct WatchTodayView: View {
    @Query(sort: \TodoItem.sortIndex) private var allTasks: [TodoItem]
    @Environment(\.modelContext) private var context

    private var snapshot: TodaySnapshot {
        TodayScope.snapshot(from: allTasks)
    }

    var body: some View {
        NavigationStack {
            List {
                if snapshot.open.isEmpty {
                    emptyRow
                } else {
                    ForEach(snapshot.open) { task in
                        row(task)
                    }
                }
            }
            .navigationTitle(title)
        }
        .task {
            WatchSync.shared.start(context: context)
        }
    }

    private var title: String {
        snapshot.remaining == 0
            ? String(localized: "All clear")
            : String(localized: "\(snapshot.remaining) left today")
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing due today")
                .font(.headline)
            Text("Add one on your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func row(_ task: TodoItem) -> some View {
        Button {
            toggle(task)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text(task.title.isEmpty ? String(localized: "Untitled") : task.title)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
        .accessibilityLabel(Text("Complete \(task.title.isEmpty ? String(localized: "Untitled") : task.title)"))
    }

    private func toggle(_ task: TodoItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            WatchSync.shared.complete(task: task)
        }
    }
}
