import AppKit
import SwiftUI

// The sound control, from the Swift Lab session player-bar, component
// player-bar, variant V6 "Panel: thick capsule like Control Center": the
// speaker in the bar opens a thick level capsule over the stage. A click
// on the speaker again, a click outside or Escape closes it. Level 0 is
// muted: a drag to the capsule's bottom mutes, and up from it unmutes.

/// What the sound control says.
enum SoundWords {
    static let checkReason = "Muted for an agent check"
    static let checkDetail = "This run started muted. It plays no sound."
    static let checkHelp = "Muted for an agent check. This run started with HAVOOCH_MUTED=1, so it plays no sound."

    /// `70%`.
    static func percent(_ level: Double) -> String {
        "\(Int((level * 100).rounded()))%"
    }

    /// The speaker's tooltip: the level and the mute key, or why a run
    /// muted for a check plays no sound.
    static func help(level: Double, isMuted: Bool, isMutedForCheck: Bool) -> String {
        if isMutedForCheck { return checkHelp }
        return isMuted ? "Muted (M)" : "Volume \(percent(level)) (M)"
    }

    /// The speaker's value for VoiceOver.
    static func value(level: Double, isMuted: Bool, isMutedForCheck: Bool) -> String {
        if isMutedForCheck { return checkReason }
        return isMuted ? "Muted" : percent(level)
    }
}

/// The speaker at the level: one `speaker.wave.3.fill` whose waves light
/// by band through its variable value, so they fill in and out with the
/// level and nothing is swapped, and a short magic replace to
/// `speaker.slash.fill` and back on mute and unmute. Only a band change or
/// a mute animates, so a drag never makes it flicker.
struct SpeakerSymbol: View {
    let level: Double
    let isMuted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The waves lit: one, two or three, as values inside each wave's
    /// share of the symbol's variable range.
    static func band(_ level: Double) -> Double {
        switch level {
        case ..<0.34: 0.2
        case ..<0.67: 0.5
        default: 1
        }
    }

    static func name(isMuted: Bool) -> String {
        isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill"
    }

    /// How long a band change or a mute takes.
    static let change = Animation.easeOut(duration: 0.18)

    var body: some View {
        let band = Self.band(level)
        Image(systemName: Self.name(isMuted: isMuted), variableValue: isMuted ? nil : band)
            .contentTransition(.symbolEffect(.replace.magic(fallback: .replace.byLayer)))
            .animation(reduceMotion ? nil : Self.change, value: band)
            .animation(reduceMotion ? nil : Self.change, value: isMuted)
    }
}

/// The speaker in the player bar, as big as the play button, held at one
/// width so nothing beside it moves. A click opens the sound panel and a
/// second closes it; a click never mutes. A run muted for an agent's
/// check has a small badge on it.
struct SpeakerButton: View {
    let model: WindowModel
    @Environment(\.palette) private var palette

    var body: some View {
        let sound = model.app.sound
        Button {
            model.soundClicks.inside = true
            model.toggleSoundPanel()
        } label: {
            SpeakerSymbol(level: sound.level, isMuted: sound.isMuted)
                .font(.title3)
                .foregroundStyle(sound.isMutedForCheck ? palette[.textSecondary] : palette[.textPrimary])
                .frame(width: 26, height: 24, alignment: .leading)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if sound.isMutedForCheck { CheckBadge().offset(x: 3, y: -4) }
                }
        }
        .buttonStyle(.plain)
        .pressedByKeys(in: model) { model.toggleSoundPanel() }
        // Where the speaker is, for the panel over the stage to point at it.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(SoundPanel.space)) } action: { model.speakerArea = $0 }
        .help(SoundWords.help(level: sound.level, isMuted: sound.isMuted, isMutedForCheck: sound.isMutedForCheck))
        .accessibilityLabel("Volume")
        .accessibilityValue(SoundWords.value(level: sound.level, isMuted: sound.isMuted, isMutedForCheck: sound.isMutedForCheck))
        .accessibilityIdentifier("player.sound")
        // The video closed: the panel goes with the bar.
        .onDisappear { try? model.setSoundPanel(open: false) }
    }
}

