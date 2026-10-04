import SwiftUI

/// The player's controls under the stage: play or pause, the time, the
/// timeline, the video's length.
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
            Timeline(time: model.time, duration: model.duration) { model.scrub(to: $0) }
            Text(TimeText.short(model.duration))
                .font(Theme.timeFont)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.edge)
        .frame(height: Theme.transportHeight)
        .background(.bar)
    }
}
