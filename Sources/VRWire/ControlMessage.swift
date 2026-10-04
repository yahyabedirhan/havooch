import Foundation
import VRLease

/// One request as it goes over the socket: what's asked, who asks, and
/// whether the answer's `output` should be JSON. On the wire it's one flat
/// JSON object, keys sorted, naming the protocol's `version`, the `command`
/// (the CLI's words joined by a dot) and the `holder`, with the command's
/// own fields beside them:
///
///     {"command":"player.seek","holder":{…},"json":false,"time":10,"version":1}
///
/// The wire format is a contract between a `video-review` and the app of
/// the same build.
public struct ControlMessage: Equatable, Sendable {
    public var request: ControlRequest
    public var holder: Holder
    /// `--json`: the reply's `output` is one JSON object, not lines.
    public var json: Bool

    public init(_ request: ControlRequest, holder: Holder, json: Bool = false) {
        self.request = request
        self.holder = holder
        self.json = json
    }

    /// The message as one JSON object.
    public func encoded() -> Data {
        var wire: Wire
        switch request {
        case .appStatus:
            wire = Wire(command: "app.status")
        case .state:
            wire = Wire(command: "state")
        case .controlTake(let waitSeconds):
            wire = Wire(command: "control.take", waitSeconds: waitSeconds)
        case .controlRelease:
            wire = Wire(command: "control.release")
        case .appOpen:
            wire = Wire(command: "app.open")
        case .appQuit:
            wire = Wire(command: "app.quit")
        case .playerOpen(let path):
            wire = Wire(command: "player.open", path: path)
        case .playerPlay:
            wire = Wire(command: "player.play")
        case .playerPause:
            wire = Wire(command: "player.pause")
        case .playerSeek(let seconds):
            wire = Wire(command: "player.seek", time: seconds)
        case .commentAdd(let text, let at, let region):
            wire = Wire(command: "comment.add", time: at, text: text, region: region)
        case .commentEdit(let id, let text):
            wire = Wire(command: "comment.edit", id: id, text: text)
        case .commentDelete(let id):
            wire = Wire(command: "comment.delete", id: id)
        case .batchSend:
            wire = Wire(command: "batch.send")
        case .contextSet(let text):
            wire = Wire(command: "context.set", text: text)
        case .screenshot(let path, let appearance):
            wire = Wire(command: "screenshot", path: path, appearance: appearance?.rawValue)
        case .wait(let timeoutSeconds):
            wire = Wire(command: "wait", timeoutSeconds: timeoutSeconds)
        case .threadAnswer(let commentID, let text):
            wire = Wire(command: "thread.answer", id: commentID, text: text)
        case .ack(let batchID, let text):
            wire = Wire(command: "ack", id: batchID, text: text)
        case .status(let commentID, let state):
            wire = Wire(command: "status", id: commentID, state: state)
        case .reply(let id, let text):
            wire = Wire(command: "reply", id: id, text: text)
        case .ask(let commentID, let question, let waitSeconds):
            wire = Wire(command: "ask", waitSeconds: waitSeconds, id: commentID, text: question)
        }
        wire.holder = holder
        wire.json = json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding a struct of strings, numbers and booleans can't fail.
        return try! encoder.encode(wire)
    }

