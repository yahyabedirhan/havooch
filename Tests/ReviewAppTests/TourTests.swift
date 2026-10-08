import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewSetup
import ReviewWire
import Testing

/// The setup tour (H4) and "Finish setup" (P11): when the button shows and
/// what it counts, the five steps and the part each one rings, the sidebar
/// each step shows, what moves a step on by itself, and Skip, Close and
/// Finish. The app model and its control server on the fixture video, with
/// setup on a file system in memory; no scene and no socket.
@Suite("The setup tour", .serialized)
struct TourTests {
    static let claude = Holder(key: "claude-1", name: "Claude Code", place: "/Users/me/shop")

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    /// Setup as the probe finds it: Claude Code with its skill, linked
    /// when `linked`; the Codex app without the skill unless `skilled`.
    private func setup(linked: Bool = false, skilled: Bool = false) -> SetupDesk {
        var items: [String: FileItem] = [
            SetupDeskTests.command: .file,
            "/Applications/Claude.app": .folder, SetupDeskTests.claudeSkill: .file,
        ]
        if !skilled { items["/Applications/Codex.app"] = .folder }
        if linked { items[SetupDeskTests.link] = .link(to: SetupDeskTests.command) }
        return SetupDesk(
            environment: ["HOME": SetupDeskTests.home, "SHELL": "/bin/zsh"], bundle: SetupDeskTests.bundle,
            fileSystem: MemoryFileSystem(items), runner: ScriptedRunner()
        )
    }

    private func run(linked: Bool = false, skilled: Bool = false) async throws -> (window: WindowModel, server: ControlServer) {
        let app = AppModel(
            environment: [SupportFolder.overrideVariable: support.path], setup: setup(linked: linked, skilled: skilled)
        )
        let window = app.makeWindow()
        try await window.open(MessageTests.fixture)
        app.windows.becameKey(window)
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: app, listeners: { app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        return (window, server)
    }

    private func waiting(_ server: ControlServer) -> Task<ControlServer.Answer, Never> {
        Task { await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 30).sent(by: Self.claude)) }
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func listen(_ request: ControlRequest, _ server: ControlServer) async -> ControlReply {
        await server.replyWritten(to: request.sent(by: Self.claude)).reply
    }

    @Test("Finish setup shows while setup isn't detected and no agent ever connected, and counts what is left")
    func finishSetup() async throws {
        defer { cleanUp() }
        let (window, server) = try await run()
        #expect(window.showsFinishSetup)
        #expect(window.setupItemsLeft == 3)
        #expect(window.tourReport.finishSetup)
        #expect(window.state().tour?.setupItemsLeft == 3)
        // The same rule as the connect button's dot.
        #expect(window.showsConnectDot)

        let wait = waiting(server)
        await eventually { window.listeners().outbox.isWaitOpen }
        #expect(window.app.agentConnectedOnce)
        #expect(!window.showsFinishSetup)
        #expect(!window.showsConnectDot)
        #expect(window.setupItemsLeft == 2)
        // The wait ends with a send.
        _ = try await window.addMessage(text: "Too fast here", at: 2)
        _ = try await window.sendQueue()
        _ = await wait.value
    }

    @Test("Finish setup and the dot go once both tools are detected, also before any agent connected")
    func detectedSetup() async throws {
        defer { cleanUp() }
        let (window, _) = try await run(linked: true, skilled: true)
        #expect(window.app.setup.isDetected)
        #expect(!window.showsFinishSetup)
        #expect(!window.showsConnectDot)
        #expect(window.setupItemsLeft == 1)
        // An open tour keeps its button, so the button that closes it stays.
        _ = try window.showTour()
        #expect(window.showsFinishSetup)
    }

    @Test("with no video there is no Finish setup, and the tour commands are refused")
    func noVideo() async throws {
        defer { cleanUp() }
        let app = AppModel(environment: [SupportFolder.overrideVariable: support.path], setup: setup())
        let window = app.makeWindow()
        #expect(!window.showsFinishSetup)
        #expect(throws: AppRefusal.self) { try window.showTour() }
    }

    @Test("the tour walks tools, connect, write, send and reply, each step in the sidebar it is about with its rings")
    func walk() async throws {
        defer { cleanUp() }
        let (window, _) = try await run()
        window.isSidebarVisible = false

        var tour = try window.showTour()
        #expect(tour.open && tour.step == "tools" && tour.stepNumber == 1 && tour.steps == 5)
        #expect(tour.title == "Give your agent two tools")
        #expect(tour.rings == ["setupSteps"])
        #expect(window.isSidebarVisible)
        #expect(window.sidebarReport.mode == "connect")

        tour = try window.nextTourStep()
        #expect(tour.step == "connect" && tour.title == "Connect your agent")
        #expect(tour.rings == ["agentStep"])
        #expect(window.sidebarReport.mode == "connect")

        tour = try window.nextTourStep()
        #expect(tour.step == "write" && tour.title == "Write on a frame")
        #expect(tour.rings == ["stage", "composer"])
        #expect(window.sidebarReport.mode == "threads")

        tour = try window.nextTourStep()
        #expect(tour.step == "send" && tour.title == "Send them to your agent")
        #expect(tour.rings == ["send"])

        tour = try window.nextTourStep()
        #expect(tour.step == "reply")
        tour = try window.nextTourStep()
        #expect(!tour.open && tour.step == "tools")
        #expect(window.tourRings.isEmpty)
    }

