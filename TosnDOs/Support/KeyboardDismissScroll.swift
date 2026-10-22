#if os(iOS)
import SwiftUI
import UIKit

/// Makes a list answer to a drag even when its content is shorter than the
/// screen, which is the only way `scrollDismissesKeyboard` gets a chance to
/// fire in an almost-empty list.
///
/// The bounce is tied to the software keyboard being on screen, not to focus:
/// with a hardware keyboard attached the text field stays focused while no
/// soft keyboard exists, and an idle list that rubber-bands for no reason is
/// worse than the problem this solves.
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
