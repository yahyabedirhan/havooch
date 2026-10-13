import Foundation
import Observation
import ReviewSetup

/// What the setup steps act on: a player window's Connect view, or the
/// first-run window. Both show the same steps: the command line, the
/// skill, and a harness picker with the prompt to paste.
protocol SetupSteering: AnyObject {
    /// What Havooch detects of the setup, Link and the install.
    var setup: SetupDesk { get }
    /// The harness the picker shows as picked.
    var steppedHarness: Harness { get }
    /// A click on a harness in the picker.
    func pick(_ harness: Harness)
    /// The prompt the person pastes in `harness`; nil when there is none.
    func pastePrompt(for harness: Harness) -> String?
    /// Link.
    func linkCommandLine()
    /// Run Command, installing for `harnesses`.
    func installSkill(for harnesses: [Harness])
    /// Cancel under the running install.
    func cancelSkillInstall()
    /// The player window whose key monitor a focused button tells
    /// (`pressedByKeys`); nil outside a player window.
    var keysWindow: WindowModel? { get }
}

/// The first-run window's steps, in order.
nonisolated enum FirstRunStep: String, CaseIterable, Equatable {
    case welcome, tools, connect
    case tryIt = "try-it"

    /// Its name on the progress bar.
    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .tools: "Tools"
        case .connect: "Connect"
        case .tryIt: "Try It"
        }
    }

    /// The step after this one; nil on the last.
    var next: FirstRunStep? { Self.allCases.first { $0.index == index + 1 } }
    /// The step before this one; nil on the first.
    var previous: FirstRunStep? { Self.allCases.first { $0.index == index - 1 } }
    /// Its place, from 0.
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// What `first-run …` asks of the first-run window.
nonisolated enum FirstRunAction: Equatable {
    case show(step: String?)
    case next, back
    case pick(harness: String)
    case demo, skip
}

/// The first-run window (first-run V1): Welcome, Tools, Connect and Try
/// it, with Back, Continue and Skip Setup on every step. Tools shows the
/// Connect view's command line and skill steps; Connect its harness picker,
/// with the demo prompt in the picked harness's form, so the person's
/// own agent opens the demo and listens. It shows by itself at each
/// launch until the person uses the app (`AppModel.showFirstRunOnFirstLaunch`),
/// and at any time through `first-run show`. Nothing in it blocks: every
/// step can be passed with nothing done.
@Observable
final class FirstRun: SetupSteering {
    /// The step it shows.
    private(set) var step: FirstRunStep = .welcome
    /// Whether the window is on screen.
    private(set) var isShowing = false
    /// The harness the person picked on Connect; nil follows setup's suggestion.
    private(set) var pickedHarness: Harness?
    /// Why the last Link or Install couldn't start, under the steps; nil
    /// when it could, or Open the Demo couldn't open it. A failed link
    /// shows in its step instead.
    var problem: String?

    let setup: SetupDesk
    /// Puts the window on screen, or takes it off; the app sets it. A run
    /// with no scene (the tests) has nothing to show.
    @ObservationIgnored var present: (Bool) -> Void = { _ in }
    /// The person used the window: Get Started, a later step, or Skip
    /// Setup. The app sets it, to mark the first run done.
    @ObservationIgnored var used: () -> Void = {}

    init(setup: SetupDesk) {
        self.setup = setup
    }

    /// Shows the window on `step`, else on the step it was on.
    func show(on step: FirstRunStep? = nil) {
        if let step { self.step = step }
        problem = nil
        isShowing = true
        // The person may have set up in a terminal meanwhile.
        setup.probe()
        present(true)
    }

    /// Takes the window off screen.
    func close() {
        guard isShowing else { return }
        isShowing = false
        present(false)
    }

    /// The person closed the window with its close button. It isn't a
    /// use: the next launch shows it again.
    func closedByPerson() {
        isShowing = false
    }

    /// Skip Setup: the person used the window, and it closes.
    func skip() {
        used()
        close()
    }

    /// Get Started, Continue, Continue Anyway and Later: each one a use.
    func next() {
        guard let next = step.next else { return }
        step = next
        used()
    }

    /// Back.
    func back() {
        if let previous = step.previous { step = previous }
    }

    /// A click on a step on the progress bar; one after Welcome is a use.
    func go(to step: FirstRunStep) {
        self.step = step
        if step != .welcome { used() }
    }

    // MARK: - The setup steps

    var steppedHarness: Harness { pickedHarness ?? setup.suggestedHarness }

    func pick(_ harness: Harness) {
        pickedHarness = harness
    }

    /// The demo prompt, whatever the harness's readiness: it stays primary.
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

// MARK: - The app's first-run actions

extension AppModel {
    /// On a person's data, a launch shows the first-run window in front of
    /// the empty window until the person uses the app. The data's
    /// `settings.json` reads, where the first run isn't done, and where no
    /// video was opened and no agent connected yet (a person who used a
    /// build before it isn't new). Closing it, or quitting, isn't a use.
    /// Never on demo data. Returns whether it showed.
    @discardableResult
    func showFirstRunOnFirstLaunch() -> Bool {
        guard !isDemoRun, keepsSettings, !firstRunDone, !agentConnectedOnce, desk.library.recents().isEmpty else { return false }
        showFirstRun(on: nil)
        return true
    }

    /// Shows the first-run window. Showing it doesn't make the first run
    /// done; the person's use of the app does (`markFirstRunDone`).
    func showFirstRun(on step: FirstRunStep?) {
        firstRun.show(on: step)
    }

    /// `first-run …`: the person's clicks in the first-run window.
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

    /// Open the Demo on the Try it step: the bundled demo video opens for
    /// the person, as `havooch open` opens it, on their own data, so it is
    /// the same review the agent opened with the demo prompt; then the
    /// first-run window closes. Refused in a build with no bundled video.
    @discardableResult
    func openDemoFromFirstRun() async throws(AppRefusal) -> WindowModel {
        guard let demoVideo else {
            throw AppRefusal("this build has no bundled demo video; run `make bundle`")
        }
        let window = try await openInFront(demoVideo)
        firstRun.close()
        // `openInFront` answers with the window it opened in.
        guard let model = window as? WindowModel else { throw AppRefusal("the demo didn't open") }
        return model
    }

    private func needFirstRun() throws(AppRefusal) {
        guard firstRun.isShowing else {
            throw AppRefusal("the first-run window isn't open; havooch first-run show opens it")
        }
    }

    /// The first-run window as `state` reports it.
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
    /// The first-run window: whether it shows, its step, the picked
    /// harness and its demo prompt.
    nonisolated struct FirstRun: Encodable, Equatable {
        var showing: Bool
        /// `welcome`, `tools`, `connect` or `try-it`.
        var step: String
        /// Whether the person used the app on this data: it never shows by
        /// itself again.
        var done: Bool
        /// The harness picked on Connect, by its install name.
        var harness: String
        /// `ready`, `skillNotDetected` or `harnessNotDetected`.
        var readiness: String
        /// The demo prompt in the harness's form.
        var prompt: String
        /// Whether an agent ever connected: the Connect step says it listens.
        var agentConnected: Bool
        /// Why the last Link or Install couldn't start; `null` when it could.
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

        /// `first run: showing connect, claude-code`, or `first run: done, closed`.
        var line: String {
            "first run: \(done ? "done" : "not done"), " + (showing ? "showing \(step), \(harness)" : "closed")
        }
    }
}
