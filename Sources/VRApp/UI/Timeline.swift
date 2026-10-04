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
    }

    let time: Double
    let duration: Double
    var markers: [Marker] = []
    let seek: (Double) -> Void
    var show: (String) -> Void = { _ in }

    private static let trackArea: CGFloat = 20
    private static let pinArea: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let played = width * Self.fraction(of: time, in: duration)
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: Theme.trackHeight)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: played, height: Theme.trackHeight)
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                        .frame(width: Theme.thumbSize, height: Theme.thumbSize)
                        .offset(x: min(max(0, played - Theme.thumbSize / 2), max(0, width - Theme.thumbSize)))
                }
                .frame(height: Self.trackArea)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        guard width > 0 else { return }
                        seek(Double(min(max(0, drag.location.x / width), 1)) * duration)
                    }
                )
                .padding(.top, Self.pinArea)

                // Above the track, so a pin never hides the played part.
                ForEach(markers) { marker in
                    pin(marker)
                        .position(x: width * Self.fraction(of: marker.time, in: duration), y: Self.pinArea / 2 + 2)
                }
            }
        }
        .frame(height: Self.pinArea + Self.trackArea)
    }

    private func pin(_ marker: Marker) -> some View {
        let size = marker.isSelected ? Theme.selectedPinSize : Theme.pinSize
        return Circle()
            .fill(Theme.colour(for: marker.state))
            .overlay(Circle().strokeBorder(.white.opacity(marker.isSelected ? 1 : 0.7), lineWidth: marker.isSelected ? 2 : 1))
            .frame(width: size, height: size)
            .frame(width: Self.pinArea + 2, height: Self.pinArea + 2)
            .contentShape(Rectangle())
            .onTapGesture { show(marker.id) }
            .help("\(marker.id) at \(TimeText.short(marker.time)), \(marker.state.rawValue)")
            .accessibilityLabel("Comment \(marker.id) at \(TimeText.short(marker.time))")
    }

    /// How far along `time` is, from 0 to 1; 0 for a video with no length.
    nonisolated static func fraction(of time: Double, in duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(0, time / duration), 1)
    }

    /// The pins for `comments`, with the selected comment's marked.
    nonisolated static func markers(for comments: [Comment], selection: String?) -> [Marker] {
        comments.map { Marker(id: $0.id, time: $0.time, state: $0.state, isSelected: $0.id == selection) }
    }
}
