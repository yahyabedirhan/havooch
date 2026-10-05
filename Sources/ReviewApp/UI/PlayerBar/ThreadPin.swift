import ReviewCore
import ReviewWire
import SwiftUI

/// One thread's pin on the timeline: a small mark, a rounded
/// square when the thread has a region and a circle when it has none, in
/// the colour of the thread's state. A queued thread is a ring; every later
/// state fills the mark, and a state the agent set adds its glyph inside,
/// so a state is never told by colour alone. The thread in focus gets a
/// ring in the accent colour.
struct ThreadPin: View {
    let look: Look
    var isSelected = false
    /// The mark's side.
    var size: CGFloat = 10

    @Environment(\.palette) private var palette

    /// What a pin shows of its thread, in words and values a test can read.
    struct Look: Equatable {
        let number: Int
        let time: Double
        let regions: Int
        let state: MessageState

        init(_ thread: ReviewThread) {
            number = thread.number
            time = thread.time ?? 0
            regions = thread.messages.count { $0.region != nil }
            // A frame thread always has a person message; queued is the
            // state before anything happened to it.
            state = thread.state ?? .queued
        }

        /// A rounded square when any message has a region.
        var isSquare: Bool { regions > 0 }

        /// The hover line: `#3 · 0:12 · 2 regions · Working`.
        var help: String {
            let regionWords = switch regions {
            case 0: "no region"
            case 1: "1 region"
            default: "\(regions) regions"
            }
            return "#\(number) · \(PlayerBar.clock(time)) · \(regionWords) · \(StateLook.name(state))"
        }
    }

    var body: some View {
        let shape = PinShape(isSquare: look.isSquare)
        let color = palette.state(look.state)
        ZStack {
            if look.state == .queued {
                // Filled with the bar's colour, so the track doesn't show through the ring.
                shape.fill(palette[.bar])
                shape.strokeBorder(color, lineWidth: size / 5)
            } else {
                shape.fill(color)
                if let glyph = StateLook.pinGlyph(look.state) {
                    Image(systemName: glyph)
                        .font(.system(size: size * 0.55, weight: .heavy))
                        .foregroundStyle(palette[.textOnAccent])
                }
            }
        }
        .frame(width: size, height: size)
        .padding(2)
        .overlay {
            if isSelected { shape.strokeBorder(palette[.accent], lineWidth: 1.5) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(look.help)
    }
}

/// A pin's outline: a circle, or a square with rounded corners.
struct PinShape: InsettableShape {
    var isSquare: Bool
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        return isSquare ? Path(roundedRect: rect, cornerRadius: rect.width * 0.28) : Path(ellipseIn: rect)
    }

    func inset(by amount: CGFloat) -> PinShape {
        PinShape(isSquare: isSquare, inset: inset + amount)
    }
}
