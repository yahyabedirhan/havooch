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

    public init(id: ThreadID, time: Double?, messages: [Message] = [], popoverFrame: PopoverFrame? = nil) {
        self.id = id
        self.time = time
        self.messages = messages
        self.popoverFrame = popoverFrame
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
