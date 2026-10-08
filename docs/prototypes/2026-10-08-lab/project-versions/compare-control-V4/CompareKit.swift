import AppKit
import SwiftUI

// The compare control's shared pieces: the drawn frame of a version, the
// header with its Compare button, the popover shell anchored under the
// button, the version menu, the mini window and the comparison window.
// Copied into each compare-control variant folder.

enum Side: String { case left = "Left", right = "Right" }

enum CompareLayout: String, CaseIterable, Identifiable {
    case sideBySide = "Side by side"
    case flip = "Flip"
    case slider = "Slider"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .sideBySide: "rectangle.split.2x1"
        case .flip: "rectangle.on.rectangle"
        case .slider: "slider.horizontal.below.rectangle"
        }
    }
}

func version(_ n: Int) -> Version {
    Fixture.versions.first { $0.number == n } ?? Fixture.many[n - 1]
}

// MARK: - A frame of the video

/// A drawn frame of one version: sky, sun and ground, coloured per version,
/// so two versions look different at a glance.
struct VideoFrame: View {
    let number: Int
    var corner: CGFloat = 4
    var body: some View {
        let hue = (0.58 + Double(number) * 0.09).truncatingRemainder(dividingBy: 1)
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color(hue: hue, saturation: 0.45, brightness: 0.32),
                             Color(hue: (hue + 0.45).truncatingRemainder(dividingBy: 1), saturation: 0.5, brightness: 0.62)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color(hue: 0.11, saturation: 0.55, brightness: 0.98).opacity(0.85))
                    .frame(width: h * 0.26, height: h * 0.26)
                    .offset(x: w * (0.18 + Double(number % 5) * 0.14), y: h * 0.2)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.72))
                    p.addQuadCurve(to: CGPoint(x: w, y: h * 0.66),
                                   control: CGPoint(x: w * 0.5, y: h * (0.5 + Double(number % 3) * 0.06)))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(Color.black.opacity(0.32))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: - Header

/// The project title: cat, project name, and the version on screen.
struct ProjectTitle: View {
    var subtitle: String = "v\(Fixture.current) · current"
    @Environment(\.pal) private var pal
    var body: some View {
        HStack(spacing: 8) {
            CatMark(size: 22)
            VStack(alignment: .leading, spacing: 1) {
                HeaderLine(symbol: "film.stack", iconColor: pal.textSecondary) {
                    Text(Fixture.project).font(.headline).foregroundStyle(pal.textPrimary)
                }
                HeaderLine(symbol: "film", iconColor: pal.textTertiary) {
                    Text(subtitle).font(.subheadline).foregroundStyle(pal.textSecondary)
                }
            }
            .lineLimit(1)
        }
        .padding(.leading, 4)
    }
}

struct CompareAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// The header's Compare button. Pressed while its popover is open.
struct CompareButton: View {
    var pressed: Bool
    var action: () -> Void = {}
    @Environment(\.pal) private var pal
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 12, weight: .medium))
                Text("Compare").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(pressed ? pal.accent : pal.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(pressed ? pal.accent.opacity(0.14) : (pal.dark ? Color.white.opacity(0.07) : Color.white.opacity(0.85))))
            .overlay(Capsule().strokeBorder(pressed ? pal.accent.opacity(0.5) : pal.popoverBorder))
        }
        .buttonStyle(.plain)
        .anchorPreference(key: CompareAnchorKey.self, value: .bounds) { $0 }
        .labID("compare-button")
    }
}

/// A window whose header holds the Compare button, with `popover` drawn
/// anchored under the button.
struct PlayerWithPopover<Pop: View>: View {
    var popoverWidth: CGFloat
    var stageHeight: CGFloat = 330
    var popoverOpen: Bool = true
    @ViewBuilder var popover: Pop
    @Environment(\.pal) private var pal

