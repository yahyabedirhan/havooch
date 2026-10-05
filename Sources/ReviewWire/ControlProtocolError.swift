/// Why a control request or reply doesn't read.
public enum ControlProtocolError: Error, Equatable, Sendable {
    /// It isn't the JSON object it should be, or a field is missing or
    /// invalid.
    case unreadable(String)
    /// It speaks another version of the protocol: the `havooch` command
    /// and the app come from different builds.
    case otherVersion(Int)
    /// Its version matches but its command doesn't exist.
    case unknownCommand(String)

    /// One line for the reply's `error`, from the app's side.
    public var message: String {
        switch self {
        case .unreadable(let why):
            return why
        case .otherVersion(let other):
            return "the havooch command speaks control version \(other) and the app speaks version \(Version.controlProtocol): "
                + "reinstall \(AppIdentity.appName) so both come from one build"
        case .unknownCommand(let command):
            return "the app doesn't know the control command `\(command)`"
        }
    }
}
