import SwiftUI

extension View {
    /// Lets Space and Return press this control while it has the keyboard
    /// focus under keyboard navigation, as a click does. The player's key
    /// monitor (`Shortcuts`) sees every key before SwiftUI, so the control
    /// tells `model` when it has the focus and what pressing it does.
    /// `isFocused`, when given, follows the control's keyboard focus: a
    /// control hidden until hover shows while it has the focus, so keys
    /// never press a button the person can't see.
    func pressedByKeys(
        in model: WindowModel, isFocused: Binding<Bool>? = nil, action: @escaping () -> Void
    ) -> some View {
        modifier(KeyPress(model: model, reportsFocus: isFocused, action: action))
    }

    /// As above in a player window; outside one (the first-run window)
    /// the player takes no keys, so the control's own keys work as they are.
    @ViewBuilder func pressedByKeys(in model: WindowModel?, action: @escaping () -> Void) -> some View {
        if let model {
            pressedByKeys(in: model, action: action)
        } else {
            self
        }
    }
}

/// Reports the control's keyboard focus to the model (`pressedByKeys`).
private struct KeyPress: ViewModifier {
    let model: WindowModel
    let reportsFocus: Binding<Bool>?
    let action: () -> Void

    @State private var id = UUID()
    @FocusState private var isFocused: Bool
    /// Whether the control's window is the key window: a control keeps
    /// its focus in a window behind Settings, and must not take the keys
    /// pressed there.
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in reportsFocus?.wrappedValue = focused }
            .onChange(of: isFocused && appearsActive) { _, pressable in
                if pressable {
                    model.focusControl(id, press: action)
                } else {
                    model.blurControl(id)
                }
            }
            .onDisappear {
                model.blurControl(id)
                reportsFocus?.wrappedValue = false
            }
    }
}
