import SwiftUI

/// The only "dashboard" in the app: a greeting, the date, and one number that
/// answers "how much is left today". No charts, no streaks, no mascots.
struct TodayHero: View {
    var remaining: Int
    var done: Int
    var progress: Double

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return String(localized: "Good morning")
        case 12..<18: return String(localized: "Good afternoon")
        default: return String(localized: "Good evening")
        }
    }

    private var dateText: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(dateText)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if remaining == 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.mint)
                        Text("Nothing due today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(remaining)")
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            .monospacedDigit()
                        Text("left today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            // Nothing was ever due: a 0% ring reads as failure next to "nothing due".
            if remaining + done > 0 {
                ProgressRing(progress: progress, size: 58, lineWidth: 6.5)
                    .padding(.top, 2)
            }
        }
        .glassCard(radius: Theme.radius, padding: 20)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: remaining)
        .accessibilityElement(children: .combine)
    }
}
