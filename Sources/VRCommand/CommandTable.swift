import Foundation
import VRWire

/// What a parsed command line asks for. Everything is one request sent to
/// the app, but the three `app` commands, which have steps of their own
/// since the app may not be running (`AppCommand`).
enum Invocation: Equatable, Sendable {
    case send(ControlRequest)
    case appStatus
    /// The demo folder, absolute, or nil for the person's data.
    case appOpen(demo: URL?)
    case appQuit
}

/// Why a command line doesn't parse: one line, printed above the usage.
struct UsageError: Error, Equatable {
    var line: String

    init(_ line: String) {
        self.line = line
    }
}

/// The words after a command's name, taken apart by its parser.
struct Arguments {
    private var words: [String]
    /// What a relative path is taken against.
    let workingDirectory: URL

    init(_ words: [String], workingDirectory: URL) {
        self.words = words
        self.workingDirectory = workingDirectory
    }

    /// The value after `--name`, taken out; nil when the option isn't there.
    mutating func option(_ name: String) throws(UsageError) -> String? {
        guard let index = words.firstIndex(of: "--\(name)") else { return nil }
        guard index + 1 < words.count else { throw UsageError("--\(name) needs a value") }
        let value = words[index + 1]
        words.removeSubrange(index...index + 1)
        return value
    }

    /// The next word, taken out. Call it after every `option`.
    mutating func positional(_ name: String) throws(UsageError) -> String {
        guard let word = words.first else { throw UsageError("missing <\(name)>") }
        guard !word.hasPrefix("--") else { throw UsageError("unknown option `\(word)`") }
        words.removeFirst()
        return word
    }

    /// Refuses whatever the parser left.
    func finish() throws(UsageError) {
        guard let extra = words.first else { return }
        throw UsageError(extra.hasPrefix("--") ? "unknown option `\(extra)`" : "unexpected `\(extra)`")
    }

    /// `path`, taken against the working folder when it's relative.
    func absolute(_ path: String, isDirectory: Bool) -> URL {
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path, isDirectory: isDirectory)
            : workingDirectory.appendingPathComponent(path, isDirectory: isDirectory)
        return url.standardizedFileURL
    }
}

/// One row of the command table.
struct Command: Sendable {
    /// The words that name it: `["player", "seek"]`.
    var words: [String]
    /// Its usage line, without the program's name.
    var usage: String
    /// What it does, for `video-review help`.
    var summary: String
    var parse: @Sendable (inout Arguments) throws(UsageError) -> Invocation

    var name: String { words.joined(separator: " ") }
}

