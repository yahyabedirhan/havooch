import Foundation
import ReviewCore

nonisolated enum ThreadGroup: CaseIterable, Equatable, Sendable {
    case needsYou
    case withAgent
    case queued
    case done

    struct Section: Equatable, Identifiable {
        var group: ThreadGroup
        var threads: [ReviewThread]
        var id: ThreadGroup { group }
    }

    static func of(_ thread: ReviewThread) -> ThreadGroup {
        if thread.openQuestion != nil { return .needsYou }
        let states = thread.messages.filter(\.isWork).compactMap(\.state)
        if states.contains(where: { $0 == .sent || $0 == .acknowledged || $0 == .working }) { return .withAgent }
        if states.contains(.queued) { return .queued }
        return .done
    }

    static func sections(of threads: [ReviewThread]) -> [Section] {
        let grouped = Dictionary(grouping: threads, by: of)
        return allCases.compactMap { group in
            grouped[group].map { Section(group: group, threads: $0) }
        }
    }

    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .withAgent: "With agent"
        case .queued: "Queued"
        case .done: "Done"
        }
    }

    var hint: String? {
        self == .queued ? "⌘↩ sends them all" : nil
    }

    @MainActor var glyph: String {
        switch self {
        case .needsYou: "questionmark.circle.fill"
        case .withAgent: StateLook.glyph(.working)
        case .queued: StateLook.glyph(.queued)
        case .done: StateLook.glyph(.done)
        }
    }
}

enum ThreadListSummary {
    static func line(threads: [ReviewThread], queued: Int, versions: Int? = nil) -> String {
        let needs = threads.filter { $0.openQuestion != nil }.count
        var parts = ["\(threads.count) \(threads.count == 1 ? "thread" : "threads")"]
        if let versions, versions > 0 { parts.append("\(versions) \(versions == 1 ? "version" : "versions")") }
        if needs > 0 { parts.append("\(needs) \(needs == 1 ? "needs" : "need") you") }
        if queued > 0 { parts.append("\(queued) queued") }
        return parts.joined(separator: " · ")
    }
}
