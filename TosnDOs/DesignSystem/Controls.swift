import SwiftUI

/// Circular completion control. One tap, immediate spring feedback —
/// this is the single most repeated gesture in the app, so it gets the
/// largest hit area and the clearest state change.
struct CompletionButton: View {
    var isOn: Bool
    var tint: Color = Theme.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(
                        isOn ? Color.clear : Color.secondary.opacity(0.32),
                        lineWidth: 1.8
                    )
                    .frame(width: 25, height: 25)

                if isOn {
                    Circle()
                        .fill(tint)
                        .frame(width: 25, height: 25)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? Text("Completed") : Text("Complete task"))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: isOn)
        .sensoryFeedback(.success, trigger: isOn) { _, newValue in newValue }
    }
}

struct ProgressRing: View {
    var progress: Double
    var size: CGFloat = 56
    var lineWidth: CGFloat = 6
    var showsLabel: Bool = true

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.02, clamped))
                .stroke(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.55, dampingFraction: 0.85), value: clamped)

            if showsLabel {
                Text("\(Int((clamped * 100).rounded()))%")
                    .font(.system(size: size * 0.26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(Text("Progress \(Int(clamped * 100))%"))
    }
}

/// Small metadata pill: due date, list name, subtask count.
struct MetaChip: View {
    var icon: String?
    var text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
            }
            Text(text)
                .scaledFont(11.5, weight: .medium)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10), in: Capsule())
    }
}

/// Deadline badge for list rows. Nothing is drawn when the list has no
/// deadline or is already finished — the badge is information, not decoration.
struct DeadlineBadge: View {
    var list: TodoList
    var now: Date = .now

    var body: some View {
        if let deadline = list.deadline, !list.isFinished {
            let label = DeadlineFormat.label(for: deadline, now: now)

            MetaChip(
                icon: deadline < now ? "exclamationmark.circle.fill" : "calendar.badge.clock",
                text: label,
                tint: tint(for: deadline)
            )
            .accessibilityLabel(Text("Deadline: \(label)"))
        }
    }

    private func tint(for deadline: Date) -> Color {
        if deadline < now { return .red }
        if DeadlineFormat.isUrgent(for: deadline, now: now) { return .orange }
        return .secondary
    }
}

struct SectionHeader: View {
    var title: String
    var count: Int?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .scaledFont(12.5, weight: .semibold)
                .foregroundStyle(tint)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .textCase(nil)
    }
}

/// Rounded square icon used for lists, templates and tags.
struct ListGlyph: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

struct TagPill: View {
    var name: String
    var color: Color
    var compact: Bool = true

    var body: some View {
        Text(name)
            .font(.system(size: compact ? 11.5 : 13, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 8 : 11)
            .padding(.vertical, compact ? 3 : 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct CountBadge: View {
    var value: Int
    var body: some View {
        Text("\(value)")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}

/// Shared empty state so every screen says the same thing in the same voice.
struct EmptyHint: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .scaledFont(15, weight: .semibold)
            Text(message)
                .scaledFont(13)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
    }
}

/// Row container that gets the glass treatment only on pointer platforms,
/// where hover and selection make elevation meaningful.
struct RowSurface: ViewModifier {
    var isSelected: Bool
    var tint: Color = Theme.accent

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.12) : Color.primary.opacity(0.001))
            }
    }
}

extension View {
    func rowSurface(isSelected: Bool, tint: Color = Theme.accent) -> some View {
        modifier(RowSurface(isSelected: isSelected, tint: tint))
    }
}

/// Over a photo backdrop a bare row becomes unreadable, so it moves onto its
/// own piece of glass. On the plain white page rows stay bare.
struct PhotoRowSurface: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.glassCard(radius: 20, padding: 10)
        } else {
            content
        }
    }
}

extension View {
    func photoRowSurface(_ enabled: Bool) -> some View {
        modifier(PhotoRowSurface(enabled: enabled))
    }
}
