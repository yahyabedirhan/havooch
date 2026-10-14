import Foundation
import ReviewCore
import SwiftUI

nonisolated struct VersionSwitch: Equatable {
    struct Entry: Equatable, Identifiable {
        var number: Int
        var label: String?
        var threads: Int
        var made: String?

        var id: Int { number }
        var name: String { "v\(number)" }
        var line: String { ([name] + [label ?? made].compactMap(\.self)).joined(separator: " · ") }
    }

    static let recentCount = 3

    var versions: [Entry]
    var current: Int?

    var recent: [Entry] { Array(versions.suffix(Self.recentCount)) }
    var hasOlder: Bool { versions.count > Self.recentCount }
    var isOld: Bool {
        guard let current else { return false }
        return !recent.contains { $0.number == current }
    }
    var field: String? {
        guard hasOlder else { return nil }
        if isOld, let current { return "v\(current)" }
        return "All \(versions.count)"
    }

    var onScreen: Entry? { current.flatMap(entry) }

    func entry(_ number: Int) -> Entry? {
        versions.indices.contains(number - 1) ? versions[number - 1] : nil
    }

    func matches(_ query: String) -> [Entry] {
        let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = Array(versions.reversed())
        guard !typed.isEmpty else { return all }
        let bare = typed.hasPrefix("v") ? String(typed.dropFirst()) : typed
        return all.filter {
            String($0.number).hasPrefix(bare) || ($0.label?.lowercased().contains(typed) ?? false)
        }
    }

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

nonisolated struct VersionPicker: Equatable {
    var query = ""
    var highlighted: Int?

    func highlight(in matches: [VersionSwitch.Entry]) -> Int? {
        if let highlighted, matches.contains(where: { $0.number == highlighted }) { return highlighted }
        return matches.first?.number
    }

    func moved(by steps: Int, in matches: [VersionSwitch.Entry]) -> VersionPicker {
        guard !matches.isEmpty else { return self }
        let at = highlight(in: matches).flatMap { number in matches.firstIndex { $0.number == number } } ?? 0
        var moved = self
        moved.highlighted = matches[min(max(at + steps, 0), matches.count - 1)].number
        return moved
    }
}

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

    static func help(_ version: VersionSwitch.Entry) -> String {
        let threads = "\(version.threads) thread\(version.threads == 1 ? "" : "s")"
        return [version.name, version.label, threads].compactMap(\.self).joined(separator: ", ")
    }

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

    private var pickerShown: Binding<Bool> {
        Binding(get: { model.versionPicker != nil }, set: { if !$0 { model.closeVersionPicker() } })
    }
}

private struct RaisedSegment: View {
    @Environment(\.palette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(palette[palette.theme.kind == .dark ? .popoverBorder : .knob])
            .shadow(color: palette[.shadow].opacity(0.5), radius: 0.5, y: 0.5)
    }
}

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
