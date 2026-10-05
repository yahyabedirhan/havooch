import Foundation

/// The video a review is about. Its identity is the hash of its content, so
/// a renamed or moved file is the same video.
public struct VideoInfo: Codable, Equatable, Sendable {
    public var contentHash: String
    /// The file's name with its extension, as the header shows it.
    public var title: String
    /// The length in seconds.
    public var duration: TimeInterval
    /// Where the file was when it was last opened.
    public var path: String
    /// Frames a second, as the player read it when the video was last
    /// opened; nil before it was. A `voiceover.json`'s scene times need it,
    /// also for a send that's delivered in a run that didn't open the video.
    public var frameRate: Double?

    public init(contentHash: String, title: String, duration: TimeInterval, path: String, frameRate: Double? = nil) {
        self.contentHash = contentHash
        self.title = title
        self.duration = duration
        self.path = path
        self.frameRate = frameRate
    }
}

/// Everything kept about one video, and every rule about its threads,
/// messages and sends. The review makes every id from its own counters,
/// which never give a number twice, so a test knows its ids.
public struct VideoReview: Codable, Equatable, Sendable {
    public var video: VideoInfo
    /// The person's context note for the agent, added to the sidecar's
    /// text; empty for none.
    public var note = ""
    /// General first, then the threads in time order.
    public private(set) var threads: [ReviewThread]
    /// The sends, in the order they were sent.
    public private(set) var sends: [Send]
    private var counters: Counters

    /// The next number of each kind of id. Numbers are never reused, so a
    /// deleted thread's number never points at another frame.
    private struct Counters: Codable, Equatable, Sendable {
        var thread = 1
        var message = 1
        var send = 1
    }

    /// A new review, with its General thread.
    public init(video: VideoInfo) {
        self.video = video
        threads = [ReviewThread(id: ThreadID(.thread, hash8: ItemID.hash8(of: video.contentHash), number: 0), time: nil)]
        sends = []
        counters = Counters()
    }

    /// The first eight hex digits of the video's content hash, which every
    /// id of the review carries.
    public var hash8: String { ItemID.hash8(of: video.contentHash) }

    /// The General thread: number 0, no keyframe.
    public var general: ReviewThread { threads[0] }

    /// The number the next new thread takes.
    public var nextThreadNumber: Int { counters.thread }

    /// What `write` did: the message, the thread as it is now, and whether
    /// the message started the thread.
    public struct Written: Equatable, Sendable {
        public var message: Message
        public var thread: ReviewThread
        public var startedThread: Bool
    }

    /// What `delete` did: the message, and its thread's id, and whether the
    /// thread went with its last message.
    public struct Deleted: Equatable, Sendable {
        public var message: Message
        public var thread: ThreadID
        public var removedThread: Bool
    }

    // MARK: - Finding

    public func thread(_ id: ThreadID) -> ReviewThread? {
        threads.first { $0.id == id }
    }

    /// The thread whose key is exactly the frame time `time`.
    public func thread(atFrame time: Double) -> ReviewThread? {
        threads.first { $0.time == time }
    }

    /// The message `id`, and the thread it's on.
    public func message(_ id: MessageID) -> (message: Message, thread: ReviewThread)? {
        for thread in threads {
            if let message = thread.messages.first(where: { $0.id == id }) { return (message, thread) }
        }
        return nil
    }

    public func send(_ id: SendID) -> Send? {
        sends.first { $0.id == id }
    }

    /// The thread a command names: a bare number of this review, or a full
    /// id of this video. Refused for an id of another video, and for a
    /// thread the review doesn't have.
    public func threadID(_ ref: ThreadRef) throws(ReviewRefusal) -> ThreadID {
        let id: ThreadID
        switch ref {
        case .number(let number): id = ThreadID(.thread, hash8: hash8, number: number)
        case .id(let given): id = given
        }
        guard id.hash8 == hash8 else { throw .otherVideo(id.text) }
        guard thread(id) != nil else { throw .unknownID(id.text) }
        return id
    }

