import LabHost
import SwiftUI

/// V2's sections by version, for a project of 50 versions: General and the
/// last three versions as sections, and an "All versions" control over the
/// list that opens a menu of every version, newest first, with a search
/// field and each version's open threads. Picking a recent version scrolls
/// to its section; picking an older one adds its section under the recent
/// ones until it is closed.
public let variant = LabVariant {
    HStack(alignment: .top, spacing: 24) {
        Captioned("Default: the last three versions") {
            SidebarSurface { JumpMenuList() }
        }
        Captioned("All versions ▾ open") {
            SidebarSurface { JumpMenuList(menuOpen: true) }
        }
        Captioned("v12 picked from the menu") {
            SidebarSurface { JumpMenuList(jumped: [12], scrollTo: "v-12") }
        }
    }
    .padding(16)
}

struct Captioned<Content: View>: View {
    let caption: String
    @ViewBuilder var content: Content

    init(_ caption: String, @ViewBuilder content: () -> Content) {
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        }
    }
}

struct JumpMenuList: View {
    @State var menuOpen = false
    /// Older versions picked from the menu, shown under the recent ones.
    @State var jumped: [Int] = []
    var scrollTo: String?
    @State private var query = ""
    @State private var target: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListHeading(summary: Summary.text)
            JumpBar(menuOpen: $menuOpen)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        SectionRows(origin: .project, rows: Fixture.rows(.project))
                        ForEach(Fixture.recent) { version in
                            section(version.number, closable: false)
                        }
                        ForEach(jumped, id: \.self) { number in
                            section(number, closable: true)
                        }
                        OlderFooter { pick($0) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .onAppear {
                    guard let scrollTo else { return }
                    for delay in [0.15, 0.5] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            proxy.scrollTo(scrollTo, anchor: .top)
                        }
                    }
                }
                .onChange(of: target) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(id, anchor: .top) }
                    target = nil
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if menuOpen {
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(0.001)
                        .onTapGesture { menuOpen = false }
                    VersionMenu(query: $query) { pick($0) }
                        .padding(.top, 86)
                        .padding(.trailing, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ number: Int, closable: Bool) -> some View {
        let origin = Origin.version(number)
        Section {
            SectionRows(origin: origin, rows: Fixture.rows(origin))
            if Fixture.rows(origin).isEmpty {
                Text("No threads on \(Fixture.version(number)?.name ?? "")")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, ThreadRowView.padding)
                    .padding(.vertical, 8)
            }
        } header: {
            VersionHeader(origin: origin, rows: Fixture.rows(origin)) {
                if closable {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { jumped.removeAll { $0 == number } }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove v\(number) from the list")
                    .labID("close-v\(number)")
                }
            }
        }
        .id("v-\(number)")
    }

    private func pick(_ number: Int) {
        menuOpen = false
        query = ""
        let isRecent = Fixture.recent.contains { $0.number == number }
        if !isRecent, !jumped.contains(number) {
            withAnimation(.snappy(duration: 0.22)) { jumped.insert(number, at: 0) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { target = "v-\(number)" }
    }
}

/// The bar over the list: what it shows, and the menu of every version.
struct JumpBar: View {
    @Binding var menuOpen: Bool
    @State private var isHovered = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Pal(dark: scheme == .dark)
        let recent = Fixture.recent
        HStack(spacing: 6) {
            Text("Showing v\(recent.last!.number)–v\(recent.first!.number)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(pal.textTertiary)
            Spacer(minLength: 4)
            Button {
                menuOpen.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack").imageScale(.small)
                    Text("All versions")
                    let open = Fixture.olderOpen.count
                    if open > 0 {
                        Text("\(open)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(pal.question)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(pal.question.opacity(0.16), in: Capsule())
                            .help("\(open) open threads on older versions")
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(pal.textTertiary)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(pal.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(menuOpen || isHovered ? pal.controlHover : pal.well,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(pal.separator, lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("Jump to any version")
            .labID("all-versions")
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}

/// The menu: a search field and every version, newest first.
struct VersionMenu: View {
    @Binding var query: String
    let pick: (Int) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Pal(dark: scheme == .dark)
        let shown = Fixture.versions.filter(matches)
        let recent = shown.filter { v in Fixture.recent.contains { $0.number == v.number } }
        let older = shown.filter { v in !Fixture.recent.contains { $0.number == v.number } }
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").imageScale(.small).foregroundStyle(pal.textTertiary)
                TextField("Jump to v… or a label", text: $query)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .labID("jump-search")
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(pal.well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(pal.separator, lineWidth: 0.5))
            .padding(8)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !recent.isEmpty {
                        groupTitle("IN THE LIST", pal)
                        ForEach(recent) { MenuLine(version: $0) { pick($0) } }
                    }
                    let stillOpen = older.filter { Fixture.openCount($0.number) > 0 }
                    if !stillOpen.isEmpty {
                        groupTitle("STILL OPEN ON OLDER VERSIONS", pal)
                        ForEach(stillOpen) { MenuLine(version: $0) { pick($0) } }
                    }
                    if !older.isEmpty {
                        groupTitle("OLDER · \(older.count)", pal)
                        ForEach(older) { MenuLine(version: $0) { pick($0) } }
                    }
                    if shown.isEmpty {
                        Text("No version matches")
                            .font(.callout)
                            .foregroundStyle(pal.textTertiary)
                            .padding(12)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.bottom, 6)
            }
        }
        .frame(width: 300)
        .frame(maxHeight: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(pal.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .labID("version-menu")
    }

    private func groupTitle(_ text: String, _ pal: Pal) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(0.2)
            .foregroundStyle(pal.textTertiary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }

    private func matches(_ version: Version) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        let digits = q.hasPrefix("v") ? String(q.dropFirst()) : q
        if !digits.isEmpty, digits.allSatisfy(\.isNumber) { return String(version.number).hasPrefix(digits) }
        return version.label.lowercased().contains(q)
    }
}

/// One version in the menu: number, label, open threads, thread count.
struct MenuLine: View {
    let version: Version
    let action: (Int) -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Pal(dark: scheme == .dark)
        let rows = Fixture.rows(.version(version.number))
        let open = rows.filter { $0.group != .done }
        let isCurrent = version.number == Fixture.current
        Button { action(version.number) } label: {
            HStack(spacing: 6) {
                Text(version.name)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(rows.isEmpty ? pal.textTertiary : (isCurrent ? pal.accent : pal.textPrimary))
                    .frame(width: 30, alignment: .leading)
                Text(version.label)
                    .font(.callout)
                    .foregroundStyle(rows.isEmpty ? pal.textTertiary : pal.textSecondary)
                    .lineLimit(1)
                if isCurrent {
                    Image(systemName: "play.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(pal.accent)
                        .help("On screen")
                }
                Spacer(minLength: 4)
                if !open.isEmpty { StateCounts(rows: open) }
                Text(rows.isEmpty ? "–" : "\(rows.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(pal.textTertiary)
                    .frame(width: 18, alignment: .trailing)
                    .help(rows.count == 1 ? "1 thread" : "\(rows.count) threads")
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(isHovered ? pal.controlHover : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .labID("jump-\(version.name)")
    }
}

/// The end of the list: how many versions are older, and a way to each
/// open thread on them, so none hides.
struct OlderFooter: View {
    let pick: (Int) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Pal(dark: scheme == .dark)
        let open = Fixture.olderOpen
        VStack(alignment: .leading, spacing: 6) {
            Text("\(Fixture.older.count) older versions in All versions ▾")
                .font(.subheadline)
                .foregroundStyle(pal.textTertiary)
            if !open.isEmpty {
                HStack(spacing: 6) {
                    Text("Still open:")
                        .font(.subheadline)
                        .foregroundStyle(pal.textTertiary)
                    ForEach(open) { thread in
                        if case .version(let n) = thread.origin {
                            Button { pick(n) } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: thread.group.glyph).imageScale(.small)
                                    Text("v\(n)").monospacedDigit()
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(thread.group.color(pal))
                                .padding(.horizontal, 6)
                                .frame(height: 20)
                                .background(thread.group.color(pal).opacity(0.12), in: Capsule())
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("#\(thread.number), \(thread.group.title.lowercased()), on v\(n)")
                            .labID("open-v\(n)")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, ThreadRowView.padding)
        .padding(.top, 18)
    }
}
