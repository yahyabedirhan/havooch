import Darwin
import Foundation
import Testing
@testable import VRApp
import VRCommand
import VRLease
import VRWire

private let agent = Holder(key: "CLAUDE_CODE_SESSION_ID=a", name: "Claude Code", place: "/work/shop")
private let other = Holder(key: "process:300@800250000", name: "codex", place: "Herdr pane w1-2")
private let third = Holder(key: "process:310@900000000", name: "aider", place: "/work/blog")

/// The server's side of the lease, with a fake player and a clock the test
/// sets: the gate before every operator request, `control take` and
/// `release`, the line of waiting takes, the person's Stop, and what the
/// banner reads. The rules themselves are `ControlLeaseTests`'.
@MainActor
@Suite struct LeaseGateTests {
    @Test(arguments: [
        ControlRequest.appOpen, .appQuit, .playerOpen(path: fixtureVideo.path), .playerPlay, .playerPause,
        .playerSeek(seconds: 1), .screenshot(path: "/tmp/a.png", appearance: nil),
    ])
    func anOperatorRequestFromAnotherHolderIsRefusedNamingTheHolderAndTheEndWithNothingDone(request: ControlRequest) async {
        let rig = Rig()
        _ = await rig.send(.playerOpen(path: fixtureVideo.path), by: agent)
        rig.clock.set(12)

        let answer = await rig.send(request, by: other)

        #expect(answer == ControlServer.Answer(reply: .refused(
            "video-review is in use by Claude Code in /work/shop until 00:01:00 (48s left); "
                + "`video-review control take --wait <seconds>` to queue"
        )))
        // Nothing reached the player, and the refusal renewed nothing.
        #expect(!rig.player.isPlaying)
        #expect(rig.player.time == 0)
        #expect(rig.server.lease.current(at: rig.clock.now)?.ends == Date(timeIntervalSince1970: 60))
    }

    @Test func theHoldersRequestsRenewTheLeaseAndOnceItRunsOutAnotherHolderTakesIt() async {
        let rig = Rig()
        _ = await rig.send(.playerOpen(path: fixtureVideo.path), by: agent)
        rig.clock.set(50)
        #expect(await rig.send(.playerPlay, by: agent).reply.ok)
        rig.clock.set(109)
        #expect(await rig.send(.playerPause, by: other).reply.ok == false)
        rig.clock.set(110)

        #expect(await rig.send(.playerPause, by: other).reply == .done("paused at 0:00.000\n"))
        #expect(rig.server.lease.current(at: rig.clock.now)?.holder == other)
    }

    @Test func statusAndStateAreNeverRefusedTakeNoLeaseAndReportItForAnyHolder() async throws {
        let rig = Rig()
        #expect(await rig.send(.appStatus, by: other).reply.output.contains("lease: free\n"))
        #expect(rig.server.lease.current(at: rig.clock.now) == nil)

        _ = await rig.send(.playerOpen(path: fixtureVideo.path), by: agent)
        rig.clock.set(12)

        #expect(await rig.send(.appStatus, by: other).reply.output.contains("lease: Claude Code in /work/shop, 48s left, 0 waiting\n"))
        #expect(await rig.send(.state, by: other).reply.output.contains("lease: Claude Code in /work/shop, 48s left, 0 waiting\n"))
        for request in [ControlRequest.appStatus, .state] {
            let answer = await rig.send(request, by: other, json: true)
            let object = try #require(try JSONSerialization.jsonObject(with: Data(answer.reply.output.utf8)) as? [String: Any])
            let lease = try #require(object["lease"] as? [String: Any])
            #expect(lease["holder"] as? String == "Claude Code")
            #expect(lease["place"] as? String == "/work/shop")
            #expect(lease["secondsLeft"] as? Int == 48)
            #expect(lease["waiting"] as? Int == 0)
        }
        // Asking renewed nothing and took nothing.
        #expect(rig.server.lease.current(at: rig.clock.now) == ControlLease.Term(
            holder: agent, taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 60)
        ))
    }

    @Test func takeHoldsTheLeaseToTheCapAndSaysUntilWhenAndReleaseFreesIt() async {
        let rig = Rig()

        let taken = await rig.send(.controlTake(waitSeconds: nil), by: agent)
        rig.clock.set(10)
        let refused = await rig.send(.controlTake(waitSeconds: nil), by: other)
        let notTheirs = await rig.send(.controlRelease, by: other, json: true)
        let stillHeld = rig.server.lease.current(at: rig.clock.now)?.holder
        let released = await rig.send(.controlRelease, by: agent)

        let term = ControlLease.Term(holder: agent, taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 300))
        #expect(taken == ControlServer.Answer(reply: .done("you hold video-review until 00:05:00\n"), granted: term))
        #expect(refused.reply == .refused(
            "video-review is in use by Claude Code in /work/shop until 00:05:00 (290s left); "
                + "`video-review control take --wait <seconds>` to queue"
        ))
        #expect(notTheirs.reply == .done(#"{"released":false}"# + "\n"))
        #expect(stillHeld == agent)
        #expect(released.reply == .done("released video-review\n"))
        #expect(rig.server.lease.current(at: rig.clock.now) == nil)
    }

    @Test func takeAndReleaseAnswerAsJSON() async {
        let rig = Rig()
        #expect(await rig.send(.controlTake(waitSeconds: nil), by: agent, json: true).reply
            == .done(#"{"held":true,"until":"1970-01-01T00:05:00Z"}"# + "\n"))
        #expect(await rig.send(.controlRelease, by: agent, json: true).reply == .done(#"{"released":true}"# + "\n"))
    }

    @Test func takesThatWaitGetTheLeaseInTheOrderTheyCame() async throws {
        let rig = Rig()
        _ = await rig.send(.controlTake(waitSeconds: nil), by: agent)
        let second = try await rig.queue(other, seconds: 120, as: 1)
        let last = try await rig.queue(third, seconds: 120, as: 2)
        #expect(rig.server.lease.status(at: rig.clock.now)?.waiting == 2)

        rig.clock.set(10)
        _ = await rig.send(.controlRelease, by: agent)
        let first = await second.value

        #expect(first.reply == .done("you hold video-review until 00:05:10\n"))
        #expect(rig.server.lease.current(at: rig.clock.now)?.holder == other)
        #expect(rig.server.lease.status(at: rig.clock.now)?.waiting == 1)
        // The one still in line can't act meanwhile.
        #expect(await rig.send(.playerPause, by: third).reply.ok == false)

        rig.clock.set(20)
        _ = await rig.send(.controlRelease, by: other)

        #expect(await last.value.reply == .done("you hold video-review until 00:05:20\n"))
        #expect(rig.server.lease.current(at: rig.clock.now)?.holder == third)
    }

    @Test func aTakeWhoseWaitRunsOutIsRefusedWithWhoStillHoldsTheLeaseAndLeavesTheLine() async throws {
        let rig = Rig()
        _ = await rig.send(.controlTake(waitSeconds: nil), by: agent)

        let waiting = try await rig.queue(other, seconds: 1, as: 1)
        rig.clock.advance(by: 1)
        let waited = await waiting.value

        #expect(waited.reply == .refused(
            "waited 1s; video-review is still in use by Claude Code in /work/shop until 00:05:00 (299s left)"
        ))
        #expect(rig.server.lease.waiting(at: rig.clock.now) == 0)
        #expect(rig.server.lease.current(at: rig.clock.now)?.holder == agent)
    }

    @Test func whenTheLeaseRunsOutWithNoRequestTheFirstWaitingTakeGetsItAndTheBannerFollows() async throws {
        let rig = Rig()
        _ = await rig.send(.playerOpen(path: fixtureVideo.path), by: agent)
        let waiting = try await rig.queue(other, seconds: 120, as: 1, json: true)
        #expect(rig.server.indicator.lease.status(at: rig.clock.now)
            == LeaseStatus(holder: "Claude Code", place: "/work/shop", secondsLeft: 60, waiting: 1))

        // No request comes: the server's own timer ends the lease.
        rig.clock.advance(by: 60)

        #expect(await waiting.value.reply == .done(#"{"held":true,"until":"1970-01-01T00:06:00Z"}"# + "\n"))
        #expect(rig.server.indicator.lease.status(at: rig.clock.now)
            == LeaseStatus(holder: "codex", place: "Herdr pane w1-2", secondsLeft: 300, waiting: 0))
    }

    @Test func theBannerShowsFromTheRequestThatTakesTheLeaseAndGoesOnceItEnds() async {
        let rig = Rig()
        let indicator = rig.server.indicator
        #expect(indicator.lease.status(at: rig.clock.now) == nil)

        _ = await rig.send(.playerOpen(path: fixtureVideo.path), by: agent)
        rig.clock.set(12)

        #expect(indicator.lease.status(at: rig.clock.now).map(LeaseIndicator.Banner.init)?.text
            == "Claude Code controls this app · shop · 48s")
        // The words follow the time they're made at, so the strip goes at the end without the server.
        #expect(indicator.lease.status(at: Date(timeIntervalSince1970: 60)) == nil)
        rig.clock.set(60)
        rig.server.settleLease()
        #expect(indicator.lease == ControlLease())
    }

    @Test func stopEndsTheLeaseAndTheStoppedAgentIsRefusedForFiveMinutesWithNothingDone() async {
        let rig = Rig()
        _ = await rig.send(.playerOpen(path: fixtureVideo.path), by: agent)
        rig.clock.set(10)

        rig.server.stopLease()

        #expect(rig.server.lease.current(at: rig.clock.now) == nil)
        #expect(rig.server.indicator.lease.status(at: rig.clock.now) == nil)
        rig.clock.set(20)
        let refusal = ControlReply.refused("the user took video-review back; ask them before using it again")
        for request in [ControlRequest.playerPlay, .controlTake(waitSeconds: nil), .controlTake(waitSeconds: 30)] {
            #expect(await rig.send(request, by: agent).reply == refusal)
        }
        #expect(!rig.player.isPlaying)
        // Free commands still answer, and nobody else is barred.
        #expect(await rig.send(.state, by: agent).reply.ok)
        rig.clock.set(309)
        #expect(await rig.send(.playerPlay, by: agent).reply == refusal)
        rig.clock.set(310)
        #expect(await rig.send(.playerPlay, by: agent).reply.ok)
    }

    @Test func stopHandsTheLeaseToTheFirstWaitingTake() async throws {
        let rig = Rig()
        _ = await rig.send(.controlTake(waitSeconds: nil), by: agent)
        let waiting = try await rig.queue(other, seconds: 120, as: 1)
        rig.clock.set(10)

        rig.server.stopLease()

        #expect(await waiting.value.reply == .done("you hold video-review until 00:05:10\n"))
        #expect(rig.server.indicator.lease.status(at: rig.clock.now)?.holder == "codex")
    }

    @Test func stopWhileTheLeaseIsFreeChangesNothing() async {
        let rig = Rig()
        rig.server.stopLease()
        #expect(await rig.send(.playerOpen(path: fixtureVideo.path), by: agent).reply.ok)
    }

    @Test func anAppLaunchedWithAHandedOverLeaseHoldsItFromTheStart() async {
        let term = ControlLease.Term(holder: agent, taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 70))
        let rig = Rig(lease: ControlLease(environment: ControlLease.handover(term), at: Date(timeIntervalSince1970: 0)))
        rig.clock.set(20)

        #expect(rig.server.indicator.lease.status(at: rig.clock.now)?.holder == "Claude Code")
        #expect(await rig.send(.playerPause, by: other).reply.ok == false)
    }

    @Test func aGrantedTakeWhoseReplyCouldNotBeWrittenGivesTheLeaseBackAndALeaseThatMovedOnIsLeftAlone() async {
        let rig = Rig()
        let taken = await rig.send(.controlTake(waitSeconds: nil), by: agent)

        rig.server.undelivered(taken)
        #expect(rig.server.lease.current(at: rig.clock.now) == nil)

        _ = await rig.send(.controlTake(waitSeconds: nil), by: other)
        rig.server.undelivered(taken)
        #expect(rig.server.lease.current(at: rig.clock.now)?.holder == other)
    }

    @Test(arguments: [
        (LeaseStatus(holder: "Claude Code", place: "/work/shop", secondsLeft: 48, waiting: 0), "Claude Code controls this app · shop · 48s"),
        (LeaseStatus(holder: "codex", place: "Herdr pane w1-2", secondsLeft: 245, waiting: 2),
         "Codex controls this app · Herdr pane w1-2 · 4m 05s · 2 waiting"),
        (LeaseStatus(holder: "aider", place: "/", secondsLeft: 60, waiting: 1), "Aider controls this app · / · 1m 00s · 1 waiting"),
    ])
    func theBannersWords(status: LeaseStatus, text: String) {
        #expect(LeaseIndicator.Banner(status).text == text)
    }
}

