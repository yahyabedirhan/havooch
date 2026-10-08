import LabHost
import SwiftUI

/// version-switcher V5 "Recent + picker": V1's segmented control keeps the
/// last three versions, then a popup field. The field names the version on
/// screen whenever it is not a recent one, and opens a searchable picker of
/// every version. Compare replaces A/B.
public let variant = LabVariant { Themed { V5Board() } }

struct V5Board: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StateCaption(text: "a · 50 versions, v50 (latest) on screen")
            WindowCard(width: 960) {
                VStack(spacing: 0) {
                    HeaderBar { ProjectTitle(versions: Big.versions, current: 50) }.zIndex(1)
                    StageStrip(height: 44).padding(.bottom, 10)
                }
            }
            StateCaption(text: "b · v12 (old) on screen: the field names it, selected").padding(.top, 10)
            WindowCard(width: 960) {
                VStack(spacing: 0) {
                    HeaderBar { ProjectTitle(versions: Big.versions, current: 12) }.zIndex(1)
                    StageStrip(height: 44, tint: 0.15).padding(.bottom, 10)
                }
            }
            StateCaption(text: "c · picker open from v50: all 50, newest first; typing filters by number or label").padding(.top, 10)
            WindowCard(width: 960) {
                VStack(spacing: 0) {
                    HeaderBar { ProjectTitle(versions: Big.versions, current: 50, pickerOpen: true) }.zIndex(1)
                    StageStrip(height: 266, caption: Big.version(50).subtitle).padding(.bottom, 10)
                }
            }
            StateCaption(text: "d · a 3-version project: no picker").padding(.top, 10)
            WindowCard(width: 960) {
                HeaderBar { ProjectTitle(versions: Fixture.versions, current: 3) }
            }
            StateCaption(text: "e · outside a project: no switcher").padding(.top, 10)
            WindowCard(width: 960) {
                HeaderBar { PlainTitle() }
            }
        }
        .padding(20)
    }
}

/// The cat mark, the project name with the switcher and Compare, and under
/// them the on-screen version and the folder.
private struct ProjectTitle: View {
    let versions: [Version]
    @State var current: Int
    @State var pickerOpen = false
    @State var query = ""
    @Environment(\.pal) private var pal

    var body: some View {
        HStack(spacing: 8) {
            CatMark(size: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 10) {
                    HeaderLine(symbol: "film.stack", iconColor: pal.textSecondary) {
                        Text(Big.project).font(.headline).foregroundStyle(pal.textPrimary)
                    }
                    Switcher(versions: versions, current: $current, pickerOpen: $pickerOpen, query: $query)
                    CompareButton()
                }
                VersionSubtitle(version: versions[current - 1])
            }
            .lineLimit(1)
        }
        .padding(.leading, 4)
    }
}

/// The last three versions as segments, then the popup field.
private struct Switcher: View {
    let versions: [Version]
    @Binding var current: Int
    @Binding var pickerOpen: Bool
    @Binding var query: String
    @Environment(\.pal) private var pal

    private let recentCount = 3
    private var recent: [Version] { Array(versions.suffix(recentCount)) }
    private var hasOlder: Bool { versions.count > recentCount }
    private var isOld: Bool { !recent.contains { $0.number == current } }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(recent) { segment($0) }
            if hasOlder {
                Rectangle().fill(pal.separator).frame(width: 1, height: 12).padding(.horizontal, 3)
                field
            }
        }
        .modifier(SegmentTrack())
    }

    private func segment(_ v: Version) -> some View {
        let on = v.number == current
        return Button {
            current = v.number
            pickerOpen = false
        } label: {
            Text(v.name)
                .font(.system(size: 11, weight: on ? .semibold : .medium).monospacedDigit())
                .foregroundStyle(on ? pal.textPrimary : pal.textSecondary)
                .frame(width: 34, height: 20)
                .background { if on { RaisedSegment() } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(v.name) · \(v.label ?? "no label") · \(v.threads) threads")
        .labID("segment-\(v.name)")
    }

    /// "v12 ⌃⌄" when an old version is on screen, else "All versions ⌃⌄".
    private var field: some View {
        Button {
            pickerOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                if isOld {
                    Text(versions[current - 1].name)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(pal.textPrimary)
                } else {
                    Text("All \(versions.count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(pickerOpen ? pal.textPrimary : pal.textSecondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isOld ? pal.textSecondary : pal.textTertiary)
            }
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(minWidth: 52, minHeight: 20)
            .background {
                if isOld {
                    RaisedSegment()
                } else if pickerOpen {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(pal.controlHover.opacity(1.6))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Go to version…")
        .labID("version-field")
        .overlay(alignment: .topLeading) {
            if pickerOpen {
                VersionPicker(versions: versions, current: current, query: $query) { n in
                    current = n
                    pickerOpen = false
                }
                .offset(x: -8, y: 28)
            }
        }
    }
}

/// The searchable picker: "Go to version…", then every version, newest first.
private struct VersionPicker: View {
    let versions: [Version]
    let current: Int
    @Binding var query: String
    let pick: (Int) -> Void
    @Environment(\.pal) private var pal

    private var matches: [Version] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = versions.reversed()
        guard !q.isEmpty else { return Array(all) }
        let bare = q.hasPrefix("v") ? String(q.dropFirst()) : q
        return all.filter {
            String($0.number).hasPrefix(bare) || ($0.label?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(pal.textTertiary)
                TextField("", text: $query, prompt: Text("Go to version…"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .labID("version-search")
                Text("\(matches.count) of \(versions.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(pal.textTertiary)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pal.well))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(pal.accent.opacity(0.6), lineWidth: 1.5))
            .padding(8)
            Divider().overlay(pal.separator)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { i, v in
                        Button { pick(v.number) } label: {
                            VersionRow(version: v, isCurrent: v.number == current, isHighlighted: i == 0)
                        }
                        .buttonStyle(.plain)
                        .labID("pick-\(v.name)")
                    }
                }
                .padding(5)
            }
            .scrollIndicators(.visible)
            .frame(height: 24 * 7 + 10)
            Divider().overlay(pal.separator)
            HStack(spacing: 10) {
                hint("↑↓", "move")
                hint("↩", "open")
                hint("esc", "close")
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
        }
        .frame(width: 320)
        .modifier(MenuPanel())
        .fixedSize()
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            KeyCap(text: key)
            Text(text).font(.system(size: 11)).foregroundStyle(pal.textTertiary)
        }
    }
}
