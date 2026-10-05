import ReviewWire
import SwiftUI

/// The timeline lane under the stage, always visible: the markers, the
/// scrubber with its ruler, the time, and the transport buttons.
struct TimelineLane: View {
    let model: AppModel
    @Environment(\.palette) private var palette

    /// The room above the track that the markers' pins stand in. It's
    /// there with no marker too, so the first comment doesn't move the lane.
    private static let markerBand: CGFloat = MarkerPin.size + 4

    var body: some View {
        let engine = model.engine
        VStack(spacing: 2) {
            ZStack(alignment: .top) {
                Scrubber(time: engine.time, duration: engine.duration) { model.scrub(to: $0) }
                    .padding(.top, Self.markerBand)
                MarkerLayer(
                    comments: model.comments, duration: engine.duration, selection: model.selection, unread: model.unread,
                    select: { model.select($0) },
                    stem: Self.markerBand - MarkerPin.size + Scrubber.trackTop
                )
            }
            TimeRuler(duration: engine.duration)
            ZStack {
                HStack(spacing: 14) {
                    timeReadout
                    Spacer()
                    frameSteps
                    commentButton
                }
                transport
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, Metrics.gutter + Metrics.laneInset)
        // The rail's foot has this height too, so the stage's lower edge
        // and the line over the rail's foot are one line.
        .frame(height: Metrics.footerHeight)
        .foregroundStyle(palette[.textPrimary])
        .background(palette[.bar])
    }

    private var commentButton: some View {
        Button {
            model.startDraft()
        } label: {
            Label("Comment", systemImage: "plus.bubble")
        }
        .disabled(model.draft != nil)
        .help("Comment at this time (C)")
    }

    private var timeReadout: some View {
        HStack(spacing: 5) {
            Text(Self.clock(model.engine.time))
                .foregroundStyle(palette[.textPrimary])
            Text("/")
                .foregroundStyle(palette[.textTertiary])
            Text(Self.clock(model.engine.duration))
                .foregroundStyle(palette[.textSecondary])
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
        .buttonStyle(QuietButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}

/// The scrubber: the track, how far the video is, and the playhead. A click
/// or a drag moves the player there. It answers on the press: the knob grows
/// and the track thickens while it's held, and it follows the pointer 1:1.
private struct Scrubber: View {
    let time: Double
    let duration: Double
    let seek: (Double) -> Void

    /// Whether the pointer holds the scrubber.
    @GestureState private var isHeld = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    private static let trackHeight: CGFloat = 6
    private static let heldTrackHeight: CGFloat = 8
    private static let knob: CGFloat = 14
    private static let heldKnob: CGFloat = 18
    private static let height: CGFloat = 20
    /// How far below the scrubber's top its track starts.
    static let trackTop = (height - trackHeight) / 2

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let played = duration > 0 ? width * min(max(time / duration, 0), 1) : 0
            let track = isHeld ? Self.heldTrackHeight : Self.trackHeight
            let knob = isHeld ? Self.heldKnob : Self.knob
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette[.track])
                    .frame(height: track)
                Capsule()
                    .fill(palette[.accent])
                    .frame(width: max(played, track), height: track)
                Circle()
                    .fill(palette[.knob])
                    .shadow(color: palette[.shadow], radius: isHeld ? 3 : 1.5, y: isHeld ? 1 : 0.5)
                    .frame(width: knob, height: knob)
                    .offset(x: min(max(played - knob / 2, 0), width - knob))
            }
            .frame(height: proxy.size.height)
            // Only the press and the release animate; the playhead itself
            // follows the pointer and the video with no lag.
            .animation(reduceMotion ? nil : .smooth(duration: 0.15), value: isHeld)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isHeld) { _, held, _ in held = true }
                    .onChanged { value in
                        guard width > 0 else { return }
                        seek(Double(min(max(value.location.x / width, 0), 1)) * duration)
                    }
            )
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue("\(TimelineLane.clock(time)) of \(TimelineLane.clock(duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: seek(min(time + Shortcuts.skip, duration))
            case .decrement: seek(max(time - Shortcuts.skip, 0))
            @unknown default: break
            }
        }
    }
}

/// The ruler under the track: a tick and a time at even steps.
private struct TimeRuler: View {
    let duration: Double
    @Environment(\.palette) private var palette

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
                        .fill(palette[.textTertiary])
                        .frame(width: 1, height: 5)
                    Text(TimeCode.text(mark))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(palette[.textTertiary])
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