/// The lease over a real socket, through the command as agents run it.
@MainActor
@Suite struct LeaseSocketTests {
    /// A server listening in a temporary support folder, and a way to run
    /// `video-review` against it as a holder, off the main actor: the
    /// command blocks on the socket while the server answers on it.
    @MainActor
    private struct Listening {
        let rig: Rig
        let support: URL

        init() throws {
            support = URL(fileURLWithPath: "/tmp", isDirectory: true)
                .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
            rig = Rig(socket: ControlSocket.url(in: support))
            try rig.server.start()
        }

        func close() {
            rig.server.stop()
            try? FileManager.default.removeItem(at: support)
        }

        func run(_ arguments: String..., key: String) async -> CommandResult {
            var environment = CommandEnvironment.system()
            environment.variables = [AppIdentity.supportVariable: support.path, Holder.keyVariable: key]
            environment.workingDirectory = URL(fileURLWithPath: "/work/shop", isDirectory: true)
            return await Task.detached { [environment] in CommandTable.standard.run(arguments, environment: environment) }.value
        }
    }

    @Test func aSecondHolderExitsOneAndATakeThatWaitsKeepsItsConnectionUntilTheRelease() async throws {
        let app = try Listening()
        defer { app.close() }

        #expect(await app.run("control", "take", key: "one") == CommandResult(output: "you hold video-review until 00:05:00\n"))
        let refused = await app.run("player", "pause", key: "two")
        #expect(refused.status == 1)
        #expect(refused.output.isEmpty)
        #expect(refused.error.hasPrefix("video-review is in use by "))
        #expect(refused.error.hasSuffix(
            " in /work/shop until 00:05:00 (300s left); `video-review control take --wait <seconds>` to queue\n"
        ))

        let waiting = Task { await app.run("control", "take", "--wait", "30", key: "two") }
        try await app.rig.untilWaiting(1)
        // Others are answered while it waits.
        #expect(await app.run("app", "status", key: "three").output.contains(", 300s left, 1 waiting\n"))
        app.rig.clock.set(12)
        #expect(await app.run("control", "release", key: "one") == CommandResult(output: "released video-review\n"))

        #expect(await waiting.value == CommandResult(output: "you hold video-review until 00:05:12\n"))
        #expect(app.rig.server.lease.current(at: app.rig.clock.now)?.holder.key == "two")
    }

    @Test func aWaitingTakeWhoseClientHasGoneGivesBackTheLeaseItIsGrantedAndTheNextWaiterGetsIt() async throws {
        let app = try Listening()
        defer { app.close() }
        let server = app.rig.server
        _ = await app.run("control", "take", key: "one")

        // A client that sends its take, then goes without reading the reply.
        let gone = UnixSocket.make()
        let address = try #require(UnixSocket.address(server.socket.path))
        #expect(UnixSocket.connectSocket(gone, to: address) == 0)
        let message = ControlMessage(.controlTake(waitSeconds: 30), holder: Holder(key: "gone", name: "codex", place: "/work"))
        #expect(UnixSocket.writeAll(gone, message.encoded()))
        UnixSocket.finishWriting(gone)
        try await app.rig.untilWaiting(1)
        Darwin.close(gone)
        let waiting = Task { await app.run("control", "take", "--wait", "30", key: "next") }
        try await app.rig.untilWaiting(2)
        app.rig.clock.set(12)

        _ = await app.run("control", "release", key: "one")

        #expect(await waiting.value == CommandResult(output: "you hold video-review until 00:05:12\n"))
        #expect(server.lease.current(at: app.rig.clock.now)?.holder.key == "next")
    }
}
