/// What the `video-review` command asks of the running app: one request per
/// connection, sent as a `ControlMessage` with its holder. A new request is
/// a case here, with its wire name (`command`) and its fields in
/// `ControlMessage`.
public enum ControlRequest: Equatable, Sendable {
    // Free: no lease.
    case appStatus
    case state
    case controlTake(waitSeconds: Int?)
    case controlRelease

    // Operator: the lease.
    case appOpen
    case appQuit
    case playerOpen(path: String)
    case playerPlay
    case playerPause
    case playerSeek(seconds: Double)
    case commentAdd(text: String, at: Double?, region: WireRegion?)
    case commentEdit(id: String, text: String)
    case commentDelete(id: String)
    case batchSend
    case threadAnswer(id: String, text: String)
    case contextSet(text: String)
    case screenshot(path: String, appearance: Appearance?)

    // Listener: no lease.
    case wait(timeoutSeconds: Int?)
    case ack(id: String, text: String?)
    case status(id: String, state: String)
    case reply(id: String, text: String)
    case ask(id: String, text: String, waitSeconds: Int?)

    /// The appearance `screenshot` draws in.
    public enum Appearance: String, Equatable, Sendable, CaseIterable {
        case light, dark
    }

    /// The protocol's version. A request of another version is refused with
    /// both numbers, never misread.
    public static let version = 1

    /// The longest `take --wait`, in seconds: an hour.
    public static let longestWait = 3600

    /// The request's name on the wire.
    public var command: String {
        switch self {
        case .appStatus: "app.status"
        case .state: "state"
        case .controlTake: "control.take"
        case .controlRelease: "control.release"
        case .appOpen: "app.open"
        case .appQuit: "app.quit"
        case .playerOpen: "player.open"
        case .playerPlay: "player.play"
        case .playerPause: "player.pause"
        case .playerSeek: "player.seek"
        case .commentAdd: "comment.add"
        case .commentEdit: "comment.edit"
        case .commentDelete: "comment.delete"
        case .batchSend: "batch.send"
        case .threadAnswer: "thread.answer"
        case .contextSet: "context.set"
        case .screenshot: "screenshot"
        case .wait: "wait"
        case .ack: "ack"
        case .status: "status"
        case .reply: "reply"
        case .ask: "ask"
        }
    }

    /// Whether the request needs the lease before it's answered: true for
    /// the operator's commands, false for the free ones and the listener's.
    public var isLeased: Bool {
        switch self {
        case .appOpen, .appQuit, .playerOpen, .playerPlay, .playerPause, .playerSeek,
             .commentAdd, .commentEdit, .commentDelete, .batchSend, .threadAnswer, .contextSet, .screenshot:
            true
        case .appStatus, .state, .controlTake, .controlRelease, .wait, .ack, .status, .reply, .ask:
            false
        }
    }
}

/// A region as it travels: four numbers, normalized 0..1, origin top left.
/// The wire doesn't judge them; the app does.
public struct WireRegion: Codable, Equatable, Sendable {
    public var x, y, w, h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}