    var body: some View {
        WindowCard {
            VStack(spacing: 0) {
                HeaderBar {
                    ProjectTitle()
                } middle: {
                    CompareButton(pressed: popoverOpen)
                }
                ZStack {
                    pal.letterbox
                    VideoFrame(number: Fixture.current, corner: 0)
                        .frame(width: stageHeight * 16 / 9)
                }
                .frame(height: stageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
                PlayerBarStrip()
            }
            .overlayPreferenceValue(CompareAnchorKey.self) { anchor in
                GeometryReader { geo in
                    if popoverOpen, let anchor {
                        let r = geo[anchor]
                        let left = min(max(12, r.midX - popoverWidth / 2), geo.size.width - 12 - popoverWidth)
                        PopoverShell(width: popoverWidth, arrowX: r.midX - left) { popover }
                            .offset(x: left, y: r.maxY + 2)
                    }
                }
            }
        }
    }
}

/// The popover's body: material card with an arrow at `arrowX`.
struct PopoverShell<Content: View>: View {
    let width: CGFloat
    let arrowX: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.pal) private var pal
    var body: some View {
        VStack(spacing: 0) {
            Arrow()
                .fill(pal.popover)
                .overlay(Arrow(open: true).stroke(pal.popoverBorder, lineWidth: 1))
                .frame(width: 18, height: 8)
                .offset(x: arrowX - width / 2)
                .zIndex(1)
                .offset(y: 1)
            content
                .frame(width: width)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(pal.popover))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(pal.popoverBorder))
        }
        .compositingGroup()
        .shadow(color: .black.opacity(pal.dark ? 0.5 : 0.2), radius: 14, y: 6)
    }

    struct Arrow: Shape {
        var open = false
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            if !open { p.closeSubpath() }
            return p
        }
    }
}

/// The popover's title row.
struct PopoverTitle: View {
    var title = "Compare two versions"
    var hint: String
    @Environment(\.pal) private var pal
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(pal.textPrimary)
            Text(hint).font(.system(size: 11)).foregroundStyle(pal.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The popover's bottom row: the note on defaults, Cancel and the action.
struct PopoverFooter: View {
    var action = "Show side by side"
    var onAction: () -> Void = {}
    @Environment(\.pal) private var pal
    var body: some View {
        HStack(spacing: 8) {
            Text("Opens on v\(Fixture.current - 1) and v\(Fixture.current)")
                .font(.system(size: 10.5))
                .foregroundStyle(pal.textTertiary)
            Spacer()
            Text("Cancel")
                .font(.system(size: 12))
                .foregroundStyle(pal.textPrimary)
                .padding(.horizontal, 10).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(pal.well))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(pal.popoverBorder))
            Button(action: onAction) {
                HStack(spacing: 6) {
                    Text(action).font(.system(size: 12, weight: .semibold))
                    Text("↩").font(.system(size: 11, weight: .semibold)).opacity(0.7)
                }
                .foregroundStyle(pal.textOnAccent)
                .padding(.horizontal, 10).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(pal.accent))
            }
            .buttonStyle(.plain)
            .labID("compare-go")
        }
    }
}

// MARK: - Mini window

/// The comparison window in miniature: a title strip, `content` and a
/// shared playhead under it.
struct MiniWindow<Content: View>: View {
    var playhead: Double = Fixture.time / Fixture.duration
    @ViewBuilder var content: Content
    @Environment(\.pal) private var pal
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(pal.textTertiary.opacity(0.5)).frame(width: 5, height: 5) }
                Spacer()
            }
            content
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(pal.track).frame(height: 3)
                    Capsule().fill(pal.accent).frame(width: geo.size.width * playhead, height: 3)
                    Circle().fill(pal.knob).shadow(color: pal.shadow, radius: 0.5).frame(width: 8, height: 8)
                        .offset(x: geo.size.width * playhead - 4)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 8)
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(pal.well))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(pal.popoverBorder))
    }
}

/// One side of the mini window: its frame, the side, the version and its
/// label. Lit while its picker is open.
struct MiniPane: View {
    let side: Side
    let number: Int
    var active: Bool = false
    var showChevron: Bool = true
    var frameHeight: CGFloat = 66
    @Environment(\.pal) private var pal

    var body: some View {
        let v = version(number)
        VStack(alignment: .leading, spacing: 5) {
            VideoFrame(number: number)
                .frame(height: frameHeight)
                .overlay(alignment: .topLeading) {
                    Text(side.rawValue.uppercased())
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.35)))
                        .padding(4)
                }
            HStack(spacing: 5) {
                Text(v.name)
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(active ? pal.accent : pal.textPrimary)
                Text(v.label ?? "no label")
                    .font(.system(size: 11))
                    .foregroundStyle(v.label == nil ? pal.textTertiary : pal.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if showChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(active ? pal.accent : pal.textTertiary)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(active ? pal.accent.opacity(0.12) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(active ? pal.accent : pal.popoverBorder, lineWidth: active ? 1.5 : 1))
        .contentShape(Rectangle())
    }
}

