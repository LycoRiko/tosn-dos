import SwiftUI

/// Home. One list, with an explicit filter the user opens when they want it —
/// the app never guesses which view you meant.
struct HomeView: View {
    @Binding var selection: TodoItem?

    @State private var scope: SidebarItem = .smart(.today)
    @State private var showsSearch = false

    var body: some View {
        TaskListView(scope: scope, selection: $selection)
            .toolbar {
                // One group so iOS 26 draws a single glass capsule around both.
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showsSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("Search"))
                    .help(Text("Search"))

                    Menu {
                        Picker("Show", selection: $scope) {
                            ForEach(SmartList.allCases) { smart in
                                Label(smart.title, systemImage: smart.symbol)
                                    .tag(SidebarItem.smart(smart))
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(Text("Filter"))
                    .help(Text("Filter"))
                }
            }
            .sheet(isPresented: $showsSearch) {
                SearchView()
            }
    }
}
