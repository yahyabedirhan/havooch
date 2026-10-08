import AppKit
import LabHost
import SwiftUI

// MARK: - Palette (Havooch's Default Light / Default Dark tokens)

struct Pal {
    let dark: Bool

    private static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(
            .sRGB, red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255, opacity: alpha
        )
    }

    var window: Color { Color(nsColor: .windowBackgroundColor) }
    var separator: Color { Color(nsColor: .separatorColor) }
    var letterbox: Color { dark ? Self.hex(0x000000) : Self.hex(0x151412) }
    var well: Color { dark ? Self.hex(0xffffff, 0.04) : Self.hex(0x000000, 0.04) }
    var controlHover: Color { dark ? Self.hex(0xffffff, 0.08) : Self.hex(0x000000, 0.06) }
    var textPrimary: Color { dark ? Self.hex(0xece9e3) : Self.hex(0x2b2925) }
    var textSecondary: Color { dark ? Self.hex(0xada79d) : Self.hex(0x6b665d) }
    var textTertiary: Color { dark ? Self.hex(0x7d776e) : Self.hex(0x9a948a) }
    var accent: Color { dark ? Self.hex(0x9db6dd) : Self.hex(0x5b7db1) }
    var agent: Color { accent }
    var question: Color { dark ? Self.hex(0x8fc7c3) : Self.hex(0x4a8a88) }
    var regionOutline: Color { dark ? Self.hex(0x9db6dd) : Self.hex(0x7d9ccc) }

    func state(_ state: RowState) -> Color {
        switch state {
        case .queued: dark ? Self.hex(0x958f85) : Self.hex(0x8e897f)
        case .sent: dark ? Self.hex(0xa7acb4) : Self.hex(0x8a8f98)
        case .working: dark ? Self.hex(0xe3bf84) : Self.hex(0xb98a45)
        case .done: dark ? Self.hex(0x9ccba8) : Self.hex(0x5e9771)
        }
    }
}

// MARK: - Fixture

enum RowState {
    case queued, sent, working, done

    var glyph: String {
        switch self {
        case .queued: "circle.dashed"
        case .sent: "arrow.up.circle.fill"
        case .working: "ellipsis.circle.fill"
        case .done: "checkmark.circle.fill"
        }
    }

    var name: String {
        switch self {
        case .queued: "Queued"
        case .sent: "Sent"
        case .working: "Working"
        case .done: "Done"
        }
    }
}

enum ThreadGroup: CaseIterable {
    case needsYou, withAgent, queued, done

    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .withAgent: "With agent"
        case .queued: "Queued"
        case .done: "Done"
        }
    }

    var glyph: String {
        switch self {
        case .needsYou: "questionmark.circle.fill"
        case .withAgent: RowState.working.glyph
        case .queued: RowState.queued.glyph
        case .done: RowState.done.glyph
        }
    }

    var hint: String? { self == .queued ? "⌘↩ sends them all" : nil }

    func color(_ pal: Pal) -> Color {
        switch self {
        case .needsYou: pal.question
        case .withAgent: pal.state(.working)
        case .queued: pal.state(.queued)
        case .done: pal.state(.done)
        }
    }
}

/// Where a thread was raised: a version of the project, one since removed,
/// or the whole project (General).
enum Origin: Hashable {
    case version(Int)
    case removed
    case project

    var short: String {
        switch self {
        case .version(let n): "v\(n)"
        case .removed: "removed"
        case .project: "all"
        }
    }
}

struct Version: Identifiable {
    let number: Int
    let label: String
    var id: Int { number }
    var name: String { "v\(number)" }
}

struct FxThread: Identifiable {
    let number: Int
    let time: String?
    let origin: Origin
    let group: ThreadGroup
    let state: RowState?
    let writer: String?
    let byAgent: Bool
    let words: String
    let ago: String
    let unread: Bool
    /// The seed of the drawn keyframe placeholder.
    let scene: Int
    let region: CGRect?

    var id: Int { number }
    var isGeneral: Bool { origin == .project }
    var title: String { isGeneral ? "General" : "#\(number)" }
    var waitsForAnswer: Bool { group == .needsYou }
}

enum Fixture {
    static let project = "Havooch launch video"
    static let current = 50
    /// How many of the newest versions show as their own sections.
    static let recentCount = 3

