import SwiftUI
#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: UIImage) { self.init(uiImage: platformImage) }
}
#else
import AppKit
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: NSImage) { self.init(nsImage: platformImage) }
}
#endif

/// The few places where SwiftUI's API still differs between iOS and macOS.
/// Keeping the shims here means feature files read the same on both platforms.
extension View {
    /// `.insetGrouped` is iOS-only; macOS uses a plain inset list.
    func groupedRows() -> some View {
        modifier(GroupedRowsStyle())
    }

    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func compactSheetDetents() -> some View {
        #if os(iOS)
        presentationDetents([.medium, .large])
        #else
        self
        #endif
    }
}

private struct GroupedRowsStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.listStyle(.insetGrouped)
        #else
        content.listStyle(.inset)
        #endif
    }
}
