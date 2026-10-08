import AppKit
import SwiftUI

// Shared pieces of Havooch's window (from version-switcher V1's Kit), trimmed from context/ (Palette, the
// Default Light and Default Dark themes, TitleView, FloatingControls,
// PlayerBar, Timeline, ThreadPin). Copied into each variant folder.

/// Havooch's Default Light / Default Dark tokens, picked by the colour scheme.
struct Pal {
    let dark: Bool

    private func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((value >> 16) & 0xff) / 255,
              green: Double((value >> 8) & 0xff) / 255,
              blue: Double(value & 0xff) / 255,
              opacity: alpha)
    }

    var window: Color { Color(nsColor: .windowBackgroundColor) }
    var separator: Color { Color(nsColor: .separatorColor) }
    var letterbox: Color { dark ? hex(0x000000) : hex(0x151412) }
    var popover: Color { Color(nsColor: .windowBackgroundColor) }
    var popoverBorder: Color { dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08) }
    var well: Color { dark ? Color.white.opacity(0.04) : Color.black.opacity(0.04) }
    var track: Color { dark ? hex(0x45423d) : hex(0xd8d2c6) }
    var knob: Color { dark ? hex(0xf2f0eb) : hex(0xffffff) }
    var shadow: Color { dark ? Color.black.opacity(0.45) : Color.black.opacity(0.25) }
    var controlHover: Color { dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
    var textPrimary: Color { dark ? hex(0xece9e3) : hex(0x2b2925) }
    var textSecondary: Color { dark ? hex(0xada79d) : hex(0x6b665d) }
    var textTertiary: Color { dark ? hex(0x7d776e) : hex(0x9a948a) }
    var textOnAccent: Color { dark ? hex(0x1a1918) : hex(0xffffff) }
    var accent: Color { dark ? hex(0x9db6dd) : hex(0x5b7db1) }
    var control: Color { dark ? hex(0xe3bf84) : hex(0xb98a45) }
    var agent: Color { dark ? hex(0x9db6dd) : hex(0x5b7db1) }
    var question: Color { dark ? hex(0x8fc7c3) : hex(0x4a8a88) }
    var stateQueued: Color { dark ? hex(0x958f85) : hex(0x8e897f) }
    var stateWorking: Color { dark ? hex(0xe3bf84) : hex(0xb98a45) }
    var stateDone: Color { dark ? hex(0x9ccba8) : hex(0x5e9771) }
    var stateAcknowledged: Color { dark ? hex(0x9db6dd) : hex(0x5b7db1) }
}

private struct PalKey: EnvironmentKey { static let defaultValue = Pal(dark: false) }
extension EnvironmentValues {
    var pal: Pal {
        get { self[PalKey.self] }
        set { self[PalKey.self] = newValue }
    }
}

/// Fills `\.pal` from the colour scheme.
struct Themed<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        content
            .environment(\.pal, Pal(dark: scheme == .dark))
            .environment(\.locale, Locale(identifier: "en_US"))
    }
}

// MARK: - Fixture

struct Version: Identifiable, Equatable {
    let number: Int
    let label: String?
    let threads: Int
    let made: String
    var id: Int { number }
    var name: String { "v\(number)" }
}

enum Fixture {
    static let project = "Havooch launch video"
    /// The live project: 50 renders, newest last. Recent ones are labelled,
    /// a few old ones too, most old ones not.
    static let many: [Version] = (1...50).map { n in
        let labels = [
            1: "first cut", 3: "new voice", 7: "tighter intro", 12: "voice retake",
            19: "warmer music", 27: "voice pass 2", 33: "shorter end card", 41: "voice + music",
            44: "new logo sting", 45: "warmer grade", 46: "music swap", 47: "captions on",
            48: "shorter intro", 49: "end card fix", 50: "brighter grade",
        ]
        let days = [50: "today", 49: "today", 48: "yesterday", 47: "yesterday", 46: "Mon", 45: "Mon", 44: "Sun"]
        return Version(number: n, label: labels[n], threads: n % 4, made: days[n] ?? "Sep \(max(1, n / 2))")
    }
    static let versions: [Version] = many
    static let current = 50
    static let time: Double = 14
    static let duration: Double = 24
    static let folder = "~/Movies/Launch/renders"
    static let loneFile = "screen-recording-0412.mov"
    static let loneFolder = "~/Desktop"
    /// Pins on v3's timeline: time and colour role.
    static let pins: [(time: Double, kind: Int)] = [(4, 0), (9.5, 1), (19, 2)]

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}

