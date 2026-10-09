import Foundation
import ReviewCore
import SwiftUI

/// The version switcher of a project's window (version-switcher V5,
/// "Recent plus picker"), as words and numbers: the last three versions
/// as segments, and a field after them for the older ones, which names
/// an older version while it is on screen and opens a searchable picker
/// of every version. Pure, so the switcher is tested without a window.
nonisolated struct VersionSwitch: Equatable {
    /// One version as the switcher and the picker show it.
    struct Entry: Equatable, Identifiable {
        /// From 1.
        var number: Int
        var label: String?
        /// How many threads are on a frame of it.
        var threads: Int
        /// When its file was made, as the picker says it (`today`,
        /// `yesterday`, `Oct 6`); nil when the file can't be read.
        var made: String?

        var id: Int { number }
        /// `v12`.
        var name: String { "v\(number)" }
        /// The header's line under the project's title: `v12 · alt
        /// opening`, else `v12 · Oct 6`, else `v12`.
        var line: String { ([name] + [label ?? made].compactMap(\.self)).joined(separator: " · ") }
    }

    /// How many of the newest versions are segments.
    static let recentCount = 3

    /// v1 first.
    var versions: [Entry]
    /// The number of the version on screen; nil for a removed version.
    var current: Int?

    /// The segments: the last three versions, oldest first.
    var recent: [Entry] { Array(versions.suffix(Self.recentCount)) }
    /// Whether the project has versions older than the segments, so the
    /// field and its picker show.
    var hasOlder: Bool { versions.count > Self.recentCount }
    /// Whether the version on screen is older than the segments: the field
    /// names it and is the selected one.
    var isOld: Bool {
        guard let current else { return false }
        return !recent.contains { $0.number == current }
    }
    /// The field's words: the older version on screen (`v12`), else
    /// `All 50`; nil when the project has no older version.
    var field: String? {
        guard hasOlder else { return nil }
        if isOld, let current { return "v\(current)" }
        return "All \(versions.count)"
    }

    /// The version on screen; nil for a removed version.
    var onScreen: Entry? { current.flatMap(entry) }

    /// The version numbered `number`; nil outside the list.
    func entry(_ number: Int) -> Entry? {
        versions.indices.contains(number - 1) ? versions[number - 1] : nil
    }

    /// The picker's rows for `query`, newest first: every version with no
    /// query, else those whose number starts with it (`1`, `v1`; `v`
    /// alone is every one) or whose label holds it, in any case.
    func matches(_ query: String) -> [Entry] {
        let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = Array(versions.reversed())
        guard !typed.isEmpty else { return all }
        let bare = typed.hasPrefix("v") ? String(typed.dropFirst()) : typed
        return all.filter {
            String($0.number).hasPrefix(bare) || ($0.label?.lowercased().contains(typed) ?? false)
        }
    }

    /// When a file made at `date` was made, as the picker says it:
    /// `today`, `yesterday`, else the month and the day (`Oct 6`).
    static func made(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: Locale(identifier: "en_US"), calendar: calendar)
            .month(.abbreviated).day()
        return date.formatted(style)
    }
}

/// The version picker while it is open: what is typed in its search
/// field, and the row Up and Down moved to.
nonisolated struct VersionPicker: Equatable {
    var query = ""
    /// The number of the highlighted version; nil highlights the first row.
    var highlighted: Int?

    /// The row Return opens among `matches`: the one moved to while it
    /// still matches, else the first.
    func highlight(in matches: [VersionSwitch.Entry]) -> Int? {
        if let highlighted, matches.contains(where: { $0.number == highlighted }) { return highlighted }
        return matches.first?.number
    }

    /// The row `steps` rows below the highlighted one (above, below 0),
    /// kept inside `matches`.
    func moved(by steps: Int, in matches: [VersionSwitch.Entry]) -> VersionPicker {
        guard !matches.isEmpty else { return self }
        let at = highlight(in: matches).flatMap { number in matches.firstIndex { $0.number == number } } ?? 0
        var moved = self
        moved.highlighted = matches[min(max(at + steps, 0), matches.count - 1)].number
        return moved
    }
}

