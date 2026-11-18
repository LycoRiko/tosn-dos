import SwiftUI

/// The Browse entry point: a field-shaped button right under the big title.
/// It opens the same sheet as the Today toolbar button.
struct SearchEntryRow: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Search tasks, lists and screenshots")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .glassPill()
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Search"))
        .accessibilityIdentifier("browse.search")
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: Theme.pagePadding, bottom: 10, trailing: Theme.pagePadding))
    }
}
