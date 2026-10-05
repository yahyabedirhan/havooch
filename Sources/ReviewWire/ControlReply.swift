import Foundation
import ReviewLease

/// The app's answer to one request: `ok` with what to print on standard
/// output (`output`) and, rarely, a note for standard error (`error`), or a
/// refusal (`ok` false) whose `error` says why. The reply to `app.quit` may
/// carry the lease the quit renewed (`lease`), for a relaunch to hand over
/// to the app it launches. The reply to a `wait` whose time ran out with no
/// send says so (`timedOut`), which the command exits 2 on. Every other
/// reply leaves both out.
public struct ControlReply: Codable, Equatable, Sendable {
    public var ok: Bool
    public var output: String
    public var error: String
    public var lease: LeaseTerm?
    /// True when the request waited its whole time and has nothing to say.
    public var timedOut: Bool?

    public init(ok: Bool, output: String = "", error: String = "", lease: LeaseTerm? = nil, timedOut: Bool? = nil) {
        self.ok = ok
        self.output = output
        self.error = error
        self.lease = lease
        self.timedOut = timedOut
    }

    /// Done: `output` printed as it is.
    public static func done(_ output: String, note: String = "") -> ControlReply {
        ControlReply(ok: true, output: output, error: note)
    }

    /// Refused: one line on standard error, exit 1.
    public static func refused(_ why: String) -> ControlReply {
        ControlReply(ok: false, error: why)
    }

    /// The wait ran out with no result: nothing printed, exit 2.
    public static let ranOut = ControlReply(ok: false, timedOut: true)

    /// The reply as one JSON object.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding a struct of strings, numbers and booleans can't fail.
        return try! encoder.encode(self)
    }

    /// Reads the app's reply.
    public static func decode(_ data: Data) throws(ControlProtocolError) -> ControlReply {
        do {
            return try JSONDecoder().decode(ControlReply.self, from: data)
        } catch {
            throw .unreadable("the app's reply doesn't read")
        }
    }
}
