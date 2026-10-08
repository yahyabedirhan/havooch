import ReviewCore
import ReviewWire

/// Where the words of the composer at the foot of the sidebar go (L41).
/// In a thread view: a follow-up on the thread shown, or the answer to its
/// open question. In the thread list: the thread of the frame on the stage,
/// a new thread on that frame, or General with the General toggle on.
struct ComposerTarget: Equatable {
    enum Kind: Equatable {
        /// A new thread on the frame on the stage.
        case newThread
        /// From the thread list, on the thread of the frame on the stage, or on General.
        case reply
        /// From a thread view, on the thread shown.
        case followUp
        /// The answer to the thread's open question: it goes at once (D 2.16).
        case answer

        /// The kind as `state` names it.
        var name: String {
            switch self {
            case .newThread: "new"
            case .reply: "reply"
            case .followUp: "follow-up"
            case .answer: "answer"
            }
        }
    }

    var kind: Kind
    /// The thread the words go on; nil for a new thread.
    var thread: ThreadID?
    /// The thread's number, or the number a new thread will take.
    var number: Int
    /// The frame the words are on; nil for General.
    var time: Double?
    /// Whether a drawn region goes with the words: the region is on the
    /// target's frame, and the words are no answer.
    var takesRegion: Bool

    /// The key of the target's draft: one per thread, and one for a new
    /// thread wherever the playhead is.
    enum DraftKey: Hashable {
        case thread(ThreadID)
        case newThread
    }

    var draftKey: DraftKey { thread.map(DraftKey.thread) ?? .newThread }

    var isGeneral: Bool { thread != nil && time == nil }

    /// Whether the words go at once, not into the queue.
    var answers: Bool { kind == .answer }

    /// The target as the composer resolves it.
    /// - `shown`: the thread the sidebar shows; nil in the thread list.
    /// - `general`: General, when the General toggle is on in the list.
    /// - `atFrame`: the thread of the frame on the stage, if it has one.
    /// - `frame`: the frame on the stage.
    /// - `regionTime`: the frame of the drawn region, if there is one.
    static func resolve(
        shown: ReviewThread?, general: ReviewThread?, atFrame: ReviewThread?, frame: Double, nextNumber: Int,
        regionTime: Double?
    ) -> ComposerTarget {
        let thread = shown ?? general ?? atFrame
        let time = thread.map(\.time) ?? frame
        // A region is on one frame; General has none, and an answer takes no region.
        let regionFits = regionTime != nil && time != nil && regionTime == time
        guard let thread else {
            return ComposerTarget(kind: .newThread, thread: nil, number: nextNumber, time: frame, takesRegion: regionFits)
        }
        // A drawn region makes the words a message on the frame, not an answer.
        if thread.openQuestion != nil, !regionFits {
            return ComposerTarget(kind: .answer, thread: thread.id, number: thread.number, time: time, takesRegion: false)
        }
        return ComposerTarget(
            kind: shown == nil ? .reply : .followUp, thread: thread.id, number: thread.number, time: time,
            takesRegion: regionFits
        )
    }

    /// The thread's name: `#3`, or General.
    var name: String { isGeneral ? "General" : "#\(number)" }

    /// What the words do, and where they go, as `state` reports it and
    /// the toolbar's label shows on hover.
    var label: String {
        switch kind {
        case .newThread: "New thread at \(TimeCode.text((time ?? 0).rounded(.down)))"
        case .reply: "Reply on \(name)"
        case .followUp: "Follow up on \(name)"
        case .answer: "Answer \(name)"
        }
    }

    /// Said after the label: an answer skips the queue.
    var note: String? { answers ? "goes at once" : nil }

    /// The label with its note, as one line: "Answer #3 · goes at once".
    var line: String { note.map { "\(label) · \($0)" } ?? label }

    /// The words in the empty field.
    var placeholder: String {
        switch kind {
        case .newThread: "Comment on \(TimeCode.text((time ?? 0).rounded(.down)))…"
        case .reply, .followUp: isGeneral ? "Write to the agent…" : "Message \(name)…"
        case .answer: "Type your answer…"
        }
    }

    /// The quiet label in the composer's toolbar: "New thread at 0:12",
    /// "#3", "General thread", or "Answer #3, goes at once".
    var toolbarLabel: String {
        switch kind {
        case .newThread: label
        case .reply, .followUp: isGeneral ? "General thread" : name
        case .answer: "Answer \(name), goes at once"
        }
    }

    /// The SF Symbol before the label.
    var glyph: String {
        switch kind {
        case .newThread: "plus.bubble"
        case .reply, .followUp: isGeneral ? "globe" : "text.bubble"
        case .answer: "questionmark.circle.fill"
        }
    }
}
