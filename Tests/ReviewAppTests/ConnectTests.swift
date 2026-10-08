import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewSetup
import ReviewWire
import Testing

/// The Connect view (G1 to G11): its three entry points, the outbox banner
/// after Send with no agent, the picked harness's readiness and prompt,
/// the listener card's Disconnect, reconnecting after a relaunch with
/// Forget, and the connect button's dot. The app model and its control
/// server on the fixture video, with setup on a file system in memory; no
/// scene and no socket.
@Suite("The Connect view", .serialized)
struct ConnectTests {
    static let claude = Holder(key: "claude-1", name: "Claude Code", place: "/Users/me/shop")
    static let operatorAgent = Holder(key: "operator", name: "Codex", place: "/work")

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    /// Setup as the probe finds it: Claude Code with its skill, the Codex
    /// app without it, Pi nowhere; linked when `linked`.
    private func setup(linked: Bool = false) -> SetupDesk {
        var items: [String: FileItem] = [
            SetupDeskTests.command: .file,
            "/Applications/Claude.app": .folder, SetupDeskTests.claudeSkill: .file,
            "/Applications/Codex.app": .folder,
        ]
        if linked { items[SetupDeskTests.link] = .link(to: SetupDeskTests.command) }
        return SetupDesk(
            environment: ["HOME": SetupDeskTests.home, "SHELL": "/bin/zsh"], bundle: SetupDeskTests.bundle,
            fileSystem: MemoryFileSystem(items), runner: ScriptedRunner()
        )
    }

    /// The app on the test's folder with the fixture open in one window,
    /// and the server in front of it.
    private func run(linked: Bool = false) async throws -> (window: WindowModel, server: ControlServer) {
        let app = AppModel(environment: [SupportFolder.overrideVariable: support.path], setup: setup(linked: linked))
        let window = app.makeWindow()
        try await window.open(MessageTests.fixture)
        app.windows.becameKey(window)
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: app, listeners: { app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        return (window, server)
    }

    private func waiting(_ server: ControlServer, _ holder: Holder = claude) -> Task<ControlServer.Answer, Never> {
        Task { await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 30).sent(by: holder)) }
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Send with no agent keeps the send in the outbox and opens the Connect view: N messages wait, then are delivered to the agent that connects")
    func sendWithNoAgent() async throws {
        defer { cleanUp() }
        let (window, server) = try await run()
        #expect(window.sidebarReport.mode == "threads")
        _ = try await window.addMessage(text: "Too fast here", at: 2)
        _ = try await window.addMessage(text: "This box", at: 4)
        _ = try await window.addMessage(text: "Late title", at: 6)

        _ = try await window.sendQueue()

        #expect(window.connect?.reason == .send)
        #expect(window.outboxBanner == .waiting(messages: 3))
        #expect(window.outboxBanner?.text == "3 messages wait for an agent. They'll be delivered when one connects.")
        let sidebar = window.sidebarReport
        #expect(sidebar.mode == "connect")
        #expect(sidebar.connect?.banner?.kind == "waiting")
        #expect(sidebar.connect?.phase == "none")
        #expect(window.listeners().outbox.pending.count == 1)
        #expect(window.app.setupReport.needsFinishing)

        let wait = waiting(server)
        let answer = await wait.value
        #expect(answer.reply.ok)
        #expect(window.outboxBanner == .delivered(messages: 3, to: "Claude Code"))
        #expect(window.outboxBanner?.text == "Delivered 3 messages to Claude Code")
        // Connected: the listener card, and setup counts as working (L57).
        #expect(window.sidebarReport.connect?.phase == "connected")
        #expect(window.sidebarReport.connect?.listener?.agent == "Claude Code")
        #expect(window.sidebarReport.connect?.listener?.place == "/Users/me/shop")
        #expect(window.sidebarReport.connect?.listener?.since != nil)
        #expect(window.sidebarReport.connect?.listener?.prompt == "/havooch-mate listen for my feedback on \(MessageTests.fixture.lastPathComponent)")
        #expect(window.app.agentConnectedOnce)
        #expect(!window.app.setupReport.needsFinishing)
        #expect(!window.showsConnectDot)
        // Kept for the next launch.
        let next = AppModel(environment: [SupportFolder.overrideVariable: support.path], setup: setup())
        #expect(next.agentConnectedOnce)
    }

    @Test("a send with an agent listening goes to it and leaves the sidebar alone")
    func sendWithAnAgent() async throws {
        defer { cleanUp() }
        let (window, server) = try await run()
        let wait = waiting(server)
        await eventually { window.listeners().outbox.isWaitOpen }
        _ = try await window.addMessage(text: "Too fast here", at: 2)
        _ = try await window.sendQueue()
        _ = await wait.value
        #expect(window.connect == nil)
        #expect(window.sidebarReport.mode == "threads")
    }

    @Test("the pill and the header button open the Connect view and go back; thread list and Escape go back too")
    func entryPoints() async throws {
        defer { cleanUp() }
        let (window, _) = try await run()
        window.isSidebarVisible = false
        window.toggleConnect(.pill)
        #expect(window.connect?.reason == .pill)
        #expect(window.isSidebarVisible)
        window.toggleConnect(.pill)
        #expect(window.connect == nil)

        window.toggleConnect(.header)
        #expect(window.sidebarReport.connect?.reason == "header")
        #expect(window.escape())
        #expect(window.connect == nil)
        // Back from the Connect view goes to the thread view it covered.
        _ = try await window.addMessage(text: "Too fast here", at: 2)
        let thread = try #require(window.frameThreads.first)
        window.showThread(thread.id)
        window.toggleConnect(.header)
        #expect(window.sidebarReport.mode == "connect")
        #expect(window.escape())
        #expect(window.sidebarReport.mode == "thread")

        let shown = try window.showConnect()
        #expect(shown.mode == "connect")
        #expect(window.showThreadList().mode == "threads")
    }

