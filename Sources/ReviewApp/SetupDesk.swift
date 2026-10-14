import Foundation
import Observation
import ReviewSetup
import ReviewWire

@Observable
final class SetupDesk {
    private(set) var report: SetupReport
    private(set) var linkFailure: CommandLink.Failure?
    private(set) var install: InstallRun?

    struct InstallRun: Equatable {
        enum State: String, Equatable {
            case running, done, failed, cancelled
            case noNode
        }

        var install: SkillInstall
        var state: State
        var exitStatus: Int32?
        var log: [String] = []
    }

    static let logLimit = 500

    @ObservationIgnored let home: String
    @ObservationIgnored let command: String?
    @ObservationIgnored private let shell: String
    @ObservationIgnored private let fileSystem: any SetupFileSystem
    @ObservationIgnored private let runner: any ProcessRunner
    @ObservationIgnored private var installing: Task<Void, Never>?
    @ObservationIgnored private(set) var probes = 0

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

    var isLinked: Bool { report.commandLine.detection == .detected }

    var isSkillDetected: Bool {
        report.harnessesLackingSkill.isEmpty && report.harnesses.contains { $0.skill == .detected }
    }

    var isDetected: Bool { isLinked && isSkillDetected }

    var suggestedHarness: Harness {
        let harnesses = report.harnesses
        let pick = harnesses.first { $0.skill == .detected && $0.presence == .detected }
            ?? harnesses.first { $0.skill == .detected }
            ?? harnesses.first { $0.presence == .detected }
        return pick?.harness ?? HarnessCatalog.all[0]
    }

    func readiness(of harness: Harness) -> Readiness {
        guard let setup = report.harnesses.first(where: { $0.harness == harness }) else { return .harnessNotDetected }
        if setup.skill == .detected { return .ready }
        return setup.presence == .detected ? .skillNotDetected : .harnessNotDetected
    }

    func probe() {
        report = SetupProbe(fileSystem: fileSystem, home: home).probe()
        probes += 1
    }

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

    func linkPlan() throws(AppRefusal) -> (path: String, command: String) {
        (CommandLink(fileSystem: fileSystem, home: home).linkPath, try bundledCommand())
    }

    private func bundledCommand() throws(AppRefusal) -> String {
        guard let command else {
            throw AppRefusal("this build of \(AppIdentity.appName) isn't an app bundle, so it has no havooch command to link")
        }
        return command
    }

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
        return SkillInstall(for: HarnessCatalog.all.filter(harnesses.contains), shell: shell)
    }

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

    func cancelInstall() async throws(AppRefusal) -> InstallRun {
        guard let install, install.state == .running, let installing else {
            throw AppRefusal("no install is running")
        }
        installing.cancel()
        await installing.value
        return self.install ?? install
    }

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

extension AppModel {
    var setupReport: StateReport.Setup {
        setupReport(for: windows.key)
    }

    func setupReport(for window: WindowModel?) -> StateReport.Setup {
        StateReport.Setup(
            setup, target: window?.promptTarget, agentConnectedOnce: agentConnectedOnce
        )
    }

    func setupStatus() -> StateReport.Setup {
        setup.probe()
        return setupReport
    }

    func linkCommand(dryRun: Bool) throws(AppRefusal) -> (line: String, setup: StateReport.Setup) {
        if dryRun {
            let plan = try setup.linkPlan()
            return ("would link \(plan.path) to \(plan.command)", setupReport)
        }
        try setup.link()
        let commandLine = setupReport.commandLine
        return ("linked \(commandLine.path) to \(commandLine.destination ?? setup.command ?? "")", setupReport)
    }

    func installSkill(harnesses names: [String], dryRun: Bool) throws(AppRefusal) -> StateReport.Setup.Install {
        if dryRun { return StateReport.Setup.Install(try setup.plan(for: names), state: "planned") }
        return StateReport.Setup.Install(try setup.startInstall(for: names))
    }

    func cancelInstall() async throws(AppRefusal) -> StateReport.Setup.Install {
        StateReport.Setup.Install(try await setup.cancelInstall())
    }
}
