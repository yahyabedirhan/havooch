import SwiftUI

/// The fixed bar under the frame: play or pause, the time, the timeline
/// and the speed. It never floats over the video.
struct TransportBar: View {
    let model: AppModel

    var body: some View {
        let player = model.player
        HStack(spacing: 12) {
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(player.playing ? "Pause" : "Play")
            .accessibilityLabel(player.playing ? "Pause" : "Play")

            Text("\(TimeText.short(player.time)) / \(TimeText.short(player.video?.duration ?? 0))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Timeline(time: player.time, duration: player.video?.duration ?? 0) { model.scrub(to: $0) }

            Menu {
                ForEach(PlayerEngine.speeds, id: \.self) { speed in
                    Toggle(Self.label(speed), isOn: Binding(get: { player.speed == speed }, set: { _ in model.setSpeed(speed) }))
                }
            } label: {
                Text(Self.label(player.speed)).font(.callout.monospacedDigit())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Playback speed")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .disabled(player.video == nil)
        .background(.bar)
    }

    /// `1×`, `1.25×`.
    private static func label(_ speed: Double) -> String {
        speed.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }
}
