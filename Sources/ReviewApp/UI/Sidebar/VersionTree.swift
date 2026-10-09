import Foundation
import ReviewCore

/// A project's thread list by version (thread-list V5):
/// General first, then the last three versions as sections, newest first;
/// an older version on screen, and the versions the person picked from
/// "All versions", each under them; and a section for threads whose
/// version left the list. A version with no section is older: its open
/// threads show in the list's footer, so none hides. A plain video's
/// list is by group (`ThreadGroup`) instead.
nonisolated struct VersionTree: Equatable, Sendable {
    /// How many of the newest versions show as sections.
    static let recentCount = 3

    /// One section of the list: a version, or the removed versions.
    struct Section: Equatable, Identifiable {
        enum Kind: Hashable {
            case version(Int)
            case removed
        }

        var kind: Kind
        /// The version's label in `config.toml`; nil with none.
        var label: String?
        /// The threads raised on it, in time order.
        var threads: [ReviewThread]
        /// Whether the version is on screen: its header says so.
        var isOnScreen: Bool
        /// Whether the person picked it from "All versions": its header
        /// has a close button.
        var isPicked: Bool

        var id: Kind { kind }

        /// The version's number; nil for the removed versions.
        var number: Int? {
            if case .version(let number) = kind { return number }
            return nil
        }

        /// The header's name: `V12`, or `REMOVED VERSION`.
        var title: String {
            number.map { "V\($0)" } ?? "REMOVED VERSION"
        }
    }

    /// The project's versions: the outline's, newest first.
    struct Version: Equatable {
        var number: Int
        var label: String?
    }

    /// General, with no section header.
    var general: [ReviewThread]
    var sections: [Section]
    /// Every version, newest first.
    var versions: [Version]
    /// The threads of each version, by number, in time order.
    var threadsByVersion: [Int: [ReviewThread]]
    /// The versions with no section, newest first.
    var older: [Int]
    /// The open threads (not done) on the versions with no section, the
    /// newest version first: the footer's way to each.
    var stillOpen: [ReviewThread]
    /// The number of each still-open thread's version, by thread.
    var versionOfThread: [ThreadID: Int]

    /// `outline` is the project as `config.toml` lists it; `threads` the
    /// review's, General first and in time order; `onScreen` the number of
    /// the version on screen; `picked` the versions picked from the menu,
    /// the latest first. A picked number outside the list is left out.
    init(outline: ProjectOutline, threads: [ReviewThread], onScreen: Int?, picked: [Int]) {
        let count = outline.versions.count
        versions = outline.versions.indices.reversed().map { index in
            Version(number: index + 1, label: outline.versions[index].label.flatMap { $0.isEmpty ? nil : $0 })
        }
        var byVersion: [Int: [ReviewThread]] = [:]
        var removed: [ReviewThread] = []
        var numbers: [ThreadID: Int] = [:]
        general = []
        for thread in threads {
            guard let anchor = thread.anchor else {
                general.append(thread)
                continue
            }
            if let number = outline.number(of: anchor.path) {
                byVersion[number, default: []].append(thread)
                numbers[thread.id] = number
            } else {
                removed.append(thread)
            }
        }
        threadsByVersion = byVersion
        versionOfThread = numbers

        let recent = versions.prefix(Self.recentCount).map(\.number)
        var extra: [Int] = []
        for number in [onScreen].compactMap(\.self) + picked
            where number >= 1 && number <= count && !recent.contains(number) && !extra.contains(number) {
            extra.append(number)
        }
        let labels = Dictionary(uniqueKeysWithValues: versions.map { ($0.number, $0.label) })
        sections = (recent + extra).map { number in
            Section(
                kind: .version(number), label: labels[number] ?? nil, threads: byVersion[number] ?? [],
                isOnScreen: number == onScreen, isPicked: extra.contains(number) && number != onScreen
            )
        }
        if !removed.isEmpty {
            sections.append(Section(kind: .removed, label: nil, threads: removed, isOnScreen: false, isPicked: false))
        }
        let shown = Set(recent + extra)
        older = versions.map(\.number).filter { !shown.contains($0) }
        stillOpen = older.flatMap { number in (byVersion[number] ?? []).filter(Self.isOpen) }
    }

    /// The numbers of the versions with a section, in the list's order.
    var shown: [Int] { sections.compactMap(\.number) }

    /// Whether a thread is open: anything but done (`ThreadGroup`).
    static func isOpen(_ thread: ReviewThread) -> Bool {
        ThreadGroup.of(thread) != .done
    }

    /// The line over the list: `Showing v48 to v50`, then each version
    /// added under them: `Showing v48 to v50, v12`.
    var showing: String {
        let recent = versions.prefix(Self.recentCount).map(\.number)
        guard let newest = recent.first, let oldest = recent.last else { return "Showing no version" }
        var line = newest == oldest ? "Showing v\(newest)" : "Showing v\(oldest) to v\(newest)"
        for number in shown.dropFirst(recent.count) {
            line += ", v\(number)"
        }
        return line
    }
}

/// "All versions", the menu over a project's thread list: a search
/// field, then the versions in the list, the older versions with open
/// threads, and every older version, each newest first.
nonisolated struct AllVersionsMenu: Equatable, Sendable {
    /// One version in the menu: its number, label and threads.
    struct Line: Equatable, Identifiable {
        var number: Int
        var label: String?
        var threads: [ReviewThread]
        var isOnScreen: Bool
        var id: Int { number }
        /// How many of its threads are open.
        var open: Int { threads.count(where: VersionTree.isOpen) }
    }

    var inList: [Line]
    var stillOpen: [Line]
    var older: [Line]

    init(tree: VersionTree, query: String) {
        let onScreen = tree.sections.first(where: \.isOnScreen)?.number
        let shown = Set(tree.shown)
        let lines = tree.versions.filter { Self.matches($0, query: query) }.map { version in
            Line(
                number: version.number, label: version.label, threads: tree.threadsByVersion[version.number] ?? [],
                isOnScreen: version.number == onScreen
            )
        }
        inList = lines.filter { shown.contains($0.number) }
        older = lines.filter { !shown.contains($0.number) }
        stillOpen = older.filter { $0.open > 0 }
    }

    /// Whether no version matches the search.
    var isEmpty: Bool { inList.isEmpty && older.isEmpty }

    /// Whether `version` matches the search: a number, with or without
    /// `v`, matches the numbers it starts; other words match the label.
    static func matches(_ version: VersionTree.Version, query: String) -> Bool {
        let words = query.trimmingCharacters(in: .whitespaces).lowercased()
        if words.isEmpty { return true }
        let digits = words.hasPrefix("v") ? String(words.dropFirst()) : words
        if !digits.isEmpty, digits.allSatisfy(\.isNumber) { return String(version.number).hasPrefix(digits) }
        return version.label?.lowercased().contains(words) ?? false
    }
}
