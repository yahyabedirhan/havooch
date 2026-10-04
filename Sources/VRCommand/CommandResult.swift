/// What one run of the command prints and how it exits: 0 done, 1 refused
/// (or the app isn't running, or gave no reply), 2 for arguments that don't
/// read, 3 for a wait whose time ran out. An `Error` so that parsing
/// returns it as a `Result`'s failure: arguments either read as a request,
/// or are already what to print.
public struct CommandResult: Error, Equatable, Sendable {
    /// Printed on standard output, as it is.
    public var output: String
    /// Printed on standard error, as it is.
    public var error: String
    public var status: Int32

    public static let refusedStatus: Int32 = 1
    public static let usageStatus: Int32 = 2
    public static let timedOutStatus: Int32 = 3

    public init(output: String = "", error: String = "", status: Int32 = 0) {
        self.output = output
        self.error = error
        self.status = status
    }

    /// Refused: `line` on standard error, exit 1.
    public static func failed(_ line: String) -> CommandResult {
        CommandResult(error: line + "\n", status: refusedStatus)
    }

    /// Arguments that don't read: `line`, then `usage`, on standard error,
    /// exit 2.
    public static func misread(_ line: String, usage: String) -> CommandResult {
        CommandResult(error: line + "\n" + usage, status: usageStatus)
    }
}