    /// Short labels the maintainer gave; most older versions have none.
    private static let labels: [Int: String] = [
        50: "shorter end card", 49: "warmer music", 48: "logo on beat", 47: "new voice, take 2",
        46: "caption above button", 44: "crossfade into demo", 41: "new voice", 38: "duck music",
        33: "4K export", 27: "tighter intro", 19: "second music bed", 12: "lower third", 5: "rough cut",
        1: "first cut",
    ]

    /// Every version, newest first.
    static let versions: [Version] = (1...50).reversed().map { Version(number: $0, label: labels[$0] ?? "") }

    static func version(_ n: Int) -> Version? { versions.first { $0.number == n } }

    static var recent: [Version] { Array(versions.prefix(recentCount)) }
    static var older: [Version] { Array(versions.dropFirst(recentCount)) }
    static var olderRange: String { "v\(older.last!.number)–v\(older.first!.number)" }

    static func rows(_ origin: Origin) -> [FxThread] { threads.filter { $0.origin == origin } }
    static func openCount(_ n: Int) -> Int { rows(.version(n)).filter { $0.group != .done }.count }
    static var olderOpen: [FxThread] {
        threads.filter { thread in
            if case .version(let n) = thread.origin { return n <= older.first!.number && thread.group != .done }
            return false
        }
    }

    private static func done(_ number: Int, _ time: String, _ v: Int, _ words: String, _ ago: String) -> FxThread {
        FxThread(number: number, time: time, origin: .version(v), group: .done, state: .done, writer: "Claude", byAgent: true,
                 words: words, ago: ago, unread: false, scene: number, region: nil)
    }

    /// General first, then the threads in time-of-raising order.
    static let threads: [FxThread] = [
        FxThread(number: 0, time: nil, origin: .project, group: .done, state: .done, writer: "Claude", byAgent: true,
                 words: "Rendered v50 with the shorter end card. Want me to try one more music bed for v51?",
                 ago: "4m", unread: true, scene: 0, region: nil),
        done(2, "0:04", 1, "Fixed in v2 at 0:02: the logo now lands on the first beat.", "6w"),
        done(4, "0:27", 1, "Fixed the spelling of \u{201C}Havooch\u{201D} in the lower third.", "6w"),
        done(7, "0:14", 3, "Smoothed the cursor path from the menu to the Send button.", "6w"),
        done(10, "0:09", 5, "Cut the two dead seconds before the demo starts.", "5w"),
        done(13, "0:31", 8, "Raised the end card logo so it clears the safe area.", "5w"),
        FxThread(number: 16, time: "0:22", origin: .version(12), group: .needsYou, state: nil, writer: "Asks", byAgent: true,
                 words: "The lower third still overlaps the cursor here. Move it left, or fade it out at 0:23?",
                 ago: "4w", unread: true, scene: 16, region: CGRect(x: 0.08, y: 0.66, width: 0.5, height: 0.18)),
        done(18, "0:12", 12, "Changed the lower third to the new font.", "4w"),
        done(21, "0:19", 15, "Matched the colour of the demo window to the brand blue.", "4w"),
        done(24, "0:06", 19, "Made the second music bed as its own render.", "3w"),
        done(28, "0:02", 22, "Trimmed the intro to one and a half seconds.", "3w"),
        done(33, "0:17", 27, "Tightened the cut between the two demo shots.", "3w"),
        FxThread(number: 36, time: "0:25", origin: .version(31), group: .withAgent, state: .working, writer: "You", byAgent: false,
                 words: "Keep the keyboard sound effect but lower it under the voice, it clicks too loud.",
                 ago: "2w", unread: false, scene: 36, region: nil),
        done(38, "0:29", 33, "Exported at 4K with the same bitrate as v32.", "2w"),
        done(42, "0:16", 38, "Ducked the music by 6 dB while the voice talks.", "10d"),
        done(45, "0:03", 41, "Recorded the new voice for the intro.", "8d"),
        done(48, "0:19", 44, "Added a short crossfade into the demo.", "5d"),
        done(51, "0:09", 46, "Moved the caption above the button.", "3d"),
        done(53, "0:03", 47, "Kept the second take of the new voice.", "2d"),
        done(56, "0:00", 48, "The logo now lands on the first beat.", "1d"),
        done(57, "0:21", 48, "Slowed the logo fade-out to match the beat.", "1d"),
        FxThread(number: 59, time: "0:08", origin: .version(49), group: .withAgent, state: .sent, writer: "You", byAgent: false,
                 words: "The warmer music is good. Bring it in half a second later, after the click.",
                 ago: "5h", unread: false, scene: 59, region: nil),
        done(60, "0:14", 49, "Swapped the music bed for the warmer one.", "6h"),
        FxThread(number: 62, time: "0:16", origin: .version(50), group: .queued, state: .queued, writer: "You", byAgent: false,
                 words: "Music is too loud under the voice. Duck it by a few dB while she talks.",
                 ago: "2m", unread: false, scene: 62, region: nil),
        FxThread(number: 63, time: "0:28", origin: .version(50), group: .queued, state: .queued, writer: "You", byAgent: false,
                 words: "End card is now too short. Hold it one more second before the fade.",
                 ago: "1m", unread: false, scene: 63, region: CGRect(x: 0.3, y: 0.25, width: 0.4, height: 0.4)),
        FxThread(number: 61, time: "0:27", origin: .version(50), group: .done, state: .done, writer: "Claude", byAgent: true,
                 words: "Cut the end card to two seconds, as asked in #57.",
                 ago: "5m", unread: true, scene: 61, region: nil),
    ]

