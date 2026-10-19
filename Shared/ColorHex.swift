import SwiftUI

extension Color {
    /// Brand colors are stored as hex integers in the data model so a record
    /// never depends on an asset name being present in every target.
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    init(hex: Int, alpha: Double = 1) {
        self.init(hex: UInt32(truncatingIfNeeded: hex), alpha: alpha)
    }

    /// Round-trips a color the user picked back into the stored hex form.
    var hexInt: Int {
        #if canImport(UIKit)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        let converted = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let red = converted.redComponent
        let green = converted.greenComponent
        let blue = converted.blueComponent
        #endif
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return (r << 16) | (g << 8) | b
    }
}

/// The color set offered for lists and templates. Shared with the widget so
/// the desktop and home screen always match the app.
enum Palette {
    static let choices: [Int] = [
        0x5E5CE6, 0x2FD3B4, 0x0A84FF, 0xFF9F0A,
        0xFF453A, 0xBF5AF2, 0x64D2FF, 0x8E8E93
    ]

    static let accent = Color(hex: 0x5E5CE6)
    static let accentBright = Color(hex: 0x6E6BFF)
    static let mint = Color(hex: 0x2FD3B4)

    static func color(_ hex: Int) -> Color { Color(hex: hex) }
}
