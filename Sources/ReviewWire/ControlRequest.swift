import Foundation

/// What the `video-review` command asks of the running app: one request per
/// connection over `control.sock`, sent as a `ControlMessage` with its
/// holder. A new request is a case here, with its `command` name and its
/// fields in `ControlMessage`.
public enum ControlRequest: Equatable, Sendable {
    /// `video-review app status`: whether the app runs, and on which data.
    case appStatus
    /// `video-review state`: everything the app shows.
    case state
    /// `video-review control take [--wait <seconds>]`: hold the lease to
    /// its cap; while another agent holds it, wait in line up to
    /// `waitSeconds`, or be refused at once without them.
    case controlTake(waitSeconds: Int?)
    /// `video-review control release`: give the lease up.
    case controlRelease
    /// `video-review app open` while the app runs: its status.
    case appOpen
    /// `video-review app quit`: the app replies, then quits.
    case appQuit
    /// `video-review player open <path>`: the video at the absolute `path`
    /// opened, paused at its start.
    case playerOpen(path: String)
    /// `video-review player play`.
    case playerPlay
    /// `video-review player pause`.
    case playerPause
    /// `video-review player seek <time>`: the player moved to exactly
    /// `seconds`, still playing or still paused.
    case playerSeek(seconds: Double)
    /// `video-review comment add <text> [--at <time>] [--region x,y,w,h]
    /// [--thread <thread>]`: a message queued at `at` seconds, or at the
    /// player's time when it's nil, on `region` of the frame when it has
    /// one. It joins the thread of that frame or starts one; with `thread`
    /// (a thread id, or a number of the open video, `0` for General) it's
    /// written on that thread.
    case commentAdd(text: String, at: Double?, region: Rectangle? = nil, thread: String? = nil)
    /// `video-review comment open [<text>] [--region x,y,w,h]`: the comment
    /// popover opened at the player's frame, as C or a drawn rectangle
    /// opens it, on `region` when it has one, with `text` in its field. An
    /// addition to the spec's contract: the popover and its region can be
    /// shown, checked and screenshotted without a click.
    case commentOpen(text: String, region: Rectangle? = nil)
    /// `video-review comment edit <message-id> <text>`: a queued message's
    /// new text.
    case commentEdit(id: String, text: String)
    /// `video-review comment delete <message-id>`: a queued message removed.
    case commentDelete(id: String)
    /// `video-review context set <text>`: the open video's context note,
    /// which the listener gets with the sidecar's text. An empty `text`
    /// clears it.
    case contextSet(text: String)
    /// `video-review send`: every queued message of the open video sent as
    /// one send, which the listener's `wait` gets.
    case send
    /// `video-review wait [--timeout <seconds>]`: the next send as its
    /// JSON payload. The app holds the request until a send is made, up to
    /// `timeoutSeconds`, or with no limit when it's nil. The sender is the
    /// listener, present while its `wait` is open.
    case wait(timeoutSeconds: Int?)
    /// `video-review ack <send-id> [<text>]`: the listener has the send.
    /// Its messages are acknowledged, and `text` is the agent's message on
    /// the General thread.
    case ack(sendID: String, text: String?)
    /// `video-review status <message-id> working|done|failed`: how far the
    /// listener is with a message.
    case status(messageID: String, state: Status)
    /// `video-review reply <thread> <text>`: the listener's message on a
    /// thread (a thread id, or a number of the open video).
    case reply(thread: String, text: String)
    /// `video-review ask <thread> <question> [--wait <seconds>]`: the
    /// listener's question on a thread. The app holds the request until the
    /// person answers, up to `waitSeconds`, or with no limit when it's nil.
    case ask(thread: String, question: String, waitSeconds: Int?)
    /// `video-review thread answer <thread> <text>`: the answer to a
    /// thread's open question, as the person gives it in the app.
    case threadAnswer(thread: String, text: String)
    /// `video-review thread open <thread> [--frame x,y,w,h]`: the thread
    /// popover opened on the thread's frame, as a click on its pin or its
    /// badge opens it. With `frame` (0 to 1 of the video area, from its
    /// top-left corner) the popover is first kept there, as a drag and a
    /// resize leave it. An addition to the spec's contract: the CLI can't
    /// click, drag or resize.
    case threadOpen(thread: String, frame: Rectangle? = nil)
    /// `video-review screenshot <abs.png> [--appearance light|dark]
    /// [--hide-agent-indicator]`: the app's window written as a PNG at the
    /// absolute `path`, in `appearance` when it's set, as the Mac shows it
    /// otherwise. The agent-control indicator shows as the person sees it,
    /// unless `hideAgentIndicator` leaves it out.
    case screenshot(path: String, appearance: Appearance?, hideAgentIndicator: Bool = false)
    /// `video-review theme list`: every theme the app knows, and which one
    /// is active and pinned.
    case themeList
    /// `video-review theme set <name>`: the theme called `name` pinned, or
    /// the pin cleared for `system`, so the theme follows the system
    /// appearance again.
    case themeSet(name: String)

