import Foundation

/// One request as it goes over the socket: what's asked, who asks, and
/// whether the caller passed `--json`. On the wire it's one JSON object
/// naming the protocol's `version`, the `command` and the `holder`, with the
/// command's own fields beside them:
///
///     {"command":"player.seek","holder":{"key":"…","name":"Claude Code","place":"/Users/me/shop"},"json":false,"seconds":10,"version":1}
///
/// The wire format is a contract between a `video-review` and the app of
/// the same build.
public struct ControlMessage: Equatable, Sendable {
    public var request: ControlRequest
    public var holder: Holder
    /// Whether the answer's `output` is JSON, not lines.
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
        case .appStatus: wire = Wire(command: "app.status")
        case .state: wire = Wire(command: "state")
        case .controlTake(let waitSeconds): wire = Wire(command: "control.take", waitSeconds: waitSeconds)
        case .controlRelease: wire = Wire(command: "control.release")
        case .appOpen: wire = Wire(command: "app.open")
        case .appQuit: wire = Wire(command: "app.quit")
        case .playerOpen(let path): wire = Wire(command: "player.open", path: path)
        case .playerPlay: wire = Wire(command: "player.play")
        case .playerPause: wire = Wire(command: "player.pause")
        case .playerSeek(let seconds): wire = Wire(command: "player.seek", seconds: seconds)
        case .screenshot(let path, let appearance, let withBanner):
            wire = Wire(command: "screenshot", path: path, appearance: appearance?.rawValue, withBanner: withBanner ? true : nil)
        case .commentAdd(let text, let at, let region):
            wire = Wire(command: "comment.add", text: text, at: at, region: region)
        case .commentEdit(let id, let text): wire = Wire(command: "comment.edit", id: id, text: text)
        case .commentDelete(let id): wire = Wire(command: "comment.delete", id: id)
        }
        wire.holder = holder
        wire.json = json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding a struct of strings, numbers and booleans can't fail.
        return try! encoder.encode(wire)
    }

    /// Reads a message the client sent. It refuses in this order: not JSON,
    /// another version (naming both), no holder, a command this build
    /// doesn't know, a field that's missing or invalid.
    public static func decode(_ data: Data) throws(ControlProtocolError) -> ControlMessage {
        // The version is read alone first: a message of another version may
        // shape its other fields differently.
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw .unreadable("the request isn't a control request")
        }
        guard envelope.version == Version.controlProtocol else { throw .otherVersion(envelope.version) }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else {
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
        case "player.open": return .playerOpen(path: try absolute(wire))
        case "player.play": return .playerPlay
        case "player.pause": return .playerPause
        case "player.seek":
            guard let seconds = wire.seconds, seconds.isFinite, seconds >= 0 else {
                throw .unreadable("the control command `player.seek` needs its `seconds`, 0 or more")
            }
            return .playerSeek(seconds: seconds)
        case "screenshot":
            let path = try absolute(wire)
            var appearance: ControlRequest.Appearance?
            if let name = wire.appearance {
                guard let known = ControlRequest.Appearance(rawValue: name) else {
                    throw .unreadable("the control command `screenshot` has no appearance `\(name)`; it takes `light` or `dark`")
                }
                appearance = known
            }
            return .screenshot(path: path, appearance: appearance, withBanner: wire.withBanner ?? false)
        case "comment.add":
            if let at = wire.at, !at.isFinite || at < 0 {
                throw .unreadable("the control command `comment.add` needs its `at` to be 0 or more")
            }
            return .commentAdd(text: try field(wire.text, "text", of: wire), at: wire.at, region: wire.region)
        case "comment.edit":
            return .commentEdit(id: try field(wire.id, "id", of: wire), text: try field(wire.text, "text", of: wire))
        case "comment.delete":
            return .commentDelete(id: try field(wire.id, "id", of: wire))
        default: throw .unknownCommand(wire.command)
        }
    }

    /// A field the command needs.
    private static func field(_ value: String?, _ name: String, of wire: Wire) throws(ControlProtocolError) -> String {
        guard let value else { throw .unreadable("the control command `\(wire.command)` needs its `\(name)`") }
        return value
    }

    /// The command's `path`, absolute since the app runs in another folder.
    private static func absolute(_ wire: Wire) throws(ControlProtocolError) -> String {
        guard let path = wire.path else {
            throw .unreadable("the control command `\(wire.command)` needs its `path`")
        }
        guard path.hasPrefix("/") else {
            throw .unreadable("the control command `\(wire.command)` needs an absolute `path`, not `\(path)`")
        }
        return path
    }

    /// What every version of the protocol has.
    private struct Envelope: Decodable {
        var version: Int
    }

    /// Every request's fields, each optional but `version` and `command`.
    /// `holder` is optional here only so a request without one is refused
    /// in words.
    private struct Wire: Codable {
        var version = Version.controlProtocol
        var command: String
        var holder: Holder?
        var json: Bool?
        var path: String?
        var seconds: Double?
        var appearance: String?
        var waitSeconds: Int?
        var withBanner: Bool?
        var id: String?
        var text: String?
        var at: Double?
        var region: ControlRequest.Rectangle?
    }
}
