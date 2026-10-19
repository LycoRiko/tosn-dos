#if os(iOS)
import SwiftUI

/// iPhone / iPad shell. Three tabs, nothing else — the same shape as
/// Reminders and Notes, so there is nothing new to learn.
struct PhoneRootView: View {
    private enum AppTab: Hashable {
        case today, browse, settings
    }

    @State private var tab: AppTab = .today

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack {
                    HomeView(selection: .constant(nil))
                }
            }

            Tab("Browse", systemImage: "square.grid.2x2", value: AppTab.browse) {
                BrowseView()
            }

            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.accent)
        .onOpenURL { url in
            if url.host == "today" { tab = .today }
            if url.host == "browse" { tab = .browse }
        }
    }
}
#endif
