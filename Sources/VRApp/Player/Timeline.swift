import SwiftUI
import VRReview

/// The scrubber: the played part of the video and the playhead, which a
/// press or a drag moves, with a pin above the track for each comment. A
/// pin is a mark, round for a comment at a time and a rounded square for
/// one on a region, in the colour and with the symbol of where the comment
/// stands, and a thin stem down to the comment's moment on the track.
/// Light time labels sit under the track when the bar has the room.
/// A click on a pin goes to its comment. The app's own, since AVKit's
/// scrubber can't carry markers.
struct Timeline: View {
    let time: Double
    let duration: Double
    /// The open video's comments, in time order.
    let comments: [Comment]
    let selection: CommentID?
    let scrub: (Double) -> Void
    let select: (CommentID) -> Void

    private static let trackHeight: CGFloat = 4
    private static let knob: CGFloat = 12
    private static let marker: CGFloat = 10
    /// The square a pin's mark takes the press in.
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
                ForEach(comments) { comment in
                    pin(comment, width: width)
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
    /// takes the press, so it is easy to hit; the pins sit over it.
    private func scrubber(width: CGFloat, height: CGFloat) -> some View {
        let played = Self.place(of: time, in: duration, width: width)
        return ZStack(alignment: .leading) {
            Capsule().fill(.quaternary).frame(width: width, height: Self.trackHeight)
            Capsule().fill(Color.accentColor).frame(width: played, height: Self.trackHeight)
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                .frame(width: Self.knob, height: Self.knob)
                .offset(x: min(max(0, played - Self.knob / 2), width - Self.knob))
        }
        .frame(width: width, height: Self.trackRow)
        .padding(.top, Self.pinRow)
        .frame(width: width, height: height, alignment: .top)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { drag in
                guard width > 0, duration > 0 else { return }
                scrub(Double(min(max(0, drag.location.x / width), 1)) * duration)
            }
        )
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue("\(TimeText.short(time)) of \(TimeText.short(duration))")
    }

    /// A thin line from each pin down to its moment on the track, in the
    /// pin's colour, soft unless the comment is in focus.
    private func stems(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(comments) { comment in
                Rectangle()
                    .fill(StatusStyle.of(comment).color.opacity(comment.id == selection ? 0.8 : 0.45))
                    .frame(width: 1, height: Self.trackCentre - Self.markCentre)
                    .position(x: Self.place(of: comment.time, in: duration, width: width), y: (Self.markCentre + Self.trackCentre) / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A comment's mark at the head of its stem.
    private func pin(_ comment: Comment, width: CGFloat) -> some View {
        let style = StatusStyle.of(comment)
        return Button {
            select(comment.id)
        } label: {
            StatusMark(style: style, squared: comment.region != nil, selected: comment.id == selection, size: Self.marker)
                .frame(width: Self.pinBox, height: Self.pinBox)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(TimeText.short(comment.time))  \(style.label)  ·  \(comment.text)")
        .accessibilityLabel("Comment at \(TimeText.short(comment.time)), \(style.label): \(comment.text)")
        .position(x: Self.place(of: comment.time, in: duration, width: width), y: Self.markCentre)
        // The comment in focus stays on top of its neighbours.
        .zIndex(comment.id == selection ? 1 : 0)
    }

    /// Small, quiet time labels under the track, each beside a short tick.
    private func labels(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.ticks(in: duration, width: width), id: \.self) { tick in
                HStack(alignment: .top, spacing: 2) {
                    Rectangle().fill(.quaternary).frame(width: 1, height: 4)
                    Text(TimeText.short(tick))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.tertiary)
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
    private static func ticks(in duration: Double, width: CGFloat) -> [Double] {
        guard duration > 0, width > labelSpacing else { return [] }
        let most = Double(Int(width / labelSpacing))
        let steps: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
        let step = steps.first { duration / $0 <= most } ?? (duration / most).rounded(.up)
        return stride(from: 0, through: duration, by: step).filter { place(of: $0, in: duration, width: width) <= width - labelSpacing / 2 }
    }

    /// Where `time` is along a track `width` wide.
    private static func place(of time: Double, in duration: Double, width: CGFloat) -> CGFloat {
        duration > 0 ? CGFloat(min(max(0, time / duration), 1)) * width : 0
    }
}
