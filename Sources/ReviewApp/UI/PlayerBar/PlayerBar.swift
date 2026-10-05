import ReviewWire
import SwiftUI

/// The fixed bar under the stage, as in proto-1: play or pause, the time
/// and the duration, the timeline with a pin per thread, the Comment button
/// and the speed. It never floats over the video, and it is as tall as the
/// sidebar's footer beside it, so the two meet on one line.
struct PlayerBar: View {
    let model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        let engine = model.engine
        HStack(spacing: 12) {
            Button {
                model.togglePlay()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(engine.isPlaying ? "Pause (Space)" : "Play (Space)")
            .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")

            Text("\(Self.clock(engine.time)) / \(Self.clock(engine.duration))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(palette[.textSecondary])
                .fixedSize()

            Timeline(
                time: engine.time, duration: engine.duration, threads: model.frameThreads, selection: model.selection,
                scrub: { model.scrub(to: $0) }, select: { model.openThread($0) }
            )
            // Where the track is, for the comment popover's notch to point
            // at the playhead from the stage above.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.trackArea = $0 }

            Button {
                model.startDraft()
            } label: {
                Image(systemName: "plus.bubble")
                    .font(.title3)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.draft != nil)
            .help("Comment at this frame (C)")
            .accessibilityLabel("Comment")

            Menu {
                ForEach(PlayerEngine.speeds, id: \.self) { speed in
                    Toggle(
                        Self.label(speed),
                        isOn: Binding(get: { engine.speed == speed }, set: { _ in model.setSpeed(speed) })
                    )
                }
            } label: {
                Text(Self.label(engine.speed)).font(.callout.monospacedDigit())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Playback speed")
        }
        .foregroundStyle(palette[.textPrimary])
        .padding(.horizontal, Metrics.barPadding)
        .frame(height: Metrics.barHeight)
        .background(palette[.bar])
    }

    /// `seconds` as the bar shows it: whole seconds, `m:ss`.
    static func clock(_ seconds: Double) -> String {
        TimeCode.text(seconds.rounded(.down))
    }

    /// `1×`, `1.25×`, with the decimal mark of `locale`.
    static func label(_ speed: Double, locale: Locale = .current) -> String {
        speed.formatted(.number.precision(.fractionLength(0...2)).locale(locale)) + "×"
    }
}
