import SwiftUI

/// The scrubber: a track with the played part filled and a thumb at the
/// player's time. A click or a drag anywhere on it seeks.
struct Timeline: View {
    let time: Double
    let duration: Double
    let seek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let played = width * Self.fraction(of: time, in: duration)
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
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    guard width > 0 else { return }
                    seek(Double(min(max(0, drag.location.x / width), 1)) * duration)
                }
            )
        }
        .frame(height: 20)
    }

    /// How far along `time` is, from 0 to 1; 0 for a video with no length.
    nonisolated static func fraction(of time: Double, in duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(0, time / duration), 1)
    }
}
