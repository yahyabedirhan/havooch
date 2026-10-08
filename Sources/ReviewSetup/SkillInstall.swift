import Foundation

/// Runs a program and hands each line it writes (standard output and
/// standard error together) to `line`, as it comes: the seam the tests
/// fake. Cancelling the task that awaits `run` stops the program.
public protocol ProcessRunner: Sendable {
    /// The program's exit status once it ends.
    func run(_ executable: String, arguments: [String], line: @escaping @Sendable (String) -> Void) async -> Int32
}

/// One global install of the `havooch-mate` skill, for some harnesses, with
/// `npx skills add` through the person's login shell, so the shell's PATH
/// finds Node as a terminal would.
public struct SkillInstall: Equatable, Sendable {
    /// The harnesses it installs for, in the catalog's order.
    public var harnesses: [Harness]
    /// The person's login shell: `$SHELL`, else zsh.
    public var shell: String

    public init(for harnesses: [Harness], shell: String = "/bin/zsh") {
        self.harnesses = harnesses
        self.shell = shell
    }

    /// How an install ended.
    public enum Outcome: Equatable, Sendable {
        /// `npx` ran and exited with `status`; 0 is success.
        case finished(status: Int32)
        /// The login shell finds no `npx`: Node is necessary. Nothing ran.
        case noNode
        /// Cancel stopped it.
        case cancelled
    }

    /// `npx skills add yahyabedirhan/havooch-mate --skill havooch-mate -g -y -a claude-code -a codex`.
    public var commandLine: String {
        Self.commandLine(for: harnesses, global: true)
    }

    /// The same install into the repository the terminal is in, for the
    /// person to copy: no `-g`.
    public var repositoryCommandLine: String {
        Self.commandLine(for: harnesses, global: false)
    }

    /// The line `npx skills add` runs from: global, with no questions
    /// (`-y`), for each harness (`-a`).
    static func commandLine(for harnesses: [Harness], global: Bool) -> String {
        var words = ["npx", "skills", "add", HarnessCatalog.source, "--skill", HarnessCatalog.skill]
        if global { words.append("-g") }
        words.append("-y")
        for harness in harnesses {
            words += ["-a", harness.installName]
        }
        return words.joined(separator: " ")
    }

    /// The line that finds `npx` in the login shell.
    static let findNode = "command -v npx"

    /// The CLI's spinner redraws one line in place with no newline, so a
    /// pipe gets nothing whole until the step ends. As CI it writes each
    /// step once, on its own line, and without colour.
    static let plainOutput = "env CI=true NO_COLOR=1 "

    /// Looks for `npx`, then runs the install, each readable line it writes
    /// handed to `line`. Cancelling the awaiting task stops it.
    public func run(with runner: any ProcessRunner, line: @escaping @Sendable (String) -> Void) async -> Outcome {
        let found = await runner.run(shell, arguments: ["-l", "-c", Self.findNode]) { _ in }
        if Task.isCancelled { return .cancelled }
        guard found == 0 else { return .noNode }
        let status = await runner.run(shell, arguments: ["-l", "-c", "exec " + Self.plainOutput + commandLine]) { written in
            Self.readable(written).map(line)
        }
        return Task.isCancelled ? .cancelled : .finished(status: status)
    }

    /// The line without its terminal escape codes and edge spaces; nil when
    /// nothing is left to read, or only the CLI's guide bar.
    static func readable(_ written: String) -> String? {
        let text = written
            .replacing(/\u{1B}\[[0-9;?]*[ -\/]*[@-~]/, with: "")
            .replacing(/\u{1B}\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\)/, with: "")
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty || text == "│" ? nil : text
    }
}

/// Runs programs on the Mac with `Process`.
public struct LocalProcessRunner: ProcessRunner {
    public init() {}

    public func run(_ executable: String, arguments: [String], line: @escaping @Sendable (String) -> Void) async -> Int32 {
        let running = RunningProcess(executable: executable, arguments: arguments)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (finished: CheckedContinuation<Int32, Never>) in
                // Reading blocks until the program ends: off the caller's thread.
                Thread.detachNewThread {
                    finished.resume(returning: running.start(line: line))
                }
            }
        } onCancel: {
            running.cancel()
        }
    }
}

/// One program, started at most once and stopped by `cancel` from any
/// thread: before it starts (it then never does) or while it runs.
private final class RunningProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var isRunning = false
    private var isCancelled = false

    /// The exit status `run` reports when the program never started.
    static let notStarted: Int32 = 127

    init(executable: String, arguments: [String]) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
    }

    /// Runs the program, hands each line to `line`, and returns the exit
    /// status once it ends.
    func start(line: @escaping @Sendable (String) -> Void) -> Int32 {
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return Self.notStarted
        }
        do {
            try process.run()
        } catch {
            lock.unlock()
            line("couldn't start \(process.executableURL?.path ?? "the program"): \(error.localizedDescription)")
            return Self.notStarted
        }
        isRunning = true
        lock.unlock()
        // The parent's copy of the writing end closes, so reading ends with the program.
        try? pipe.fileHandleForWriting.close()
        var lines = LineBuffer()
        let reading = pipe.fileHandleForReading
        while true {
            let data = reading.availableData
            if data.isEmpty { break }
            lines.append(data).forEach(line)
        }
        lines.rest().map(line)
        process.waitUntilExit()
        return process.terminationStatus
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        if isRunning, process.isRunning { process.terminate() }
    }
}

/// Bytes cut into lines at each newline, a line split across two reads
/// kept until its end comes.
struct LineBuffer {
    private var pending = Data()

    /// The whole lines `data` ends, without their newlines.
    mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let end = pending.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(Self.text(pending[pending.startIndex..<end]))
            pending.removeSubrange(pending.startIndex...end)
        }
        return lines
    }

    /// The last line, when the program ended without a newline.
    mutating func rest() -> String? {
        defer { pending.removeAll() }
        return pending.isEmpty ? nil : Self.text(pending)
    }

    /// The line as text, a carriage return at its end left out.
    private static func text(_ bytes: Data) -> String {
        var text = String(decoding: bytes, as: UTF8.self)
        if text.hasSuffix("\r") { text.removeLast() }
        return text
    }
}
