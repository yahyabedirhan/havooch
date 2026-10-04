import Foundation
import VRLease

/// The app's answer to one request: `ok` with what to print on standard
/// output (`output`) and, rarely, a note for standard error (`error`), or a
/// refusal (`ok` false) whose `error` says why. The reply to `app.quit`
/// also carries the lease the quit renewed (`lease`), for a relaunch to
/// hand over to the app it launches; every other reply leaves it out.
public struct ControlReply: Codable, Equatable, Sendable {
    public var ok: Bool
    public var output: String
    public var error: String
    public var lease: ControlLease.Term?

    public init(ok: Bool, output: String = "", error: String = "", lease: ControlLease.Term? = nil) {
        self.ok = ok
        self.output = output
        self.error = error
        self.lease = lease
    }

    /// Done: `output` printed as it is.
    public static func done(_ output: String, note: String = "") -> ControlReply {
        ControlReply(ok: true, output: output, error: note)
    }

    /// Refused: one line on standard error, exit 1.
    public static func refused(_ why: String) -> ControlReply {
        ControlReply(ok: false, error: why)
    }

    /// The reply as one JSON object.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding a struct of strings, booleans and dates can't fail.
        return try! encoder.encode(self)
    }

    /// Reads the app's reply. Spaces before it (a waiting connection's
    /// heartbeat) are skipped, as JSON allows.
    public static func decode(_ data: Data) throws(ControlProtocolError) -> ControlReply {
        do {
            return try JSONDecoder().decode(ControlReply.self, from: data)
        } catch {
            throw .unreadable("the app's reply doesn't read")
        }
    }
}
