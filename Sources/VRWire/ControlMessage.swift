import Foundation
import VRLease

/// One request as it goes over the socket: what's asked, who asks, and
/// whether the output is wanted as JSON. On the wire it's one JSON object
/// naming the protocol's `version`, the `command`, the `holder` and `json`,
/// with the command's own fields beside them:
///
///     {"command":"player.seek","holder":{"key":"…","name":"Claude Code","place":"/Users/me/repo"},"json":false,"seconds":10,"version":1}
///
/// The wire format is a contract between a `video-review` and the app of
/// the same build.
public struct ControlMessage: Equatable, Sendable {
    public var request: ControlRequest
    public var holder: Holder
    public var json: Bool

    public init(_ request: ControlRequest, holder: Holder, json: Bool = false) {
        self.request = request
        self.holder = holder
        self.json = json
    }

    /// The message as one JSON object.
    public func encoded() -> Data {
        var wire = Wire(command: request.command, holder: holder, json: json)
        switch request {
        case .appStatus, .state, .controlRelease, .appOpen, .appQuit, .playerPlay, .playerPause, .batchSend:
            break
        case .controlTake(let waitSeconds):
            wire.waitSeconds = waitSeconds
        case .playerOpen(let path):
            wire.path = path
        case .playerSeek(let seconds):
            wire.seconds = seconds
        case .commentAdd(let text, let at, let region):
            wire.text = text
            wire.at = at
            wire.region = region
        case .commentEdit(let id, let text), .threadAnswer(let id, let text), .reply(let id, let text):
            wire.id = id
            wire.text = text
        case .commentDelete(let id):
            wire.id = id
        case .contextSet(let text):
            wire.text = text
        case .screenshot(let path, let appearance):
            wire.path = path
            wire.appearance = appearance?.rawValue
        case .wait(let timeoutSeconds):
            wire.timeoutSeconds = timeoutSeconds
        case .ack(let id, let text):
            wire.id = id
            wire.text = text
        case .status(let id, let state):
            wire.id = id
            wire.state = state
        case .ask(let id, let text, let waitSeconds):
            wire.id = id
            wire.text = text
            wire.waitSeconds = waitSeconds
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding a struct of strings, numbers and booleans can't fail.
        return try! encoder.encode(wire)
    }

    /// Reads a message the client sent. The version is checked before
    /// anything else: a request of another version is refused whatever else
    /// it holds. Then refused when it isn't a request, has no holder, names
    /// a command this build doesn't know, or lacks a field its command needs.
    public static func decode(_ data: Data) throws(ControlProtocolError) -> ControlMessage {
        let decoder = JSONDecoder()
        guard let versioned = try? decoder.decode(Versioned.self, from: data) else {
            throw .unreadable("the request isn't a control request")
        }
        guard versioned.version == ControlRequest.version else { throw .otherVersion(versioned.version) }
        guard let wire = try? decoder.decode(Wire.self, from: data) else {
            throw .unreadable("the request isn't a control request")
        }
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
        case "player.open": return .playerOpen(path: try wire.absolutePath())
        case "player.play": return .playerPlay
        case "player.pause": return .playerPause
        case "player.seek":
            let seconds = try wire.field(\.seconds, "seconds")
            guard seconds.isFinite, seconds >= 0 else {
                throw .unreadable("the control command `player.seek` needs `seconds` of 0 or more, not \(seconds)")
            }
            return .playerSeek(seconds: seconds)
        case "comment.add": return .commentAdd(text: try wire.field(\.text, "text"), at: wire.at, region: wire.region)
        case "comment.edit": return .commentEdit(id: try wire.field(\.id, "id"), text: try wire.field(\.text, "text"))
        case "comment.delete": return .commentDelete(id: try wire.field(\.id, "id"))
        case "batch.send": return .batchSend
        case "thread.answer": return .threadAnswer(id: try wire.field(\.id, "id"), text: try wire.field(\.text, "text"))
        case "context.set": return .contextSet(text: try wire.field(\.text, "text"))
        case "screenshot":
            var appearance: ControlRequest.Appearance?
            if let name = wire.appearance {
                guard let known = ControlRequest.Appearance(rawValue: name) else {
                    throw .unreadable("the control command `screenshot` has no appearance `\(name)`; it takes `light` or `dark`")
                }
                appearance = known
            }
            return .screenshot(path: try wire.absolutePath(), appearance: appearance)
        case "wait":
            if let seconds = wire.timeoutSeconds, !(0...ControlRequest.longestWait).contains(seconds) {
                throw .unreadable(
                    "the control command `wait` needs a `timeoutSeconds` from 0 to \(ControlRequest.longestWait), not \(seconds)"
                )
            }
            return .wait(timeoutSeconds: wire.timeoutSeconds)
        case "ack": return .ack(id: try wire.field(\.id, "id"), text: wire.text)
        case "status": return .status(id: try wire.field(\.id, "id"), state: try wire.field(\.state, "state"))
        case "reply": return .reply(id: try wire.field(\.id, "id"), text: try wire.field(\.text, "text"))
        case "ask":
            if let seconds = wire.waitSeconds, !(0...ControlRequest.longestWait).contains(seconds) {
                throw .unreadable(
                    "the control command `ask` needs a `waitSeconds` from 0 to \(ControlRequest.longestWait), not \(seconds)"
                )
            }
            return .ask(id: try wire.field(\.id, "id"), text: try wire.field(\.text, "text"), waitSeconds: wire.waitSeconds)
        default: throw .unknownCommand(wire.command)
        }
    }

    /// Only the version, read first, so a request of another version is
    /// told so even when its other fields have changed shape.
    private struct Versioned: Decodable {
        var version: Int
    }

    /// Every request's fields, each optional but `version` and `command`.
    /// `holder` is optional here only so a request without one is refused
    /// in words.
    private struct Wire: Codable {
        var version = ControlRequest.version
        var command: String
        var holder: Holder?
        var json: Bool?
        var path: String?
        var seconds: Double?
        var text: String?
        var at: Double?
        var region: WireRegion?
        var id: String?
        var state: String?
        var appearance: String?
        var waitSeconds: Int?
        var timeoutSeconds: Int?

        /// The field at `path`, which `command` needs: refused when the
        /// request leaves it out.
        func field<Value>(_ path: KeyPath<Wire, Value?>, _ key: String) throws(ControlProtocolError) -> Value {
            guard let value = self[keyPath: path] else {
                throw .unreadable("the control command `\(command)` needs its `\(key)`")
            }
            return value
        }

        /// `path`, which must be absolute: the app runs in another folder.
        func absolutePath() throws(ControlProtocolError) -> String {
            let path = try field(\.path, "path")
            guard path.hasPrefix("/") else {
                throw .unreadable("the control command `\(command)` needs an absolute `path`, not `\(path)`")
            }
            return path
        }
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
                + "run the command from this app's bundle (Contents/Helpers/video-review) so both come from one build"
        case .unknownCommand(let command):
            return "the app doesn't know the control command `\(command)`"
        }
    }
}
