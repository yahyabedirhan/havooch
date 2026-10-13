import SwiftUI

/// A hairline in the theme's `separator`, one pixel thick on the screen it
/// shows on. It separates two parts of the window's one surface.
struct Hairline: View {
    let axis: Axis
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let thickness = 1 / max(displayScale, 1)
        Rectangle()
            .fill(palette[.separator])
            .frame(width: axis == .vertical ? thickness : nil, height: axis == .horizontal ? thickness : nil)
            .accessibilityHidden(true)
    }
}
