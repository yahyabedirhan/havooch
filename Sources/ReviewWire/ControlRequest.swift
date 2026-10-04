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
    /// `video-review comment add <text> [--at <time>] [--region x,y,w,h]`: a
    /// comment queued at `at` seconds, or at the player's time when it's
    /// nil, on `region` of the frame when it has one.
    case commentAdd(text: String, at: Double?, region: Rectangle? = nil)
    /// `video-review comment edit <id> <text>`: a queued comment's new text.
    case commentEdit(id: String, text: String)
    /// `video-review comment delete <id>`: a queued comment removed.
    case commentDelete(id: String)
    /// `video-review context set <text>`: the open video's context note,
    /// which the listener gets with the sidecar's text. An empty `text`
    /// clears it.
    case contextSet(text: String)
    /// `video-review batch send`: every queued comment of the open video
    /// sent as one batch, which the listener's `wait` gets.
    case batchSend
    /// `video-review wait [--timeout <seconds>]`: the next batch as its
    /// JSON payload. The app holds the request until a batch is sent, up to
    /// `timeoutSeconds`, or with no limit when it's nil. The sender is the
    /// listener, present while its `wait` is open.
    case wait(timeoutSeconds: Int?)
    /// `video-review screenshot <abs.png> [--appearance light|dark]
    /// [--with-banner]`: the app's window written as a PNG at the absolute
    /// `path`, in `appearance` when it's set, as the Mac shows it otherwise.
    /// The lease banner is left out unless `withBanner` asks for it.
    case screenshot(path: String, appearance: Appearance?, withBanner: Bool = false)

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
        /// The agent that receives batches, beside the person: no lease.
        case listener
    }

    /// The request's role, so the app and the command agree on which
    /// requests take the lease without a table.
    public var role: Role {
        switch self {
        case .appStatus, .state, .controlTake, .controlRelease: .free
        case .appOpen, .appQuit, .playerOpen, .playerPlay, .playerPause, .playerSeek, .screenshot: .operator
        case .contextSet: .operator
        case .commentAdd, .commentEdit, .commentDelete, .batchSend: .operator
        case .wait: .listener
        }
    }

    /// How long the app may keep the connection before it answers, past the
    /// client's usual timeout; nil for no limit. A `take` waits in line for
    /// its `waitSeconds`, and a `wait` for a batch for its `timeoutSeconds`.
    public var holdSeconds: TimeInterval? {
        switch self {
        case .controlTake(let waitSeconds): TimeInterval(waitSeconds ?? 0)
        case .wait(let timeoutSeconds): timeoutSeconds.map(TimeInterval.init)
        default: 0
        }
    }

    /// The longest a `control take --wait` may wait in line, in seconds.
    public static let longestWait = 3600

    /// The longest `wait --timeout` a listener may ask for, in seconds: a
    /// day. Without the option a `wait` has no limit.
    public static let longestListen = 86400

    /// The most bytes the app reads of one request.
    public static let largestMessage = 1 << 20
}