    /// The thread whose frame is on the stage.
    static let onStage = 62
}

// MARK: - Small views

struct Hairline: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Pal(dark: scheme == .dark).separator.frame(height: 0.5)
    }
}

struct StateChip: View {
    let state: RowState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: state.glyph).imageScale(.small)
            Text(state.name)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Pal(dark: scheme == .dark).state(state))
        .lineLimit(1)
        .fixedSize()
    }
}

/// A small tag naming the version a thread was raised on.
struct VersionChip: View {
    let origin: Origin
    var isCurrent = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Pal(dark: scheme == .dark)
        HStack(spacing: 2) {
            if origin == .removed {
                Image(systemName: "trash").imageScale(.small)
            }
            Text(origin == .removed ? "removed version" : origin.short)
        }
        .font(.caption2.weight(.semibold).monospacedDigit())
        .foregroundStyle(isCurrent ? pal.accent : pal.textSecondary)
        .padding(.horizontal, 5)
        .frame(height: 15)
        .background(isCurrent ? pal.accent.opacity(0.14) : pal.well, in: Capsule())
        .overlay(Capsule().strokeBorder(isCurrent ? pal.accent.opacity(0.35) : pal.separator, lineWidth: 0.5))
        .lineLimit(1)
        .fixedSize()
    }
}

/// A keyframe placeholder: a drawn frame of the video, seeded per thread.
struct Keyframe: View {
    let scene: Int
    let region: CGRect?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Pal(dark: scheme == .dark)
        let hue = Double((scene * 37) % 100) / 100
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color(hue: hue, saturation: 0.35, brightness: 0.42),
                             Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.45, brightness: 0.2)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                // A window, a title bar and a button in it: a screen recording.
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.82))
                    .frame(width: size.width * 0.56, height: size.height * 0.5)
                    .offset(x: size.width * (0.12 + Double(scene % 3) * 0.06), y: size.height * 0.2)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hue: hue, saturation: 0.5, brightness: 0.75))
                    .frame(width: size.width * 0.16, height: size.height * 0.1)
                    .offset(x: size.width * (0.42 + Double(scene % 3) * 0.06), y: size.height * 0.55)
                Capsule()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: size.width * 0.4, height: 2)
                    .offset(x: size.width * 0.08, y: size.height * 0.84)
                if let region {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(pal.regionOutline, lineWidth: 1.5)
                        .frame(width: size.width * region.width, height: size.height * region.height)
                        .offset(x: size.width * region.minX, y: size.height * region.minY)
                }
            }
        }
        .background(pal.letterbox)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(pal.separator, lineWidth: 0.5)
        }
    }
}

// MARK: - The row

