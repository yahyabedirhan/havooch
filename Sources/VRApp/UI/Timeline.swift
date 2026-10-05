import SwiftUI
import VRReview

/// The scrubber: a track with the played part filled and a thumb at the
/// player's time, and one pin above the track for each comment. A click or
/// a drag on the track seeks; a click on a pin shows its comment.
struct Timeline: View {
    /// A comment as the timeline marks it.
    struct Marker: Equatable, Identifiable {
        var id: String
        var time: Double
        var state: CommentState
        var isSelected: Bool
        /// Whether the agent's question on it waits for an answer.
        var hasOpenQuestion = false
    }

    let time: Double
    let duration: Double
    var markers: [Marker] = []
    /// A drag on the track started.
    var scrubStarted: () -> Void = {}
    let seek: (Double) -> Void
    /// The drag on the track ended, or was cancelled.
    var scrubEnded: () -> Void = {}
    var show: (String) -> Void = { _ in }

    /// Where the pointer is along the track while a drag goes on, from 0 to
    /// 1, else nil. The played part and the thumb follow it, not the
    /// player's time, so they stay under the pointer while seeks land.
    @State private var dragFraction: Double?
    @State private var isHovered = false
    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let trackArea: CGFloat = 20
    private static let pinArea: CGFloat = 14
    /// The track under the pointer, or held: thicker, so it reads as live.
    private static let activeTrackHeight: CGFloat = 6
    /// How much the thumb grows while the track is held.
    private static let pressedThumbScale: CGFloat = 1.25
    /// The smallest area a pin takes clicks in. It overlaps the track's
    /// top, so the bar keeps its height.
    private static let pinHitSize: CGFloat = 22
    /// How much the selected comment's pin grows.
    private static let selectedPinScale: CGFloat = 1.2
    /// The motion of the track and the pins as they respond: quick, with no
    /// bounce.
    private static let response = Animation.spring(duration: 0.25, bounce: 0)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let played = width * (dragFraction ?? Self.fraction(of: time, in: duration))
            let trackHeight = isPressed || isHovered ? Self.activeTrackHeight : Theme.trackHeight
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: trackHeight)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: played, height: trackHeight)
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                        .frame(width: Theme.thumbSize, height: Theme.thumbSize)
                        .scaleEffect(isPressed ? Self.pressedThumbScale : 1)
                        .offset(x: min(max(0, played - Theme.thumbSize / 2), max(0, width - Theme.thumbSize)))
                }
                .frame(height: Self.trackArea)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .gesture(scrubbing(width: width))
                .onChange(of: isPressed) { _, pressed in
                    // A drag the system cancelled never reaches `onEnded`.
                    if !pressed { finishScrub() }
                }
                .animation(reduceMotion ? nil : Self.response, value: isPressed)
                .animation(reduceMotion ? nil : Self.response, value: isHovered)
                .padding(.top, Self.pinArea)
                .accessibilityElement()
                .accessibilityLabel("Timeline")
                .accessibilityValue("\(TimeText.short(time)) of \(TimeText.short(duration))")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: seek(time + PlayerKey.skip)
                    case .decrement: seek(time - PlayerKey.skip)
                    @unknown default: break
                    }
                }

                // Above the track, so a pin never hides the played part.
                ForEach(markers) { marker in
                    pin(marker)
                        .position(x: width * Self.fraction(of: marker.time, in: duration), y: Self.pinArea / 2 + 2)
                }
            }
        }
        .frame(height: Self.pinArea + Self.trackArea)
    }

    /// A press on the track seeks at once; a drag then seeks 1:1 with the
    /// pointer, which can leave the track and keep scrubbing.
    private func scrubbing(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isPressed) { _, pressed, _ in pressed = true }
            .onChanged { drag in
                guard width > 0, duration > 0 else { return }
                if dragFraction == nil { scrubStarted() }
                let fraction = Double(min(max(0, drag.location.x / width), 1))
                dragFraction = fraction
                seek(fraction * duration)
            }
            .onEnded { _ in finishScrub() }
    }

    /// Ends the drag once, whether it ended or was cancelled.
    private func finishScrub() {
        guard dragFraction != nil else { return }
        dragFraction = nil
        scrubEnded()
    }

    private func pin(_ marker: Marker) -> some View {
        // The state's glyph in its colour, as on the card: the status reads
        // without colour too. An open question shows instead, since the
        // agent waits for the person there.
        let isWorking = marker.state == .working && !marker.hasOpenQuestion
        return Button {
            show(marker.id)
        } label: {
            Image(systemName: marker.hasOpenQuestion ? "questionmark.circle.fill" : Theme.glyph(for: marker.state))
                .font(.system(size: Theme.pinSize))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(marker.hasOpenQuestion ? Theme.question : Theme.colour(for: marker.state))
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isWorking && !reduceMotion)
                .frame(width: Theme.pinSize, height: Theme.pinSize)
                .background(Circle().fill(.background).padding(0.5))
                .scaleEffect(marker.isSelected ? Self.selectedPinScale : 1)
                .animation(reduceMotion ? nil : Self.response, value: marker.isSelected)
                .frame(width: Self.pinHitSize, height: Self.pinHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(PinButtonStyle())
        .help("\(marker.id) at \(TimeText.short(marker.time)), \(marker.state.rawValue)\(marker.hasOpenQuestion ? ", the agent asks" : "")")
        .accessibilityLabel("Comment \(marker.id) at \(TimeText.short(marker.time)), \(marker.state.rawValue)\(marker.hasOpenQuestion ? ", the agent asks" : "")")
        .accessibilityAddTraits(marker.isSelected ? .isSelected : [])
    }

    /// How far along `time` is, from 0 to 1; 0 for a video with no length.
    nonisolated static func fraction(of time: Double, in duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(0, time / duration), 1)
    }

    /// The pins for `comments`, with the selected comment's marked, and
    /// those whose last question has no answer yet.
    nonisolated static func markers(for comments: [Comment], selection: String?) -> [Marker] {
        comments.map {
            Marker(id: $0.id, time: $0.time, state: $0.state, isSelected: $0.id == selection, hasOpenQuestion: $0.openQuestion != nil)
        }
    }
}

/// A pin's press: it gives a little under the pointer, and nothing else
/// changes, so the timeline stays quiet.
private struct PinButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0), value: configuration.isPressed)
    }
}
