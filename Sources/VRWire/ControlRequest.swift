import Foundation

/// What the `video-review` command asks of the running app: one request per
/// connection over `control.sock`, sent as a `ControlMessage` with its
/// holder. A new request is a case here, its role, and its wire name and
/// fields in `ControlMessage`.
public enum ControlRequest: Equatable, Sendable {
    // Free: no lease.
    /// `app status`: whether the app runs, and what it is showing in short.
    case appStatus
    /// `state`: everything the app shows.
    case state
    /// `control take [--wait <seconds>]`: the lease held until its cap. While
    /// another agent holds it, the take waits in line for up to
    /// `waitSeconds` (0 to `longestWait`), answered once the lease is this
    /// agent's or the wait runs out.
    case controlTake(waitSeconds: Int?)
    /// `control release`: the lease given up, so the next agent in line
    /// gets it.
    case controlRelease

    // Operator: leased.
    /// `app open` while the app runs: its status, and, unlike `app.status`,
    /// leased, so the opener's lease is renewed.
    case appOpen
    /// `app quit`: the app replies, then quits.
    case appQuit
    /// `player open <path>`: the video at the absolute `path` opened, paused
    /// at its start.
    case playerOpen(path: String)
    case playerPlay
    case playerPause
    /// `player seek <time>`: the player at `seconds`, exactly.
    case playerSeek(seconds: Double)
    /// `comment add <text> [--at <time>] [--region x,y,w,h]`: a comment
    /// queued at `at`, or at the player's time, with the frame there as its
    /// keyframe; on `region` of that frame when it's given, with its crop.
    case commentAdd(text: String, at: Double?, region: WireRegion?)
    /// `comment edit <id> <text>`: a queued comment's text replaced.
    case commentEdit(id: String, text: String)
    /// `comment delete <id>`: a queued comment taken out.
    case commentDelete(id: String)
    /// `batch send`: every queued comment of the open video sent as one
    /// batch, for a listener's `wait`.
    case batchSend
    /// `context set <text>`: the open video's note replaced; an empty text
    /// takes it away.
    case contextSet(text: String)
    /// `thread answer <comment-id> <text>`: the person's answer to the
    /// question open on that comment, as the answer box gives it.
    case threadAnswer(commentID: String, text: String)
    /// `screenshot <abs.png> [--appearance light|dark]`: the app's window
    /// written as a PNG at `path`, absolute since the app runs in another
    /// folder; in `appearance` when it's set, as the Mac shows it otherwise.
    case screenshot(path: String, appearance: Appearance?)

    // Listener: no lease.
    /// `wait [--timeout <seconds>]`: the next batch as the payload's JSON.
    /// The app holds the connection until a batch comes or `timeoutSeconds`
    /// (0 to `longestTimeout`) ran out; without one, for as long as it takes.
    /// The listener is present while a `wait` is open.
    case wait(timeoutSeconds: Int?)
    /// `ack <batch-id> [<text>]`: the listener has the batch; its comments
    /// are acknowledged, and `text` is a message for the full batch.
    case ack(batchID: String, text: String?)
    /// `status <comment-id> working|done|failed`: `state` is one of
    /// `statuses`.
    case status(commentID: String, state: String)
    /// `reply <comment-id|batch-id> <text>`: a message in the thread of the
    /// comment or the batch `id`.
    case reply(id: String, text: String)
    /// `ask <comment-id> <question> [--wait <seconds>]`: a question in the
    /// comment's thread, answered with the person's answer. The app holds
    /// the connection until the answer comes or `waitSeconds` (0 to
    /// `longestTimeout`) ran out; without one, for as long as it takes.
    case ask(commentID: String, question: String, waitSeconds: Int?)

    /// The states `status` sets a comment to.
    public static let statuses = ["working", "done", "failed"]

    /// A rectangle on the frame as `--region x,y,w,h` gives it: four
    /// numbers, parts of the frame from its top left. The app decides
    /// whether they are inside the frame.
    public struct WireRegion: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var w: Double
        public var h: Double

        public init(x: Double, y: Double, w: Double, h: Double) {
            self.x = x
            self.y = y
            self.w = w
            self.h = h
        }
    }

    /// The appearance `screenshot` draws in.
    public enum Appearance: String, Equatable, Sendable, CaseIterable {
        case light, dark
    }

    /// The protocol's version. A request or app of another version is
    /// refused with both numbers, never misread.
    public static let version = 1

    /// The most bytes the app reads of one request.
    public static let largestMessage = 1 << 20

    /// The longest wait in line a `take` asks for, in seconds: an hour.
    public static let longestWait = 3600

    /// The longest `--timeout` a `wait` and `--wait` an `ask` ask for, in
    /// seconds: a day.
    public static let longestTimeout = 86_400

    /// How long the app may hold the connection before it answers, past the
    /// client's usual timeout: a `take`'s wait in line.
    public var hold: TimeInterval {
        if case .controlTake(let seconds?) = self { return TimeInterval(seconds) }
        return 0
    }

    /// Whether the app holds the connection for as long as it takes and
    /// writes a heartbeat meanwhile: a listener's `wait` and `ask`.
    public var isLongPoll: Bool {
        switch self {
        case .wait, .ask: true
        default: false
        }
    }

    /// Who a request is for, which decides whether it needs the lease.
    public enum Role: Equatable, Sendable {
        /// Changes nothing, or is the lease's own request: no lease.
        case free
        /// Drives the UI: needs the lease.
        case `operator`
        /// Receives and answers batches beside a person: no lease.
        case listener
    }

    public var role: Role {
        switch self {
        case .appStatus, .state, .controlTake, .controlRelease:
            .free
        case .appOpen, .appQuit, .playerOpen, .playerPlay, .playerPause, .playerSeek, .screenshot:
            .operator
        case .commentAdd, .commentEdit, .commentDelete, .batchSend, .contextSet, .threadAnswer:
            .operator
        case .wait, .ack, .status, .reply, .ask:
            .listener
        }
    }
}
