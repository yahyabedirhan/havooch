import Darwin
import Foundation
import Testing
@testable import VRApp
import VRLease
import VRWire

/// How the control server leases app control: requests answered in memory
/// at times the test sets, and over the real socket in a temporary folder.
/// No window is opened and no video played.
@Suite @MainActor struct ControlServerTests {
    /// The time the server decides the lease at, moved by the test.
    final class Clock {
        var now = Date(timeIntervalSince1970: 0)
    }

    /// How often the server asked the app to quit.
    final class Quits: @unchecked Sendable {
        var count = 0
    }

    nonisolated static let agent = Holder(key: "CLAUDE_CODE_SESSION_ID=agent", name: "Claude Code", place: "/work")
    nonisolated static let other = Holder(key: "process:300@800250000", name: "codex", place: "Herdr pane w1-2")
    nonisolated static let third = Holder(key: "second agent", name: "Claude Code", place: "/blog")

    let clock = Clock()
    let quits = Quits()
    let indicator = LeaseIndicator()
    /// A folder of its own for each test, short enough for a socket's path.
    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
    var socket: URL { folder.appendingPathComponent("control.sock") }

    /// A server on a model with no video, deciding the lease at the clock's
    /// time and naming times in UTC.
    func server(lease: ControlLease = ControlLease()) -> ControlServer {
        let model = AppModel(environment: [SupportFolder.overrideVariable: folder.path])
        return ControlServer(
            socket: socket, model: model, screenshotter: Screenshotter(model: model), lease: lease, indicator: indicator,
            now: { [clock] in clock.now }, timeZone: TimeZone(identifier: "UTC") ?? .gmt,
            quit: { [quits] in quits.count += 1 }
        )
    }

    /// `request` as `holder`'s `video-review` command sends it.
    static func sent(_ request: ControlRequest, by holder: Holder = agent, json: Bool = false) -> Data {
        ControlMessage(request, holder: holder, json: json).encoded()
    }

