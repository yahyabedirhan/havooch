import ReviewCore
import ReviewWire

struct ComposerTarget: Equatable {
    enum Kind: Equatable {
        case newThread
        case reply
        case followUp
        case answer

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
    var thread: ThreadID?
    var number: Int
    var time: Double?
    var takesRegion: Bool

    enum DraftKey: Hashable {
        case thread(ThreadID)
        case newThread
    }

    var draftKey: DraftKey { thread.map(DraftKey.thread) ?? .newThread }

    var isGeneral: Bool { thread != nil && time == nil }

    var answers: Bool { kind == .answer }

    static func resolve(
        shown: ReviewThread?, general: ReviewThread?, atFrame: ReviewThread?, frame: Double, nextNumber: Int,
        regionTime: Double?
    ) -> ComposerTarget {
        let thread = shown ?? general ?? atFrame
        let time = thread.map(\.time) ?? frame
        let regionFits = regionTime != nil && time != nil && regionTime == time
        guard let thread else {
            return ComposerTarget(kind: .newThread, thread: nil, number: nextNumber, time: frame, takesRegion: regionFits)
        }
        if thread.openQuestion != nil, !regionFits {
            return ComposerTarget(kind: .answer, thread: thread.id, number: thread.number, time: time, takesRegion: false)
        }
        return ComposerTarget(
            kind: shown == nil ? .reply : .followUp, thread: thread.id, number: thread.number, time: time,
            takesRegion: regionFits
        )
    }

    var name: String { isGeneral ? "General" : "#\(number)" }

    var label: String {
        switch kind {
        case .newThread: "New thread at \(TimeCode.text((time ?? 0).rounded(.down)))"
        case .reply: "Reply on \(name)"
        case .followUp: "Follow up on \(name)"
        case .answer: "Answer \(name)"
        }
    }

    var note: String? { answers ? "goes at once" : nil }

    var line: String { note.map { "\(label) · \($0)" } ?? label }

    static func atMoment(_ frame: Double) -> String {
        "At \(TimeCode.text(frame.rounded(.down)))"
    }

    var placeholder: String {
        switch kind {
        case .newThread: "Comment on \(TimeCode.text((time ?? 0).rounded(.down)))…"
        case .reply, .followUp: isGeneral ? "Write to the agent…" : "Message \(name)…"
        case .answer: "Type your answer…"
        }
    }

    var toolbarLabel: String {
        switch kind {
        case .newThread: label
        case .reply, .followUp: isGeneral ? "General thread" : name
        case .answer: "Answer \(name), goes at once"
        }
    }

    var glyph: String {
        switch kind {
        case .newThread: "plus.bubble"
        case .reply, .followUp: isGeneral ? "globe" : "text.bubble"
        case .answer: "questionmark.circle.fill"
        }
    }
}
