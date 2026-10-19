import WidgetKit
import SwiftUI

/// One view per size. Each size answers a different question:
/// small = how much is left, medium = what is next, large = the whole day.
struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemLarge:
            largeView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            mediumView
        }
    }

    // MARK: - Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ring(size: 22)
            }

            Spacer(minLength: 0)

            if entry.remaining == 0 {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.mint)
                    Text("All clear")
                        .font(.headline)
                }
            } else {
                Text("\(entry.remaining)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text("left today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Medium

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if entry.tasks.isEmpty {
                emptyLine
            } else {
                ForEach(entry.tasks.prefix(3)) { task in
                    taskRow(task)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Large

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if entry.tasks.isEmpty {
                Spacer(minLength: 0)
                emptyLine
                Spacer(minLength: 0)
            } else {
                ForEach(entry.tasks.prefix(6)) { task in
                    taskRow(task)
                }
                Spacer(minLength: 0)
                footer
            }
        }
    }

    // MARK: - Accessory

    private var circularView: some View {
        Gauge(value: entry.progress) {
            Image(systemName: "checkmark")
        } currentValueLabel: {
            Text("\(entry.remaining)")
                .font(.system(.body, design: .rounded).weight(.semibold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.remaining == 0 ? "All clear" : "\(entry.remaining) left today")
                .font(.headline)
            if let first = entry.tasks.first {
                Text(first.title)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .widgetAccentable()
    }

    private var inlineView: some View {
        Text(entry.remaining == 0 ? "All clear" : "\(entry.remaining) left today")
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Today")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(entry.remaining == 0 ? "All clear" : "\(entry.remaining) left")
                .font(.caption2.weight(.medium))
                .foregroundStyle(entry.remaining == 0 ? Palette.mint : .secondary)
        }
    }

    private var emptyLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "sun.max")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("Nothing due today")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 9, weight: .semibold))
            Text("\(entry.done) done today")
                .font(.caption2)
        }
        .foregroundStyle(.tertiary)
    }

    private func taskRow(_ task: WidgetTask) -> some View {
        Button(intent: CompleteTaskIntent(taskUID: task.id)) {
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(task.isLate ? Color(hex: 0xFF453A) : Color.secondary.opacity(0.6))

                Text(task.title)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if task.isLate {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(hex: 0xFF453A))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Complete \(task.title)"))
    }

    private func ring(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, entry.progress))
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}
