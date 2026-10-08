import SwiftUI

/// The 50-version project: v1 to v50, recent ones labelled, old ones mostly not.
enum Big {
    static let project = "Havooch launch video"
    static let labels: [Int: String] = [
        50: "shorter end card", 49: "warmer music", 48: "logo sting earlier",
        47: "tighter cut", 46: "new voice, take 2", 44: "colour pass",
        41: "music swap", 33: "captions on", 25: "second edit",
        12: "alt opening", 1: "first cut",
    ]
    static let versions: [Version] = (1...50).map {
        Version(number: $0, label: labels[$0], threads: threads($0), made: made($0))
    }
    static func version(_ n: Int) -> Version { versions[n - 1] }

    static func threads(_ n: Int) -> Int {
        switch n {
        case 50: 2
        case 46...49: [4, 6, 3, 5][n - 46]
        default: (n * 7 + 3) % 6
        }
    }

    /// Two renders a day, counted back from today (Oct 8).
    static func made(_ n: Int) -> String {
        let back = (50 - n) / 2
        switch back {
        case 0: return "today"
        case 1: return "yesterday"
        case ..<8: return "Oct \(8 - back)"
        default: return "Sep \(38 - back)"
        }
    }
}

extension Version {
    /// "v12 · alt opening", or "v13 · Sep 26" when it has no label.
    var subtitle: String { "\(name) · \(label ?? made)" }
}

/// Compare: opens the compare popover (another component).
struct CompareButton: View {
    @Environment(\.pal) private var pal
    var body: some View {
        Button {} label: {
            HStack(spacing: 5) {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 11, weight: .medium))
                Text("Compare")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(pal.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .overlay(Capsule().strokeBorder(pal.popoverBorder.opacity(2)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Compare two versions")
        .labID("compare")
    }
}

/// The raised look of the segment on screen.
struct RaisedSegment: View {
    @Environment(\.pal) private var pal
    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(pal.dark ? Color.white.opacity(0.16) : Color.white)
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
    }
}

/// The segmented control's track.
struct SegmentTrack: ViewModifier {
    @Environment(\.pal) private var pal
    func body(content: Content) -> some View {
        content
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(pal.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)))
    }
}

/// A menu-like panel, as a system menu or popover draws.
struct MenuPanel: ViewModifier {
    @Environment(\.pal) private var pal
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(pal.popover))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(pal.popoverBorder))
            .shadow(color: pal.shadow, radius: 10, y: 4)
    }
}

/// One version row in a list: check, name, label, threads, date.
struct VersionRow: View {
    let version: Version
    let isCurrent: Bool
    let isHighlighted: Bool
    @Environment(\.pal) private var pal

    var body: some View {
        let fg = isHighlighted ? pal.textOnAccent : pal.textPrimary
        let fg2 = isHighlighted ? pal.textOnAccent.opacity(0.85) : pal.textSecondary
        let fg3 = isHighlighted ? pal.textOnAccent.opacity(0.75) : pal.textTertiary
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .opacity(isCurrent ? 1 : 0)
                .foregroundStyle(fg)
                .frame(width: 12)
            Text(version.name)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(fg)
                .frame(width: 30, alignment: .leading)
            if let label = version.label {
                Text(label).font(.system(size: 12)).foregroundStyle(fg2)
            } else {
                Text("no label").font(.system(size: 12).italic()).foregroundStyle(fg3)
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                Image(systemName: "bubble.left").font(.system(size: 9))
                Text("\(version.threads)").font(.system(size: 11).monospacedDigit())
            }
            .foregroundStyle(version.threads == 0 ? fg3.opacity(0.6) : fg2)
            .frame(width: 30, alignment: .trailing)
            Text(version.made)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(fg3)
                .frame(width: 58, alignment: .trailing)
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(pal.accent)
            }
        }
        .contentShape(Rectangle())
    }
}

/// The header's second line: the version on screen and the folder.
struct VersionSubtitle: View {
    let version: Version
    @Environment(\.pal) private var pal
    var body: some View {
        HeaderLine(symbol: "folder", iconColor: pal.textTertiary) {
            HStack(spacing: 0) {
                Text(version.subtitle).foregroundStyle(pal.textSecondary)
                Text("  ·  \(Fixture.folder)").foregroundStyle(pal.textTertiary)
            }
            .font(.subheadline)
        }
    }
}
