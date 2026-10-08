import Foundation
import Observation
import ReviewSetup
import ReviewWire

/// The person's setup as Havooch sees it: the latest probe, the link
/// action and its failure, and the skill install with its live log. It
/// probes when the app launches, when the app comes forward, and after Link
/// or an install ends; it never polls (P10). Only what is detected counts
/// as done (ADR 0005).
@Observable
final class SetupDesk {
    /// What the last probe found.
    private(set) var report: SetupReport
    /// Why the last Link failed, with the `ln -sf` line; nil once one works.
    private(set) var linkFailure: CommandLink.Failure?
    /// The running install, or the last one, kept after it ends so its log
    /// and its outcome still show.
    private(set) var install: InstallRun?

    /// One install: what it runs, for which harnesses, how far it is, and
    /// the lines it wrote.
    struct InstallRun: Equatable {
        enum State: String, Equatable {
            case running, done, failed, cancelled
            /// The login shell finds no `npx`: Node is necessary.
            case noNode
        }

        var install: SkillInstall
        var state: State
        /// The exit status once `npx` ended; nil while it runs, and when it
        /// never ran.
        var exitStatus: Int32?
        /// The lines it wrote, the oldest first, the last `logLimit` kept.
        var log: [String] = []
    }

    /// The most log lines an install keeps.
    static let logLimit = 500

    /// The home folder setup reads: `$HOME` of the app's environment.
    @ObservationIgnored let home: String
    /// The `havooch` command in this app's bundle; nil in a build that
    /// isn't bundled (`swift test`, `swift run`).
    @ObservationIgnored let command: String?
    @ObservationIgnored private let shell: String
    @ObservationIgnored private let fileSystem: any SetupFileSystem
    @ObservationIgnored private let runner: any ProcessRunner
    @ObservationIgnored private var installing: Task<Void, Never>?
    /// How many times the disk was read, for the tests.
    @ObservationIgnored private(set) var probes = 0

