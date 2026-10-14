import ReviewCore
import ReviewWire
import SwiftUI

struct ThreadPin: View {
    let look: Look
    var isSelected = false
    var size: CGFloat = 10

    @Environment(\.palette) private var palette

    struct Look: Equatable {
        let number: Int
        let time: Double
        let regions: Int
        let state: MessageState
        let waitsForAnswer: Bool

        init(_ thread: ReviewThread) {
            number = thread.number
            time = thread.time ?? 0
            regions = thread.messages.count { $0.region != nil }
            state = thread.state ?? .queued
            waitsForAnswer = thread.openQuestion != nil
        }

        var glyph: String? {
            waitsForAnswer ? "questionmark" : StateLook.pinGlyph(state)
        }

        var isRing: Bool { state == .queued && !waitsForAnswer }

        func color(in palette: Palette) -> Color {
            waitsForAnswer ? palette[.question] : palette.state(state)
        }

        var isSquare: Bool { regions > 0 }

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
