import Foundation
import Observation
import ReviewSetup

protocol SetupSteering: AnyObject {
    var setup: SetupDesk { get }
    var steppedHarness: Harness { get }
    func pick(_ harness: Harness)
    func pastePrompt(for harness: Harness) -> String?
    func linkCommandLine()
    func installSkill(for harnesses: [Harness])
    func cancelSkillInstall()
    var keysWindow: WindowModel? { get }
}

nonisolated enum FirstRunStep: String, CaseIterable, Equatable {
    case welcome, tools, connect
    case tryIt = "try-it"

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .tools: "Tools"
        case .connect: "Connect"
        case .tryIt: "Try It"
        }
    }

    var next: FirstRunStep? { Self.allCases.first { $0.index == index + 1 } }
    var previous: FirstRunStep? { Self.allCases.first { $0.index == index - 1 } }
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

nonisolated enum FirstRunAction: Equatable {
    case show(step: String?)
    case next, back
    case pick(harness: String)
    case demo, skip
}

@Observable
final class FirstRun: SetupSteering {
    private(set) var step: FirstRunStep = .welcome
    private(set) var isShowing = false
    private(set) var pickedHarness: Harness?
    var problem: String?

    let setup: SetupDesk
    @ObservationIgnored var present: (Bool) -> Void = { _ in }
    @ObservationIgnored var used: () -> Void = {}

    init(setup: SetupDesk) {
        self.setup = setup
    }

    func show(on step: FirstRunStep? = nil) {
        if let step { self.step = step }
        problem = nil
        isShowing = true
        setup.probe()
        present(true)
    }

    func close() {
        guard isShowing else { return }
        isShowing = false
        present(false)
    }

    func closedByPerson() {
        isShowing = false
    }

    func skip() {
        used()
        close()
    }

    func next() {
        guard let next = step.next else { return }
        step = next
        used()
    }

    func back() {
        if let previous = step.previous { step = previous }
    }

    func go(to step: FirstRunStep) {
        self.step = step
        if step != .welcome { used() }
    }

    var steppedHarness: Harness { pickedHarness ?? setup.suggestedHarness }

    func pick(_ harness: Harness) {
        pickedHarness = harness
    }

    func pastePrompt(for harness: Harness) -> String? {
        harness.demoPrompt
    }

    func linkCommandLine() {
        do throws(AppRefusal) {
            try setup.link()
            problem = nil
        } catch {
            if setup.linkFailure == nil { problem = error.reason }
        }
    }

    func installSkill(for harnesses: [Harness]) {
        do throws(AppRefusal) {
            try setup.startInstall(for: harnesses.map(\.installName))
            problem = nil
        } catch {
            problem = error.reason
        }
    }

    func cancelSkillInstall() {
        Task { _ = try? await setup.cancelInstall() }
    }

    var keysWindow: WindowModel? { nil }
}

extension AppModel {
    @discardableResult
    func showFirstRunOnFirstLaunch() -> Bool {
        guard !isDemoRun, keepsSettings, !firstRunDone, !agentConnectedOnce, desk.library.recents().isEmpty else { return false }
        showFirstRun(on: nil)
        return true
    }

    func showFirstRun(on step: FirstRunStep?) {
        firstRun.show(on: step)
    }

    func firstRun(_ action: FirstRunAction) async throws(AppRefusal) -> (line: String, firstRun: StateReport.FirstRun) {
        switch action {
        case .show(let name):
            let step = try name.map { name throws(AppRefusal) in
                guard let step = FirstRunStep(rawValue: name) else {
                    throw AppRefusal("no step \(name); the steps are \(FirstRunStep.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                return step
            }
            showFirstRun(on: step)
            return ("the first-run window shows \(firstRun.step.rawValue)", firstRunReport)
        case .next:
            try needFirstRun()
            guard firstRun.step.next != nil else {
                throw AppRefusal("try-it is the last step; havooch first-run demo opens the demo")
            }
            firstRun.next()
            return ("the first-run window shows \(firstRun.step.rawValue)", firstRunReport)
        case .back:
            try needFirstRun()
            guard firstRun.step.previous != nil else { throw AppRefusal("welcome is the first step") }
            firstRun.back()
            return ("the first-run window shows \(firstRun.step.rawValue)", firstRunReport)
        case .pick(let name):
            try needFirstRun()
            guard let harness = HarnessCatalog.harness(named: name) else {
                let known = HarnessCatalog.all.map(\.installName)
                throw AppRefusal("no harness \(name); Havooch sets up \(known.dropLast().joined(separator: ", ")) and \(known.last ?? "")")
            }
            if firstRun.step != .connect { firstRun.go(to: .connect) }
            firstRun.pick(harness)
            return ("picked \(harness.installName)\nprompt: \(harness.demoPrompt)", firstRunReport)
        case .demo:
            let window = try await openDemoFromFirstRun()
            let title = window.video?.title ?? DemoRun.videoName
            return ("opened \(title) in \(window.id), playing; the first-run window is closed", firstRunReport)
        case .skip:
            try needFirstRun()
            firstRun.skip()
            return ("the first-run window is closed", firstRunReport)
        }
    }

    @discardableResult
    func openDemoFromFirstRun() async throws(AppRefusal) -> WindowModel {
        guard let demoVideo else {
            throw AppRefusal("this build has no bundled demo video; run `make bundle`")
        }
        let window = try await openInFront(demoVideo)
        firstRun.close()
        guard let model = window as? WindowModel else { throw AppRefusal("the demo didn't open") }
        return model
    }

    private func needFirstRun() throws(AppRefusal) {
        guard firstRun.isShowing else {
            throw AppRefusal("the first-run window isn't open; havooch first-run open opens it")
        }
    }

    var firstRunReport: StateReport.FirstRun {
        let harness = firstRun.steppedHarness
        return StateReport.FirstRun(
            showing: firstRun.isShowing, step: firstRun.step.rawValue, done: firstRunDone, harness: harness.installName,
            readiness: setup.readiness(of: harness).rawValue, prompt: harness.demoPrompt,
            agentConnected: agentConnectedOnce, problem: firstRun.problem
        )
    }
}

extension StateReport {
    nonisolated struct FirstRun: Encodable, Equatable {
        var showing: Bool
        var step: String
        var done: Bool
        var harness: String
        var readiness: String
        var prompt: String
        var agentConnected: Bool
        var problem: String?

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(showing, forKey: .showing)
            try container.encode(step, forKey: .step)
            try container.encode(done, forKey: .done)
            try container.encode(harness, forKey: .harness)
            try container.encode(readiness, forKey: .readiness)
            try container.encode(prompt, forKey: .prompt)
            try container.encode(agentConnected, forKey: .agentConnected)
            try container.encode(problem, forKey: .problem)
        }

        private enum CodingKeys: String, CodingKey {
            case showing, step, done, harness, readiness, prompt, agentConnected, problem
        }

        var line: String {
            "first run: \(done ? "done" : "not done"), " + (showing ? "showing \(step), \(harness)" : "closed")
        }
    }
}