// MARK: - Version list

/// The search field over a version list.
struct SearchField: View {
    @Binding var text: String
    var prompt = "Filter by number or label"
    @Environment(\.pal) private var pal
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(pal.textTertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(pal.well))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(pal.popoverBorder))
    }
}

/// The versions, newest last, each with its label; the chosen one checked,
/// the one on the other side and the one on screen tagged.
struct VersionRows: View {
    let versions: [Version]
    let chosen: Int
    var other: (side: Side, number: Int)? = nil
    var hovered: Int? = nil
    var query: String = ""
    var maxHeight: CGFloat = 168
    var idPrefix: String = "pick"
    var onPick: (Int) -> Void = { _ in }
    @Environment(\.pal) private var pal

    private var shown: [Version] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return versions }
        return versions.filter { "v\($0.number)".hasPrefix(q) || "\($0.number)" == q || ($0.label ?? "").lowercased().contains(q) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(shown) { v in
                        row(v).id(v.number)
                    }
                    if shown.isEmpty {
                        Text("No version matches").font(.system(size: 11)).foregroundStyle(pal.textTertiary).padding(8)
                    }
                }
                .padding(3)
            }
            .frame(maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: shown.count < 7)
            .onAppear { proxy.scrollTo(chosen, anchor: .center) }
        }
    }

    private func row(_ v: Version) -> some View {
        let isChosen = v.number == chosen
        let isHover = v.number == hovered
        return Button { onPick(v.number) } label: {
            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(isChosen ? 1 : 0)
                    .frame(width: 10)
                VideoFrame(number: v.number, corner: 2).frame(width: 28, height: 16)
                Text(v.name).font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .frame(width: 26, alignment: .leading)
                Text(v.label ?? "—").font(.system(size: 12))
                    .foregroundStyle(isHover ? pal.textOnAccent.opacity(0.85) : (v.label == nil ? pal.textTertiary : pal.textSecondary))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let other, other.number == v.number {
                    tag("on \(other.side.rawValue.lowercased())", isHover)
                }
                else if v.number == (versions.last?.number ?? 0) {
                    tag("on screen", isHover)
                }
            }
            .foregroundStyle(isHover ? pal.textOnAccent : pal.textPrimary)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(isHover ? pal.accent : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .labID("\(idPrefix)-v\(v.number)")
    }

    private func tag(_ text: String, _ onAccent: Bool) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(onAccent ? pal.textOnAccent : pal.textTertiary)
            .padding(.horizontal, 5).frame(height: 15)
            .background(Capsule().strokeBorder(onAccent ? pal.textOnAccent.opacity(0.5) : pal.popoverBorder.opacity(2)))
    }
}

/// A menu-styled card: search, then the rows.
struct VersionMenu: View {
    let side: Side
    let versions: [Version]
    let chosen: Int
    var other: (side: Side, number: Int)? = nil
    var hovered: Int? = nil
    var width: CGFloat = 250
    @State var query: String = ""
    var onPick: (Int) -> Void = { _ in }
    @Environment(\.pal) private var pal
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(side.rawValue) side shows")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(pal.textTertiary)
                .padding(.horizontal, 6).padding(.top, 4)
            if versions.count > 8 { SearchField(text: $query).padding(.horizontal, 3) }
            VersionRows(versions: versions, chosen: chosen, other: other, hovered: hovered,
                        query: query, idPrefix: "\(side.rawValue.lowercased())-pick", onPick: onPick)
        }
        .padding(4)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(pal.dark ? Color(white: 0.17) : Color.white))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(pal.popoverBorder))
        .shadow(color: .black.opacity(pal.dark ? 0.5 : 0.18), radius: 10, y: 4)
    }
}

// MARK: - The comparison window

/// The window while comparing: the header names both sides and offers the
/// way out; the stage shows the two versions in `layout`; one player bar
/// drives both.
struct ComparisonWindow: View {
    let left: Int
    let right: Int
    var layout: CompareLayout = .sideBySide
    var flipShowsRight = false
    var stageHeight: CGFloat = 180
    var onExit: () -> Void = {}
    @Environment(\.pal) private var pal