    /// Reads the setup once. `environment` names the home folder and the
    /// login shell; `bundle` is the app's, whose `havooch` Link links.
    init(
        environment: [String: String], bundle: URL = Bundle.main.bundleURL,
        fileSystem: any SetupFileSystem = LocalFileSystem(), runner: any ProcessRunner = LocalProcessRunner()
    ) {
        home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        shell = environment["SHELL"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? "/bin/zsh"
        let bundled = bundle.appendingPathComponent(CommandLink.bundlePath).path
        command = bundle.pathExtension == "app" && fileSystem.target(at: bundled) == .file ? bundled : nil
        self.fileSystem = fileSystem
        self.runner = runner
        report = SetupProbe(fileSystem: fileSystem, home: home).probe()
        probes = 1
    }

    /// Reads the disk again.
    func probe() {
        report = SetupProbe(fileSystem: fileSystem, home: home).probe()
        probes += 1
    }

    // MARK: - Link

    /// Links this app's `havooch` in `~/.local/bin`, then reads the disk
    /// again. A failure is kept for the view, and refused with the line to
    /// run in a terminal.
    func link() throws(AppRefusal) {
        let command = try bundledCommand()
        do throws(CommandLink.Failure) {
            try CommandLink(fileSystem: fileSystem, home: home).make(to: command)
            linkFailure = nil
            probe()
        } catch {
            linkFailure = error
            probe()
            throw AppRefusal("\(error.reason). Run this in a terminal: \(error.fallback)")
        }
    }

    /// What Link would do, without doing it.
    func linkPlan() throws(AppRefusal) -> (path: String, command: String) {
        (CommandLink(fileSystem: fileSystem, home: home).linkPath, try bundledCommand())
    }

    private func bundledCommand() throws(AppRefusal) -> String {
        guard let command else {
            throw AppRefusal("this build of \(AppIdentity.appName) isn't an app bundle, so it has no havooch command to link")
        }
        return command
    }

    // MARK: - Install

    /// The install for the harnesses `names` name, or for every harness
    /// found without the skill when they name none. Refused when an install
    /// runs, when a name is no harness Havooch knows, and when there is no
    /// harness to install for.
    func plan(for names: [String]) throws(AppRefusal) -> SkillInstall {
        if install?.state == .running {
            throw AppRefusal("an install is already running; havooch setup cancel stops it")
        }
        var harnesses: [Harness] = []
        for name in names {
            guard let harness = HarnessCatalog.harness(named: name) else {
                let known = HarnessCatalog.all.map(\.installName)
                throw AppRefusal("no harness \(name); Havooch sets up \(known.dropLast().joined(separator: ", ")) and \(known.last ?? "")")
            }
            if !harnesses.contains(harness) { harnesses.append(harness) }
        }
        if names.isEmpty {
            probe()
            harnesses = report.harnessesLackingSkill
            guard !harnesses.isEmpty else {
                let found = report.harnesses.filter { $0.presence == .detected }.map(\.harness.name)
                throw AppRefusal(found.isEmpty
                    ? "Havooch found no harness to install for; name one with --harness"
                    : "the skill is detected for every harness found (\(found.joined(separator: ", "))); name one with --harness to install it again")
            }
        }
        // The catalog's order, whatever order they were named in.
        return SkillInstall(for: HarnessCatalog.all.filter(harnesses.contains), shell: shell)
    }

    /// Starts installing the skill for the harnesses `names` name (see
    /// `plan(for:)`). The install runs on; its lines join the log as they
    /// come, and the disk is read again once it ends.
    @discardableResult
    func startInstall(for names: [String]) throws(AppRefusal) -> InstallRun {
        let install = try plan(for: names)
        let run = InstallRun(install: install, state: .running)
        self.install = run
        let (lines, writer) = AsyncStream.makeStream(of: String.self)
        let runner = runner
        installing = Task { [weak self] in
            let reading = Task { [weak self] in
                for await line in lines { self?.logged(line) }
            }
            let outcome = await install.run(with: runner) { writer.yield($0) }
            writer.finish()
            await reading.value
            self?.ended(outcome)
        }
        return run
    }

    /// Stops the running install, and answers once it has stopped.
    func cancelInstall() async throws(AppRefusal) -> InstallRun {
        guard let install, install.state == .running, let installing else {
            throw AppRefusal("no install is running")
        }
        installing.cancel()
        await installing.value
        return self.install ?? install
    }

    /// Waits for the running install to end; at once with none.
    func installEnded() async {
        await installing?.value
    }

    private func logged(_ line: String) {
        guard install != nil else { return }
        install?.log.append(line)
        if let count = install?.log.count, count > Self.logLimit {
            install?.log.removeFirst(count - Self.logLimit)
        }
    }

    private func ended(_ outcome: SkillInstall.Outcome) {
        switch outcome {
        case .finished(let status):
            install?.exitStatus = status
            install?.state = status == 0 ? .done : .failed
        case .noNode:
            install?.state = .noNode
            install?.log.append("Node is necessary to install the skill: npx wasn't found in your login shell. Install Node, then try again.")
        case .cancelled:
            install?.state = .cancelled
        }
        installing = nil
        probe()
    }
}

// MARK: - The model's setup actions

extension AppModel {
    /// Setup as `state` reports it, prompts naming the open video.
    var setupReport: StateReport.Setup {
        StateReport.Setup(setup, target: video.map { .video(fileName: $0.url.lastPathComponent) })
    }

    /// `setup status`: the disk read again, then the report.
    func setupStatus() -> StateReport.Setup {
        setup.probe()
        return setupReport
    }

    /// Links the command, as Link does, or with `dryRun` says what Link
    /// would do. Returns the line the command prints.
    func linkCommand(dryRun: Bool) throws(AppRefusal) -> (line: String, setup: StateReport.Setup) {
        if dryRun {
            let plan = try setup.linkPlan()
            return ("would link \(plan.path) to \(plan.command)", setupReport)
        }
        try setup.link()
        let commandLine = setupReport.commandLine
        return ("linked \(commandLine.path) to \(commandLine.destination ?? setup.command ?? "")", setupReport)
    }

    /// Starts the skill install, as Install does, or with `dryRun` plans it.
    func installSkill(harnesses names: [String], dryRun: Bool) throws(AppRefusal) -> StateReport.Setup.Install {
        if dryRun { return StateReport.Setup.Install(try setup.plan(for: names), state: "planned") }
        return StateReport.Setup.Install(try setup.startInstall(for: names))
    }

    /// Stops the running install, as Cancel does.
    func cancelInstall() async throws(AppRefusal) -> StateReport.Setup.Install {
        StateReport.Setup.Install(try await setup.cancelInstall())
    }
}
