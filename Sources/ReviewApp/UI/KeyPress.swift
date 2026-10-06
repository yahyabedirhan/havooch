import SwiftUI

extension View {
    /// Lets Space and Return press this control while it has the keyboard
    /// focus under keyboard navigation, as a click does. The player's key
    /// monitor (`Shortcuts`) sees every key before SwiftUI, so the control
    /// tells `model` when it has the focus and what pressing it does.
    func pressedByKeys(in model: AppModel, action: @escaping () -> Void) -> some View {
        modifier(KeyPress(model: model, action: action))
    }
}

/// Reports the control's keyboard focus to the model (`pressedByKeys`).
private struct KeyPress: ViewModifier {
    let model: AppModel
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
            .onChange(of: isFocused && appearsActive) { _, pressable in
                if pressable {
                    model.focusControl(id, press: action)
                } else {
                    model.blurControl(id)
                }
            }
            .onDisappear { model.blurControl(id) }
    }
}