/// One thread in the list, as Havooch draws it today, with an optional
/// version tag and a quieter look for a thread off the version on screen.
struct ThreadRowView: View {
    let thread: FxThread
    var isOnStage = false
    /// Whether the row shows the version chip on its first line.
    var showsVersion = false
    /// Whether the thread was raised on another version than the one on
    /// screen: its keyframe and title are quieter, nothing else changes.
    var isOffVersion = false

    static let thumbnail = CGSize(width: 88, height: 50)
    static let spacing: CGFloat = 11
    static let padding: CGFloat = 10

    @State private var isHovered = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Pal(dark: scheme == .dark)
        HStack(alignment: .top, spacing: Self.spacing) {
            picture(pal)
                .opacity(isOffVersion ? 0.55 : 1)
                .saturation(isOffVersion ? 0.3 : 1)
            VStack(alignment: .leading, spacing: 2) {
                firstLine(pal)
                preview(pal)
            }
        }
        .padding(.horizontal, Self.padding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isOnStage ? pal.well : (isHovered ? pal.controlHover : .clear),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topLeading) {
            if thread.unread {
                Circle().fill(pal.accent).frame(width: 8, height: 8).offset(x: -3, y: 13)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(helpText)
        .labID("row-\(thread.number)")
    }

    private var helpText: String {
        switch thread.origin {
        case .version(let n) where n != Fixture.current: "Raised on v\(n). Click to show v\(n) at \(thread.time ?? "")."
        case .removed: "Raised on a version you removed. Click to show its keyframe."
        default: "Click to show the thread"
        }
    }

    private func firstLine(_ pal: Pal) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(thread.title)
                .font(.body.weight(thread.unread ? .bold : .semibold).monospacedDigit())
                .foregroundStyle(isOffVersion ? pal.textSecondary : pal.textPrimary)
            if let time = thread.time {
                Text(time).font(.callout.monospacedDigit()).foregroundStyle(pal.textSecondary)
            }
            if showsVersion, !thread.isGeneral {
                VersionChip(origin: thread.origin, isCurrent: thread.origin == .version(Fixture.current))
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }
            if thread.waitsForAnswer {
                Label("Answer", systemImage: "questionmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(pal.question)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .fixedSize()
            } else if let state = thread.state, !(showsVersion && thread.origin == .removed) {
                StateChip(state: state)
            }
            Spacer(minLength: 4)
            Text(thread.ago)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(thread.unread ? pal.accent : pal.textTertiary)
                .fixedSize()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(pal.textTertiary)
        }
        .frame(height: 18)
    }

    private func preview(_ pal: Pal) -> some View {
        let writer = thread.writer.map { Text("\($0): ").foregroundStyle(pal.textTertiary) } ?? Text("")
        let mark = thread.byAgent ? Text("\(Image(systemName: "sparkles")) ").foregroundStyle(pal.agent) : Text("")
        return Text("\(mark)\(writer)\(thread.words)")
            .font(.callout)
            .foregroundStyle(thread.unread ? pal.textPrimary : pal.textSecondary)
            .lineLimit(2, reservesSpace: false)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func picture(_ pal: Pal) -> some View {
        if thread.isGeneral {
            Image(systemName: "globe")
                .font(.system(size: 18))
                .foregroundStyle(pal.textSecondary)
                .frame(width: Self.thumbnail.width, height: Self.thumbnail.height)
                .background(pal.well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Keyframe(scene: thread.scene, region: thread.region)
                .frame(width: Self.thumbnail.width, height: Self.thumbnail.height)
        }
    }
}

/// The hairline between two rows, under the words only.
struct RowHairline: View {
    var body: some View {
        Hairline()
            .padding(.leading, ThreadRowView.padding + ThreadRowView.thumbnail.width + ThreadRowView.spacing)
            .padding(.trailing, ThreadRowView.padding)
    }
}

/// A state group's header, as Havooch draws it today.
struct StateHeader: View {
    let group: ThreadGroup
    let count: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Pal(dark: scheme == .dark)
        HStack(spacing: 6) {
            Image(systemName: group.glyph).imageScale(.small).foregroundStyle(group.color(pal))
            Text(group.title.uppercased()).fontWeight(.semibold).tracking(0.2)
            Text("\(count)").monospacedDigit()
            Spacer(minLength: 4)
            if let hint = group.hint { Text(hint) }
        }
        .font(.subheadline)
        .foregroundStyle(group == .needsYou ? pal.question : pal.textTertiary)
        .padding(.horizontal, ThreadRowView.padding)
        .padding(.top, 12)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pal.window)
    }
}

