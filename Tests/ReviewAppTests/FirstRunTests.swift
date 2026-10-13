import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewSetup
import ReviewWire
import Testing

/// The fake app answers each first-run action with a fixed window.
extension ControlServerTests.FakeApp {
    func firstRun(_ action: FirstRunAction) async throws(AppRefusal) -> (line: String, firstRun: StateReport.FirstRun) {
        calls.append("firstRun \(action)")
        return ("the first-run window shows connect", StateReport.FirstRun(
            showing: true, step: "connect", done: true, harness: "codex", readiness: "skillNotDetected",
            prompt: "$havooch-mate use Havooch to open the demo video and listen for my feedback", agentConnected: false
        ))
    }
}

/// The first-run window: it shows at launch until the person
/// uses the app, every step can be passed or skipped, Tools and Connect act on the
/// Connect view's setup, the demo prompt takes the picked harness's form,
/// and Open the Demo opens the bundled video for the person, whose sends
/// are marked as the demo's. The app model and its control server, with
/// setup on a file system in memory; no scene and no socket.
@Suite("The first-run window", .serialized)
struct FirstRunTests {
    static let agent = Holder(key: "agent-1", name: "Claude Code", place: "/Users/me/shop")

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
    var support: URL { root.appendingPathComponent("person", isDirectory: true) }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Setup as the probe finds it: Claude Code with its skill, the Codex
    /// app without it; the command not linked.
    private func setup() -> SetupDesk {
        SetupDesk(
            environment: ["HOME": SetupDeskTests.home, "SHELL": "/bin/zsh"], bundle: SetupDeskTests.bundle,
            fileSystem: MemoryFileSystem([
                SetupDeskTests.command: .file,
                "/Applications/Claude.app": .folder, SetupDeskTests.claudeSkill: .file,
                "/Applications/Codex.app": .folder,
            ]),
            runner: ScriptedRunner()
        )
    }

    /// The app on the test's folder, the demo video bundled as `demoVideo`.
    private func app(environment: [String: String] = [:], demoVideo: URL? = WindowTests.launch) -> AppModel {
        AppModel(
            environment: [SupportFolder.overrideVariable: support.path].merging(environment) { $1 }, speech: SlowRecognizer(),
            demoFolder: root.appendingPathComponent("Havooch Demo", isDirectory: true), demoVideo: demoVideo, setup: setup()
        )
    }