/// Every command the `video-review` executable knows: the one list `help`
/// and a usage error print from. A new command is a row here.
enum CommandTable {
    static let all: [Command] = [
        Command(words: ["app", "status"], usage: "app status", summary: "whether the app runs, and on which data") { _ in
            .appStatus
        },
        Command(
            words: ["app", "open"], usage: "app open [--demo <folder>]",
            summary: "start the app; with --demo, on that folder's data, leaving the person's alone"
        ) { arguments throws(UsageError) in
            let demo = try arguments.option("demo")
            return .appOpen(demo: demo.map { arguments.absolute($0, isDirectory: true) })
        },
        Command(words: ["app", "quit"], usage: "app quit", summary: "quit the app, and wait until it's gone") { _ in
            .appQuit
        },
        Command(words: ["state"], usage: "state --json", summary: "what the app shows, as one JSON object") { _ in
            .send(.state)
        },
        Command(
            words: ["control", "take"], usage: "control take [--wait <s>]",
            summary: "hold app control for 5 minutes; with --wait, queue behind its holder for up to <s> seconds"
        ) { arguments throws(UsageError) in
            var wait: Int?
            if let text = try arguments.option("wait") {
                guard let seconds = Int(text), (0...ControlRequest.longestWait).contains(seconds) else {
                    throw UsageError("--wait takes whole seconds from 0 to \(ControlRequest.longestWait), not `\(text)`")
                }
                wait = seconds
            }
            return .send(.controlTake(waitSeconds: wait))
        },
        Command(
            words: ["control", "release"], usage: "control release",
            summary: "give app control up, so the next agent in line gets it"
        ) { _ in
            .send(.controlRelease)
        },
        Command(words: ["player", "open"], usage: "player open <path>", summary: "open a video") { arguments throws(UsageError) in
            let path = try arguments.positional("path")
            return .send(.playerOpen(path: arguments.absolute(path, isDirectory: false).path))
        },
        Command(words: ["player", "play"], usage: "player play", summary: "play") { _ in
            .send(.playerPlay)
        },
        Command(words: ["player", "pause"], usage: "player pause", summary: "pause") { _ in
            .send(.playerPause)
        },
        Command(
            words: ["player", "seek"], usage: "player seek <seconds|mm:ss>", summary: "move to a time, exactly"
        ) { arguments throws(UsageError) in
            let text = try arguments.positional("seconds|mm:ss")
            guard let seconds = TimeArgument.seconds(text) else {
                throw UsageError("`\(text)` isn't a time; write seconds (10, 10.5) or mm:ss (0:10)")
            }
            return .send(.playerSeek(seconds: seconds))
        },
        Command(
            words: ["comment", "add"], usage: "comment add <text> [--at <time>] [--region x,y,w,h]",
            summary: "queue a comment at a time, or at the playhead; with --region, on that part of the frame (0..1, origin top left)"
        ) { arguments throws(UsageError) in
            var at: Double?
            if let text = try arguments.option("at") {
                guard let seconds = TimeArgument.seconds(text) else {
                    throw UsageError("`\(text)` isn't a time; write seconds (10, 10.5) or mm:ss (0:10)")
                }
                at = seconds
            }
            var region: WireRegion?
            if let text = try arguments.option("region") {
                guard let numbers = RegionArgument.region(text) else {
                    throw UsageError(
                        "`\(text)` isn't a region; write x,y,w,h as parts of the frame from 0 to 1 (0.48,0.3,0.28,0.12)"
                    )
                }
                region = numbers
            }
            return .send(.commentAdd(text: try arguments.positional("text"), at: at, region: region))
        },
        Command(
            words: ["comment", "edit"], usage: "comment edit <id> <text>", summary: "change a queued comment's text"
        ) { arguments throws(UsageError) in
            let id = try arguments.positional("id")
            return .send(.commentEdit(id: id, text: try arguments.positional("text")))
        },
        Command(
            words: ["comment", "delete"], usage: "comment delete <id>", summary: "delete a queued comment"
        ) { arguments throws(UsageError) in
            .send(.commentDelete(id: try arguments.positional("id")))
        },
        Command(
            words: ["batch", "send"], usage: "batch send", summary: "send every queued comment to the listener as one batch"
        ) { _ in
            .send(.batchSend)
        },
        Command(
            words: ["context", "set"], usage: "context set <text>",
            summary: "set the open video's context note, which the listener gets with the sidecar's text; an empty text clears it"
        ) { arguments throws(UsageError) in
            .send(.contextSet(text: try arguments.positional("text")))
        },
        Command(
            words: ["wait"], usage: "wait [--timeout <s>]",
            summary: "listen: wait for the next batch and print it as JSON; with --timeout, exit 3 when none came in <s> seconds"
        ) { arguments throws(UsageError) in
            var timeout: Int?
            if let text = try arguments.option("timeout") {
                guard let seconds = Int(text), (0...ControlRequest.longestWait).contains(seconds) else {
                    throw UsageError("--timeout takes whole seconds from 0 to \(ControlRequest.longestWait), not `\(text)`")
                }
                timeout = seconds
            }
            return .send(.wait(timeoutSeconds: timeout))
        },
        Command(
            words: ["screenshot"], usage: "screenshot <abs.png> [--appearance light|dark]",
            summary: "write the app's window as a PNG"
        ) { arguments throws(UsageError) in
            var appearance: ControlRequest.Appearance?
            if let name = try arguments.option("appearance") {
                guard let known = ControlRequest.Appearance(rawValue: name) else {
                    throw UsageError("no appearance `\(name)`; it takes `light` or `dark`")
                }
                appearance = known
            }
            let path = try arguments.positional("abs.png")
            // The app runs in another folder, so the contract asks for an absolute path.
            guard path.hasPrefix("/") else { throw UsageError("`\(path)` isn't an absolute path") }
            return .send(.screenshot(path: path, appearance: appearance))
        },
    ]

    /// The command `words` starts with: the row with the most words that
    /// all match.
    static func match(_ words: [String]) -> Command? {
        all.filter { words.starts(with: $0.words) }.max { $0.words.count < $1.words.count }
    }

    /// What `video-review help` prints.
    static var help: String {
        let width = all.map(\.usage.count).max() ?? 0
        let rows = all.map { "  video-review \($0.usage.padding(toLength: width, withPad: " ", startingAt: 0))  \($0.summary)" }
        return """
            usage: video-review <command> [--json]

            \(rows.joined(separator: "\n"))

            --json, anywhere on the line, gives the output as one JSON object.
            One agent at a time drives the app. A command that drives it takes or renews
            the lease, which ends 60 s after its holder's last command and 5 min after it
            was taken at most. While another agent holds it, such a command exits 1 and
            names the holder and the lease's end. `app status`, `state` and `wait` need no
            lease. A listener is present while its `wait` is open.
            Exit codes: 0 done, 1 refused or failed, 2 the command line doesn't parse,
            3 a `wait --timeout` ran out with no batch.

            """
    }
}
