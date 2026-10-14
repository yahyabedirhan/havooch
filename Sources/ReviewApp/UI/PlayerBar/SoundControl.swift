import AppKit
import SwiftUI

enum SoundWords {
    static let checkReason = "Muted for an agent check"
    static let checkDetail = "This run started muted. It plays no sound."
    static let checkHelp = "Muted for an agent check. This run started with HAVOOCH_MUTED=1, so it plays no sound."

    static func percent(_ level: Double) -> String {
        "\(Int((level * 100).rounded()))%"
    }

    static func help(level: Double, isMuted: Bool, isMutedForCheck: Bool) -> String {
        if isMutedForCheck { return checkHelp }
        return isMuted ? "Muted (M)" : "Volume \(percent(level)) (M)"
    }

    static func value(level: Double, isMuted: Bool, isMutedForCheck: Bool) -> String {
        if isMutedForCheck { return checkReason }
        return isMuted ? "Muted" : percent(level)
    }
}

struct SpeakerSymbol: View {
    let level: Double
    let isMuted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    static let change = Animation.easeOut(duration: 0.18)

    var body: some View {
        let band = Self.band(level)
        Image(systemName: Self.name(isMuted: isMuted), variableValue: isMuted ? nil : band)
            .contentTransition(.symbolEffect(.replace.magic(fallback: .replace.byLayer)))
            .animation(reduceMotion ? nil : Self.change, value: band)
            .animation(reduceMotion ? nil : Self.change, value: isMuted)
    }
}

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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(SoundPanel.space)) } action: { model.speakerArea = $0 }
        .help(SoundWords.help(level: sound.level, isMuted: sound.isMuted, isMutedForCheck: sound.isMutedForCheck))
        .accessibilityLabel("Volume")
        .accessibilityValue(SoundWords.value(level: sound.level, isMuted: sound.isMuted, isMutedForCheck: sound.isMutedForCheck))
        .accessibilityIdentifier("player.sound")
        .onDisappear { try? model.setSoundPanel(open: false) }
    }
}

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

struct SoundPanel: View {
    let model: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static let space = "player.column"
    static let sideArrow: CGFloat = 30
    static let checkWidth: CGFloat = 250
    static let gap: CGFloat = (Metrics.barHeight - 24) / 2 + 8

    var body: some View {
        let sound = model.app.sound
        let speaker = model.speakerArea
        let shift = sound.isMutedForCheck ? -(Self.checkWidth / 2 - Self.sideArrow) : 0
        ZStack {
            if model.isSoundPanelOpen, speaker != .zero {
                content(sound)
                    .fixedSize()
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

final class SoundPanelClicks {
    var inside = false
    private var monitor: Any?

    func start(close: @escaping @MainActor () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .keyDown]) { [weak self] event in
            let isKey = event.type == .keyDown
            if isKey, event.keyCode != KeyCode.escape { return event }
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

struct LevelCapsule: View {
    let app: AppModel

    @GestureState private var isHeld = false
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 34
    static let height: CGFloat = 120
    static let glyphRise: CGFloat = 17
    static let muteZone = 0.02

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
            glyph(palette[.textOnAccent], sound)
                .mask(alignment: .bottom) { Rectangle().frame(height: filled) }
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(Capsule())
        .contentShape(Capsule())
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

    private func glyph(_ colour: Color, _ sound: Sound) -> some View {
        SpeakerSymbol(level: sound.level, isMuted: sound.isMuted)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(colour)
            .frame(width: Self.width, height: 20)
            .padding(.bottom, Self.glyphRise - 10)
            .frame(width: Self.width, height: Self.height, alignment: .bottom)
    }
}

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