    /// The person's messages waiting to be sent: threads in their order
    /// (General first, then by time), and the order written within one.
    public var queue: [Message] {
        threads.flatMap { $0.messages.filter { $0.isWork && $0.state == .queued } }
    }

    /// The messages of the send `id`, each with its thread's id.
    public func messages(of id: SendID) -> [(message: Message, thread: ThreadID)] {
        threads.flatMap { thread in thread.messages.filter { $0.sendID == id }.map { ($0, thread.id) } }
    }

    /// Whether the listener has nothing left to do on the send `id`: every
    /// message in it is `done` or `failed`. A send the review doesn't have
    /// counts as finished.
    public func isFinished(_ id: SendID) -> Bool {
        messages(of: id).allSatisfy { $0.message.state?.isFinal ?? true }
    }

    // MARK: - The person and the operator

    /// Queues the person's message. On `thread` it joins that thread; then
    /// a `time` must be the thread's own frame. Without `thread`, a `time`
    /// joins the thread whose key is exactly that frame time, or starts a
    /// new one with the next number; with neither, it goes on General. A
    /// region needs a frame, so General refuses it. The text loses the
    /// space around it; one with no words is refused.
    @discardableResult
    public mutating func write(
        text: String, at time: Double?, region: Region? = nil, to thread: ThreadID? = nil, now: Date
    ) throws(ReviewRefusal) -> Written {
        let words = try Self.trimmed(text, or: .emptyText)
        var index: Int
        var started = false
        if let thread {
            guard thread.hash8 == hash8 else { throw .otherVideo(thread.text) }
            guard let found = threads.firstIndex(where: { $0.id == thread }) else { throw .unknownID(thread.text) }
            index = found
            if threads[index].isGeneral {
                guard time == nil, region == nil else { throw .noFrame }
            } else if let time, time != threads[index].time {
                throw .frameMismatch(thread, time: time)
            }
        } else if let time {
            if let found = threads.firstIndex(where: { $0.time == time }) {
                index = found
            } else {
                index = threads.firstIndex { ($0.time ?? -.infinity) > time } ?? threads.endIndex
                threads.insert(ReviewThread(id: nextID(.thread), time: time), at: index)
                started = true
            }
        } else {
            guard region == nil else { throw .noFrame }
            index = 0
        }
        let message = Message(
            id: nextID(.message), author: .person, kind: .message, text: words, at: Self.kept(now),
            region: region, state: .queued
        )
        threads[index].messages.append(message)
        return Written(message: message, thread: threads[index], startedThread: started)
    }

    /// Replaces a queued message's text.
    @discardableResult
    public mutating func edit(_ id: MessageID, text: String) throws(ReviewRefusal) -> Message {
        let (thread, index) = try queuedIndex(id)
        threads[thread].messages[index].text = try Self.trimmed(text, or: .emptyText)
        return threads[thread].messages[index]
    }

    /// Removes a queued message. A thread whose last message goes, goes
    /// too; its number is not given again. General always stays.
    @discardableResult
    public mutating func delete(_ id: MessageID) throws(ReviewRefusal) -> Deleted {
        let (thread, index) = try queuedIndex(id)
        let message = threads[thread].messages.remove(at: index)
        let threadID = threads[thread].id
        let removed = threads[thread].messages.isEmpty && !threads[thread].isGeneral
        if removed { threads.remove(at: thread) }
        return Deleted(message: message, thread: threadID, removedThread: removed)
    }