/// The switcher on the header's first line, after the project's title:
/// the last three versions as segments, then the field that opens the
/// picker. A plain video has none (the title shows no switcher).
struct VersionSwitcher: View {
    let model: WindowModel
    let versions: VersionSwitch
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(versions.recent) { segment($0) }
            if versions.hasOlder {
                Rectangle()
                    .fill(palette[.separator])
                    .frame(width: 1, height: 12)
                    .padding(.horizontal, 3)
                field
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette[.controlHover]))
    }

    private func segment(_ version: VersionSwitch.Entry) -> some View {
        let on = version.number == versions.current
        return Button {
            model.showVersionForPerson(version.number)
        } label: {
            Text(version.name)
                .font(.system(size: 11, weight: on ? .semibold : .medium).monospacedDigit())
                .foregroundStyle(palette[on ? .textPrimary : .textSecondary])
                .frame(minWidth: 34, minHeight: 20)
                .background { if on { RaisedSegment() } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pressedByKeys(in: model) { model.showVersionForPerson(version.number) }
        .help(Self.help(version))
        .accessibilityLabel(version.name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// `v12, alt opening, 3 threads`.
    static func help(_ version: VersionSwitch.Entry) -> String {
        let threads = "\(version.threads) thread\(version.threads == 1 ? "" : "s")"
        return [version.name, version.label, threads].compactMap(\.self).joined(separator: ", ")
    }

    /// `v12` and the chevrons while an older version is on screen, else
    /// `All 50`; it opens the picker.
    private var field: some View {
        let isOpen = model.versionPicker != nil
        return Button {
            model.toggleVersionPicker()
        } label: {
            HStack(spacing: 4) {
                Text(versions.field ?? "")
                    .font(.system(size: 11, weight: versions.isOld ? .semibold : .medium).monospacedDigit())
                    .foregroundStyle(palette[versions.isOld || isOpen ? .textPrimary : .textSecondary])
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(palette[versions.isOld ? .textSecondary : .textTertiary])
            }
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(minWidth: 52, minHeight: 20)
            .background {
                if versions.isOld {
                    RaisedSegment()
                } else if isOpen {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(palette[.controlHover])
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pressedByKeys(in: model) { model.toggleVersionPicker() }
        .help("Go to version…")
        .accessibilityLabel(versions.isOld ? "\(versions.field ?? ""), go to version" : "Go to version")
        .popover(isPresented: pickerShown, arrowEdge: .bottom) {
            VersionPickerPanel(model: model, versions: versions)
                .tint(palette[.accent])
                .popoverSurface(palette)
        }
    }

    /// Open while the model's picker is; closing the popover closes it.
    private var pickerShown: Binding<Bool> {
        Binding(get: { model.versionPicker != nil }, set: { if !$0 { model.closeVersionPicker() } })
    }
}

/// The raised look of the segment on screen: a light fill in a light
/// theme, a lighter veil in a dark one, from the theme's tokens.
private struct RaisedSegment: View {
    @Environment(\.palette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(palette[palette.theme.kind == .dark ? .popoverBorder : .knob])
            .shadow(color: palette[.shadow].opacity(0.5), radius: 0.5, y: 0.5)
    }
}

/// The searchable picker: "Go to version…", then every version, newest
/// first, typing filtering them by number or label. Up and Down move the
/// highlight, Return opens it, Escape closes the picker.
private struct VersionPickerPanel: View {
    let model: WindowModel
    let versions: VersionSwitch
    @FocusState private var isSearchFocused: Bool
    @Environment(\.palette) private var palette

    private var query: Binding<String> {
        Binding(get: { model.versionPicker?.query ?? "" }, set: { model.typeVersionQuery($0) })
    }

    var body: some View {
        let matches = versions.matches(model.versionPicker?.query ?? "")
        let highlighted = model.versionPicker?.highlight(in: matches)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(palette[.textTertiary])
                TextField("", text: query, prompt: Text("Go to version…"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)
                    .onKeyPress(.upArrow) {
                        model.moveVersionHighlight(by: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        model.moveVersionHighlight(by: 1)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        model.openHighlightedVersion()
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        model.closeVersionPicker()
                        return .handled
                    }
                Text("\(matches.count) of \(versions.versions.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(palette[.textTertiary])
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette[.well]))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(palette[.accent].opacity(0.6), lineWidth: 1.5))
            .padding(8)
            Divider().overlay(palette[.separator])
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(matches) { version in
                            Button {
                                model.showVersionForPerson(version.number)
                            } label: {
                                VersionRow(
                                    version: version, isCurrent: version.number == versions.current,
                                    isHighlighted: version.number == highlighted
                                )
                            }
                            .buttonStyle(.plain)
                            .id(version.number)
                        }
                    }
                    .padding(5)
                }
                .scrollIndicators(.visible)
                .frame(height: 24 * 7 + 10)
                .onChange(of: highlighted) { _, number in
                    if let number { scroller.scrollTo(number) }
                }
            }
            Divider().overlay(palette[.separator])
            HStack(spacing: 10) {
                hint("↑↓", "move")
                hint("↩", "open")
                hint("esc", "close")
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
        }
        .frame(width: 320)
        .onAppear { isSearchFocused = true }
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium).monospaced())
                .foregroundStyle(palette[.textSecondary])
                .padding(.horizontal, 4)
                .frame(minWidth: 16, minHeight: 16)
                .background(RoundedRectangle(cornerRadius: 4).fill(palette[.well]))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(palette[.popoverBorder]))
            Text(text).font(.system(size: 11)).foregroundStyle(palette[.textTertiary])
        }
        .accessibilityElement(children: .combine)
    }
}

/// One version in the picker: a check on the one on screen, its name,
/// its label, its threads and when it was made.
private struct VersionRow: View {
    let version: VersionSwitch.Entry
    let isCurrent: Bool
    let isHighlighted: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        let primary = isHighlighted ? palette[.textOnAccent] : palette[.textPrimary]
        let secondary = isHighlighted ? palette[.textOnAccent].opacity(0.85) : palette[.textSecondary]
        let tertiary = isHighlighted ? palette[.textOnAccent].opacity(0.75) : palette[.textTertiary]
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .opacity(isCurrent ? 1 : 0)
                .foregroundStyle(primary)
                .frame(width: 12)
            Text(version.name)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(primary)
                .frame(width: 30, alignment: .leading)
            if let label = version.label {
                Text(label).font(.system(size: 12)).foregroundStyle(secondary)
            } else {
                Text("no label").font(.system(size: 12).italic()).foregroundStyle(tertiary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                Image(systemName: "bubble.left").font(.system(size: 9))
                Text("\(version.threads)").font(.system(size: 11).monospacedDigit())
            }
            .foregroundStyle(version.threads == 0 ? tertiary.opacity(0.6) : secondary)
            .frame(width: 30, alignment: .trailing)
            Text(version.made ?? "")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(tertiary)
                .frame(width: 58, alignment: .trailing)
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(palette[.accent])
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