    /// Reads a message the client sent: refused when it isn't JSON, names
    /// another version, has no holder, or names a command this build
    /// doesn't know.
    public static func decode(_ data: Data) throws(ControlProtocolError) -> ControlMessage {
        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: data)
        } catch {
            throw .unreadable("the request isn't a control request")
        }
        // Before anything else is read: another version's fields may differ.
        guard wire.version == ControlRequest.version else { throw .otherVersion(wire.version) }
        guard let holder = wire.holder else {
            throw .unreadable("the control command `\(wire.command)` needs its `holder`")
        }
        return ControlMessage(try request(wire), holder: holder, json: wire.json ?? false)
    }

    /// The request `wire` names, with the fields its command needs.
    private static func request(_ wire: Wire) throws(ControlProtocolError) -> ControlRequest {
        switch wire.command {
        case "app.status": return .appStatus
        case "state": return .state
        case "control.take":
            if let seconds = wire.waitSeconds, !(0...ControlRequest.longestWait).contains(seconds) {
                throw .unreadable(
                    "the control command `control.take` needs a `waitSeconds` from 0 to \(ControlRequest.longestWait), not \(seconds)"
                )
            }
            return .controlTake(waitSeconds: wire.waitSeconds)
        case "control.release": return .controlRelease
        case "app.open": return .appOpen
        case "app.quit": return .appQuit
        case "player.open": return .playerOpen(path: try absolute(wire))
        case "player.play": return .playerPlay
        case "player.pause": return .playerPause
        case "player.seek":
            guard let time = wire.time else { throw .unreadable("the control command `player.seek` needs its `time`") }
            guard time.isFinite, time >= 0 else {
                throw .unreadable("the control command `player.seek` needs a `time` of 0 or more, not \(time)")
            }
            return .playerSeek(seconds: time)
        case "comment.add":
            if let time = wire.time, !time.isFinite || time < 0 {
                throw .unreadable("the control command `comment.add` needs a `time` of 0 or more, not \(time)")
            }
            return .commentAdd(text: try field(wire.text, "text", of: wire), at: wire.time, region: wire.region)
        case "comment.edit":
            return .commentEdit(id: try field(wire.id, "id", of: wire), text: try field(wire.text, "text", of: wire))
        case "comment.delete":
            return .commentDelete(id: try field(wire.id, "id", of: wire))
        case "batch.send": return .batchSend
        case "context.set": return .contextSet(text: try field(wire.text, "text", of: wire))
        case "wait":
            if let seconds = wire.timeoutSeconds, !(0...ControlRequest.longestTimeout).contains(seconds) {
                throw .unreadable(
                    "the control command `wait` needs a `timeoutSeconds` from 0 to \(ControlRequest.longestTimeout), not \(seconds)"
                )
            }
            return .wait(timeoutSeconds: wire.timeoutSeconds)
        case "thread.answer":
            return .threadAnswer(commentID: try field(wire.id, "id", of: wire), text: try field(wire.text, "text", of: wire))
        case "ack":
            return .ack(batchID: try field(wire.id, "id", of: wire), text: wire.text)
        case "status":
            let state = try field(wire.state, "state", of: wire)
            guard ControlRequest.statuses.contains(state) else {
                throw .unreadable("the control command `status` has no state `\(state)`; it takes `working`, `done` or `failed`")
            }
            return .status(commentID: try field(wire.id, "id", of: wire), state: state)
        case "reply":
            return .reply(id: try field(wire.id, "id", of: wire), text: try field(wire.text, "text", of: wire))
        case "ask":
            if let seconds = wire.waitSeconds, !(0...ControlRequest.longestTimeout).contains(seconds) {
                throw .unreadable(
                    "the control command `ask` needs a `waitSeconds` from 0 to \(ControlRequest.longestTimeout), not \(seconds)"
                )
            }
            return .ask(
                commentID: try field(wire.id, "id", of: wire), question: try field(wire.text, "text", of: wire),
                waitSeconds: wire.waitSeconds
            )
        case "screenshot":
            let path = try absolute(wire)
            // The command checks this too, but the app answers whoever
            // writes to its socket, and it writes a PNG whatever the name.
            guard path.lowercased().hasSuffix(".png") else {
                throw .unreadable("the control command `screenshot` needs a `path` that ends in `.png`, not `\(path)`")
            }
            var appearance: ControlRequest.Appearance?
            if let name = wire.appearance {
                guard let known = ControlRequest.Appearance(rawValue: name) else {
                    throw .unreadable("the control command `screenshot` has no appearance `\(name)`; it takes `light` or `dark`")
                }
                appearance = known
            }
            return .screenshot(path: path, appearance: appearance)
        default: throw .unknownCommand(wire.command)
        }
    }

    /// A field the command can't do without.
    private static func field(_ value: String?, _ name: String, of wire: Wire) throws(ControlProtocolError) -> String {
        guard let value else {
            throw .unreadable("the control command `\(wire.command)` needs its `\(name)`")
        }
        return value
    }

    /// The command's `path`, which must be absolute: the app runs in another
    /// folder than the command.
    private static func absolute(_ wire: Wire) throws(ControlProtocolError) -> String {
        guard let path = wire.path else {
            throw .unreadable("the control command `\(wire.command)` needs its `path`")
        }
        guard path.hasPrefix("/") else {
            throw .unreadable("the control command `\(wire.command)` needs an absolute `path`, not `\(path)`")
        }
        return path
    }

    /// Every request's fields, each optional but `version` and `command`.
    /// `holder` is optional here only so a request without one is refused
    /// in words.
    struct Wire: Codable {
        var version = ControlRequest.version
        var command: String
        var holder: Holder?
        var json: Bool?
        var path: String?
        var time: Double?
        var appearance: String?
        var waitSeconds: Int?
        var timeoutSeconds: Int?
        var id: String?
        var text: String?
        var region: ControlRequest.WireRegion?
        var state: String?
    }
}

/// Why a control request or reply doesn't read.
public enum ControlProtocolError: Error, Equatable, Sendable {
    /// It isn't the JSON object it should be.
    case unreadable(String)
    /// It speaks another version of the protocol: the `video-review`
    /// command and the app come from different builds.
    case otherVersion(Int)
    /// Its version matches but its command doesn't exist.
    case unknownCommand(String)

    /// One line for the reply's `error`, from the app's side.
    public var message: String {
        switch self {
        case .unreadable(let why):
            return why
        case .otherVersion(let other):
            return "the video-review command speaks control version \(other) and the app version \(ControlRequest.version): "
                + "reinstall \(AppIdentity.name) so both come from one build"
        case .unknownCommand(let command):
            return "the app doesn't know the control command `\(command)`"
        }
    }
}
