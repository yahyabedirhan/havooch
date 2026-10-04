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
    /// `screenshot <abs.png> [--appearance light|dark]`: the app's window
    /// written as a PNG at `path`, absolute since the app runs in another
    /// folder; in `appearance` when it's set, as the Mac shows it otherwise.
    case screenshot(path: String, appearance: Appearance?)

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

    /// How long the app may hold the connection before it answers, past the
    /// client's usual timeout: a `take`'s wait in line.
    public var wait: TimeInterval {
        if case .controlTake(let seconds?) = self { return TimeInterval(seconds) }
        return 0
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
        case .commentAdd, .commentEdit, .commentDelete:
            .operator
        }
    }
}