    private func server(_ app: AppModel) -> ControlServer {
        ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: app, listeners: { app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
    }

    private func reply(_ server: ControlServer, _ request: ControlRequest, json: Bool = false) async -> ControlReply {
        await server.reply(to: request.sent(by: Self.agent, json: json)).reply
    }

    @Test("the first launch shows the first-run window on Welcome, and showing it doesn't make the first run done")
    func firstLaunch() {
        defer { cleanUp() }
        let first = app()
        var shown = 0
        first.firstRun.present = { if $0 { shown += 1 } }
        #expect(first.showFirstRunOnFirstLaunch())
        #expect(shown == 1)
        #expect(first.firstRun.isShowing)
        #expect(first.firstRun.step == .welcome)
        #expect(!first.firstRunReport.done)
        #expect(first.firstRunReport.line == "first run: not done, showing welcome, claude-code")
    }

    @Test("closed with its close button, or quit at once, the first-run window shows again at the next launch")
    func closedOrQuitShowsAgain() {
        defer { cleanUp() }
        let closed = app()
        #expect(closed.showFirstRunOnFirstLaunch())
        closed.firstRun.closedByPerson()
        #expect(!closed.firstRunDone)
        let next = app()
        #expect(next.showFirstRunOnFirstLaunch())

        // Quit as the app quits: the positions are saved, nothing else.
        next.savePositions()
        #expect(!next.firstRunDone)
        #expect(app().showFirstRunOnFirstLaunch())
    }

    /// The first run is done on `app`, and the next launch doesn't show it.
    private func expectDone(_ app: AppModel, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(app.firstRunDone, sourceLocation: sourceLocation)
        #expect(app.firstRunReport.done, sourceLocation: sourceLocation)
        let next = self.app()
        #expect(next.firstRunDone, sourceLocation: sourceLocation)
        #expect(!next.showFirstRunOnFirstLaunch(), sourceLocation: sourceLocation)
    }

    @Test("Get Started makes the first run done, and the next launch doesn't show it")
    func getStartedIsDone() {
        defer { cleanUp() }
        let app = app()
        app.showFirstRunOnFirstLaunch()
        app.firstRun.back()
        #expect(!app.firstRunDone)
        app.firstRun.next()
        #expect(app.firstRun.step == .tools)
        expectDone(app)
    }

    @Test("a click on a later step on the progress bar makes the first run done; a click on Welcome doesn't")
    func laterStepIsDone() {
        defer { cleanUp() }
        let app = app()
        app.showFirstRunOnFirstLaunch()
        app.firstRun.go(to: .welcome)
        #expect(!app.firstRunDone)
        app.firstRun.go(to: .connect)
        expectDone(app)
    }

    @Test("first-run next and first-run pick make the first run done, as the person's clicks do")
    func commandsAreDone() async {
        defer { cleanUp() }
        let next = app()
        let server = server(next)
        _ = await reply(server, .firstRunShow())
        #expect(!next.firstRunDone)
        _ = await reply(server, .firstRunNext)
        expectDone(next)
        cleanUp()

        let picked = app()
        let pickServer = self.server(picked)
        _ = await reply(pickServer, .firstRunShow())
        _ = await reply(pickServer, .firstRunPick(harness: "codex"))
        expectDone(picked)
    }

    @Test("Skip Setup makes the first run done, from the window and from first-run skip")
    func skipIsDone() async {
        defer { cleanUp() }
        let clicked = app()
        clicked.showFirstRunOnFirstLaunch()
        clicked.firstRun.skip()
        #expect(!clicked.firstRun.isShowing)
        expectDone(clicked)
        cleanUp()

        let commanded = app()
        let server = server(commanded)
        _ = await reply(server, .firstRunShow())
        _ = await reply(server, .firstRunSkip)
        expectDone(commanded)
    }

    @Test("opening a video makes the first run done, with the first-run window open or not")
    func openingAVideoIsDone() async throws {
        defer { cleanUp() }
        let app = app()
        app.showFirstRunOnFirstLaunch()
        let window = app.makeWindow()
        try await window.open(MessageTests.fixture)
        expectDone(app)
    }

    @Test("an agent connecting makes the first run done")
    func agentConnectingIsDone() async {
        defer { cleanUp() }
        let app = app()
        let server = server(app)
        app.showFirstRunOnFirstLaunch()
        let wait = Task { await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 1, video: WindowTests.launch.path).sent(by: Self.agent)) }
        _ = await wait.value
        #expect(app.agentConnectedOnce)
        expectDone(app)
    }

    @Test("a person who already opened a video, or connected an agent, isn't new; demo data never shows it")
    func notNew() async throws {
        defer { cleanUp() }
        let used = app()
        let window = used.makeWindow()
        try await window.open(MessageTests.fixture)
        window.closed()
        #expect(!app().showFirstRunOnFirstLaunch())
        cleanUp()

        #expect(!app(environment: [SupportFolder.demoRunVariable: "1"]).showFirstRunOnFirstLaunch())
    }

    @Test("Get Started, Continue and Back walk the four steps; the next step after Try it and the one before Welcome are refused")
    func steps() async throws {
        defer { cleanUp() }
        let app = app()
        let server = server(app)
        #expect(await reply(server, .firstRunNext) == .refused("the first-run window isn't open; havooch first-run show opens it"))

        #expect(await reply(server, .firstRunShow()) == .done("the first-run window shows welcome\n"))
        #expect(await reply(server, .firstRunBack) == .refused("welcome is the first step"))
        for step in ["tools", "connect", "try-it"] {
            #expect(await reply(server, .firstRunNext) == .done("the first-run window shows \(step)\n"))
        }
        #expect(await reply(server, .firstRunNext) == .refused("try-it is the last step; havooch first-run demo opens the demo"))
        #expect(await reply(server, .firstRunBack) == .done("the first-run window shows connect\n"))
        #expect(await reply(server, .firstRunShow(step: "tools")) == .done("the first-run window shows tools\n"))
        #expect(await reply(server, .firstRunShow(step: "later")) == .refused("no step later; the steps are welcome, tools, connect, try-it"))
        #expect(FirstRunStep.allCases.map(\.rawValue) == ["welcome", "tools", "connect", "try-it"])
    }

    @Test("Connect shows the demo prompt in the picked harness's form, and what Havooch detects of it")
    func pick() async throws {
        defer { cleanUp() }
        let app = app()
        let server = server(app)
        _ = await reply(server, .firstRunShow())
        // Before a pick: the harness whose skill and app are detected.
        #expect(app.firstRunReport.harness == "claude-code")
        #expect(app.firstRunReport.readiness == "ready")
        #expect(app.firstRunReport.prompt == "/havooch-mate use Havooch to open the demo video and listen for my feedback")

        #expect(await reply(server, .firstRunPick(harness: "codex")) == .done("""
            picked codex
            prompt: $havooch-mate use Havooch to open the demo video and listen for my feedback

            """))
        #expect(app.firstRun.step == .connect)
        #expect(app.firstRunReport.readiness == "skillNotDetected")
        #expect(app.firstRun.pastePrompt(for: app.firstRun.steppedHarness) == app.firstRunReport.prompt)
        #expect(await reply(server, .firstRunPick(harness: "gemini")).error.hasPrefix("no harness gemini"))
    }

    @Test("Tools links the command and installs the skill on the same setup as the Connect view")
    func tools() async throws {
        defer { cleanUp() }
        let app = app()
        app.showFirstRun(on: .tools)
        #expect(!app.setup.isLinked)
        app.firstRun.linkCommandLine()
        #expect(app.setup.isLinked)
        #expect(app.firstRun.problem == nil)
        app.firstRun.installSkill(for: [HarnessCatalog.harness(named: "codex")!])
        #expect(app.setup.install?.install.harnesses.map(\.installName) == ["codex"])
        await app.setup.installEnded()
    }

    @Test("Skip Setup closes the window at any step, and state reports it")
    func skip() async throws {
        defer { cleanUp() }
        let app = app()
        let server = server(app)
        #expect(await reply(server, .firstRunSkip) == .refused("the first-run window isn't open; havooch first-run show opens it"))
        _ = await reply(server, .firstRunShow(step: "connect"))
        let state = try #require(try app.state(window: nil).firstRun)
        #expect(state.showing && state.step == "connect" && !state.done)
        #expect(await reply(server, .firstRunSkip) == .done("the first-run window is closed\n"))
        #expect(!app.firstRun.isShowing)
        let json = await reply(server, .state, json: true).output
        #expect(json.contains("\"firstRun\" : {"))
        #expect(json.contains("\"showing\" : false"))
    }

    @Test("each first-run action takes the lease, as the person's click is theirs")
    func lease() async {
        defer { cleanUp() }
        let server = server(app())
        _ = await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent(by: Holder(key: "other", name: "Codex", place: "/x")))
        for request in [ControlRequest.firstRunShow(), .firstRunNext, .firstRunBack, .firstRunPick(harness: "pi"), .firstRunDemo, .firstRunSkip] {
            #expect(await reply(server, request).ok == false)
        }
    }

    @Test("Open the Demo opens the bundled video for the person, playing, and closes the window; a send on it is marked demo")
    func demo() async throws {
        defer { cleanUp() }
        let app = app()
        let server = server(app)
        _ = await reply(server, .firstRunShow(step: "try-it"))
        let opened = await reply(server, .firstRunDemo)
        #expect(opened == .done("opened havooch-demo.mp4 in w1, playing; the first-run window is closed\n"))
        #expect(!app.firstRun.isShowing)
        let window = try #require(app.windows.window("w1"))
        #expect(window.video?.contentHash == DemoVideo.contentHash)
        // On the person's own data, as `havooch open` opens it.
        #expect(!app.isDemo)
        try window.pause()

        // The agent the demo prompt started listens to it, and its first send says it's the demo.
        let wait = Task { await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 30, video: WindowTests.launch.path).sent(by: Self.agent)) }
        _ = try await window.addMessage(text: "Make the title bigger", at: 3)
        _ = try await window.sendQueue()
        let payload = await wait.value.reply.output
        #expect(payload.contains("\"demo\" : true"))
    }

    @Test("Open the Demo in a build with no bundled video says so, under the steps")
    func noDemoVideo() async {
        defer { cleanUp() }
        let app = app(demoVideo: nil)
        let server = server(app)
        _ = await reply(server, .firstRunShow(step: "try-it"))
        #expect(await reply(server, .firstRunDemo) == .refused("this build has no bundled demo video; run `make bundle`"))
        #expect(app.firstRun.isShowing)
    }
}

/// Where the first-run window opens: centered over the player window in
/// front, kept on that window's screen; centered on the screen with none.
@Suite("The first-run window's place")
struct FirstRunPlaceTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)

    @Test("over the player window, with equal space on the left and the right, and above and below")
    func overThePlayerWindow() {
        let player = CGRect(x: 76, y: 107, width: 1360, height: 730)
        let frame = FirstRunWindow.frame(of: CGSize(width: 760, height: 568), over: player, on: screen)
        #expect(frame == CGRect(x: 376, y: 188, width: 760, height: 568))
        #expect(frame.minX - player.minX == player.maxX - frame.maxX)
    }

    @Test("with no player window, in the middle of the screen")
    func onTheScreen() {
        let frame = FirstRunWindow.frame(of: CGSize(width: 760, height: 568), over: nil, on: screen)
        #expect(frame == CGRect(x: 376, y: 188, width: 760, height: 568))
    }

    @Test("over a player window near the screen's edge, moved in to stay on the screen")
    func keptOnTheScreen() {
        let player = CGRect(x: 900, y: 0, width: 700, height: 400)
        let frame = FirstRunWindow.frame(of: CGSize(width: 760, height: 568), over: player, on: screen)
        #expect(frame == CGRect(x: 752, y: 0, width: 760, height: 568))
    }
}