/// A run muted for an agent's check: a pointer, as the agent-control sign
/// has, small, in the agent-control colour.
private struct CheckBadge: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(palette[.textOnAccent])
            .frame(width: 14, height: 14)
            .background(palette[.control], in: Circle())
            .overlay(Circle().strokeBorder(palette[.window], lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

/// The sound panel over the foot of the stage, its arrow over the speaker:
/// the level capsule, or in a run muted for a check, why it plays no
/// sound. It is drawn over the stage and the bar together, in their
/// coordinate space (`space`), so it is inside the views that take its
/// clicks.
struct SoundPanel: View {
    let model: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The coordinate space of the stage and the bar together.
    nonisolated static let space = "player.column"
    /// The arrow of the wider panel, from its trailing edge.
    static let sideArrow: CGFloat = 30
    static let checkWidth: CGFloat = 250
    /// Between the speaker's top and the panel's arrow: the bar's half
    /// height less the speaker's, and a little air over the stage.
    static let gap: CGFloat = (Metrics.barHeight - 24) / 2 + 8

    var body: some View {
        let sound = model.app.sound
        let speaker = model.speakerArea
        // The capsule's panel sits centred over the speaker; the wider
        // panel of a muted run moves left so its arrow still points at it.
        let shift = sound.isMutedForCheck ? -(Self.checkWidth / 2 - Self.sideArrow) : 0
        ZStack {
            if model.isSoundPanelOpen, speaker != .zero {
                content(sound)
                    .fixedSize()
                    // A click anywhere on the panel is inside it.
                    .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in model.soundClicks.inside = true })
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
            }
        }
        .alignmentGuide(HorizontalAlignment.leading) { $0[HorizontalAlignment.center] - (speaker.midX + shift) }
        .alignmentGuide(VerticalAlignment.top) { $0[.bottom] - (speaker.minY - Self.gap) }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: model.isSoundPanelOpen)
        .onChange(of: model.isSoundPanelOpen, initial: true) { _, open in
            if open {
                model.soundClicks.start { [weak model] in try? model?.setSoundPanel(open: false) }
            } else {
                model.soundClicks.stop()
            }
        }
        .onDisappear { model.soundClicks.stop() }
    }

    @ViewBuilder
    private func content(_ sound: Sound) -> some View {
        if sound.isMutedForCheck {
            CheckReason()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(width: Self.checkWidth, alignment: .leading)
                .modifier(PanelSurface(arrowFromTrailing: Self.sideArrow))
        } else {
            LevelCapsule(app: model.app)
                .padding(7)
                .modifier(PanelSurface(arrowFromTrailing: nil))
        }
    }
}

/// While the sound panel is open: a click that lands outside the speaker
/// and the panel closes it, and so does Escape. The click is checked after
/// the views had it, so the speaker and the panel can claim it first
/// (`inside`).
final class SoundPanelClicks {
    var inside = false
    private var monitor: Any?

    func start(close: @escaping @MainActor () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .keyDown]) { [weak self] event in
            let isKey = event.type == .keyDown
            if isKey, event.keyCode != 53 { return event } // Escape
            let swallow = MainActor.assumeIsolated { () -> Bool in
                if isKey {
                    close()
                    self?.stop()
                    return true
                }
                self?.inside = false
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, !self.inside, self.monitor != nil else { return }
                        close()
                        self.stop()
                    }
                }
                return false
            }
            return swallow ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// The level, a thick capsule like Control Center's: filled from the bottom
/// in the accent up to the level, with a speaker inside near the bottom
/// that follows it. A press or a drag anywhere on it sets the level, and
/// at the bottom it mutes; there is no knob. The level shows in a small
/// chip beside it while dragging.
struct LevelCapsule: View {
    let app: AppModel

    @GestureState private var isHeld = false
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 34
    static let height: CGFloat = 120
    /// The speaker's centre, up from the capsule's bottom.
    static let glyphRise: CGFloat = 17
    /// The share of the capsule at its bottom that is level 0, so a drag
    /// to the bottom mutes for sure.
    static let muteZone = 0.02

    /// The level at `y` points down from the top of a capsule `height`
    /// tall: 1 at the top, 0 at the bottom, inside 0 to 1, and 0 in the
    /// bottom `muteZone`.
    nonisolated static func level(at y: Double, height: Double) -> Double {
        guard height > 0 else { return 0 }
        let level = min(max(1 - y / height, 0), 1)
        return level < muteZone ? 0 : level
    }

