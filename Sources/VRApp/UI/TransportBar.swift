import SwiftUI

/// The player's controls under the stage: play or pause, the time, the
/// timeline with the comments' pins, the video's length, and the button
/// that opens the comment box.
struct TransportBar: View {
    let model: ReviewModel

    var body: some View {
        HStack(spacing: Theme.gap) {
            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")

            Text(TimeText.short(model.time))
                .font(Theme.timeFont)
            Timeline(
                time: model.time,
                duration: model.duration,
                markers: Timeline.markers(for: model.comments, selection: model.selection),
                seek: { model.scrub(to: $0) },
                show: { model.showByPerson($0) }
            )
            Text(TimeText.short(model.duration))
                .font(Theme.timeFont)
                .foregroundStyle(.secondary)

            Button {
                model.compose()
            } label: {
                Image(systemName: "plus.bubble")
                    .font(.title3)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(model.composing != nil)
            .help("Comment at this time (C)")
        }
        .padding(.horizontal, Theme.edge)
        .frame(height: Theme.footerHeight)
        .background(.bar)
    }
}
