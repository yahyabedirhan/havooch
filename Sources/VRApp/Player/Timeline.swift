import SwiftUI
import VRReview

/// The scrubber: the played part of the video and the playhead, which a
/// click or a drag moves, with a marker above the track for each comment:
/// round for a comment at a time, a rounded square for one on a region,
/// in the colour and with the symbol of where the comment stands.
/// A click on a marker goes to its comment. The app's own, since AVKit's
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
    /// The markers' row, above the track's.
    private static let markerRow: CGFloat = 16
    private static let trackRow: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let played = duration > 0 ? CGFloat(min(max(0, time / duration), 1)) * width : 0
            VStack(spacing: 0) {
                ZStack {
                    ForEach(comments) { comment in
                        let style = StatusStyle.of(comment)
                        Button {
                            select(comment.id)
                        } label: {
                            StatusMark(style: style, squared: comment.region != nil, selected: comment.id == selection, size: Self.marker)
                                .frame(width: Self.markerRow, height: Self.markerRow)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("\(TimeText.short(comment.time))  \(style.label)  ·  \(comment.text)")
                        .accessibilityLabel("Comment at \(TimeText.short(comment.time)), \(style.label): \(comment.text)")
                        .position(x: Self.place(of: comment.time, in: duration, width: width), y: Self.markerRow / 2)
                        // The comment in focus stays on top of its neighbours.
                        .zIndex(comment.id == selection ? 1 : 0)
                    }
                }
                .frame(width: width, height: Self.markerRow)

                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: Self.trackHeight)
                    Capsule().fill(Color.accentColor).frame(width: played, height: Self.trackHeight)
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                        .frame(width: Self.knob, height: Self.knob)
                        .offset(x: min(max(0, played - Self.knob / 2), width - Self.knob))
                }
                .frame(height: Self.trackRow)
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
        }
        .frame(height: Self.markerRow + Self.trackRow)
    }

    /// Where `time` is along a track `width` wide.
    private static func place(of time: Double, in duration: Double, width: CGFloat) -> CGFloat {
        duration > 0 ? CGFloat(min(max(0, time / duration), 1)) * width : 0
    }
}
