import SwiftUI

/// The fixed bar under the frame: play or pause, the time, the timeline
/// and the speed. It never floats over the video, and it sits on the
/// window's background like the sidebar's send bar beside it.
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

            Timeline(
                time: player.time, duration: player.video?.duration ?? 0,
                comments: model.desk.open?.comments ?? [], selection: model.selection,
                scrub: { model.scrub(to: $0) }, select: { model.select($0) }
            )

            Button {
                model.attempt { () throws(ActionError) in try model.startDraft() }
            } label: {
                Image(systemName: "plus.bubble")
                    .font(.title3)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Comment at this moment (Return)")
            .accessibilityLabel("Comment at this moment")

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
        .padding(.horizontal, Theme.edge)
        // As tall as the sidebar's send bar, on the same window background,
        // so the two bars line up across the window.
        .frame(height: Theme.footerHeight)
        .disabled(player.video == nil)
    }

    /// `1×`, `1.25×`.
    private static func label(_ speed: Double) -> String {
        speed.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }
}
