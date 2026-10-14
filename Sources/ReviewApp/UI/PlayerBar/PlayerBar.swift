import ReviewWire
import SwiftUI

struct PlayerBar: View {
    let model: WindowModel
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
            .pressedByKeys(in: model) { model.togglePlay() }
            .help(engine.isPlaying ? "Pause (Space)" : "Play (Space)")
            .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")

            Text("\(Self.clock(engine.time)) / \(Self.clock(engine.duration))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(palette[.textSecondary])
                .fixedSize()

            Timeline(
                model: model, time: engine.time, duration: engine.duration, threads: model.frameThreads,
                selection: model.selection, scrub: { model.scrub(to: $0) }, select: { model.openThread($0) }
            )
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
            .pressedByKeys(in: model) { model.startDraft() }
            .disabled(model.draft != nil)
            .help("Comment at this frame (C)")
            .accessibilityLabel("Comment")

            SpeakerButton(model: model)

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
        .background(palette[.window])
    }

    static func clock(_ seconds: Double) -> String {
        TimeCode.text(seconds.rounded(.down))
    }

    static func label(_ speed: Double, locale: Locale = .current) -> String {
        speed.formatted(.number.precision(.fractionLength(0...2)).locale(locale)) + "×"
    }
}
