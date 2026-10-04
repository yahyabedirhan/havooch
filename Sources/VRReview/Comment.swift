/// Where a comment is on its way from the person to the agent's answer. A
/// comment moves only forward, except for a requeue: a batch a listener took
/// and didn't finish goes back to `sent` for the next listener.
///
///     draft → queued → sent → acknowledged → working → done | failed
public enum CommentState: String, Codable, Equatable, Sendable, CaseIterable {
    /// Being written: it has its time and its frame, not yet its text.
    case draft
    /// Written, waiting in the queue to be sent.
    case queued
    case sent
    case acknowledged
    case working
    case done
    case failed

    /// `done` and `failed` end a comment: nothing moves it again.
    public var isFinal: Bool {
        self == .done || self == .failed
    }

    /// Whether a comment in this state may move to `next`. A listener's
    /// status (`working`, `done`, `failed`) may skip forward from any sent
    /// state; `acknowledged` and `working` may go back to `sent`, the
    /// requeue.
    public func canMove(to next: CommentState) -> Bool {
        switch (self, next) {
        case (.draft, .queued), (.queued, .sent), (.sent, .acknowledged):
            true
        case (.sent, .working), (.sent, .done), (.sent, .failed),
             (.acknowledged, .working), (.acknowledged, .done), (.acknowledged, .failed),
             (.working, .done), (.working, .failed):
            true
        case (.acknowledged, .sent), (.working, .sent):
            true
        default:
            false
        }
    }
}

/// One piece of feedback: a time in the video, what the person wrote about
/// it, the part of the frame it points at when the person drew one, and
/// where it is on its way. Its keyframe and its region's crop are files the
/// store names by the comment's id.
public struct Comment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /// In seconds, to the millisecond.
    public var time: Double
    public var text: String
    /// The rectangle drawn on the frame, or nil for a comment on the whole
    /// frame.
    public var region: Region?
    public var state: CommentState
    /// The batch it was sent in, or nil while it wasn't sent.
    public var batchID: String?
    /// What the agent wrote on this comment and what the person answered,
    /// oldest first.
    public var thread: [ThreadMessage]

    public init(
        id: String, time: Double, text: String = "", region: Region? = nil, state: CommentState = .draft, batchID: String? = nil,
        thread: [ThreadMessage] = []
    ) {
        self.id = id
        self.time = time
        self.text = text
        self.region = region
        self.state = state
        self.batchID = batchID
        self.thread = thread
    }

    /// The agent's question the person hasn't answered, or nil: the last
    /// question, while no answer follows it.
    public var openQuestion: ThreadMessage? {
        guard let last = thread.last(where: { $0.kind != .message }), last.kind == .question else { return nil }
        return last
    }

    /// A comment kept before it had a thread has none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        time = try container.decode(Double.self, forKey: .time)
        text = try container.decode(String.self, forKey: .text)
        region = try container.decodeIfPresent(Region.self, forKey: .region)
        state = try container.decode(CommentState.self, forKey: .state)
        batchID = try container.decodeIfPresent(String.self, forKey: .batchID)
        thread = try container.decodeIfPresent([ThreadMessage].self, forKey: .thread) ?? []
    }
}