    /// Keeps where the person left a thread's popover.
    public mutating func setPopoverFrame(_ id: ThreadID, _ frame: PopoverFrame?) throws(ReviewRefusal) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { throw .unknownID(id.text) }
        threads[index].popoverFrame = frame
    }

    /// Sends every queued message as one send: each moves to `sent` and
    /// names the send. `transcript` gives each thread with a frame its
    /// window as it is now; the send keeps those lines, so a delivery again
    /// gives the same ones. Refused when nothing is queued.
    @discardableResult
    public mutating func send(
        at now: Date, transcript: (ReviewThread) -> [SendPayload.Line] = { _ in [] }
    ) throws(ReviewRefusal) -> Send {
        let queued = threads.indices.flatMap { thread in
            threads[thread].messages.indices
                .filter { threads[thread].messages[$0].isWork && threads[thread].messages[$0].state == .queued }
                .map { (thread: thread, index: $0) }
        }
        guard !queued.isEmpty else { throw .nothingQueued }
        let id = nextID(.send)
        for (thread, index) in queued {
            threads[thread].messages[index].state = .sent
            threads[thread].messages[index].sendID = id
        }
        var transcripts: [ThreadID: [SendPayload.Line]] = [:]
        for thread in Set(queued.map(\.thread)) where !threads[thread].isGeneral {
            transcripts[threads[thread].id] = transcript(threads[thread])
        }
        let send = Send(
            id: id, sentAt: Self.kept(now), messageIDs: queued.map { threads[$0.thread].messages[$0.index].id },
            transcripts: transcripts
        )
        sends.append(send)
        return send
    }

    /// The person's answer to the open question on `thread`, which closes
    /// it. It's never queued: it goes to the waiting `ask` at once.
    @discardableResult
    public mutating func answer(_ thread: ThreadID, text: String, now: Date) throws(ReviewRefusal) -> Message {
        let index = try threadIndex(thread)
        guard threads[index].openQuestion != nil else { throw .noQuestion(thread) }
        let message = Message(id: nextID(.message), author: .person, kind: .answer, text: try Self.trimmed(text, or: .emptyMessage), at: Self.kept(now))
        threads[index].messages.append(message)
        return message
    }

    // MARK: - The listener

    /// The listener has the send `id`: each of its messages still `sent`
    /// moves to `acknowledged`, and one further on stays where it is.
    /// Words that come with it are the agent's message on General. Returns
    /// the send.
    @discardableResult
    public mutating func acknowledge(_ id: SendID, text: String? = nil, now: Date) throws(ReviewRefusal) -> Send {
        guard id.hash8 == hash8 else { throw .otherVideo(id.text) }
        guard let send = send(id) else { throw .unknownID(id.text) }
        for thread in threads.indices {
            for index in threads[thread].messages.indices
            where threads[thread].messages[index].sendID == id && threads[thread].messages[index].state == .sent {
                threads[thread].messages[index].state = .acknowledged
            }
        }
        if let words = text?.trimmingCharacters(in: .whitespacesAndNewlines), !words.isEmpty {
            threads[0].messages.append(Message(id: nextID(.message), author: .agent, kind: .message, text: words, at: Self.kept(now)))
        }
        return send
    }

    /// The listener says how far it is with a person's message: `working`,
    /// `done` or `failed`. A state only moves forward and may skip one;
    /// `done` and `failed` are final. Saying the state the message already
    /// has changes nothing and isn't refused.
    @discardableResult
    public mutating func setState(_ id: MessageID, _ state: MessageState) throws(ReviewRefusal) -> Message {
        guard id.hash8 == hash8 else { throw .otherVideo(id.text) }
        guard let (thread, index) = messageIndex(id) else { throw .unknownID(id.text) }
        let message = threads[thread].messages[index]
        guard message.isWork else { throw .illegalMove(id, from: nil, to: state) }
        guard message.sendID != nil else { throw .notSent(threads[thread].id) }
        let from = message.state
        guard from != state else { return message }
        guard state.isStatus, let from, from.canMove(to: state) else { throw .illegalMove(id, from: from, to: state) }
        threads[thread].messages[index].state = state
        return threads[thread].messages[index]
    }

    /// The agent's message on `thread`. It needs something sent on the
    /// thread; General takes one always.
    @discardableResult
    public mutating func reply(on thread: ThreadID, text: String, now: Date) throws(ReviewRefusal) -> Message {
        let index = try answerableIndex(thread)
        let message = Message(id: nextID(.message), author: .agent, kind: .message, text: try Self.trimmed(text, or: .emptyMessage), at: Self.kept(now))
        threads[index].messages.append(message)
        return message
    }

    /// The agent's question on `thread`. Refused while the thread has a
    /// question with no answer: an answer names a thread, so it must have
    /// one question to go to.
    @discardableResult
    public mutating func ask(on thread: ThreadID, question: String, now: Date) throws(ReviewRefusal) -> Message {
        let index = try answerableIndex(thread)
        let words = try Self.trimmed(question, or: .emptyMessage)
        guard threads[index].openQuestion == nil else { throw .questionOpen(thread) }
        let message = Message(id: nextID(.message), author: .agent, kind: .question, text: words, at: Self.kept(now))
        threads[index].messages.append(message)
        return message
    }

    /// The send `id` goes back to the listener's line, since the listener
    /// that took it is gone: its unfinished messages return to `sent`, the
    /// one move back the states allow. Returns those messages.
    @discardableResult
    public mutating func requeue(_ id: SendID) -> [MessageID] {
        var requeued: [MessageID] = []
        for thread in threads.indices {
            for index in threads[thread].messages.indices
            where threads[thread].messages[index].sendID == id && threads[thread].messages[index].state?.isFinal == false {
                threads[thread].messages[index].state = .sent
                requeued.append(threads[thread].messages[index].id)
            }
        }
        return requeued
    }

    // MARK: - Helpers

    /// A new id of `kind` from its counter.
    private mutating func nextID(_ kind: ItemID.Kind) -> ItemID {
        switch kind {
        case .thread:
            defer { counters.thread += 1 }
            return ItemID(kind, hash8: hash8, number: counters.thread)
        case .message:
            defer { counters.message += 1 }
            return ItemID(kind, hash8: hash8, number: counters.message)
        case .send:
            defer { counters.send += 1 }
            return ItemID(kind, hash8: hash8, number: counters.send)
        }
    }

    /// A time as the review keeps it: to the millisecond, which is what
    /// its file holds, so a review reads back as it was.
    private static func kept(_ time: Date) -> Date {
        Date(timeIntervalSince1970: (time.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
    }

    private func threadIndex(_ id: ThreadID) throws(ReviewRefusal) -> Int {
        guard id.hash8 == hash8 else { throw .otherVideo(id.text) }
        guard let index = threads.firstIndex(where: { $0.id == id }) else { throw .unknownID(id.text) }
        return index
    }

    /// A thread the listener can write on: General, or one with something
    /// sent.
    private func answerableIndex(_ id: ThreadID) throws(ReviewRefusal) -> Int {
        let index = try threadIndex(id)
        guard threads[index].isGeneral || threads[index].wasSent else { throw .notSent(id) }
        return index
    }

    private func messageIndex(_ id: MessageID) -> (thread: Int, index: Int)? {
        for thread in threads.indices {
            if let index = threads[thread].messages.firstIndex(where: { $0.id == id }) { return (thread, index) }
        }
        return nil
    }

    private func queuedIndex(_ id: MessageID) throws(ReviewRefusal) -> (thread: Int, index: Int) {
        guard id.hash8 == hash8 else { throw .otherVideo(id.text) }
        guard let (thread, index) = messageIndex(id) else { throw .unknownID(id.text) }
        let message = threads[thread].messages[index]
        guard message.isWork, message.state?.isEditable == true else { throw .notQueued(id, message.state) }
        return (thread, index)
    }

    /// `text` without the space around it; `refusal` when nothing is left.
    private static func trimmed(_ text: String, or refusal: ReviewRefusal) throws(ReviewRefusal) -> String {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { throw refusal }
        return words
    }
}
