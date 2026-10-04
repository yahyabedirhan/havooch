import ReviewWire
import SwiftUI

/// The timeline lane under the stage, always visible: the scrubber with its
/// ruler, the time, and the transport buttons.
struct TimelineLane: View {
    let model: AppModel

    var body: some View {
        let engine = model.engine
        VStack(spacing: 2) {
            Scrubber(time: engine.time, duration: engine.duration) { model.scrub(to: $0) }
            TimeRuler(duration: engine.duration)
            ZStack {
                HStack {
                    timeReadout
                    Spacer()
                    frameSteps
                }
                transport
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, Theme.gutter + 4)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var timeReadout: some View {
        HStack(spacing: 5) {
            Text(Self.clock(model.engine.time))
                .foregroundStyle(.primary)
            Text("/")
                .foregroundStyle(.tertiary)
            Text(Self.clock(model.engine.duration))
                .foregroundStyle(.secondary)
        }
        .font(.callout.monospacedDigit().weight(.medium))
        .accessibilityElement(children: .combine)
    }

    private var transport: some View {
        HStack(spacing: 14) {
            LaneButton("Back 5 seconds", symbol: "gobackward.5") { model.skip(by: -Shortcuts.skip) }
            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .help(model.engine.isPlaying ? "Pause (Space)" : "Play (Space)")
            .accessibilityLabel(model.engine.isPlaying ? "Pause" : "Play")
            LaneButton("Forward 5 seconds", symbol: "goforward.5") { model.skip(by: Shortcuts.skip) }
        }
    }

    private var frameSteps: some View {
        HStack(spacing: 10) {
            LaneButton("Previous frame (Shift+Left)", symbol: "backward.frame") { model.step(frames: -1) }
            LaneButton("Next frame (Shift+Right)", symbol: "forward.frame") { model.step(frames: 1) }
        }
    }

    /// `seconds` as the lane shows it: whole seconds, `m:ss`.
    static func clock(_ seconds: Double) -> String {
        TimeCode.text(seconds.rounded(.down))
    }
}

/// A quiet symbol button of the lane.
private struct LaneButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    init(_ title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// The scrubber: the track, how far the video is, and the playhead. A click
/// or a drag moves the player there.
private struct Scrubber: View {
    let time: Double
    let duration: Double
    let seek: (Double) -> Void

    private static let trackHeight: CGFloat = 6
    private static let knob: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let played = duration > 0 ? width * min(max(time / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: Self.trackHeight)
                Capsule()
                    .fill(.tint)
                    .frame(width: max(played, Self.trackHeight), height: Self.trackHeight)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)
                    .frame(width: Self.knob, height: Self.knob)
                    .offset(x: min(max(played - Self.knob / 2, 0), width - Self.knob))
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        seek(Double(min(max(value.location.x / width, 0), 1)) * duration)
                    }
            )
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue("\(TimelineLane.clock(time)) of \(TimelineLane.clock(duration))")
    }
}

/// The ruler under the track: a tick and a time at even steps.
private struct TimeRuler: View {
    let duration: Double

    /// The steps a ruler may use, in seconds.
    private static let steps: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
    /// The room one label takes.
    private static let labelWidth: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ForEach(Self.marks(duration: duration, width: width), id: \.self) { mark in
                HStack(alignment: .top, spacing: 4) {
                    Rectangle()
                        .fill(.tertiary)
                        .frame(width: 1, height: 5)
                    Text(TimeCode.text(mark))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .offset(x: width * mark / duration)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    /// The times to mark: the smallest step whose labels don't touch, and
    /// no mark so near the end that its label would leave the ruler.
    static func marks(duration: Double, width: CGFloat) -> [Double] {
        guard duration > 0, width > labelWidth else { return [] }
        let room = max(Int(width / (labelWidth * 1.6)), 1)
        let step = steps.first { duration / $0 <= Double(room) } ?? duration
        return stride(from: 0, through: duration, by: step).filter { width * (1 - $0 / duration) >= labelWidth }
    }
}
