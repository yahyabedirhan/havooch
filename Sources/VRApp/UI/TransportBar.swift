import SwiftUI

/// The player's controls under the stage: back 5 s, play or pause, forward
/// 5 s, the time, the timeline with the comments' pins, the video's length,
/// and the button that opens the comment box.
struct TransportBar: View {
    let model: ReviewModel

    /// The side of an icon button's square, which is also where it takes
    /// clicks.
    private static let iconSide: CGFloat = 28

    var body: some View {
        HStack(spacing: Theme.gap) {
            HStack(spacing: 2) {
                iconButton("Back 5 seconds", systemImage: "gobackward.5") {
                    model.skip(by: -PlayerKey.skip)
                }
                .foregroundStyle(.secondary)
                .help("Back 5 seconds (←)")

                iconButton(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                    model.togglePlay()
                }
                .font(.title3)
                .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")

                iconButton("Forward 5 seconds", systemImage: "goforward.5") {
                    model.skip(by: PlayerKey.skip)
                }
                .foregroundStyle(.secondary)
                .help("Forward 5 seconds (→)")
            }

            Text(TimeText.short(model.shownTime))
                .font(Theme.timeFont)
            Timeline(
                time: model.shownTime,
                duration: model.duration,
                markers: Timeline.markers(for: model.comments, selection: model.selection),
                scrubStarted: { model.beginScrub() },
                seek: { model.scrub(to: $0) },
                scrubEnded: { model.endScrub() },
                show: { model.showByPerson($0) }
            )
            Text(TimeText.short(model.duration))
                .font(Theme.timeFont)
                .foregroundStyle(.secondary)

            Button("Comment", systemImage: "plus.bubble") {
                model.compose()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.composing != nil)
            .help("Comment at this time (C)")
        }
        .padding(.horizontal, Theme.edge)
        .frame(height: Theme.footerHeight)
        .background(.bar)
    }

    /// A borderless button that shows only its symbol, with `title` as its
    /// accessibility label, and the whole square taking clicks.
    private func iconButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: Self.iconSide, height: Self.iconSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}
