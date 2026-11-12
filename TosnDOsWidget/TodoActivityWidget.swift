#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// The lock-screen and Dynamic Island face of a running reminder.
struct TodoActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TodoActivityAttributes.self) { context in
            banner(context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isDone ? "checkmark.circle.fill" : "hourglass")
                        .font(.title3)
                        .foregroundStyle(context.state.isDone ? .green : .orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.state.isDone ? "checkmark" : "hourglass")
                    .foregroundStyle(context.state.isDone ? .green : .orange)
            } compactTrailing: {
                countdown(context.state)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: context.state.isDone ? "checkmark" : "hourglass")
                    .foregroundStyle(context.state.isDone ? .green : .orange)
            }
        }
    }

    private func banner(_ state: TodoActivityAttributes.ContentState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: state.isDone ? "checkmark.circle.fill" : "hourglass")
                .font(.title2)
                .foregroundStyle(state.isDone ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Tos'n DOs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                countdown(state)
                    .font(.headline.monospacedDigit())
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// A live timer while the deadline is ahead; a dash when it has no end time.
    @ViewBuilder
    private func countdown(_ state: TodoActivityAttributes.ContentState) -> some View {
        if state.isDone {
            Text("Done")
        } else if let endsAt = state.endsAt {
            Text(timerInterval: Date.now...max(endsAt, Date.now), countsDown: true)
        } else {
            Text("—")
        }
    }
}
#endif
