import Darwin
import Foundation
@testable import ReviewApp
import ReviewLease
import ReviewWire
import Testing

/// The control server enforcing the lease: one server with a fake app and a
/// clock the test moves, asked as agents ask it, and over the real socket
/// for the takes that wait in line.
@Suite("The control server's lease")
struct LeaseServerTests {
    /// The time the server decides the lease at, moved by the test.
    final class Clock {
        var now = Date(timeIntervalSince1970: 0)
    }

    /// The agent the tests' requests come from, and two others.
    nonisolated static let agent = Holder(key: "CLAUDE_CODE_SESSION_ID=agent", name: "Claude Code", place: "/work")
    nonisolated static let other = Holder(key: "process:300@800250000", name: "codex", place: "Herdr pane w1-2")
    nonisolated static let third = Holder(key: "operator-3", name: "amp", place: "/blog")

    /// A lease `holder` took at `taken` seconds, held to its cap, as a `take` grants it.
    nonisolated static func term(_ holder: Holder, taken: TimeInterval) -> LeaseTerm {
        LeaseTerm(holder: holder, taken: Date(timeIntervalSince1970: taken), ends: Date(timeIntervalSince1970: taken + ControlLease.cap))
    }

    nonisolated static let name = AppIdentity.appName

    let app = ControlServerTests.FakeApp()
    let screenshotter = ControlServerTests.FakeScreenshotter()
    let clock = Clock()
    let indicator = AgentControlIcon()
    /// A folder of its own for each test, short enough for a socket's path.
    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("video-review-\(UUID().uuidString.prefix(8))", isDirectory: true)
    var socket: URL { ControlSocket.url(in: folder) }

    private func server(
        socket: URL = URL(fileURLWithPath: "/nowhere/control.sock"), lease: ControlLease = ControlLease()
    ) -> ControlServer {
        let clock = clock
        return ControlServer(
            socket: socket, app: app, listeners: ControlServerTests.noListeners(), screenshotter: screenshotter, lease: lease,
            indicator: indicator,
            now: { clock.now }, timeZone: TimeZone(identifier: "UTC")!, quit: {}
        )
    }