    /// The four numbers of `--region x,y,w,h` as they were written. The
    /// app decides whether they're a region of the frame.
    public struct Rectangle: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var w: Double
        public var h: Double

        public init(x: Double, y: Double, w: Double, h: Double) {
            (self.x, self.y, self.w, self.h) = (x, y, w, h)
        }

        /// Reads `x,y,w,h`; nil when it isn't four numbers.
        public init?(_ text: String) {
            let numbers = text.split(separator: ",", omittingEmptySubsequences: false)
                .map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard numbers.count == 4, let x = numbers[0], let y = numbers[1], let w = numbers[2], let h = numbers[3],
                  [x, y, w, h].allSatisfy(\.isFinite)
            else { return nil }
            self.init(x: x, y: y, w: w, h: h)
        }
    }

    /// What `status` can say of a message.
    public enum Status: String, Equatable, Sendable, CaseIterable {
        case working, done, failed
    }

    /// The appearance `screenshot` draws in.
    public enum Appearance: String, Equatable, Sendable, CaseIterable {
        case light, dark
    }

    /// Who may send a request.
    public enum Role: Equatable, Sendable {
        /// Anyone, at any time: it changes nothing a person sees.
        case free
        /// An agent that drives the UI: one at a time, under the lease.
        case `operator`
        /// The agent that receives sends, beside the person: no lease.
        case listener
    }

    /// The request's role, so the app and the command agree on which
    /// requests take the lease without a table.
    public var role: Role {
        switch self {
        case .appStatus, .state, .controlTake, .controlRelease, .themeList: .free
        case .themeSet: .operator
        case .appOpen, .appQuit, .playerOpen, .playerPlay, .playerPause, .playerSeek, .screenshot: .operator
        case .contextSet: .operator
        case .commentAdd, .commentOpen, .commentEdit, .commentDelete, .send: .operator
        case .threadAnswer, .threadOpen: .operator
        case .wait, .ack, .status, .reply, .ask: .listener
        }
    }

    /// How long the app may keep the connection before it answers, past the
    /// client's usual timeout; nil for no limit. A `take` waits in line for
    /// its `waitSeconds`, a `wait` for a send for its `timeoutSeconds`,
    /// and an `ask` for its answer for its `waitSeconds`.
    public var holdSeconds: TimeInterval? {
        switch self {
        case .controlTake(let waitSeconds): TimeInterval(waitSeconds ?? 0)
        case .wait(let timeoutSeconds): timeoutSeconds.map(TimeInterval.init)
        case .ask(_, _, let waitSeconds): waitSeconds.map(TimeInterval.init)
        default: 0
        }
    }

    /// The longest a `control take --wait` may wait in line, in seconds.
    public static let longestWait = 3600

    /// The longest `wait --timeout` or `ask --wait` a listener may ask for,
    /// in seconds: a day. Without the option neither has a limit.
    public static let longestListen = 86400

    /// The most bytes the app reads of one request.
    public static let largestMessage = 1 << 20
}
