import Foundation
import ReviewCore

nonisolated struct VersionTree: Equatable, Sendable {
    static let recentCount = 3

    struct Section: Equatable, Identifiable {
        enum Kind: Hashable {
            case version(Int)
            case removed
        }

        var kind: Kind
        var label: String?
        var threads: [ReviewThread]
        var isOnScreen: Bool
        var isPicked: Bool

        var id: Kind { kind }

        var number: Int? {
            if case .version(let number) = kind { return number }
            return nil
        }

        var title: String {
            number.map { "V\($0)" } ?? "REMOVED VERSION"
        }
    }

    struct Version: Equatable {
        var number: Int
        var label: String?
    }

    var general: [ReviewThread]
    var sections: [Section]
    var versions: [Version]
    var threadsByVersion: [Int: [ReviewThread]]
    var older: [Int]
    var stillOpen: [ReviewThread]
    var versionOfThread: [ThreadID: Int]

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

    var shown: [Int] { sections.compactMap(\.number) }

    static func isOpen(_ thread: ReviewThread) -> Bool {
        ThreadGroup.of(thread) != .done
    }

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

nonisolated struct AllVersionsMenu: Equatable, Sendable {
    struct Line: Equatable, Identifiable {
        var number: Int
        var label: String?
        var threads: [ReviewThread]
        var isOnScreen: Bool
        var id: Int { number }
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

    var isEmpty: Bool { inList.isEmpty && older.isEmpty }

    static func matches(_ version: VersionTree.Version, query: String) -> Bool {
        let words = query.trimmingCharacters(in: .whitespaces).lowercased()
        if words.isEmpty { return true }
        let digits = words.hasPrefix("v") ? String(words.dropFirst()) : words
        if !digits.isEmpty, digits.allSatisfy(\.isNumber) { return String(version.number).hasPrefix(digits) }
        return version.label?.lowercased().contains(words) ?? false
    }
}