    private func move(to seconds: TimeInterval) {
        clock.now = Date(timeIntervalSince1970: seconds)
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    /// Waits until `count` takes wait in line.
    private func line(of count: Int, in server: ControlServer) async throws {
        for _ in 0..<500 where server.lease.waiting(at: clock.now) != count {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(server.lease.waiting(at: clock.now) == count)
    }

    /// A `video-review` command's exchange, as it runs in its own process:
    /// on a thread of its own, since `send` blocks until the app answers,
    /// and a blocked send must not hold one of the few threads the server's
    /// own tasks answer on.
    nonisolated static func sending(
        _ send: @escaping @Sendable () -> Result<ControlReply, ControlClient.Failure>
    ) async -> Result<ControlReply, ControlClient.Failure> {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread { continuation.resume(returning: send()) }
        }
    }

    // MARK: - Operator requests

    @Test("an operator request from another holder is refused, naming the holder and when the lease ends, with nothing done", arguments: [
        ControlRequest.appOpen, .appQuit, .playerOpen(path: "/videos/sample.mp4"), .playerPlay, .playerPause,
        .playerSeek(seconds: 3), .screenshot(path: "/tmp/shot.png", appearance: nil), .contextSet(text: "A note"),
    ])
    func refusesAnotherHolder(request: ControlRequest) async {
        let server = server()
        // The agent's first operator request takes the lease, for a minute.
        _ = await server.reply(to: ControlRequest.playerPlay.sent(by: Self.agent))
        move(to: 12.5)

        let refused = await server.reply(to: request.sent(by: Self.other))

        #expect(refused == .init(reply: .refused(
            "\(Self.name) is in use by Claude Code in /work until 00:01:00 (48s left); `video-review control take --wait <seconds>` to queue"
        )))
        #expect(app.calls == ["play"])
        #expect(screenshotter.calls.isEmpty)
        // The refusal renews nothing.
        #expect(server.lease.current(at: clock.now) == LeaseTerm(holder: Self.agent, taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 60)))
    }

    @Test("the lease ends 60 s after the holder's last command and 5 min after it was taken at most")
    func renewsAndEnds() async {
        let server = server()
        _ = await server.reply(to: ControlRequest.playerPlay.sent(by: Self.agent))
        move(to: 30)
        _ = await server.reply(to: ControlRequest.playerPause.sent(by: Self.agent))
        // Renewed at 30: held until 90, not 60.
        move(to: 89)
        let early = await server.reply(to: ControlRequest.playerPlay.sent(by: Self.other))
        move(to: 90)
        let taken = await server.reply(to: ControlRequest.playerPlay.sent(by: Self.other))

        #expect(!early.reply.ok)
        #expect(early.reply.error.contains("until 00:01:30 (1s left)"))
        #expect(taken.reply == .done("playing from 0:00\n"))
        #expect(server.lease.current(at: clock.now)?.holder == Self.other)

        // A holder that keeps sending commands loses it at the cap, 5 minutes after it took it at 90.
        for seconds in stride(from: 140.0, through: 380, by: 50) {
            move(to: seconds)
            _ = await server.reply(to: ControlRequest.playerPause.sent(by: Self.other))
        }
        #expect(server.lease.current(at: clock.now)?.ends == Date(timeIntervalSince1970: 390))
        move(to: 390)
        let next = await server.reply(to: ControlRequest.playerPlay.sent(by: Self.agent))
        #expect(next.reply.ok)
        #expect(server.lease.current(at: clock.now)?.holder == Self.agent)
    }

    @Test("app status and state are never refused, take no lease, and show the lease as lines and as JSON")
    func freeCommandsShowTheLease() async throws {
        let server = server()
        let free = await server.reply(to: ControlRequest.appStatus.sent(by: Self.other))
        #expect(free.reply.output.contains("lease: free\n"))
        #expect(server.lease.current(at: clock.now) == nil)

        _ = await server.reply(to: ControlRequest.playerPlay.sent(by: Self.agent))
        move(to: 12.5)
        let status = await server.reply(to: ControlRequest.appStatus.sent(by: Self.other))
        let lines = await server.reply(to: ControlRequest.state.sent(by: Self.other))
        let state = try object(await server.reply(to: ControlRequest.state.sent(by: Self.other, json: true)).reply.output)
        let statusJSON = try object(await server.reply(to: ControlRequest.appStatus.sent(by: Self.other, json: true)).reply.output)

        #expect(status.reply.output.contains("lease: held by Claude Code in /work, 48s left, 0 waiting\n"))
        #expect(lines.reply.output.contains("lease: held by Claude Code in /work, 48s left, 0 waiting\n"))
        let lease = try #require(state["lease"] as? [String: Any])
        #expect(lease["holder"] as? [String: String] == ["key": Self.agent.key, "name": "Claude Code", "place": "/work"])
        #expect(lease["taken"] as? String == "1970-01-01T00:00:00Z")
        #expect(lease["ends"] as? String == "1970-01-01T00:01:00Z")
        #expect(lease["secondsLeft"] as? Int == 48)
        #expect(lease["waiting"] as? Int == 0)
        #expect((statusJSON["lease"] as? [String: Any])?["secondsLeft"] as? Int == 48)
        // Asking didn't renew the holder's lease, or take it for the one who asked.
        #expect(server.lease.current(at: clock.now)?.ends == Date(timeIntervalSince1970: 60))
    }

    // MARK: - Take and release

    @Test("take holds the lease to the cap and says until when; release frees it, and from anyone else changes nothing")
    func takeAndRelease() async throws {
        let server = server()

        let taken = await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent(by: Self.agent))
        move(to: 10)
        let refused = await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent(by: Self.other))
        let notTheirs = await server.reply(to: ControlRequest.controlRelease.sent(by: Self.other))
        let stillHeld = server.lease.current(at: clock.now)?.holder
        let released = await server.reply(to: ControlRequest.controlRelease.sent(by: Self.agent))

        #expect(taken == .init(reply: .done("you hold \(Self.name) until 00:05:00\n"), granted: Self.term(Self.agent, taken: 0)))
        #expect(refused == .init(reply: .refused(
            "\(Self.name) is in use by Claude Code in /work until 00:05:00 (290s left); `video-review control take --wait <seconds>` to queue"
        )))
        #expect(notTheirs == .init(reply: .done("released \(Self.name)\n")))
        #expect(stillHeld == Self.agent)
        #expect(released == .init(reply: .done("released \(Self.name)\n")))
        #expect(server.lease.current(at: clock.now) == nil)

        let json = try object(await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent(by: Self.other, json: true)).reply.output)
        #expect((json["lease"] as? [String: Any])?["secondsLeft"] as? Int == 300)
    }

    @Test("a take whose wait runs out is refused with who still holds the lease, and leaves the line")
    func waitRunsOut() async {
        let server = server()
        _ = await server.reply(to: ControlRequest.playerPlay.sent(by: Self.agent))

        let waited = await server.reply(to: ControlRequest.controlTake(waitSeconds: 1).sent(by: Self.other))

        #expect(waited == .init(reply: .refused(
            "waited 1s; \(Self.name) is still in use by Claude Code in /work until 00:01:00 (59s left)"
        )))
        #expect(server.lease.waiting(at: clock.now) == 0)
        #expect(server.lease.current(at: clock.now)?.holder == Self.agent)
    }

    @Test("when the lease runs out with no request, the first waiting take gets it, and the agent-control icon shows the line, then the waiter")
    func waiterGetsTheLeaseAtItsEnd() async throws {
        let server = server()
        _ = await server.reply(to: ControlRequest.playerPlay.sent(by: Self.agent))
        let waiting = Task { await server.reply(to: ControlRequest.controlTake(waitSeconds: 120).sent(by: Self.other)) }
        try await line(of: 1, in: server)
        let before = indicator.shown(at: clock.now)

        // Its end comes with no request: the server's timer settles it.
        move(to: 60)
        server.settleLease()
        let granted = await waiting.value

        #expect(before?.holder == Self.agent)
        #expect(before?.waiting == 1)
        #expect(granted == .init(reply: .done("you hold \(Self.name) until 00:06:00\n"), granted: Self.term(Self.other, taken: 60)))
        #expect(indicator.shown(at: clock.now)
            == ControlLease.Status(holder: Self.other, taken: clock.now, ends: Date(timeIntervalSince1970: 360), secondsLeft: 300, waiting: 0))
    }

    @Test("over the socket, takes that wait queue in order: each release hands the lease to the one that came first")
    func takesQueueInOrder() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = server(socket: socket)
        try server.start()
        defer { server.stop() }
        let socket = socket
        func client(_ holder: Holder) -> ControlClient {
            ControlClient(socket: socket, holder: holder, transport: UnixSocketTransport())
        }
        let first = client(Self.agent), second = client(Self.other), third = client(Self.third)

        let taken = await Self.sending { first.send(.controlTake(waitSeconds: nil)) }
        #expect(taken == .success(.done("you hold \(Self.name) until 00:05:00\n")))
        // Each waiting client blocks its own thread until the lease is handed to it.
        let secondWaits = Task { await Self.sending { second.send(.controlTake(waitSeconds: 30)) } }
        try await line(of: 1, in: server)
        let thirdWaits = Task { await Self.sending { third.send(.controlTake(waitSeconds: 30)) } }
        try await line(of: 2, in: server)
        // The app answers others while the takes wait, and shows the line.
        let status = await Self.sending { third.send(.appStatus) }
        // A waiting agent's operator command is refused: it doesn't hold the lease yet.
        let early = await Self.sending { second.send(.playerPlay) }

        move(to: 12)
        let released = await Self.sending { first.send(.controlRelease) }
        let secondGot = await secondWaits.value
        let holderAfterFirst = server.lease.current(at: clock.now)?.holder
        try await line(of: 1, in: server)
        move(to: 20)
        _ = await Self.sending { second.send(.controlRelease) }
        let thirdGot = await thirdWaits.value

        guard case .success(let reply) = status else { Issue.record("no status: \(status)"); return }
        #expect(reply.output.contains("lease: held by Claude Code in /work, 300s left, 2 waiting\n"))
        guard case .success(let refusal) = early else { Issue.record("no reply: \(early)"); return }
        #expect(!refusal.ok)
        #expect(refusal.error.hasPrefix("\(Self.name) is in use by Claude Code in /work until 00:05:00"))
        #expect(released == .success(.done("released \(Self.name)\n")))
        #expect(secondGot == .success(.done("you hold \(Self.name) until 00:05:12\n")))
        #expect(holderAfterFirst == Self.other)
        #expect(thirdGot == .success(.done("you hold \(Self.name) until 00:05:20\n")))
        #expect(server.lease.current(at: clock.now)?.holder == Self.third)
        #expect(app.calls.isEmpty)
    }

    @Test("over the socket, a waiting take whose client has gone gives back the lease it's granted, and the next waiter gets it")
    func goneWaiter() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = server(socket: socket)
        try server.start()
        defer { server.stop() }
        let socket = socket
        let holder = ControlClient(socket: socket, holder: Self.agent, transport: UnixSocketTransport())
        let next = ControlClient(socket: socket, holder: Self.third, transport: UnixSocketTransport())
        _ = await Self.sending { holder.send(.controlTake(waitSeconds: nil)) }

        // A take that waits in line, sent as the command sends it, whose
        // client then goes (stopped, or its harness's timeout) before the lease is free.
        let gone = UnixSocket.make()
        try #require(UnixSocket.connectSocket(gone, to: try #require(UnixSocket.address(socket.path))) == 0)
        _ = UnixSocket.writeAll(gone, ControlRequest.controlTake(waitSeconds: 30).sent(by: Self.other))
        UnixSocket.finishWriting(gone)
        try await line(of: 1, in: server)
        close(gone)
        // Another take waits behind it, its client still there.
        let waiting = Task { await Self.sending { next.send(.controlTake(waitSeconds: 30)) } }
        try await line(of: 2, in: server)
        move(to: 12)
        _ = await Self.sending { holder.send(.controlRelease) }
        let granted = await waiting.value

        #expect(granted == .success(.done("you hold \(Self.name) until 00:05:12\n")))
        #expect(server.lease.current(at: clock.now)?.holder == Self.third)
    }

    // MARK: - The person's Stop

    @Test("Stop ends the lease and bars its holder for 5 minutes: its operator commands and takes are refused, with nothing done")
    func stopBarsTheHolder() async {
        let server = server()
        _ = await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent(by: Self.agent))
        move(to: 10)

        server.stopLease()

        #expect(server.lease.current(at: clock.now) == nil)
        #expect(indicator.shown(at: clock.now) == nil)
        move(to: 20)
        var answers: [ControlServer.Answer] = []
        for request in [
            ControlRequest.playerPlay, .playerSeek(seconds: 3), .appQuit, .screenshot(path: "/tmp/shot.png", appearance: nil),
            .controlTake(waitSeconds: nil), .controlTake(waitSeconds: 30),
        ] {
            answers.append(await server.reply(to: request.sent(by: Self.agent)))
        }
        #expect(answers == Array(
            repeating: ControlServer.Answer(reply: .refused("the person took \(Self.name) back; ask them before using it again")), count: 6
        ))
        #expect(app.calls.isEmpty)
        #expect(screenshotter.calls.isEmpty)
        // Free commands still answer a barred holder, and anyone else drives the app.
        #expect(await server.reply(to: ControlRequest.state.sent(by: Self.agent)).reply.ok)
        #expect(await server.reply(to: ControlRequest.playerPlay.sent(by: Self.other)).reply.ok)
        _ = await server.reply(to: ControlRequest.controlRelease.sent(by: Self.other))

        // The bar ends 5 minutes after the Stop, at 310.
        move(to: 309)
        #expect(await server.reply(to: ControlRequest.playerPause.sent(by: Self.agent)).reply.ok == false)
        move(to: 310)
        #expect(await server.reply(to: ControlRequest.playerPause.sent(by: Self.agent)).reply == .done("paused at 0:00\n"))
    }

    @Test("Stop hands the lease to the first waiting take, answered at once")
    func stopHandsOver() async throws {
        let server = server()
        _ = await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent(by: Self.agent))
        let waiting = Task { await server.reply(to: ControlRequest.controlTake(waitSeconds: 120).sent(by: Self.other)) }
        try await line(of: 1, in: server)

        move(to: 10)
        server.stopLease()
        let granted = await waiting.value

        #expect(granted == .init(reply: .done("you hold \(Self.name) until 00:05:10\n"), granted: Self.term(Self.other, taken: 10)))
        #expect(indicator.shown(at: clock.now)?.holder == Self.other)
        // The bar and the waiter's cap end together, with no request: the timer settles both.
        move(to: 310)
        server.settleLease()
        #expect(indicator.lease == ControlLease())
    }

    // MARK: - The agent-control icon

    @Test("the agent-control icon follows the lease: shown from the request that takes it, gone once it's settled at its end, with no request")
    func iconFollowsTheLease() async {
        let server = server()
        #expect(indicator.shown(at: clock.now) == nil)

        _ = await server.reply(to: ControlRequest.playerPlay.sent(by: Self.agent))
        move(to: 12.5)
        let shown = indicator.shown(at: clock.now)
        // A capture that leaves the agent-control icon out hides a lease that's held, until the last one ends.
        indicator.hideForCapture()
        indicator.hideForCapture()
        let hidden = indicator.shown(at: clock.now)
        indicator.showAfterCapture()
        let stillHidden = indicator.shown(at: clock.now)
        indicator.showAfterCapture()
        let back = indicator.shown(at: clock.now)
        move(to: 60)
        server.settleLease()

        #expect(shown == ControlLease.Status(
            holder: Self.agent, taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 60), secondsLeft: 48, waiting: 0
        ))
        #expect(hidden == nil)
        #expect(stillHidden == nil)
        #expect(back == shown)
        #expect(indicator.lease == ControlLease())
        #expect(indicator.shown(at: clock.now) == nil)
    }

    @Test("the agent-control icon says who controls the app, where, the time left and how many wait")
    func agentControlWords() {
        func status(_ holder: Holder, left: Int, waiting: Int) -> ControlLease.Status {
            ControlLease.Status(holder: holder, taken: clock.now, ends: clock.now, secondsLeft: left, waiting: waiting)
        }

        let short = AgentControlWords(status(Holder(key: "k", name: "Claude Code", place: "/Users/me/video-review"), left: 48, waiting: 0))
        let long = AgentControlWords(status(Self.other, left: 245, waiting: 2))

        #expect(short.title == "Claude Code controls \(Self.name)")
        #expect(short.detail == "video-review · 48s left")
        #expect(long.title == "Codex controls \(Self.name)")
        #expect(long.detail == "Herdr pane w1-2 · 4m 05s left · 2 waiting")
        #expect(long.text == "Codex controls \(Self.name) · Herdr pane w1-2 · 4m 05s left · 2 waiting")
    }

    @Test("a screenshot shows the agent-control indicator unless --hide-agent-indicator asks to leave it out")
    func screenshotAgentControlIcon() async {
        let server = server()
        _ = await server.reply(to: ControlRequest.screenshot(path: "/tmp/a.png", appearance: nil).sent(by: Self.agent))
        _ = await server.reply(to: ControlRequest.screenshot(path: "/tmp/b.png", appearance: .dark, hideAgentIndicator: true).sent(by: Self.agent))
        #expect(screenshotter.calls == ["/tmp/a.png as is", "/tmp/b.png dark without the indicator"])
    }

    // MARK: - A relaunch

    @Test("quit answers with the lease it renewed, for a relaunch to hand over; the app launched with it holds it for the same agent")
    func quitHandsTheLeaseOver() async {
        let server = server()
        _ = await server.reply(to: ControlRequest.playerPlay.sent(by: Self.agent))
        move(to: 20)

        let quit = await server.reply(to: ControlRequest.appQuit.sent(by: Self.agent))

        let term = LeaseTerm(holder: Self.agent, taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 80))
        #expect(quit == .init(reply: ControlReply(ok: true, output: "\(Self.name) quit\n", lease: term), quits: true))

        move(to: 25)
        let indicator = AgentControlIcon()
        let relaunched = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: app, listeners: ControlServerTests.noListeners(),
            screenshotter: screenshotter,
            lease: ControlLease(environment: ControlLease.handover(term), at: clock.now), indicator: indicator,
            now: { [clock] in clock.now }, timeZone: TimeZone(identifier: "UTC")!, quit: {}
        )
        // Held, and shown, from the start, with no request.
        #expect(indicator.shown(at: clock.now)?.holder == Self.agent)
        #expect(await relaunched.reply(to: ControlRequest.playerPlay.sent(by: Self.other)).reply.ok == false)
        #expect(await relaunched.reply(to: ControlRequest.appOpen.sent(by: Self.agent)).reply.ok)
        #expect(relaunched.lease.current(at: clock.now)?.taken == Date(timeIntervalSince1970: 0))
    }
}

extension ControlRequest {
    /// The request as `holder` sends it over the socket.
    func sent(by holder: Holder, json: Bool = false) -> Data {
        ControlMessage(self, holder: holder, json: json).encoded()
    }
}
