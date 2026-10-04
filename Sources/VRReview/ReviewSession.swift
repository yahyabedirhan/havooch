import Foundation

/// Why a review won't do what was asked, as one line.
public struct ReviewRefusal: Error, Equatable, Sendable {
    public var reason: String

    public init(_ reason: String) {
        self.reason = reason
    }
}

/// One video's review: its comments, the batches they were sent in and the
/// threads on both, and every change to them. The rules about a comment's
/// state and about questions and answers live here, so the window and the
/// command line are refused the same things in the same words.
public struct ReviewSession: Codable, Equatable, Sendable {
    public var video: VideoInfo
    /// Every comment of the video, drafts included, in time order; comments
    /// at the same time keep the order they were made in.
    public private(set) var comments: [Comment] = []
    /// The batches sent from this video, oldest first.
    public private(set) var batches: [Batch] = []
    /// The person's note about the video, part of its context for the
    /// listener; empty when there's none.
    public private(set) var note = ""

    /// The comments whose last answer no `ask` has been given yet: the
    /// question's `ask` had run out of time, or its reply didn't arrive.
    public private(set) var unheard: Set<String> = []

    /// A question and the answer the person gave to it.
    public struct Exchange: Equatable, Sendable {
        public var question: ThreadMessage
        public var answer: ThreadMessage

        public init(question: ThreadMessage, answer: ThreadMessage) {
            self.question = question
            self.answer = answer
        }
    }

    /// Where a reply went: the thread of a comment, or of a batch.
    public enum Place: Equatable, Sendable {
        case comment(String)
        case batch(String)
    }

    public init(video: VideoInfo) {
        self.video = video
    }

