import SwiftUI

extension View {
    func pressedByKeys(
        in model: WindowModel, isFocused: Binding<Bool>? = nil, action: @escaping () -> Void
    ) -> some View {
        modifier(KeyPress(model: model, reportsFocus: isFocused, action: action))
    }

    @ViewBuilder func pressedByKeys(in model: WindowModel?, action: @escaping () -> Void) -> some View {
        if let model {
            pressedByKeys(in: model, action: action)
        } else {
            self
        }
    }
}

private struct KeyPress: ViewModifier {
    let model: WindowModel
    let reportsFocus: Binding<Bool>?
    let action: () -> Void

    @State private var id = UUID()
    @FocusState private var isFocused: Bool
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