    @Test("picking a harness shows its readiness and its prompt in its own form; not detected is never an error and the prompt stays")
    func pickHarness() async throws {
        defer { cleanUp() }
        let (window, _) = try await run()
        let video = MessageTests.fixture.lastPathComponent
        // With nothing picked: the harness whose skill and app are detected.
        #expect(window.connectHarness.agent == .claude)

        var connect = try #require(try window.pickHarness(named: "claude-code").connect)
        #expect(window.sidebarReport.mode == "connect")
        #expect((connect.harness, connect.readiness) == ("claude-code", "ready"))
        #expect(connect.prompt == "/havooch-mate listen for my feedback on \(video)")

        connect = try #require(try window.pickHarness(named: "codex").connect)
        #expect((connect.harness, connect.readiness) == ("codex", "skillNotDetected"))
        #expect(connect.prompt == "$havooch-mate listen for my feedback on \(video)")

        connect = try #require(try window.pickHarness(named: "pi").connect)
        #expect((connect.harness, connect.readiness) == ("pi", "harnessNotDetected"))
        #expect(connect.prompt == "/skill:havooch-mate listen for my feedback on \(video)")

        connect = try #require(try window.pickHarness(named: "OpenCode").connect)
        #expect(connect.prompt == "Use the havooch-mate skill to listen for my feedback on \(video)")

        #expect(throws: AppRefusal("no harness gemini; Havooch sets up claude-code, codex, cursor, pi and opencode")) {
            try window.pickHarness(named: "gemini")
        }
    }

    @Test("the connect button's dot shows until setup is detected or an agent connects")
    func dot() async throws {
        defer { cleanUp() }
        let (window, _) = try await run(linked: false)
        #expect(window.showsConnectDot)
        // Codex is found without the skill: the skill step isn't done.
        #expect(!window.app.setup.isSkillDetected)
        #expect(window.app.setup.isLinked == false)
    }

    @Test("Disconnect lets the agent go: its wait is refused so it stops, and nobody listens; with nobody there it's refused")
    func disconnect() async throws {
        defer { cleanUp() }
        let (window, server) = try await run()
        #expect(throws: AppRefusal("no agent is connected to this window")) { try window.disconnectAgent() }
        let wait = waiting(server)
        await eventually { window.listeners().outbox.isWaitOpen }
        #expect(window.listenerPhase(at: Date()) != .none)

        let done = await server.replyWritten(to: ControlRequest.connectDisconnect.sent(by: Self.operatorAgent))
        #expect(done.reply == .done("Claude Code disconnected\n"))

        let answer = await wait.value
        #expect(answer.reply == .refused(
            "the person disconnected you from this video or project in Havooch: stop listening and tell the person"
        ))
        #expect(window.listenerPhase(at: Date()) == .none)
        #expect(window.listeners().outbox.session == nil)
    }

    @Test("an agent disconnected while it works, with no wait open, is refused on its next wait, once")
    func disconnectWhileWorking() async throws {
        defer { cleanUp() }
        let (window, server) = try await run()
        _ = try await window.addMessage(text: "Too fast here", at: 2)
        _ = try await window.sendQueue()
        // The agent takes the send and works on it: no wait is open.
        let taken = await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.claude))
        #expect(taken.reply.ok)
        #expect(window.listenerPhase(at: Date()) != .none)

        #expect(try window.disconnectAgent() == "Claude Code")
        // Its send is first in line again, for the next agent.
        #expect(window.listeners().outbox.pending.count == 1)
        let next = await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.claude))
        #expect(next.reply == .refused(
            "the person disconnected you from this video or project in Havooch: stop listening and tell the person"
        ))
        // Only once: the person may connect it again.
        let again = await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.claude))
        #expect(again.reply.ok)
    }

    @Test("after a relaunch the last listener reconnects for 30 s, with Forget; then nobody is waited for")
    func reconnecting() async throws {
        defer { cleanUp() }
        let (window, server) = try await run()
        let wait = waiting(server)
        await eventually { window.listeners().outbox.isWaitOpen }
        window.app.listeners.stop()
        _ = await wait.value

        // The next launch, on the same data.
        let app = AppModel(environment: [SupportFolder.overrideVariable: support.path], setup: setup())
        let relaunched = app.makeWindow()
        try await relaunched.open(MessageTests.fixture)
        guard case .reconnecting(let session, let until) = relaunched.listenerPhase(at: Date()) else {
            Issue.record("the window doesn't reconnect: \(relaunched.listenerPhase(at: Date()))")
            return
        }
        #expect(session.name == "Claude Code")
        #expect(until.timeIntervalSince(app.listeners.startedAt) == ListenerQueue.reconnectSeconds)
        #expect(relaunched.listenerPhase(at: until.addingTimeInterval(1)) == .none)
        _ = try relaunched.showConnect()
        #expect(relaunched.sidebarReport.connect?.phase == "reconnecting")
        #expect(relaunched.sidebarReport.connect?.listener?.reconnectingUntil == until)

        #expect(try relaunched.forgetAgent() == "Claude Code")
        #expect(relaunched.listenerPhase(at: Date()) == .none)
        #expect(throws: AppRefusal("no agent is reconnecting to this window")) { try relaunched.forgetAgent() }
    }
}
