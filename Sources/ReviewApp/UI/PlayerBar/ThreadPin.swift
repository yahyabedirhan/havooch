import ReviewCore
import ReviewWire
import SwiftUI

/// One thread's pin on the timeline: a small mark, a rounded
/// square when the thread has a region and a circle when it has none, in
/// the colour of the thread's state. A queued thread is a ring; every later
/// state fills the mark, and a state the agent set adds its glyph inside,
/// so a state is never told by colour alone. While the agent waits for the
/// person's answer on the thread, the pin is filled in the question colour
/// with a question mark instead, so the person sees it from the timeline
/// alone; the answer gives the pin its state colour back. The thread in
/// focus gets a ring in the accent colour.
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
        /// Whether the thread has an open question: the agent waits for
        /// the person's answer.
        let waitsForAnswer: Bool

        init(_ thread: ReviewThread) {
            number = thread.number
            time = thread.time ?? 0
            regions = thread.messages.count { $0.region != nil }
            // A frame thread always has a person message; queued is the
            // state before anything happened to it.
            state = thread.state ?? .queued
            waitsForAnswer = thread.openQuestion != nil
        }

        /// The SF Symbol inside the mark: a question mark while the agent
        /// waits for an answer, else the state's glyph, if it has one.
        var glyph: String? {
            waitsForAnswer ? "questionmark" : StateLook.pinGlyph(state)
        }

        /// A ring rather than a filled mark: a queued thread with no open
        /// question.
        var isRing: Bool { state == .queued && !waitsForAnswer }

        /// The mark's colour, also its stem's: the question colour while the
        /// agent waits for an answer, else the state's.
        func color(in palette: Palette) -> Color {
            waitsForAnswer ? palette[.question] : palette.state(state)
        }

        /// A rounded square when any message has a region.
        var isSquare: Bool { regions > 0 }

        /// The hover line: `#3 · 0:12 · 2 regions · Working`, with
        /// `Question waiting` in place of the state while the agent waits
        /// for an answer.
        var help: String {
            let regionWords = switch regions {
            case 0: "no region"
            case 1: "1 region"
            default: "\(regions) regions"
            }
            return "#\(number) · \(PlayerBar.clock(time)) · \(regionWords) · \(waitsForAnswer ? "Question waiting" : StateLook.name(state))"
        }
    }

    var body: some View {
        let shape = PinShape(isSquare: look.isSquare)
        let color = look.color(in: palette)
        ZStack {
            if look.isRing {
                // Filled with the window's colour, so the track doesn't show through the ring.
                shape.fill(palette[.window])
                shape.strokeBorder(color, lineWidth: size / 5)
            } else {
                shape.fill(color)
                if let glyph = look.glyph {
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
