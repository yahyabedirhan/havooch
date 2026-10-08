import ReviewCore
import SwiftUI

/// The timeline in the player bar: the played part of the
/// video and the playhead, which a press or a drag moves, with a pin above
/// the track for each thread and a thin stem down to the thread's frame.
/// Light time labels with short ticks sit under the track when the bar has
/// the room. A click on a pin goes to its thread's frame.
struct Timeline: View {
    /// Told which pin has the keyboard focus, so Space and Return press it.
    let model: WindowModel
    let time: Double
    let duration: Double
    /// The threads on a frame, in time order. General has no pin.
    let threads: [ReviewThread]
    let selection: ThreadID?
    let scrub: (Double) -> Void
    let select: (ThreadID) -> Void

    @GestureState private var isHeld = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    private static let trackHeight: CGFloat = 4
    private static let heldTrackHeight: CGFloat = 6
    private static let knob: CGFloat = 12
    private static let heldKnob: CGFloat = 15
    private static let mark: CGFloat = 10
    /// The square a pin takes the press in.
    private static let pinBox: CGFloat = 16
    /// The pins' row, above the track's: the marks and their stems.
    private static let pinRow: CGFloat = 18
    private static let trackRow: CGFloat = 12
    /// The time labels' row, under the track's.
    private static let labelRow: CGFloat = 11
    /// The least room a time label takes along the track.
    private static let labelSpacing: CGFloat = 56

    private static var markCentre: CGFloat { pinBox / 2 }
    private static var trackCentre: CGFloat { pinRow + trackRow / 2 }

    var body: some View {
        // With the time labels when the bar is tall enough, else without.
        ViewThatFits(in: .vertical) {
            content(labelled: true)
            content(labelled: false)
        }
    }

    private func content(labelled: Bool) -> some View {
        let height = Self.pinRow + Self.trackRow + (labelled ? Self.labelRow : 0)
        return GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                stems(width: width)
                scrubber(width: width, height: height)
                if labelled {
                    labels(width: width)
                        .offset(y: Self.pinRow + Self.trackRow)
                }
                ForEach(threads) { thread in
                    pin(thread, width: width)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
        .frame(height: height)
        // Up by what the pins add over the labels, so the track, not the
        // whole timeline, sits on the bar's centre line.
        .offset(y: height / 2 - Self.trackCentre)
    }

    /// The track, the played part and the knob. The whole timeline's height
    /// takes the press, so it is easy to hit; the pins sit over it. It
    /// answers on the press: the knob grows and the track thickens while
    /// it's held, and it follows the pointer 1:1.
    private func scrubber(width: CGFloat, height: CGFloat) -> some View {
        let played = Self.place(of: time, in: duration, width: width)
        let track = isHeld ? Self.heldTrackHeight : Self.trackHeight
        let knob = isHeld ? Self.heldKnob : Self.knob
        return ZStack(alignment: .leading) {
            Capsule().fill(palette[.track]).frame(width: width, height: track)
            Capsule().fill(palette[.accent]).frame(width: max(played, track), height: track)
            Circle()
                .fill(palette[.knob])
                .shadow(color: palette[.shadow], radius: isHeld ? 2 : 1, y: 0.5)
                .frame(width: knob, height: knob)
                .offset(x: min(max(0, played - knob / 2), width - knob))
        }
        .frame(width: width, height: Self.trackRow)
        .animation(reduceMotion ? nil : .smooth(duration: 0.15), value: isHeld)
        .padding(.top, Self.pinRow)
        .frame(width: width, height: height, alignment: .top)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isHeld) { _, held, _ in held = true }
                .onChanged { drag in
                    guard width > 0, duration > 0 else { return }
                    scrub(Double(min(max(0, drag.location.x / width), 1)) * duration)
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue("\(PlayerBar.clock(time)) of \(PlayerBar.clock(duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: scrub(min(time + Shortcuts.skip, duration))
            case .decrement: scrub(max(time - Shortcuts.skip, 0))
            @unknown default: break
            }
        }
    }

    /// A thin line from each pin down to its frame on the track, in the
    /// pin's colour, soft unless the thread is in focus.
    private func stems(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(threads) { thread in
                Rectangle()
                    .fill(ThreadPin.Look(thread).color(in: palette).opacity(thread.id == selection ? 0.8 : 0.45))
                    .frame(width: 1, height: Self.trackCentre - Self.markCentre)
                    .position(
                        x: Self.place(of: thread.time ?? 0, in: duration, width: width),
                        y: (Self.markCentre + Self.trackCentre) / 2
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A thread's pin at the head of its stem.
    private func pin(_ thread: ReviewThread, width: CGFloat) -> some View {
        let look = ThreadPin.Look(thread)
        let isSelected = thread.id == selection
        return Button {
            select(thread.id)
        } label: {
            ThreadPin(look: look, isSelected: isSelected, size: Self.mark)
                .frame(width: Self.pinBox, height: Self.pinBox)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pressedByKeys(in: model) { select(thread.id) }
        .help(look.help)
        .position(x: Self.place(of: look.time, in: duration, width: width), y: Self.markCentre)
        // The thread in focus stays on top of its neighbours.
        .zIndex(isSelected ? 1 : 0)
    }

    /// Small, quiet time labels under the track, each beside a short tick.
    private func labels(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.ticks(in: duration, width: width), id: \.self) { tick in
                HStack(alignment: .top, spacing: 2) {
                    Rectangle().fill(palette[.track]).frame(width: 1, height: 4)
                    Text(PlayerBar.clock(tick))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(palette[.textTertiary])
                }
                .fixedSize()
                .offset(x: Self.place(of: tick, in: duration, width: width))
            }
        }
        .frame(width: width, height: Self.labelRow, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The times to label: a round step that leaves each label its room,
    /// without one too near the track's end to fit.
    static func ticks(in duration: Double, width: CGFloat) -> [Double] {
        guard duration > 0, width > labelSpacing else { return [] }
        let most = Double(Int(width / labelSpacing))
        let steps: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
        let step = steps.first { duration / $0 <= most } ?? (duration / most).rounded(.up)
        return stride(from: 0, through: duration, by: step).filter {
            place(of: $0, in: duration, width: width) <= width - labelSpacing / 2
        }
    }

    /// Where `time` is along a track `width` wide.
    private static func place(of time: Double, in duration: Double, width: CGFloat) -> CGFloat {
        duration > 0 ? CGFloat(min(max(0, time / duration), 1)) * width : 0
    }
}