// MARK: - Window chrome

/// The traffic lights, drawn, since a tile is not a real window.
struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
            Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
            Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
        }
        .frame(width: 52, height: 12)
    }
}

/// Stand-in for the cat mark (the real one is a PDF in the app bundle).
struct CatMark: View {
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            Path { p in
                let s = size
                p.move(to: CGPoint(x: s * 0.14, y: s * 0.42))
                p.addLine(to: CGPoint(x: s * 0.2, y: s * 0.06))
                p.addLine(to: CGPoint(x: s * 0.44, y: s * 0.26))
                p.move(to: CGPoint(x: s * 0.86, y: s * 0.42))
                p.addLine(to: CGPoint(x: s * 0.8, y: s * 0.06))
                p.addLine(to: CGPoint(x: s * 0.56, y: s * 0.26))
            }
            .fill(Color(red: 0.93, green: 0.55, blue: 0.24))
            Ellipse()
                .fill(Color(red: 0.93, green: 0.55, blue: 0.24))
                .frame(width: size * 0.78, height: size * 0.66)
                .offset(y: size * 0.12)
            HStack(spacing: size * 0.18) {
                Capsule().frame(width: size * 0.08, height: size * 0.14)
                Capsule().frame(width: size * 0.08, height: size * 0.14)
            }
            .foregroundStyle(Color(red: 0.2, green: 0.14, blue: 0.1))
            .offset(y: size * 0.1)
        }
        .frame(width: size, height: size)
    }
}

/// An icon and its words on one line, as the header's `HeaderLabelStyle`.
struct HeaderLine<Words: View>: View {
    let symbol: String
    let iconColor: Color
    @ViewBuilder var words: Words
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(iconColor)
                .frame(width: 14)
            words
        }
    }
}

/// The floating group at the top right: Open a Video…, Context, Sidebar.
struct FloatingGroup: View {
    @Environment(\.pal) private var pal
    var body: some View {
        HStack(spacing: 2) {
            ForEach(["folder", "doc.text", "sidebar.trailing"], id: \.self) { name in
                Image(systemName: name)
                    .font(.system(size: 14))
                    .foregroundStyle(pal.textPrimary)
                    .frame(width: 34, height: 30)
            }
        }
        .padding(.horizontal, 4)
        .background(Capsule().fill(pal.dark ? Color.white.opacity(0.07) : Color.white.opacity(0.85)))
        .overlay(Capsule().strokeBorder(pal.popoverBorder))
        .shadow(color: .black.opacity(pal.dark ? 0.3 : 0.08), radius: 3, y: 1)
    }
}

/// The header row, 52 pt tall: lights, the leading content, and the group.
struct HeaderBar<Leading: View, Middle: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var middle: Middle
    var body: some View {
        HStack(spacing: 14) {
            TrafficLights()
            leading
            Spacer(minLength: 12)
            middle
            FloatingGroup()
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(height: 52)
    }
}

extension HeaderBar where Middle == EmptyView {
    init(@ViewBuilder leading: () -> Leading) {
        self.leading = leading()
        self.middle = EmptyView()
    }
}

