#if os(iOS)
import SwiftUI
import UIKit

/// Lets a short list be dragged so the keyboard can be dismissed.
/// Bounce follows the software keyboard, not focus.
struct KeyboardDismissScroll: ViewModifier {
    @State private var keyboardVisible = false

    func body(content: Content) -> some View {
        content
            // `.interactively`: the keyboard follows the finger. The taps that
            // felt laggy are covered by `dismissKeyboardOnTap` below.
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(keyboardVisible ? .always : .basedOnSize)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardVisible = false
            }
    }
}
extension View {
    /// Tapping anywhere in the list puts the keyboard away. Safe only where no
    /// text field lives inside the list — the quick-add field is in a
    /// `safeAreaInset`, so it keeps focus.
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        })
    }
}
#endif
