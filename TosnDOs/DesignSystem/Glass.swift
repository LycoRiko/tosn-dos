import SwiftUI

/// The whole Liquid Glass story lives in this file.
///
/// On iOS 26 / macOS 26 we hand the surface to the system (`.glassEffect`),
/// which gives real refraction, specular highlights and neighbor merging.
/// On iOS 18 / macOS 15 we fall back to `.ultraThinMaterial` plus a hairline
/// stroke — close enough that the layout never shifts between OS versions.
struct GlassSurface: ViewModifier {
    var radius: CGFloat = Theme.radius
    var tint: Color?
    var interactive: Bool = false
    var contentPadding: CGFloat?

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let padded = content.padding(contentPadding ?? 0)

        if #available(iOS 26.0, macOS 26.0, *) {
            padded.glassEffect(glass, in: shape)
        } else {
            padded
                .background {
                    if let tint { shape.fill(tint) }
                }
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(
                        .white.opacity(scheme == .dark ? 0.10 : 0.55),
                        lineWidth: 1
                    )
                }
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.06), radius: 18, y: 8)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    /// Glass surface without touching the layout.
    func glassSurface(
        radius: CGFloat = Theme.radius,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(GlassSurface(radius: radius, tint: tint, interactive: interactive))
    }

    /// Glass surface with built-in padding — the default card treatment.
    func glassCard(
        radius: CGFloat = Theme.radius,
        tint: Color? = nil,
        padding: CGFloat = 16
    ) -> some View {
        modifier(GlassSurface(radius: radius, tint: tint, interactive: false, contentPadding: padding))
    }

    func glassPill(tint: Color? = nil) -> some View {
        modifier(GlassSurface(radius: 999, tint: tint, interactive: false, contentPadding: 0))
    }
}

/// Wraps siblings so Liquid Glass can merge them into one continuous shape.
/// A no-op on older systems.
struct GlassCluster<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Capsule button used for the primary action in every sheet. Glass with a
/// light accent wash and an accent label — no gradient, but enough contrast to
/// stay readable on plain white.
struct PrimaryActionStyle: ButtonStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        let accent = tint ?? Theme.accent

        configuration.label
            .scaledFont(16, weight: .semibold)
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .glassPill(tint: accent.opacity(0.22))
            .overlay {
                Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 1)
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Quiet secondary action — text only, no chrome.
struct QuietActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(16, weight: .medium)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}
