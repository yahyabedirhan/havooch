import Foundation

/// The whole conversation about one keyframe of a video: its messages in
/// the order written. Its key is the exact frame time; its number is unique
/// in its review and starts at 1. The General thread has the number 0 and
/// no keyframe. The keyframe is a file named after the thread's id.
public struct ReviewThread: Codable, Equatable, Sendable, Identifiable {
    public let id: ThreadID
    /// The thread's number, as `#3` shows it: its id's counter.
    public var number: Int { id.number }
    /// The frame time the thread is about, in seconds; nil for General.
    public let time: Double?
    public internal(set) var messages: [Message]
    /// Where the person left the thread's popover; nil until they move or
    /// resize it.
    public internal(set) var popoverFrame: PopoverFrame?
    /// When the person last opened the thread's view; nil until they do.
    public internal(set) var lastSeen: Date?
    /// The version of a project the thread was raised on; nil
    /// on a plain video, and for General, which is the whole project's.
    public internal(set) var anchor: VersionAnchor?

    public init(
        id: ThreadID, time: Double?, messages: [Message] = [], popoverFrame: PopoverFrame? = nil, lastSeen: Date? = nil,
        anchor: VersionAnchor? = nil
    ) {
        self.id = id
        self.time = time
        self.messages = messages
        self.popoverFrame = popoverFrame
        self.lastSeen = lastSeen
        self.anchor = anchor
    }

    private enum CodingKeys: String, CodingKey {
        case id, time, messages, popoverFrame, lastSeen, anchor
    }

    /// A thread kept before the last opening was has no `lastSeen` key:
    /// its agent messages count as read, so an update marks nothing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ThreadID.self, forKey: .id)
        time = try container.decodeIfPresent(Double.self, forKey: .time)
        messages = try container.decode([Message].self, forKey: .messages)
        popoverFrame = try container.decodeIfPresent(PopoverFrame.self, forKey: .popoverFrame)
        lastSeen = if container.contains(.lastSeen) {
            try container.decodeIfPresent(Date.self, forKey: .lastSeen)
        } else {
            messages.last(where: { $0.author == .agent })?.at
        }
        anchor = try container.decodeIfPresent(VersionAnchor.self, forKey: .anchor)
    }

    /// `lastSeen` is written as `null` until the person opens the thread,
    /// so it reads back apart from a thread kept before it was.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(popoverFrame, forKey: .popoverFrame)
        try container.encode(lastSeen, forKey: .lastSeen)
        try container.encodeIfPresent(anchor, forKey: .anchor)
    }

    /// Whether this is the General thread.
    public var isGeneral: Bool { time == nil }

    /// Whether any message points at a region of the keyframe.
    public var hasRegion: Bool { messages.contains { $0.region != nil } }

    /// The thread's state: that of its latest open person message, else
    /// that of its latest person message; nil with no person message.
    public var state: MessageState? {
        let work = messages.filter(\.isWork).compactMap(\.state)
        return work.last(where: \.isOpen) ?? work.last
    }

    /// The agent's question that waits for the person's answer: the last
    /// question, while no answer follows it. A thread has one at most.
    public var openQuestion: Message? {
        guard let index = messages.lastIndex(where: { $0.kind == .question }),
              !messages[index...].contains(where: { $0.kind == .answer })
        else { return nil }
        return messages[index]
    }

    /// Whether an agent message came after the person last opened the
    /// thread's view: its row shows the unread dot.
    public var isUnread: Bool {
        messages.contains { message in
            message.author == .agent && lastSeen.map { message.at > $0 } ?? true
        }
    }

    /// Whether anything on the thread was sent: the listener answers only a
    /// thread it got.
    public var wasSent: Bool { messages.contains { $0.sendID != nil } }
}

/// Where a thread's popover sits: a rectangle in normalized coordinates of
/// the video area, 0 to 1 from its top-left corner.
public struct PopoverFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        (self.x, self.y, self.w, self.h) = (x, y, w, h)
    }
}
