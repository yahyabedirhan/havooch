/// What a command leaves behind: its standard output, its standard error
/// and its exit code. An `Error` too, so a step that can't go on fails with
/// what the command then exits with.
public struct CommandResult: Error, Equatable, Sendable {
    public var output: String
    public var error: String
    public var exitCode: Int32

    /// Done.
    public static let success: Int32 = 0
    /// Refused or failed: the app isn't running, or it refused the request.
    public static let refusal: Int32 = 1
    /// The command line doesn't parse.
    public static let usage: Int32 = 2
    /// A `wait --timeout` ran out with nothing to return.
    public static let ranOut: Int32 = 3

    public init(output: String = "", error: String = "", exitCode: Int32 = CommandResult.success) {
        self.output = output
        self.error = error
        self.exitCode = exitCode
    }

    /// One line on standard error, exit 1.
    static func failed(_ line: String) -> CommandResult {
        CommandResult(error: line + "\n", exitCode: refusal)
    }
}
