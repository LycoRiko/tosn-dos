import SwiftUI

/// Dynamic Type for the hand-picked point sizes used across the design system.
///
/// The app deliberately uses exact sizes so a 50-task day stays scannable, but
/// a fixed `.system(size:)` ignores the user's text-size setting entirely.
/// `@ScaledMetric` keeps the design at the default setting and grows it only
/// when someone actually asks for larger text.
private struct ScaledFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func scaledFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design))
    }
}
