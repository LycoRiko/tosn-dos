import SwiftUI

/// Shared preference keys.
///
/// The same keys are declared in `Settings.bundle/Root.plist`, which is what
/// puts these switches inside the system Settings app on iOS. Keep the two
/// files in sync when adding a preference.
enum PreferenceKey {
    static let showCompleted = "pref.showCompleted"
    static let appearance = "pref.appearance"
    static let templateDueToday = "pref.templateDueToday"
    static let hasOnboarded = "pref.hasOnboarded"
}

enum AppearanceMode: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum Prefs {
    /// Matches the `DefaultValue` entries in Settings.bundle/Root.plist.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PreferenceKey.showCompleted: true,
            PreferenceKey.appearance: AppearanceMode.system.rawValue,
            PreferenceKey.templateDueToday: true
        ])
    }
}

extension EnvironmentValues {
    /// True when the current screen shows a photo backdrop, which is what
    /// tells rows to put themselves on glass for legibility.
    @Entry var photoBackground: Bool = false
}