    /// A review kept before anything was sent has no batches, and one kept
    /// before a note was written has no note.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        video = try container.decode(VideoInfo.self, forKey: .video)
        comments = try container.decode([Comment].self, forKey: .comments)
        batches = try container.decodeIfPresent([Batch].self, forKey: .batches) ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        unheard = try container.decodeIfPresent(Set<String>.self, forKey: .unheard) ?? []
    }

    /// The review as the store keeps it: a draft isn't kept, so a comment
    /// box left open when the app quit leaves nothing behind.
    public var kept: ReviewSession {
        var kept = self
        kept.comments.removeAll { $0.state == .draft }
        return kept
    }

    /// The comments waiting to be sent, in time order.
    public var queue: [Comment] {
        comments.filter { $0.state == .queued }
    }

    public func comment(_ id: String) -> Comment? {
        comments.first { $0.id == id }
    }

    public func batch(_ id: String) -> Batch? {
        batches.first { $0.id == id }
    }

    /// Whether every comment of the batch `batchID` is done or failed.
    public func isFinished(_ batchID: String) -> Bool {
        comments.filter { $0.batchID == batchID }.allSatisfy(\.state.isFinal)
    }

    /// The question on the comment `id` the person hasn't answered, or nil.
    public func openQuestion(on id: String) -> ThreadMessage? {
        comment(id)?.openQuestion
    }

    /// The last answer on the comment `id` with its question, when no `ask`
    /// has been given it yet; else nil.
    public func unheardAnswer(on id: String) -> Exchange? {
        guard unheard.contains(id), let thread = comment(id)?.thread,
              let answer = thread.lastIndex(where: { $0.kind == .answer }),
              let question = thread[..<answer].last(where: { $0.kind == .question }) else { return nil }
        return Exchange(question: question, answer: thread[answer])
    }

    // MARK: - Changes

    /// Replaces the note, without the white space around it. An empty text
    /// takes the note away.
    public mutating func setNote(_ text: String) {
        note = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Starts a comment at `time`, on `region` of the frame when one was
    /// drawn: a draft, with no text yet.
    @discardableResult
    public mutating func draft(id: String, time: Double, region: Region? = nil) -> Comment {
        let comment = Comment(id: id, time: time, region: region)
        let index = comments.firstIndex { $0.time > time } ?? comments.endIndex
        comments.insert(comment, at: index)
        return comment
    }

    /// Gives a draft its text and puts it in the queue.
    public mutating func commit(_ id: String, text: String) throws(ReviewRefusal) {
        let index = try index(of: id)
        guard comments[index].state.canMove(to: .queued) else {
            throw ReviewRefusal("\(id) isn't a draft; it's \(comments[index].state.rawValue)")
        }
        comments[index].text = try Self.written(text)
        comments[index].state = .queued
    }

    /// Drops a draft that was never queued.
    public mutating func discard(_ id: String) throws(ReviewRefusal) {
        let index = try index(of: id)
        guard comments[index].state == .draft else {
            throw ReviewRefusal("\(id) isn't a draft; it's \(comments[index].state.rawValue)")
        }
        comments.remove(at: index)
    }

    /// Replaces a queued comment's text. A comment that was sent stays as
    /// the agent got it.
    public mutating func edit(_ id: String, text: String) throws(ReviewRefusal) {
        let index = try queued(id, toBe: "edited")
        comments[index].text = try Self.written(text)
    }

    /// Takes a queued comment out of the review.
    public mutating func delete(_ id: String) throws(ReviewRefusal) {
        comments.remove(at: try queued(id, toBe: "deleted"))
    }

    /// Sends every queued comment as one batch: each is `sent`, and names
    /// the batch. Refused with nothing queued.
    public mutating func send(batchID: String, at now: Date) throws(ReviewRefusal) -> Batch {
        let ids = queue.map(\.id)
        guard !ids.isEmpty else {
            throw ReviewRefusal("there's nothing to send: no comment is queued")
        }
        for index in comments.indices where comments[index].state == .queued {
            comments[index].state = .sent
            comments[index].batchID = batchID
        }
        let batch = Batch(id: batchID, sentAt: now, commentIDs: ids)
        batches.append(batch)
        return batch
    }

    /// The batch goes to another listener: its comments a listener had
    /// acknowledged or started go back to `sent`, the one move backward.
    /// Those done or failed stay.
    public mutating func requeue(_ batchID: String) {
        for index in comments.indices where comments[index].batchID == batchID {
            let state = comments[index].state
            if state != .sent, state.canMove(to: .sent) { comments[index].state = .sent }
        }
    }

    // MARK: - What the listener does

    /// The listener has the batch: each of its comments still `sent` is
    /// `acknowledged`. `text`, when given, is a message for the full batch.
    /// Acknowledging again changes no state.
    public mutating func acknowledge(_ batchID: String, text: String? = nil, at now: Date) throws(ReviewRefusal) {
        let batch = try batchIndex(of: batchID)
        var message: String?
        if let text { message = try Self.said(text) }
        for index in comments.indices where comments[index].batchID == batchID && comments[index].state == .sent {
            comments[index].state = .acknowledged
        }
        if let message {
            batches[batch].thread.append(ThreadMessage(author: .agent, kind: .message, text: message, at: now))
        }
    }

    /// Sets a sent comment to `working`, `done` or `failed`. A status may
    /// skip forward (`sent` to `done`); `done` and `failed` are final. The
    /// state it already has is set again without a change.
    public mutating func setStatus(_ id: String, to state: CommentState) throws(ReviewRefusal) {
        guard state == .working || state.isFinal else {
            throw ReviewRefusal("a comment's status is working, done or failed, not \(state.rawValue)")
        }
        let index = try sent(id, toBe: "given a status")
        let current = comments[index].state
        guard current != state else { return }
        guard current.canMove(to: state) else {
            throw ReviewRefusal("\(id) is \(current.rawValue); it can't be set to \(state.rawValue)")
        }
        comments[index].state = state
    }

    /// Adds the agent's message to the thread of the comment or the batch
    /// `id`, and says which it was.
    @discardableResult
    public mutating func reply(to id: String, text: String, at now: Date) throws(ReviewRefusal) -> Place {
        let message = ThreadMessage(author: .agent, kind: .message, text: try Self.said(text), at: now)
        if let batch = batches.firstIndex(where: { $0.id == id }) {
            batches[batch].thread.append(message)
            return .batch(id)
        }
        guard comments.contains(where: { $0.id == id }) else {
            throw ReviewRefusal("there's no comment or batch \(id)")
        }
        comments[try sent(id, toBe: "replied on")].thread.append(message)
        return .comment(id)
    }

    /// Adds the agent's question to the thread of the comment `id`. One
    /// question at a time: while one is open, another is refused. The open
    /// question asked again in the same words is the same question, and
    /// adds nothing.
    public mutating func ask(_ id: String, question: String, at now: Date) throws(ReviewRefusal) {
        let text = try Self.said(question)
        let index = try sent(id, toBe: "asked about")
        if let open = openQuestion(on: id) {
            guard open.text == text else {
                throw ReviewRefusal("\(id) has a question the person hasn't answered: \(open.text)")
            }
            return
        }
        comments[index].thread.append(ThreadMessage(author: .agent, kind: .question, text: text, at: now))
    }

    /// Adds the person's answer to the open question on the comment `id`.
    /// The answer waits for an `ask` to be given to (`unheardAnswer`).
    public mutating func answer(_ id: String, text: String, at now: Date) throws(ReviewRefusal) {
        let index = try index(of: id)
        let text = try Self.said(text)
        guard openQuestion(on: id) != nil else {
            throw ReviewRefusal("\(id) has no question to answer")
        }
        comments[index].thread.append(ThreadMessage(author: .person, kind: .answer, text: text, at: now))
        unheard.insert(id)
    }

    /// The answer on the comment `id` reached an `ask`: it isn't given again.
    public mutating func answerHeard(_ id: String) {
        unheard.remove(id)
    }

    // MARK: - Rules

    /// A comment's text as it's kept: without the space around it, and not
    /// empty.
    public static func written(_ text: String) throws(ReviewRefusal) -> String {
        let kept = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kept.isEmpty else { throw ReviewRefusal("a comment needs its text") }
        return kept
    }

    /// A thread message's text as it's kept: without the space around it,
    /// and not empty.
    public static func said(_ text: String) throws(ReviewRefusal) -> String {
        let kept = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kept.isEmpty else { throw ReviewRefusal("a message needs its text") }
        return kept
    }

    private func batchIndex(of id: String) throws(ReviewRefusal) -> Int {
        guard let index = batches.firstIndex(where: { $0.id == id }) else {
            throw ReviewRefusal("there's no batch \(id)")
        }
        return index
    }

    /// The place of the comment `id`, which a listener has or had; refused
    /// for one that wasn't sent.
    private func sent(_ id: String, toBe change: String) throws(ReviewRefusal) -> Int {
        let index = try index(of: id)
        switch comments[index].state {
        case .draft, .queued:
            throw ReviewRefusal("\(id) wasn't sent yet; it can't be \(change)")
        case .sent, .acknowledged, .working, .done, .failed:
            return index
        }
    }

    private func index(of id: String) throws(ReviewRefusal) -> Int {
        guard let index = comments.firstIndex(where: { $0.id == id }) else {
            throw ReviewRefusal("there's no comment \(id)")
        }
        return index
    }

    /// The place of the queued comment `id`; refused for a draft, and for a
    /// comment that was sent.
    private func queued(_ id: String, toBe change: String) throws(ReviewRefusal) -> Int {
        let index = try index(of: id)
        switch comments[index].state {
        case .queued:
            return index
        case .draft:
            throw ReviewRefusal("\(id) is still being written; it can't be \(change)")
        case .sent, .acknowledged, .working, .done, .failed:
            throw ReviewRefusal("\(id) was sent; it can't be \(change)")
        }
    }
}
