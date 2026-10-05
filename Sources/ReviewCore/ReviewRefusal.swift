import Foundation

/// Why a change to a review is refused. A refused change leaves the review
/// as it was.
public enum ReviewRefusal: Error, Equatable, Sendable {
    /// A person's message needs words.
    case emptyText
    /// The review has no thread, message or send with this id.
    case unknownID(String)
    /// The id names a thread, message or send of another video.
    case otherVideo(String)
    /// Only a queued message can be edited or deleted.
    case notQueued(MessageID, MessageState?)
    /// A region is inside the frame and has an area.
    case badRegion(x: Double, y: Double, w: Double, h: Double)
    /// A send needs at least one queued message.
    case nothingQueued
    /// An agent's message or an answer needs words.
    case emptyMessage
    /// The listener answers only on a thread that was sent to it.
    case notSent(ThreadID)
    /// A message's state only moves forward, and `done` and `failed` are
    /// final.
    case illegalMove(MessageID, from: MessageState?, to: MessageState)
    /// A thread has one open question at most.
    case questionOpen(ThreadID)
    /// An answer needs an open question.
    case noQuestion(ThreadID)
    /// A message on a thread must be on that thread's frame.
    case frameMismatch(ThreadID, time: Double)
    /// The General thread has no frame: a message on it has no time and no
    /// region.
    case noFrame

    /// The refusal as the one line the command prints.
    public var line: String {
        switch self {
        case .emptyText:
            "a message needs text"
        case .unknownID(let id):
            "no `\(id)` on this video; `video-review state --json` lists the threads and their messages"
        case .otherVideo(let id):
            "`\(id)` is on another video than the open one; open that video first"
        case .notQueued(let id, let state):
            "\(id) is \(state?.rawValue ?? "not a queued message"), and only a queued message can change"
        case .badRegion(let x, let y, let w, let h):
            "the region \(x),\(y),\(w),\(h) isn't a rectangle inside the frame; give x,y,w,h from 0 to 1 from the top-left corner, with a width and a height above 0, x+w at most 1 and y+h at most 1"
        case .nothingQueued:
            "no message is queued, so there's nothing to send; queue one with `video-review comment add <text>`"
        case .emptyMessage:
            "a message needs text"
        case .notSent(let thread):
            "nothing on #\(thread.number) (\(thread)) was sent yet, so there's nothing to answer"
        case .illegalMove(let id, let from, let to):
            "\(id) is \(from?.rawValue ?? "not a person's message") and can't move to \(to.rawValue): a message only moves forward (sent, acknowledged, working, then done or failed)"
        case .questionOpen(let thread):
            "#\(thread.number) (\(thread)) already has an open question; its answer comes on the thread, which `video-review state --json` shows"
        case .noQuestion(let thread):
            "#\(thread.number) (\(thread)) has no open question to answer"
        case .frameMismatch(let thread, let time):
            "#\(thread.number) (\(thread)) is on another frame than \(time) s; leave out `--at` to write on its frame"
        case .noFrame:
            "the General thread (#0) has no frame, so a message on it takes no `--at` and no `--region`"
        }
    }
}
