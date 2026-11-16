import SwiftUI
import SwiftData

/// iPad and Mac-width answer to Browse: a real sidebar, so choosing a list does
/// not cost a push. The iPhone keeps the tab + push stack.
struct LibrarySplitView: View {
    @Binding var pendingList: UUID?

    @Query(sort: \TodoList.sortIndex) private var lists: [TodoList]
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var selection: SidebarItem? = .smart(.today)
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var usesSplit: Bool {
        sizeClass != .compact
    }

    var body: some View {
        if usesSplit {
            split
        } else {
            BrowseView(pendingList: $pendingList)
        }
    }

    private var split: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(SmartList.allCases) { smart in
                        Label(smart.title, systemImage: smart.symbol)
                            .tag(SidebarItem.smart(smart))
                    }
                } header: {
                    SectionHeader(title: String(localized: "Smart lists"))
                }

                if !lists.isEmpty {
                    Section {
                        ForEach(lists) { list in
                            HStack(spacing: 10) {
                                ListGlyph(symbol: list.symbol, color: ListPalette.color(list.colorHex))
                                Text(list.title).font(.subheadline)
                                Spacer(minLength: 4)
                                CountBadge(value: list.openTaskCount)
                            }
                            .tag(SidebarItem.list(list.uid))
                        }
                    } header: {
                        SectionHeader(title: String(localized: "Lists"))
                    }
                }

                if !tags.isEmpty {
                    Section {
                        ForEach(tags) { tag in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(ListPalette.color(tag.colorHex))
                                    .frame(width: 8, height: 8)
                                Text(tag.name).font(.subheadline)
                            }
                            .tag(SidebarItem.tag(tag.uid))
                        }
                    } header: {
                        SectionHeader(title: String(localized: "Tags"))
                    }
                }

                Section {
                    NavigationLink {
                        TemplateLibraryView()
                    } label: {
                        Label {
                            Text("Template library")
                        } icon: {
                            Image(systemName: "square.grid.2x2")
                                .foregroundStyle(Theme.accent)
                        }
                        .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Browse")
            .onChange(of: pendingList) { _, uid in
                guard let uid else { return }
                selection = .list(uid)
                pendingList = nil
            }
        } detail: {
            NavigationStack {
                if let selection {
                    TaskListView(scope: selection, selection: .constant(nil))
                } else {
                    EmptyHint(
                        symbol: "square.grid.2x2",
                        title: String(localized: "Pick a list"),
                        message: String(localized: "Everything you wrote is on the left.")
                    )
                }
            }
        }
    }
}
