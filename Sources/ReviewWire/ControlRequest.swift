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
    /// `video-review screenshot <abs.png> [--appearance light|dark]`: the
    /// app's window written as a PNG at the absolute `path`, in `appearance`
    /// when it's set, as the Mac shows it otherwise.
    case screenshot(path: String, appearance: Appearance?)

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
        case .appStatus, .state: .free
        case .appOpen, .appQuit, .playerOpen, .playerPlay, .playerPause, .playerSeek, .screenshot: .operator
        }
    }

    /// How long the app may keep the connection before it answers, past the
    /// client's usual timeout; nil for no limit. No request waits yet.
    public var holdSeconds: TimeInterval? { 0 }

    /// The most bytes the app reads of one request.
    public static let largestMessage = 1 << 20
}
