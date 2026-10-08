import Foundation
import ReviewCore

/// The thread list's groups (L38), by who must act next, in this order. A
/// thread is in the first group it matches.
nonisolated enum ThreadGroup: CaseIterable, Equatable, Sendable {
    /// The agent asked a question that waits for the person's answer.
    case needsYou
    /// A message is sent, acknowledged or being worked on.
    case withAgent
    /// A message waits in the queue.
    case queued
    /// Everything else: every message done or failed, or no message of
    /// the person's yet (General with nothing on it).
    case done

    /// One group of the list with its threads, in time order.
    struct Section: Equatable, Identifiable {
        var group: ThreadGroup
        var threads: [ReviewThread]
        var id: ThreadGroup { group }
    }

    /// The group `thread` is in.
    static func of(_ thread: ReviewThread) -> ThreadGroup {
        if thread.openQuestion != nil { return .needsYou }
        let states = thread.messages.filter(\.isWork).compactMap(\.state)
        if states.contains(where: { $0 == .sent || $0 == .acknowledged || $0 == .working }) { return .withAgent }
        if states.contains(.queued) { return .queued }
        return .done
    }

    /// `threads` (General first, then in time order) in their groups, in
    /// the groups' order; a group with no thread is left out. Each group
    /// keeps the order it is given.
    static func sections(of threads: [ReviewThread]) -> [Section] {
        let grouped = Dictionary(grouping: threads, by: of)
        return allCases.compactMap { group in
            grouped[group].map { Section(group: group, threads: $0) }
        }
    }

    /// The group's header.
    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .withAgent: "With agent"
        case .queued: "Queued"
        case .done: "Done"
        }
    }

    /// The words at the trailing end of the header: Queued's reminder of
    /// how to send.
    var hint: String? {
        self == .queued ? "⌘↩ sends them all" : nil
    }

    /// The header's glyph, an SF Symbol, the state's that the group holds.
    @MainActor var glyph: String {
        switch self {
        case .needsYou: "questionmark.circle.fill"
        case .withAgent: StateLook.glyph(.working)
        case .queued: StateLook.glyph(.queued)
        case .done: StateLook.glyph(.done)
        }
    }
}

/// The line under the thread list's title (L38): how many threads, in a
/// project how many versions (E9), how many need the person and how many
/// messages are queued: `6 threads · 3 versions · 1 needs you · 2 queued`.
/// A count of none is left out.
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
