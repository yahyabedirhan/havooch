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
    /// `screenshot <abs.png> [--appearance light|dark]`: the app's window
    /// written as a PNG at `path`, absolute since the app runs in another
    /// folder; in `appearance` when it's set, as the Mac shows it otherwise.
    case screenshot(path: String, appearance: Appearance?)

    /// The appearance `screenshot` draws in.
    public enum Appearance: String, Equatable, Sendable, CaseIterable {
        case light, dark
    }

    /// The protocol's version. A request or app of another version is
    /// refused with both numbers, never misread.
    public static let version = 1

    /// The most bytes the app reads of one request.
    public static let largestMessage = 1 << 20

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
        case .appStatus, .state:
            .free
        case .appOpen, .appQuit, .playerOpen, .playerPlay, .playerPause, .playerSeek, .screenshot:
            .operator
        }
    }
}
