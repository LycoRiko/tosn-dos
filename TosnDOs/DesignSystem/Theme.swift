import SwiftUI

/// One source of truth for spacing, radii and color.
/// Keep this file small: if a value is not here, it is a one-off.
enum Theme {
    // Layout
    static let radius: CGFloat = 24
    static let radiusSmall: CGFloat = 16
    static let pagePadding: CGFloat = 20
    static let rowSpacing: CGFloat = 10
    static let rowHeight: CGFloat = 52

    // Color — single source is `Palette` in the shared layer.
    static let accent = Palette.accent
    static let accentBright = Palette.accentBright
    static let mint = Palette.mint
}

extension TaskPriority {
    var color: Color {
        switch self {
        case .none: return .secondary
        case .low: return Color(hex: 0x0A84FF)
        case .medium: return Color(hex: 0xFF9F0A)
        case .high: return Color(hex: 0xFF453A)
        }
    }
}

/// The palette offered when creating lists and templates.
enum ListPalette {
    static let colors: [Int] = Palette.choices

    static func color(_ hex: Int) -> Color { Palette.color(hex) }
}

enum ListSymbols {
    static let all: [String] = [
        "list.bullet", "checklist", "tray.full", "briefcase", "house",
        "book", "cart", "figure.run", "airplane", "lightbulb",
        "hammer", "paintbrush", "graduationcap", "heart", "star"
    ]
}

/// Page backdrop.
///
/// Plain white by default — the app supplies no decoration of its own. When the
/// user picks a photo (globally, or for a single list) that photo becomes the
/// backdrop, with user-controlled blur and a scrim that keeps text readable.
struct AppBackground: View {
    /// `nil` means "use the global setting".
    var setting: BackgroundSetting?

    @Environment(\.colorScheme) private var scheme
    @AppStorage(BackgroundKey.imageName) private var globalImage = ""
    @AppStorage(BackgroundKey.blur) private var globalBlur = 24.0
    @AppStorage(BackgroundKey.opacity) private var globalOpacity = 0.92

    private var resolved: BackgroundSetting {
        setting ?? BackgroundSetting(imageName: globalImage, blur: globalBlur, opacity: globalOpacity)
    }

    private var base: Color {
        scheme == .dark ? Color(hex: 0x000000) : Color.white
    }

    var body: some View {
        ZStack {
            base

            if resolved.hasImage, let image = BackgroundStore.image(named: resolved.imageName) {
                image
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.12)          // hides blur bleed at the edges
                    .blur(radius: resolved.blur)
                    .opacity(resolved.opacity)
                    .overlay(base.opacity(scheme == .dark ? 0.45 : 0.34))
            }
        }
        .ignoresSafeArea()
        .clipped()
    }
}
