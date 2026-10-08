import ReviewCore
import SwiftUI

// A project's thread list by version (decision E9), built from Swift Lab's
// `project-versions` session, component `thread-list`, variant V5 "Final:
// Jump menu" (`docs/prototypes/2026-10-08-lab/project-versions/thread-list-V5/`).

/// A project's thread list (E9): the bar with what it shows and "All
/// versions", General, then a section per version of `VersionTree` under
/// a header that stays at the top while the list scrolls, and a footer
/// with the older versions and a way to each open thread on them. Every
/// row is today's row, with its state chip, and works as it does on any
/// version (E6).
struct VersionList: View {
    let model: WindowModel
    let tree: VersionTree

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AllVersionsBar(model: model, tree: tree)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        ThreadRows(model: model, threads: tree.general)
                        ForEach(tree.sections) { section in
                            Section {
                                ThreadRows(
                                    model: model, threads: section.threads, showsVersion: false,
                                    isOffVersion: !section.isOnScreen
                                )
                                if section.threads.isEmpty {
                                    Text("No threads on v\(section.number ?? 0)")
                                        .font(.callout)
                                        .foregroundStyle(palette[.textTertiary])
                                        .padding(.horizontal, ThreadRow.padding)
                                        .padding(.vertical, 8)
                                }
                            } header: {
                                VersionHeader(model: model, section: section)
                            }
                            .id(section.kind)
                        }
                        OlderFooter(model: model, tree: tree)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .onChange(of: model.versionJump) { _, jump in
                    guard let jump else { return }
                    // The section a pick added is laid out first.
                    Task { @MainActor in
                        withAnimation(.snappy(duration: 0.3)) {
                            proxy.scrollTo(VersionTree.Section.Kind.version(jump.number), anchor: .top)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.allVersionsMenu != nil {
                ZStack(alignment: .topTrailing) {
                    // A click outside the menu closes it.
                    palette[.window].opacity(0.001)
                        .onTapGesture { _ = model.closeVersionMenu() }
                        .accessibilityHidden(true)
                    AllVersionsMenuView(model: model)
                        .padding(.top, 32)
                        .padding(.trailing, 12)
                }
            }
        }
    }
}

/// The bar over the list: which versions it shows, and "All versions"
/// with the number of open threads on the versions it doesn't.
private struct AllVersionsBar: View {
    let model: WindowModel
    let tree: VersionTree

    @State private var isHovered = false
    @Environment(\.palette) private var palette

    var body: some View {
        let isOpen = model.versionMenu != nil
        let open = tree.stillOpen.count
        HStack(spacing: 6) {
            Text(tree.showing)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(palette[.textTertiary])
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                if isOpen {
                    _ = model.closeVersionMenu()
                } else {
                    _ = try? model.openVersionMenu(search: nil)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath").imageScale(.small)
                    Text("All versions")
                    if open > 0 {
                        Text("\(open)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(palette[.question])
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(palette[.question].opacity(0.16), in: Capsule())
                            .help("\(open) open \(open == 1 ? "thread" : "threads") on older versions")
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(palette[.textTertiary])
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette[.textSecondary])
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(isOpen || isHovered ? palette[.controlHover] : palette[.well], in: Self.shape)
                .overlay(Self.shape.strokeBorder(palette[.separator], lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("Jump to any version")
            .accessibilityLabel(open > 0 ? "All versions, \(open) open on older versions" : "All versions")
        }
        .padding(.horizontal, Metrics.sidebarPadding + 2)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private static let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
}

/// "All versions": a search field, then the versions in the list, the
/// older versions with open threads, and every older version.
private struct AllVersionsMenuView: View {
    let model: WindowModel

    @FocusState private var isSearchFocused: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        let menu = model.allVersionsMenu
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").imageScale(.small).foregroundStyle(palette[.textTertiary])
                TextField("Jump to v12 or a label", text: Binding(
                    get: { model.versionMenu ?? "" },
                    set: { model.typeVersionSearch($0) }
                ))
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isSearchFocused)
                .onSubmit {
                    // Return picks the first version the search finds.
                    guard let first = (menu?.inList.first ?? menu?.older.first) else { return }
                    _ = try? model.pickVersion(first.number)
                }
                .accessibilityLabel("Search versions")
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(palette[.well], in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(palette[.separator], lineWidth: 0.5))
            .padding(8)
            Hairline(axis: .horizontal)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let menu {
                        group("IN THE LIST", menu.inList)
                        group("STILL OPEN ON OLDER VERSIONS", menu.stillOpen)
                        group("OLDER · \(menu.older.count)", menu.older)
                        if menu.isEmpty {
                            Text("No version matches")
                                .font(.callout)
                                .foregroundStyle(palette[.textTertiary])
                                .padding(12)
                        }
                    }
                }
                .padding(.horizontal, 5)
                .padding(.bottom, 6)
            }
        }
        .frame(width: 300)
        .frame(maxHeight: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(palette[.popover], in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette[.popoverBorder], lineWidth: 0.5))
        .shadow(color: palette[.shadow], radius: 14, y: 6)
        .onAppear { isSearchFocused = true }
        .onExitCommand { _ = model.closeVersionMenu() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("All versions")
    }

    @ViewBuilder
    private func group(_ title: String, _ lines: [AllVersionsMenu.Line]) -> some View {
        if !lines.isEmpty {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(0.2)
                .foregroundStyle(palette[.textTertiary])
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 3)
                .accessibilityAddTraits(.isHeader)
            ForEach(lines) { line in
                MenuLine(line: line) { _ = try? model.pickVersion(line.number) }
            }
        }
    }
}

/// One version in "All versions": its number, its label, a mark when it
/// is on screen, its open threads by group and how many threads it has.
private struct MenuLine: View {
    let line: AllVersionsMenu.Line
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.palette) private var palette

