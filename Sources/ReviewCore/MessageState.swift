import Foundation

/// Where a person's message of the kind `message` is on its way to the
/// agent and back: `queued → sent → acknowledged → working → done | failed`.
/// There is no draft state: the open popover is view state only.
public enum MessageState: String, Codable, Sendable, CaseIterable {
    case queued, sent, acknowledged, working, done, failed

    /// Whether a message in this state may move to `next`: forward only. A
    /// state may be skipped (`sent → working`), and `done` and `failed` are
    /// final.
    public func canMove(to next: MessageState) -> Bool {
        guard !isFinal, next != self else { return false }
        return next.isFinal || next.step > step
    }

    /// Whether the message is finished: `done` or `failed`.
    public var isFinal: Bool {
        self == .done || self == .failed
    }

    /// Whether the message is still open: not `done` or `failed`. A
    /// thread shows the state of its latest open message.
    public var isOpen: Bool { !isFinal }

    /// Whether the person can still change or delete the message: only
    /// while it's queued. A sent message is a record.
    public var isEditable: Bool {
        self == .queued
    }

    /// Whether the listener can set this state with `status`: `working`,
    /// `done` or `failed`.
    public var isStatus: Bool {
        self == .working || isFinal
    }

    /// The state's place on the way; `done` and `failed` share the end.
    private var step: Int {
        switch self {
        case .queued: 0
        case .sent: 1
        case .acknowledged: 2
        case .working: 3
        case .done, .failed: 4
        }
    }
}
