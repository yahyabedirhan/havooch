import SwiftUI

/// The scrubber: the played part of the video and the playhead, which a
/// click or a drag moves. The app's own, since it is where the comment
/// markers go.
struct Timeline: View {
    let time: Double
    let duration: Double
    let scrub: (Double) -> Void

    private static let trackHeight: CGFloat = 4
    private static let knob: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let played = duration > 0 ? CGFloat(min(max(0, time / duration), 1)) * width : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: Self.trackHeight)
                Capsule().fill(Color.accentColor).frame(width: played, height: Self.trackHeight)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                    .frame(width: Self.knob, height: Self.knob)
                    .offset(x: min(max(0, played - Self.knob / 2), width - Self.knob))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    guard width > 0, duration > 0 else { return }
                    scrub(Double(min(max(0, drag.location.x / width), 1)) * duration)
                }
            )
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue("\(TimeText.short(time)) of \(TimeText.short(duration))")
    }
}