    var body: some View {
        WindowCard {
            VStack(spacing: 0) {
                HeaderBar {
                    ProjectTitle(subtitle: "Comparing v\(left) and v\(right)")
                } middle: {
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: layout.symbol).font(.system(size: 11, weight: .medium))
                            Text("v\(left) · v\(right)").font(.system(size: 12, weight: .semibold).monospacedDigit())
                        }
                        .foregroundStyle(pal.textOnAccent)
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Capsule().fill(pal.accent))
                        Button(action: onExit) {
                            HStack(spacing: 5) {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                Text("Exit Compare").font(.system(size: 12, weight: .medium))
                                KeyCap(text: "esc")
                            }
                            .foregroundStyle(pal.textPrimary)
                            .padding(.leading, 10).padding(.trailing, 5).frame(height: 28)
                            .background(Capsule().fill(pal.dark ? Color.white.opacity(0.07) : Color.white.opacity(0.85)))
                            .overlay(Capsule().strokeBorder(pal.popoverBorder))
                        }
                        .buttonStyle(.plain)
                        .labID("exit-compare")
                    }
                }
                stage
                    .frame(height: stageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 12)
                PlayerBarStrip()
            }
        }
    }

    @ViewBuilder private var stage: some View {
        ZStack {
            pal.letterbox
            switch layout {
            case .sideBySide:
                HStack(spacing: 6) {
                    half(left, side: .left)
                    half(right, side: .right)
                }
                .padding(.horizontal, 6)
            case .flip:
                let n = flipShowsRight ? right : left
                VideoFrame(number: n, corner: 0)
                    .frame(width: stageHeight * 16 / 9)
                    .overlay(alignment: .topLeading) { label(n, side: flipShowsRight ? .right : .left) }
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 6) {
                            Text("v\(left)").fontWeight(flipShowsRight ? .regular : .bold)
                            KeyCap(text: "\\")
                            Text("v\(right)").fontWeight(flipShowsRight ? .bold : .regular)
                            Text("hold or tap to flip").foregroundStyle(.white.opacity(0.7))
                        }
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .padding(10)
                    }
            case .slider:
                let w = stageHeight * 16 / 9
                ZStack {
                    VideoFrame(number: right, corner: 0)
                    VideoFrame(number: left, corner: 0)
                        .mask(alignment: .leading) { Rectangle().frame(width: w * 0.42) }
                    Rectangle().fill(.white).frame(width: 2).offset(x: w * 0.42 - w / 2)
                    Circle().fill(.white).frame(width: 26, height: 26)
                        .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.black.opacity(0.7)))
                        .shadow(radius: 2)
                        .offset(x: w * 0.42 - w / 2)
                }
                .frame(width: w)
                .overlay(alignment: .topLeading) { label(left, side: .left) }
                .overlay(alignment: .topTrailing) { label(right, side: .right) }
            }
        }
    }

    private func half(_ n: Int, side: Side) -> some View {
        VideoFrame(number: n, corner: 0)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(alignment: .topLeading) { label(n, side: side) }
    }

    private func label(_ n: Int, side: Side) -> some View {
        let v = version(n)
        return HStack(spacing: 5) {
            Text(side.rawValue.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.5).opacity(0.7)
            Text(v.name).font(.system(size: 12, weight: .bold).monospacedDigit())
            if let l = v.label { Text(l).font(.system(size: 11.5)) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).frame(height: 22)
        .background(Capsule().fill(.black.opacity(0.5)))
        .padding(8)
    }
}

/// Places `menu` just under the pane it belongs to, flush with the pane's
/// outer edge, drawn over whatever is below.
struct PaneMenu<Menu: View>: View {
    let side: Side
    @ViewBuilder var menu: Menu
    var body: some View {
        GeometryReader { geo in
            menu
                .fixedSize()
                .frame(width: geo.size.width, alignment: side == .left ? .topLeading : .topTrailing)
                .offset(y: geo.size.height + 4)
        }
    }
}

/// The 50-version case: the menu scrolls to the chosen version, and the
/// search field filters by number or label.
struct FiftyVersions: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StateCaption(text: "50 versions · scrolls to the choice")
            VersionMenu(side: .left, versions: Fixture.many, chosen: 49,
                        other: (.right, 50), hovered: 47, width: 250)
            StateCaption(text: "50 versions · filtered by “voice”").padding(.top, 14)
            VersionMenu(side: .left, versions: Fixture.many, chosen: 49,
                        other: (.right, 50), hovered: 12, width: 250, query: "voice")
        }
        .frame(width: 250)
    }
}