/// The stage, cut short: the letterbox with a frame of the video.
struct StageStrip: View {
    var height: CGFloat = 110
    var tint: Double = 0
    var caption: String? = nil
    @Environment(\.pal) private var pal
    var body: some View {
        ZStack {
            pal.letterbox
            LinearGradient(
                colors: [Color(hue: 0.6 + tint, saturation: 0.45, brightness: 0.35),
                         Color(hue: 0.08 + tint, saturation: 0.55, brightness: 0.6)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: height * 16 / 9 * 1.2)
                .overlay(alignment: .bottomLeading) {
                    if let caption {
                        Text(caption)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(8)
                    }
                }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
    }
}

/// The player bar's timeline: track, played part, knob and a few pins.
struct TimelineTrack: View {
    var time: Double = Fixture.time
    var duration: Double = Fixture.duration
    var pins: [(time: Double, kind: Int)] = Fixture.pins
    @Environment(\.pal) private var pal

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let played = CGFloat(time / duration) * w
            ZStack(alignment: .topLeading) {
                ForEach(Array(pins.enumerated()), id: \.offset) { _, pin in
                    let x = CGFloat(pin.time / duration) * w
                    let color = pinColor(pin.kind)
                    Rectangle().fill(color.opacity(0.45))
                        .frame(width: 1, height: 16)
                        .position(x: x, y: 16)
                    Group {
                        if pin.kind == 0 {
                            Circle().fill(pal.window).overlay(Circle().strokeBorder(color, lineWidth: 2))
                        } else {
                            RoundedRectangle(cornerRadius: 2.8).fill(color)
                                .overlay(Image(systemName: "checkmark").font(.system(size: 5.5, weight: .heavy)).foregroundStyle(pal.textOnAccent))
                        }
                    }
                    .frame(width: 10, height: 10)
                    .position(x: x, y: 8)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(pal.track).frame(width: w, height: 4)
                    Capsule().fill(pal.accent).frame(width: played, height: 4)
                    Circle().fill(pal.knob)
                        .shadow(color: pal.shadow, radius: 1, y: 0.5)
                        .frame(width: 12, height: 12)
                        .offset(x: played - 6)
                }
                .frame(width: w, height: 12)
                .offset(y: 18)
                ForEach(Array(stride(from: 0.0, through: duration - 3, by: duration > 30 ? 10 : 5)), id: \.self) { tick in
                    HStack(alignment: .top, spacing: 2) {
                        Rectangle().fill(pal.track).frame(width: 1, height: 4)
                        Text(Fixture.clock(tick))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(pal.textTertiary)
                    }
                    .fixedSize()
                    .offset(x: CGFloat(tick / duration) * w, y: 30)
                }
            }
        }
        .frame(height: 41)
        .offset(y: 41 / 2 - 24)
    }

    private func pinColor(_ kind: Int) -> Color {
        switch kind {
        case 0: pal.stateQueued
        case 1: pal.stateDone
        default: pal.stateAcknowledged
        }
    }
}

/// The player bar: play, the clock, the timeline, Comment and speed.
struct PlayerBarStrip<Leading: View>: View {
    var time: Double = Fixture.time
    var duration: Double = Fixture.duration
    @ViewBuilder var leading: Leading
    @Environment(\.pal) private var pal
    var body: some View {
        HStack(spacing: 12) {
            leading
            Image(systemName: "play.fill").font(.title3).frame(width: 24, height: 24)
            Text("\(Fixture.clock(time)) / \(Fixture.clock(duration))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(pal.textSecondary)
                .fixedSize()
            TimelineTrack(time: time, duration: duration)
            Image(systemName: "plus.bubble").font(.title3).frame(width: 24, height: 24)
            Text("1×").font(.callout.monospacedDigit())
        }
        .foregroundStyle(pal.textPrimary)
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

extension PlayerBarStrip where Leading == EmptyView {
    init(time: Double = Fixture.time, duration: Double = Fixture.duration) {
        self.time = time
        self.duration = duration
        self.leading = EmptyView()
    }
}

/// A window-shaped frame around a piece of the window.
struct WindowCard<Content: View>: View {
    var width: CGFloat = 900
    @ViewBuilder var content: Content
    @Environment(\.pal) private var pal
    var body: some View {
        content
            .frame(width: width)
            .background(pal.window)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(pal.separator))
            .shadow(color: .black.opacity(pal.dark ? 0.4 : 0.12), radius: 10, y: 4)
    }
}

/// A small caption above a state.
struct StateCaption: View {
    let text: String
    @Environment(\.pal) private var pal
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(pal.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A keyboard key, for shortcut hints.
struct KeyCap: View {
    let text: String
    var onAccent = false
    @Environment(\.pal) private var pal
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium).monospaced())
            .foregroundStyle(onAccent ? pal.textOnAccent : pal.textSecondary)
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(RoundedRectangle(cornerRadius: 4).fill(onAccent ? pal.textOnAccent.opacity(0.18) : pal.well))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(onAccent ? pal.textOnAccent.opacity(0.3) : pal.popoverBorder))
    }
}