/// The project's name over "Threads", and the summary line.
struct ListHeading: View {
    let summary: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Pal(dark: scheme == .dark)
        VStack(alignment: .leading, spacing: 1) {
            Text("Threads").font(.title2.weight(.bold)).foregroundStyle(pal.textPrimary)
            Text(summary).font(.subheadline.monospacedDigit()).foregroundStyle(pal.textTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The sidebar's own surface at its size.
struct SidebarSurface<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .frame(width: 360, height: 620, alignment: .top)
            .background(Pal(dark: scheme == .dark).window)
            .environment(\.locale, Locale(identifier: "en_US"))
    }
}

// MARK: - Version sections (from thread-list V2)

/// A version section's rows, with the hairlines between them.
struct SectionRows: View {
    let origin: Origin
    let rows: [FxThread]
    var showsVersion = false

    var body: some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, thread in
            ThreadRowView(
                thread: thread,
                isOnStage: thread.number == Fixture.onStage,
                showsVersion: showsVersion,
                isOffVersion: thread.origin != .version(Fixture.current) && thread.origin != .project
            )
            .overlay(alignment: .top) { if index > 0 { RowHairline() } }
        }
    }
}

/// One glyph and number per state group, as in a version header.
struct StateCounts: View {
    let rows: [FxThread]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Pal(dark: scheme == .dark)
        HStack(spacing: 7) {
            ForEach(ThreadGroup.allCases, id: \.self) { group in
                let count = rows.filter { $0.group == group }.count
                if count > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: group.glyph).imageScale(.small)
                        Text("\(count)").monospacedDigit()
                    }
                    .foregroundStyle(group.color(pal))
                    .help("\(count) \(group.title.lowercased())")
                }
            }
        }
        .font(.subheadline.weight(.medium))
        .fixedSize()
    }
}

/// A version's header: its name, its label, "On screen" for the current
/// one, and its counts by who acts next.
struct VersionHeader<Trailing: View>: View {
    let origin: Origin
    let rows: [FxThread]
    @ViewBuilder var trailing: Trailing
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Pal(dark: scheme == .dark)
        let isCurrent = origin == .version(Fixture.current)
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .tracking(0.2)
                .foregroundStyle(isCurrent ? pal.textPrimary : pal.textTertiary)
            if let label {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(isCurrent ? pal.textSecondary : pal.textTertiary)
                    .lineLimit(1)
            }
            if isCurrent {
                HStack(spacing: 3) {
                    Image(systemName: "play.fill").font(.system(size: 7, weight: .bold))
                    Text("On screen")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(pal.accent)
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(pal.accent.opacity(0.14), in: Capsule())
                .fixedSize()
            }
            Spacer(minLength: 4)
            StateCounts(rows: rows)
            trailing
        }
        .padding(.horizontal, ThreadRowView.padding)
        .padding(.top, 14)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pal.window)
        .labID("version-\(origin.short)")
    }

    private var title: String {
        switch origin {
        case .version(let n): "V\(n)"
        case .removed: "REMOVED VERSION"
        case .project: "PROJECT"
        }
    }

    private var label: String? {
        if case .version(let n) = origin, let label = Fixture.version(n)?.label, !label.isEmpty { return label }
        return nil
    }
}

extension VersionHeader where Trailing == EmptyView {
    init(origin: Origin, rows: [FxThread]) {
        self.init(origin: origin, rows: rows) { EmptyView() }
    }
}

/// Two states of one variant side by side, each captioned.
struct StatePair<A: View, B: View>: View {
    let first: String
    let second: String
    @ViewBuilder var a: A
    @ViewBuilder var b: B

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            captioned(first) { a }
            captioned(second) { b }
        }
        .padding(16)
    }

    private func captioned<C: View>(_ caption: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content()
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }
}

/// The summary line over the list.
enum Summary {
    static var text: String {
        let threads = Fixture.threads
        let needs = threads.filter { $0.group == .needsYou }.count
        let queued = threads.filter { $0.group == .queued }.count
        return "\(threads.count) threads · \(Fixture.versions.count) versions · \(needs) need you · \(queued) queued"
    }
}
