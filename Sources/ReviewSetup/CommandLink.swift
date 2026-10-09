import Foundation

/// The `havooch` command linked into `~/.local/bin`: whether the link is
/// there, making it, and the `ln -sf` line to copy when Havooch can't.
/// Havooch never claims the agent's PATH reaches the folder.
public struct CommandLink: Sendable {
    public var fileSystem: any SetupFileSystem
    public var home: String

    /// The folder the link goes in, from the home folder.
    public static let folder = ".local/bin"
    /// The command's name, and the link's.
    public static let command = "havooch"
    /// Where the command is inside an app bundle.
    public static let bundlePath = "Contents/Helpers/havooch"

    public init(fileSystem: any SetupFileSystem = LocalFileSystem(), home: String) {
        self.fileSystem = fileSystem
        self.home = home
    }

    /// The link file: `~/.local/bin/havooch`.
    public var linkPath: String { "\(home)/\(Self.folder)/\(Self.command)" }

    /// The link as the probe found it.
    public struct State: Equatable, Sendable {
        public var detection: Detection
        public var path: String
        /// Where the link points, when there is a link.
        public var destination: String?

        public init(detection: Detection, path: String, destination: String? = nil) {
            self.detection = detection
            self.path = path
            self.destination = destination
        }
    }

    /// Detected when the link file is a link and points to the command
    /// inside an app bundle that is there. A link elsewhere, a plain file
    /// or nothing is not detected.
    public func state() -> State {
        switch fileSystem.item(at: linkPath) {
        case .link(let written):
            let destination = resolved(written)
            let found = Self.isInBundle(destination) && fileSystem.target(at: destination) == .file
            return State(detection: found ? .detected : .notDetected, path: linkPath, destination: destination)
        case .unreadable:
            return State(detection: .cannotKnow, path: linkPath)
        case .missing, .file, .folder:
            return State(detection: .notDetected, path: linkPath)
        }
    }

    /// Why Havooch couldn't make the link, with the line that makes it
    /// in a terminal.
    public struct Failure: Error, Equatable, Sendable {
        public var reason: String
        /// `mkdir -p ~/.local/bin && ln -sf '<command>' ~/.local/bin/havooch`.
        public var fallback: String

        public init(reason: String, fallback: String) {
            self.reason = reason
            self.fallback = fallback
        }
    }

    /// Links `command` (the `havooch` inside this app's bundle) at
    /// `~/.local/bin/havooch`, making the folder when it isn't there. A link
    /// already there is replaced, as `ln -sf` does; anything else there is
    /// left alone and the link fails.
    public func make(to command: String) throws(Failure) {
        let folder = "\(home)/\(Self.folder)"
        do {
            try fileSystem.makeFolder(at: folder)
        } catch {
            throw failure("Havooch couldn't make \(folder): \(error.localizedDescription)", command)
        }
        switch fileSystem.item(at: linkPath) {
        case .missing:
            break
        case .link:
            do {
                try fileSystem.remove(at: linkPath)
            } catch {
                throw failure("Havooch couldn't replace the link at \(linkPath): \(error.localizedDescription)", command)
            }
        case .file, .folder:
            throw failure("\(linkPath) is already there and isn't a link, so Havooch leaves it alone", command)
        case .unreadable:
            throw failure("Havooch can't read \(folder)", command)
        }
        do {
            try fileSystem.makeLink(at: linkPath, to: command)
        } catch {
            throw failure("Havooch couldn't make the link at \(linkPath): \(error.localizedDescription)", command)
        }
    }

    /// The line that links `command` in a terminal.
    public static func fallback(to command: String) -> String {
        "mkdir -p ~/\(folder) && ln -sf \(shellQuoted(command)) ~/\(folder)/\(Self.command)"
    }

    private func failure(_ reason: String, _ command: String) -> Failure {
        Failure(reason: reason, fallback: Self.fallback(to: command))
    }

    /// `written` as an absolute path: a relative link points from the
    /// link's folder.
    private func resolved(_ written: String) -> String {
        guard !written.hasPrefix("/") else { return written }
        return URL(fileURLWithPath: "\(home)/\(Self.folder)", isDirectory: true)
            .appendingPathComponent(written).standardizedFileURL.path
    }

    /// Whether `path` is the command inside an app bundle:
    /// `…/<name>.app/Contents/Helpers/havooch`.
    static func isInBundle(_ path: String) -> Bool {
        guard path.hasSuffix("/" + bundlePath) else { return false }
        let bundle = path.dropLast(bundlePath.count + 1)
        return bundle.hasSuffix(".app") && bundle.count > ".app".count
    }
}

/// `text` as one shell word: in single quotes when it needs them.
func shellQuoted(_ text: String) -> String {
    let plain = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+:@%="))
    if !text.isEmpty, text.unicodeScalars.allSatisfy(plain.contains) { return text }
    return "'" + text.replacing("'", with: "'\\''") + "'"
}