    @Test("Close keeps the step for Finish setup; Skip starts the next tour from the first step")
    func closeAndSkip() async throws {
        defer { cleanUp() }
        let (window, _) = try await run()
        #expect(throws: AppRefusal.self) { try window.nextTourStep() }
        #expect(throws: AppRefusal.self) { try window.closeTour() }

        _ = try window.showTour()
        _ = try window.nextTourStep()
        var tour = try window.closeTour()
        #expect(!tour.open && tour.step == "connect")
        #expect(window.tourRings.isEmpty)
        // Finish setup opens it where it was left.
        window.toggleTour()
        #expect(window.tour.isOpen && window.tour.step == .connect)
        window.toggleTour()
        #expect(!window.tour.isOpen)

        _ = try window.showTour()
        tour = try window.skipTour()
        #expect(!tour.open && tour.step == "tools")
        tour = try window.showTour()
        #expect(tour.step == "tools")
    }

    @Test("an agent connecting moves the connect step on, a queued message moves write on, and the reply step watches the send until the agent answers it")
    func movesOnByItself() async throws {
        defer { cleanUp() }
        let (window, server) = try await run()
        _ = try window.showTour()
        _ = try window.nextTourStep()
        #expect(window.tour.step == .connect)

        let wait = waiting(server)
        await eventually { window.listeners().outbox.isWaitOpen }
        #expect(window.tour.step == .write)
        #expect(window.tourAgentName == "Claude Code")

        // Write an Example puts the words in the composer, as `comment compose` does.
        window.writeTourExample()
        #expect(window.composerText == WindowModel.tourExample)

        let added = try await window.addMessage(text: "Make the title bigger", at: 2)
        #expect(window.tour.step == .send)
        #expect(window.tourTitle == "Send them to Claude Code")

        _ = try await window.sendQueue()
        _ = await wait.value
        #expect(window.tour.step == .reply)
        #expect(!window.isTourSendWaiting)
        #expect(!window.tourReplied)
        #expect(window.tourRings.isEmpty)
        #expect(window.sidebarReport.mode == "threads")

        #expect(await listen(.status(messageID: added.message.id, state: .done), server).ok)
        #expect(window.tourReplied)
        #expect(window.tourTitle == "Claude Code answered in the player")
        #expect(window.tourRings == [.thread])
        #expect(window.tourReplyThread?.text == added.thread.id)
        #expect(window.tourReport.replied)

        // Finish ends the tour.
        let tour = try window.nextTourStep()
        #expect(!tour.open && tour.step == "tools")
    }

    @Test("a send with no agent leaves the reply step on the outbox banner and rings the agent step until an agent takes it")
    func sendWithNoAgent() async throws {
        defer { cleanUp() }
        let (window, server) = try await run()
        _ = try window.showTour()
        _ = try window.nextTourStep()
        _ = try window.nextTourStep()
        #expect(window.tour.step == .write)
        _ = try await window.addMessage(text: "Make the title bigger", at: 2)
        _ = try await window.sendQueue()

        #expect(window.tour.step == .reply)
        #expect(window.isTourSendWaiting)
        #expect(window.tourTitle == "Your messages wait for an agent")
        #expect(window.tourRings == [.agentStep])
        #expect(window.sidebarReport.mode == "connect")

        _ = await waiting(server).value
        #expect(!window.isTourSendWaiting)
        #expect(window.tourTitle == "Claude Code is on it")
    }

    @Test("both tools detected move the tools step on; while one isn't, it stays")
    func toolsDetected() async throws {
        defer { cleanUp() }
        let (window, _) = try await run()
        _ = try window.showTour()
        window.tourNoticedSetup()
        #expect(window.tour.step == .tools)

        let (linked, _) = try await run(linked: true, skilled: true)
        _ = try linked.showTour()
        linked.tourNoticedSetup()
        #expect(linked.tour.step == .connect)
    }

    @Test("the ring stands 9 points outside the part it marks, 6 in the thread list's narrow margin")
    func ringPadding() {
        #expect(CoachRing.padding == 9)
        #expect(CoachRing.tightPadding == 6)
    }

    @Test("state --json reports the tour")
    func stateReport() async throws {
        defer { cleanUp() }
        let (window, _) = try await run()
        _ = try window.showTour()
        let json = try #require(
            JSONSerialization.jsonObject(with: Data(window.state().json.utf8)) as? [String: Any]
        )
        let tour = try #require(json["tour"] as? [String: Any])
        #expect(tour["open"] as? Bool == true)
        #expect(tour["step"] as? String == "tools")
        #expect(tour["stepNumber"] as? Int == 1)
        #expect(tour["steps"] as? Int == 5)
        #expect(tour["rings"] as? [String] == ["setupSteps"])
        #expect(tour["finishSetup"] as? Bool == true)
        #expect(tour["setupItemsLeft"] as? Int == 3)
        #expect(tour["replied"] as? Bool == false)
    }
}