    /// Runs `body`, which blocks on the socket, off the main actor.
    static func sending<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: body()) }
        }
    }

    /// Waits until `count` takes wait in line.
    func waiting(_ count: Int, on server: ControlServer) async throws {
        for _ in 0..<500 where server.lease.waiting(at: clock.now) != count {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(server.lease.waiting(at: clock.now) == count)
    }

    // MARK: - Operator commands

    @Test func anOperatorCommandFromASecondHolderIsRefusedNamingTheHolderAndTheEndWithNothingDone() async {
        let server = server()
        _ = await server.reply(to: Self.sent(.appOpen))
        clock.now = Date(timeIntervalSince1970: 12.5)

        for request in [ControlRequest.appQuit, .playerPlay, .playerSeek(seconds: 3), .screenshot(path: "/tmp/w.png", appearance: nil)] {
            let refused = await server.reply(to: Self.sent(request, by: Self.other))

            #expect(refused == .init(reply: .refused(
                "video-review is in use by Claude Code in /work until 00:01:00 (48s left); "
                    + "`video-review control take --wait <seconds>` to queue"
            )))
        }
        // The quit wasn't acted on, and the refusals renewed nothing.
        #expect(quits.count == 0)
        #expect(server.lease.current(at: clock.now) == .init(holder: Self.agent, taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 60)))
    }

    @Test func theHoldersCommandsRenewTheLeaseAndOnceItRunsOutAnotherHolderTakesIt() async {
        let server = server()
        _ = await server.reply(to: Self.sent(.appOpen))
        clock.now = Date(timeIntervalSince1970: 30)
        // A command the app refuses for its own reasons still renews: the holder is driving.
        let noVideo = await server.reply(to: Self.sent(.playerPlay))
        clock.now = Date(timeIntervalSince1970: 89)
        let stillHeld = await server.reply(to: Self.sent(.appOpen, by: Self.other))
        clock.now = Date(timeIntervalSince1970: 90)
        let taken = await server.reply(to: Self.sent(.appOpen, by: Self.other))

        #expect(noVideo == .init(reply: .refused("no video is open")))
        #expect(!stillHeld.reply.ok)
        #expect(stillHeld.reply.error.contains("until 00:01:30 (1s left)"))
        #expect(taken.reply.ok)
        #expect(server.lease.current(at: clock.now)?.holder == Self.other)
    }

    @Test func quitHandsTheLeaseItRenewedBackInItsReply() async {
        let server = server()

        let quit = await server.reply(to: Self.sent(.appQuit))

        let term = ControlLease.Term(holder: Self.agent, taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 60))
        #expect(quit == .init(reply: ControlReply(ok: true, output: "quit\n", lease: term), quits: true))
    }

    // MARK: - Free commands

    @Test func statusAndStateAnswerAnyHolderTakeNoLeaseAndShowTheLease() async throws {
        let server = server()
        let free = await server.reply(to: Self.sent(.appStatus, by: Self.other))
        #expect(free.reply.output.contains("lease: free\n"))
        #expect(server.lease.current(at: clock.now) == nil)

        _ = await server.reply(to: Self.sent(.appOpen))
        clock.now = Date(timeIntervalSince1970: 12.5)
        let lines = await server.reply(to: Self.sent(.appStatus, by: Self.other))
        let status = await server.reply(to: Self.sent(.appStatus, by: Self.other, json: true))
        let state = await server.reply(to: Self.sent(.state, by: Self.other, json: true))

        #expect(lines.reply.ok)
        #expect(lines.reply.output.contains("lease: Claude Code in /work, 48s left, 0 waiting\n"))
        let lease = #""lease":{"holder":"Claude Code","place":"/work","secondsLeft":48,"waiting":0}"#
        #expect(status.reply.ok)
        #expect(status.reply.output.contains(lease))
        #expect(state.reply.ok)
        #expect(state.reply.output.contains(lease))
        // Asking renewed nothing and took nothing.
        #expect(server.lease.current(at: clock.now)?.holder == Self.agent)
        #expect(server.lease.current(at: clock.now)?.ends == Date(timeIntervalSince1970: 60))
    }

    // MARK: - Take and release

    @Test func takeHoldsTheLeaseToTheCapAndSaysUntilWhenAndReleaseFreesIt() async {
        let server = server()

        let taken = await server.reply(to: Self.sent(.controlTake(waitSeconds: nil)))
        clock.now = Date(timeIntervalSince1970: 10)
        let again = await server.reply(to: Self.sent(.controlTake(waitSeconds: nil), json: true))
        let refused = await server.reply(to: Self.sent(.controlTake(waitSeconds: nil), by: Self.other))
        let notTheirs = await server.reply(to: Self.sent(.controlRelease, by: Self.other))
        let stillHeld = server.lease.current(at: clock.now)?.holder
        let released = await server.reply(to: Self.sent(.controlRelease, json: true))

        let term = ControlLease.Term(holder: Self.agent, taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 300))
        #expect(taken == .init(reply: .done("you hold video-review until 00:05:00\n"), granted: term))
        #expect(again == .init(
            reply: .done(#"{"holder":"Claude Code","place":"/work","secondsLeft":290,"waiting":0}"# + "\n"), granted: term
        ))
        #expect(refused == .init(reply: .refused(
            "video-review is in use by Claude Code in /work until 00:05:00 (290s left); "
                + "`video-review control take --wait <seconds>` to queue"
        )))
        #expect(notTheirs == .init(reply: .done("released\n")))
        #expect(stillHeld == Self.agent)
        #expect(released == .init(reply: .done("{\"released\":true}\n")))
        #expect(server.lease.current(at: clock.now) == nil)
    }

    @Test func aTakeWhoseWaitRunsOutIsRefusedWithWhoStillHoldsTheLeaseAndLeavesTheLine() async {
        let server = server()
        _ = await server.reply(to: Self.sent(.appOpen))

        let waited = await server.reply(to: Self.sent(.controlTake(waitSeconds: 1), by: Self.other))

        #expect(waited == .init(reply: .refused("waited 1s; video-review is still in use by Claude Code in /work until 00:01:00 (59s left)")))
        #expect(server.lease.status(at: clock.now)?.waiting == 0)
        #expect(server.lease.current(at: clock.now)?.holder == Self.agent)
    }

    @Test func waitingTakesGetTheLeaseInTheOrderTheyCame() async throws {
        let server = server()
        _ = await server.reply(to: Self.sent(.controlTake(waitSeconds: nil)))
        let second = Task { await server.reply(to: Self.sent(.controlTake(waitSeconds: 120), by: Self.other)) }
        try await waiting(1, on: server)
        let last = Task { await server.reply(to: Self.sent(.controlTake(waitSeconds: 120), by: Self.third, json: true)) }
        try await waiting(2, on: server)
        let line = server.lease.status(at: clock.now)

        clock.now = Date(timeIntervalSince1970: 12)
        _ = await server.reply(to: Self.sent(.controlRelease))
        let first = await second.value
        let holderAfterFirst = server.lease.current(at: clock.now)?.holder
        let stillWaiting = server.lease.status(at: clock.now)?.waiting
        clock.now = Date(timeIntervalSince1970: 20)
        _ = await server.reply(to: Self.sent(.controlRelease, by: Self.other))
        let next = await last.value

        #expect(line == .init(holder: "Claude Code", place: "/work", secondsLeft: 300, waiting: 2))
        #expect(first.reply == .done("you hold video-review until 00:05:12\n"))
        #expect(holderAfterFirst == Self.other)
        #expect(stillWaiting == 1)
        #expect(next.reply == .done(#"{"holder":"Claude Code","place":"/blog","secondsLeft":300,"waiting":0}"# + "\n"))
        #expect(server.lease.current(at: clock.now)?.holder == Self.third)
    }

    @Test func whenTheLeaseRunsOutWithNoRequestTheFirstWaitingTakeGetsIt() async throws {
        let server = server()
        _ = await server.reply(to: Self.sent(.appOpen))
        let waiting = Task { await server.reply(to: Self.sent(.controlTake(waitSeconds: 120), by: Self.other)) }
        try await self.waiting(1, on: server)

        // Its end comes with no request: the server's timer settles it.
        clock.now = Date(timeIntervalSince1970: 60)
        server.settleLease()
        let granted = await waiting.value

        let term = ControlLease.Term(holder: Self.other, taken: Date(timeIntervalSince1970: 60), ends: Date(timeIntervalSince1970: 360))
        #expect(granted == .init(reply: .done("you hold video-review until 00:06:00\n"), granted: term))
    }

    // MARK: - The banner and Stop

    @Test func theBannerFollowsTheLeaseFromTheCommandThatTakesItToItsEnd() async {
        let server = server()
        #expect(indicator.banner(at: clock.now) == nil)

        _ = await server.reply(to: Self.sent(.appOpen))
        clock.now = Date(timeIntervalSince1970: 12.5)
        let held = indicator.banner(at: clock.now)
        clock.now = Date(timeIntervalSince1970: 60)
        let ended = indicator.banner(at: clock.now)
        server.settleLease()

        #expect(held?.title == "Claude Code controls \(Identity.appName)")
        #expect(held?.detail == "/work · 48 s left")
        #expect(ended == nil)
        #expect(indicator.lease == ControlLease())
    }

    @Test func theBannerSaysHowManyWaitAndStartsWithACapital() {
        let text = LeaseBannerText(.init(holder: "codex", place: "Herdr pane w1-2", secondsLeft: 245, waiting: 2))

        #expect(text.title == "Codex controls \(Identity.appName)")
        #expect(text.detail == "Herdr pane w1-2 · 245 s left · 2 waiting")
    }

    @Test func aLeaseARelaunchHandedOverIsShownFromTheStart() {
        let term = ControlLease.Term(holder: Self.agent, taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 60))
        let handed = ControlLease(environment: ControlLease.handover(term), at: clock.now)

        let server = server(lease: handed)

        #expect(server.lease.current(at: clock.now) == term)
        #expect(indicator.banner(at: clock.now)?.detail == "/work · 60 s left")
    }

    @Test func stopEndsTheLeaseAndTheStoppedHoldersCommandsAreRefusedForFiveMinutes() async {
        let server = server()
        _ = await server.reply(to: Self.sent(.controlTake(waitSeconds: nil)))
        clock.now = Date(timeIntervalSince1970: 10)

        // What the banner's Stop button calls.
        indicator.stop()
        let freed = server.lease.current(at: clock.now)
        let banner = indicator.banner(at: clock.now)
        clock.now = Date(timeIntervalSince1970: 20)
        let command = await server.reply(to: Self.sent(.appQuit))
        let take = await server.reply(to: Self.sent(.controlTake(waitSeconds: 30)))
        let others = await server.reply(to: Self.sent(.appOpen, by: Self.other))
        _ = await server.reply(to: Self.sent(.controlRelease, by: Self.other))
        clock.now = Date(timeIntervalSince1970: 309)
        let barred = await server.reply(to: Self.sent(.appOpen))
        clock.now = Date(timeIntervalSince1970: 310)
        let allowed = await server.reply(to: Self.sent(.appOpen))

        let stopped = ControlServer.Answer(reply: .refused("the person took video-review back; ask them before using it again"))
        #expect(freed == nil)
        #expect(banner == nil)
        #expect(command == stopped)
        #expect(quits.count == 0)
        #expect(take == stopped)
        #expect(others.reply.ok)
        #expect(barred == stopped)
        #expect(allowed.reply.ok)
        #expect(server.lease.current(at: clock.now)?.holder == Self.agent)
    }

    @Test func stopHandsTheLeaseToTheFirstWaitingTakeAndTheBannerShowsIt() async throws {
        let server = server()
        _ = await server.reply(to: Self.sent(.controlTake(waitSeconds: nil)))
        let waiting = Task { await server.reply(to: Self.sent(.controlTake(waitSeconds: 120), by: Self.other)) }
        try await self.waiting(1, on: server)
        clock.now = Date(timeIntervalSince1970: 10)

        server.stopLease()
        let granted = await waiting.value

        #expect(granted.reply == .done("you hold video-review until 00:05:10\n"))
        #expect(indicator.banner(at: clock.now) == LeaseBannerText(.init(holder: "codex", place: "Herdr pane w1-2", secondsLeft: 300, waiting: 0)))
    }

    @Test func stopWhileTheLeaseIsFreeChangesNothing() async {
        let server = server()

        server.stopLease()
        let taken = await server.reply(to: Self.sent(.appOpen))

        #expect(taken.reply.ok)
    }

    // MARK: - The socket

    @Test func overTheSocketASecondHolderIsRefusedAndAWaitingTakeGetsTheLeaseOnRelease() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = server()
        try server.start()
        defer { server.stop() }
        let socket = socket
        let holder = ControlClient(socket: socket, holder: Self.agent, transport: UnixSocketTransport())
        let waiter = ControlClient(socket: socket, holder: Self.other, transport: UnixSocketTransport())

        let taken = await Self.sending { holder.send(.controlTake(waitSeconds: nil)) }
        let refused = await Self.sending { waiter.send(.playerPlay) }
        // The waiting client blocks its own thread until the lease is handed over.
        let waiting = Task { await Self.sending { waiter.send(.controlTake(waitSeconds: 30)) } }
        try await self.waiting(1, on: server)
        let status = await Self.sending { waiter.send(.appStatus) }
        clock.now = Date(timeIntervalSince1970: 12)
        let released = await Self.sending { holder.send(.controlRelease) }
        let granted = await waiting.value

        #expect(taken == .success(.done("you hold video-review until 00:05:00\n")))
        #expect(refused == .success(.refused(
            "video-review is in use by Claude Code in /work until 00:05:00 (300s left); "
                + "`video-review control take --wait <seconds>` to queue"
        )))
        guard case .success(let reply) = status else { Issue.record("no status: \(status)"); return }
        #expect(reply.output.contains("lease: Claude Code in /work, 300s left, 1 waiting\n"))
        #expect(released == .success(.done("released\n")))
        #expect(granted == .success(.done("you hold video-review until 00:05:12\n")))
        #expect(server.lease.current(at: clock.now)?.holder == Self.other)
    }

    @Test func overTheSocketAWaitingTakeWhoseClientHasGoneGivesBackTheLeaseItIsGranted() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = server()
        try server.start()
        defer { server.stop() }
        let socket = socket
        let holder = ControlClient(socket: socket, holder: Self.agent, transport: UnixSocketTransport())
        let next = ControlClient(socket: socket, holder: Self.third, transport: UnixSocketTransport())
        _ = await Self.sending { holder.send(.controlTake(waitSeconds: nil)) }

        // A take that waits in line, whose client then goes (stopped, or cut
        // off by its harness) before the lease is free.
        let gone = UnixSocket.make()
        try #require(UnixSocket.connectSocket(gone, to: try #require(UnixSocket.address(socket.path))) == 0)
        _ = UnixSocket.writeAll(gone, Self.sent(.controlTake(waitSeconds: 30), by: Self.other))
        UnixSocket.finishWriting(gone)
        try await waiting(1, on: server)
        close(gone)
        // Another take waits behind it, its client still there.
        let waiting = Task { await Self.sending { next.send(.controlTake(waitSeconds: 30)) } }
        try await self.waiting(2, on: server)
        clock.now = Date(timeIntervalSince1970: 12)
        _ = await Self.sending { holder.send(.controlRelease) }
        let granted = await waiting.value

        #expect(granted == .success(.done("you hold video-review until 00:05:12\n")))
        #expect(server.lease.current(at: clock.now)?.holder == Self.third)
    }

    @Test func aTakeWaitingInLineHearsThatTheAppIsQuitting() async throws {
        let server = server()
        _ = await server.reply(to: Self.sent(.controlTake(waitSeconds: nil)))
        let waiting = Task { await server.reply(to: Self.sent(.controlTake(waitSeconds: 120), by: Self.other)) }
        try await self.waiting(1, on: server)

        server.stop()

        #expect(await waiting.value == .init(reply: .refused("video-review is quitting")))
    }
}
