import SwiftUI
import SwiftData

/// What already happened, in four cards. No targets, no streaks-as-guilt: the
/// numbers are there to be read once and closed.
struct StatisticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TodoItem.sortIndex) private var allTasks: [TodoItem]
    @Query(sort: \TodoList.sortIndex) private var lists: [TodoList]

    private var stats: StatsSnapshot {
        StatsService.snapshot(from: allTasks, lists: lists)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    monthCard
                    streakCard
                    heatmapCard
                    onTimeCard
                    byListCard
                    byHourCard
                    templateCard
                    medianCard
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Statistics")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Cards

    private var monthCard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("This month")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(stats.monthDone)")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    Text("done")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(comparisonText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .glassCard()
    }

    private var comparisonText: String {
        let delta = stats.monthDone - stats.previousMonthDone
        if stats.previousMonthDone == 0 {
            return String(localized: "Nothing recorded last month.")
        }
        if delta == 0 {
            return String(localized: "Same as last month.")
        }
        return delta > 0
            ? String(localized: "\(delta) more than last month.")
            : String(localized: "\(-delta) fewer than last month.")
    }

    private var streakCard: some View {
        HStack(spacing: 0) {
            streakColumn(value: stats.currentStreak, title: String(localized: "Current streak"))
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1, height: 42)
            streakColumn(value: stats.longestStreak, title: String(localized: "Longest"))
        }
        .glassCard()
    }

    private func streakColumn(value: Int, title: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit()
            Text(value == 1 ? String(localized: "day") : String(localized: "days"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 12 weeks")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 5) {
                ForEach(0..<StatsService.weeks, id: \.self) { column in
                    VStack(spacing: 5) {
                        ForEach(0..<7, id: \.self) { row in
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(heatColor(stats.heatmap[column][row]))
                                .frame(height: 15)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
        }
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private func heatColor(_ count: Int) -> Color {
        switch count {
        case 0: return Color.primary.opacity(0.07)
        case 1: return Theme.accent.opacity(0.28)
        case 2: return Theme.accent.opacity(0.48)
        case 3: return Theme.accent.opacity(0.7)
        default: return Theme.accent
        }
    }

    private var onTimeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On time")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let rate = stats.onTimeRate {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(rate.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(rate >= 0.8 ? Theme.mint : .primary)
                        .monospacedDigit()
                    Text("of the last 30 days' deadlines")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("\(stats.onTime) on time · \(stats.late) late")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No deadlines to measure yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var byListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This month by list")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if stats.byList.isEmpty {
                Text("Nothing finished yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let top = stats.byList.first?.count ?? 1
                ForEach(stats.byList, id: \.name) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(entry.name)
                                .font(.footnote)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text("\(entry.count)")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Theme.accent.opacity(0.55))
                                .frame(
                                    width: max(4, proxy.size.width * CGFloat(entry.count) / CGFloat(max(top, 1))),
                                    height: 6
                                )
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var byHourCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When you finish")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let top = stats.byHour.max() ?? 0
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { hour in
                    let count = stats.byHour[hour]
                    Capsule()
                        .fill(count == 0 ? Color.primary.opacity(0.08) : Theme.accent.opacity(0.75))
                        .frame(height: max(3, 34 * CGFloat(count) / CGFloat(max(top, 1))))
                        // Bars are decoration; the caption below carries the meaning.
                        .frame(maxWidth: .infinity, alignment: .bottom)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 40, alignment: .bottom)

            if let peak = peakHour {
                Text("Most often around \(peak)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var peakHour: String? {
        guard let top = stats.byHour.max(), top > 0,
              let hour = stats.byHour.firstIndex(of: top) else { return nil }
        let date = Calendar.current.date(
            bySettingHour: hour, minute: 0, second: 0, of: Date()
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var templateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From templates")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let rate = stats.templateRate {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(rate.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    Text("\(stats.templateFinished) of \(stats.templateTotal) finished")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No list has come from a template yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var medianCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Typical time to finish")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let hours = stats.medianHours {
                Text(DurationFormat.short(hours * 3600))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text("From writing it down to ticking it off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not enough finished tasks yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