    var body: some View {
        let sound = app.sound
        let filled = CGFloat(sound.level) * Self.height
        let fill = sound.isMuted ? palette[.textTertiary] : palette[.accent]

        ZStack(alignment: .bottom) {
            Rectangle().fill(palette[.track])
            Rectangle().fill(fill).frame(height: filled)
            glyph(palette[.textSecondary], sound)
            // The same glyph in the on-accent colour, only where the fill
            // covers it, so it reads on both sides of the fill's edge.
            glyph(palette[.textOnAccent], sound)
                .mask(alignment: .bottom) { Rectangle().frame(height: filled) }
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(Capsule())
        .contentShape(Capsule())
        // The level from the capsule's own frame, top 1 and bottom 0.
        .coordinateSpace(.named(Self.space))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                .updating($isHeld) { _, held, _ in held = true }
                .onChanged { app.setVolume(Self.level(at: $0.location.y, height: Self.height), keep: false) }
                .onEnded { app.setVolume(Self.level(at: $0.location.y, height: Self.height)) }
        )
        .overlay(alignment: .bottomLeading) {
            if isHeld {
                LevelChip(level: sound.level)
                    .frame(width: 0, height: 0, alignment: .trailing)
                    .offset(x: -16, y: -min(max(filled, 10), Self.height - 10))
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.15), value: isHeld)
        .help("Volume \(SoundWords.percent(sound.level))")
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue(SoundWords.value(level: sound.level, isMuted: sound.isMuted, isMutedForCheck: false))
        .accessibilityIdentifier("player.volume")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: app.setVolume(sound.level + 0.1)
            case .decrement: app.setVolume(sound.level - 0.1)
            @unknown default: break
            }
        }
    }

    private nonisolated static let space = "player.volume"

    /// The speaker near the capsule's bottom, the full capsule tall.
    private func glyph(_ colour: Color, _ sound: Sound) -> some View {
        SpeakerSymbol(level: sound.level, isMuted: sound.isMuted)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(colour)
            .frame(width: Self.width, height: 20)
            .padding(.bottom, Self.glyphRise - 10)
            .frame(width: Self.width, height: Self.height, alignment: .bottom)
    }
}

/// Why a run muted for an agent's check plays no sound.
private struct CheckReason: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(SoundWords.checkReason)
            } icon: {
                Image(systemName: "cursorarrow.rays").foregroundStyle(palette[.control])
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(palette[.textPrimary])
            Text(SoundWords.checkDetail)
                .font(.caption)
                .foregroundStyle(palette[.textSecondary])
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("player.sound.check")
    }
}

/// The level, small, in a chip on the popover surface, while dragging.
private struct LevelChip: View {
    let level: Double
    @Environment(\.palette) private var palette

    var body: some View {
        Text(SoundWords.percent(level))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(palette[.textSecondary])
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(palette[.popover], in: Capsule())
            .overlay(Capsule().strokeBorder(palette[.popoverBorder]))
            .fixedSize()
            .allowsHitTesting(false)
    }
}

/// The popover surface the panel sits on: the theme's popover fill and
/// border, a soft shadow and the arrow down to the speaker.
private struct PanelSurface: ViewModifier {
    let arrowFromTrailing: CGFloat?
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        let shape = CalloutShape(arrowFromTrailing: arrowFromTrailing)
        content
            .padding(.bottom, CalloutShape.arrow)
            .background(shape.fill(palette[.popover]).shadow(color: palette[.shadow], radius: 8, y: 3))
            .overlay(shape.stroke(palette[.popoverBorder], lineWidth: 1))
    }
}

/// A rounded panel with a small arrow down to its button, centred or a
/// set distance from the trailing edge.
private struct CalloutShape: Shape {
    static let arrow: CGFloat = 7
    let arrowFromTrailing: CGFloat?
    let radius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let arrow = Self.arrow
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - arrow)
        let tip = arrowFromTrailing.map { body.maxX - $0 } ?? body.midX
        var path = Path()
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY), radius: radius)
        path.addLine(to: CGPoint(x: tip + arrow, y: body.maxY))
        path.addLine(to: CGPoint(x: tip, y: rect.maxY))
        path.addLine(to: CGPoint(x: tip - arrow, y: body.maxY))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.minY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY), radius: radius)
        path.closeSubpath()
        return path
    }
}
