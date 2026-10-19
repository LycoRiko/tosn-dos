import SwiftUI
import SwiftData

/// The whole watch app. Scope is deliberately one screen: what is left today,
/// and one tap to tick it off. No templates, no tags, no editing, no settings —
/// anything more belongs on the phone.
@main
struct TosnDOsWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchTodayView()
        }
        .modelContainer(SharedStore.boot().container)
    }
}