    var body: some View {
        let isEmpty = line.threads.isEmpty
        Button(action: action) {
            HStack(spacing: 6) {
                Text("v\(line.number)")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isEmpty ? palette[.textTertiary] : palette[line.isOnScreen ? .accent : .textPrimary])
                    .frame(minWidth: 30, alignment: .leading)
                if let label = line.label {
                    Text(label)
                        .font(.callout)
                        .foregroundStyle(palette[isEmpty ? .textTertiary : .textSecondary])
                        .lineLimit(1)
                }
                if line.isOnScreen {
                    Image(systemName: "play.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(palette[.accent])
                        .help("On screen")
                }
                Spacer(minLength: 4)
                StateCounts(threads: line.threads.filter(VersionTree.isOpen))
                Text(isEmpty ? "" : "\(line.threads.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(palette[.textTertiary])
                    .frame(width: 18, alignment: .trailing)
                    .help(line.threads.count == 1 ? "1 thread" : "\(line.threads.count) threads")
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(isHovered ? palette[.controlHover] : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let threads = line.threads.count == 1 ? "1 thread" : "\(line.threads.count) threads"
        return ["v\(line.number)", line.label, line.isOnScreen ? "on screen" : nil, threads, line.open > 0 ? "\(line.open) open" : nil]
            .compactMap(\.self).joined(separator: ", ")
    }
}

/// A version's header: its name, its label, "On screen" for the version
/// on screen, its threads counted by who acts next, and a close button
/// for a version picked from "All versions".
private struct VersionHeader: View {
    let model: WindowModel
    let section: VersionTree.Section

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))
                .tracking(0.2)
                .foregroundStyle(palette[section.isOnScreen ? .textPrimary : .textTertiary])
            if let label = section.label {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(palette[section.isOnScreen ? .textSecondary : .textTertiary])
                    .lineLimit(1)
            }
            if section.isOnScreen {
                HStack(spacing: 3) {
                    Image(systemName: "play.fill").font(.system(size: 7, weight: .bold))
                    Text("On screen")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette[.accent])
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(palette[.accent].opacity(0.14), in: Capsule())
                .fixedSize()
            }
            Spacer(minLength: 4)
            StateCounts(threads: section.threads)
            if section.isPicked, let number = section.number {
                Button {
                    withAnimation(.snappy(duration: 0.22)) { _ = try? model.removePickedVersion(number) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(palette[.textTertiary])
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove v\(number) from the list")
                .accessibilityLabel("Remove v\(number) from the list")
            }
        }
        .padding(.horizontal, ThreadRow.padding)
        .padding(.top, 14)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette[.window])
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One glyph and count per group of who acts next, as a version's header
/// and a line of "All versions" show them.
private struct StateCounts: View {
    let threads: [ReviewThread]

    @Environment(\.palette) private var palette

    var body: some View {
        let counts = Dictionary(grouping: threads, by: ThreadGroup.of).mapValues(\.count)
        HStack(spacing: 7) {
            ForEach(ThreadGroup.allCases, id: \.self) { group in
                if let count = counts[group] {
                    HStack(spacing: 2) {
                        Image(systemName: group.glyph).imageScale(.small)
                        Text("\(count)").monospacedDigit()
                    }
                    .foregroundStyle(group.color(palette))
                    .help("\(count) \(group.title.lowercased())")
                }
            }
        }
        .font(.subheadline.weight(.medium))
        .fixedSize()
    }
}

/// The end of the list: how many versions are older, and a chip for each
/// open thread on them, which adds its version's section, so none hides.
private struct OlderFooter: View {
    let model: WindowModel
    let tree: VersionTree

    @Environment(\.palette) private var palette

    var body: some View {
        if !tree.older.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(tree.older.count) older \(tree.older.count == 1 ? "version" : "versions") in All versions")
                    .font(.subheadline)
                    .foregroundStyle(palette[.textTertiary])
                if !tree.stillOpen.isEmpty {
                    HStack(spacing: 6) {
                        Text("Still open:")
                            .font(.subheadline)
                            .foregroundStyle(palette[.textTertiary])
                        ForEach(tree.stillOpen) { thread in
                            if let number = tree.versionOfThread[thread.id] {
                                chip(thread, number: number)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, ThreadRow.padding)
            .padding(.top, 18)
        }
    }

    private func chip(_ thread: ReviewThread, number: Int) -> some View {
        let group = ThreadGroup.of(thread)
        let color = group.color(palette)
        return Button {
            _ = try? model.pickVersion(number)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: group.glyph).imageScale(.small)
                Text("v\(number)").monospacedDigit()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(color.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("#\(thread.number), \(group.title.lowercased()), on v\(number)")
        .accessibilityLabel("#\(thread.number), \(group.title.lowercased()), on v\(number)")
    }
}

extension ThreadGroup {
    /// The group's colour: the state's that it holds.
    func color(_ palette: Palette) -> Color {
        switch self {
        case .needsYou: palette[.question]
        case .withAgent: palette.state(.working)
        case .queued: palette.state(.queued)
        case .done: palette.state(.done)
        }
    }
}
