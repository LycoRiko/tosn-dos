#if os(iOS)
import SwiftUI
import SwiftData

/// iPhone / iPad shell. Three tabs, nothing else — the same shape as
/// Reminders and Notes, so there is nothing new to learn.
struct PhoneRootView: View {
    private enum AppTab: Hashable {
        case today, browse, settings
    }

    @Environment(\.modelContext) private var context
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
            if url.host == "import" { importSharedList(from: url) }
        }
    }

    /// `tosndos://import?c=<code>` — always lands as a new list, never merges
    /// into an existing one, so a shared code cannot overwrite local work.
    private func importSharedList(from url: URL) {
        guard
            let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "c" })?.value,
            let snapshot = ListCodec.decode(code)
        else { return }

        let existing = (try? context.fetch(FetchDescriptor<TodoList>())) ?? []
        let next = (existing.map(\.sortIndex).max() ?? 0) + 1
        ListCodec.importList(snapshot, into: context, sortIndex: next)
        tab = .browse
    }
}
#endif
