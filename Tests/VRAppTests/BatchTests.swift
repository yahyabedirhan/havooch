import Foundation
import Testing
@testable import VRApp
import VRCommand
import VRLease
import VRReview
import VRStore
import VRWire

private let operatorHolder = Holder(key: "operator", name: "Claude Code", place: "/Users/me/repo")
private let listener = Holder(key: "listener-1", name: "Claude Code", place: "/Users/me/shop")
private let restarted = Holder(key: "listener-2", name: "Claude Code", place: "/Users/me/shop")

/// A frame grabber whose first keyframes fail, then work.
private struct FlakyFrames: FrameGrabbing {
    let failures: FakeFrames.Count
    let failing: Int

    func writeKeyframe(of video: URL, at seconds: Double, to file: URL) async throws -> CGSize {
        if failures.value < failing {
            failures.add()
            throw FakeFrames.Failure()
        }
        return try await FakeFrames().writeKeyframe(of: video, at: seconds, to: file)
    }

    func writeCrop(of keyframe: URL, region: Region, to file: URL) async throws {
        try await FakeFrames().writeCrop(of: keyframe, region: region, to: file)
    }
}

/// A control server over a fake player, a library of its own and a clock the
/// test sets, with the fixture video open: an operator and a listener.
@MainActor
final class BatchRig {
    let player = FakePlayer()
    let clock = FakeClock()
    let library = scratchLibrary()
    let model: ReviewModel
    let server: ControlServer

    init(frames: any FrameGrabbing = FakeFrames(), socket: URL = URL(fileURLWithPath: "/tmp/vr-unused/control.sock")) {
        clock.set(1_759_579_200)
        let model = ReviewModel(player: player, frames: frames, library: library, now: { [clock] in clock.now })
        self.model = model
        server = ControlServer(
            socket: socket,
            model: model,
            desk: OperatorDesk(model: model) { _, _ in .captured },
            now: { [clock] in clock.now },
            quit: {}
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: library.root)
    }

    func opened() async -> BatchRig {
        _ = await send(.playerOpen(path: fixtureVideo.path))
        return self
    }

    func send(_ request: ControlRequest, by holder: Holder = operatorHolder, json: Bool = false) async -> ControlReply {
        await server.reply(to: ControlMessage(request, holder: holder, json: json).encoded()).reply
    }

    /// Two queued comments: one on the whole frame, one on a region.
    func queueTwo() async {
        _ = await send(.commentAdd(text: "too fast", at: 10, region: nil))
        _ = await send(.commentAdd(text: "this button", at: 4.5, region: .init(x: 0.5, y: 0, w: 0.5, h: 0.5)))
    }

    func object(_ request: ControlRequest) async throws -> [String: Any] {
        let reply = await send(request, json: true)
        #expect(reply.ok, "\(reply.error)")
        return try #require(try JSONSerialization.jsonObject(with: Data(reply.output.utf8)) as? [String: Any])
    }

    func state() async throws -> [String: Any] {
        try await object(.state)
    }

    func presence() async throws -> String? {
        (try await state()["listener"] as? [String: Any])?["presence"] as? String
    }

    func commentStates() async throws -> [String] {
        try #require(try await state()["comments"] as? [[String: Any]]).compactMap { $0["state"] as? String }
    }

    /// A `wait`, answered as the socket would: the reply counts as written.
    func wait(by holder: Holder = listener, timeout: Int? = nil) async -> ControlServer.Answer {
        let answer = await server.reply(to: ControlMessage(.wait(timeoutSeconds: timeout), holder: holder).encoded())
        server.written(answer, delivered: true)
        return answer
    }

    /// A `wait` sent without waiting for its answer, on the connection
    /// `ticket`; returns once the server holds it.
    func park(by holder: Holder = listener, timeout: Int? = nil, ticket: UUID = UUID()) async -> Task<ControlServer.Answer, Never> {
        let held = server.listeners.waiting
        let waiting = Task { await server.reply(to: ControlMessage(.wait(timeoutSeconds: timeout), holder: holder).encoded(), ticket: ticket) }
        for _ in 0..<2_000 where server.listeners.waiting == held {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return waiting
    }
}

private func payload(_ answer: ControlServer.Answer) throws -> BatchPayload {
    #expect(answer.reply.ok, "\(answer.reply.error)")
    return try JSONDecoder().decode(BatchPayload.self, from: Data(answer.reply.output.utf8))
}

@MainActor
@Suite struct BatchTests {
    @Test func batchSendSendsEveryQueuedCommentAsOneBatch() async throws {
        let rig = await BatchRig().opened()
        await rig.queueTwo()

        #expect(await rig.send(.batchSend) == .done("sent b1 with 2 comments\n"))

        let state = try await rig.state()
        #expect(state["queue"] as? [String] == [])
        let comments = try #require(state["comments"] as? [[String: Any]])
        #expect(comments.map { $0["state"] as? String } == ["sent", "sent"])
        #expect(comments.map { $0["batchId"] as? String } == ["b1", "b1"])
        let batches = try #require(state["batches"] as? [[String: Any]])
        #expect(batches.count == 1)
        #expect(batches[0]["id"] as? String == "b1")
        #expect(batches[0]["sentAt"] as? String == "2025-10-04T12:00:00Z")
        #expect(batches[0]["commentIds"] as? [String] == ["c2", "c1"])
        #expect(batches[0]["delivery"] as? String == "pending")
        #expect(batches[0]["finished"] as? Bool == false)
        // What the timeline marks: both pins say sent.
        #expect(Timeline.markers(for: rig.model.comments, selection: nil).map(\.state) == [.sent, .sent])
    }

    @Test func batchSendAsJSONNamesTheBatchAndItsComments() async throws {
        let rig = await BatchRig().opened()
        await rig.queueTwo()

        let sent = try await rig.object(.batchSend)

        #expect(sent["id"] as? String == "b1")
        #expect(sent["sentAt"] as? String == "2025-10-04T12:00:00Z")
        #expect(sent["commentIds"] as? [String] == ["c2", "c1"])
    }

    @Test func sendingWithNothingQueuedIsRefusedAndASentCommentIsNotSentTwice() async throws {
        let rig = await BatchRig().opened()
        let nothing = ControlReply.refused("there's nothing to send: no comment is queued")
        #expect(await rig.send(.batchSend) == nothing)

        _ = await rig.send(.commentAdd(text: "one", at: 1, region: nil))
        #expect(await rig.send(.batchSend) == .done("sent b1 with 1 comment\n"))
        #expect(await rig.send(.batchSend) == nothing)
        #expect(await rig.send(.commentEdit(id: "c1", text: "other")) == .refused("c1 was sent; it can't be edited"))
    }

    @Test func sendingNeedsAnOpenVideoAndTheLease() async {
        let rig = BatchRig()
        #expect(await rig.send(.batchSend) == .refused("no video is open; `video-review player open <path>`"))
        // The first operator holds the lease; a listener is not an operator.
        let reply = await rig.send(.batchSend, by: listener)
        #expect(!reply.ok)
        #expect(reply.error.hasPrefix("video-review is in use by Claude Code"))
    }

    @Test func commandEnterSendsTheSameBatchAsBatchSend() async throws {
        let rig = await BatchRig().opened()
        await rig.queueTwo()

        rig.model.sendByPerson()
        await settle { rig.model.session?.batches.isEmpty == false }

        #expect(rig.model.session?.batches.map(\.commentIDs) == [["c2", "c1"]])
        #expect(rig.model.outbox.parcels.map(\.batchID) == ["b1"])
        #expect(try await rig.commentStates() == ["sent", "sent"])
        #expect(rig.model.sendFailure == nil)
    }

    @Test func commandEnterInsideTheCommentBoxQueuesWhatItHoldsFirst() async throws {
        let rig = await BatchRig().opened()
        _ = await rig.send(.playerSeek(seconds: 3))
        rig.model.compose()
        rig.model.composerText = "typed, not yet queued"

        rig.model.sendByPerson()
        await settle { rig.model.session?.batches.isEmpty == false }

        #expect(rig.model.composing == nil)
        #expect(rig.model.comments.map(\.text) == ["typed, not yet queued"])
        #expect(try await rig.commentStates() == ["sent"])
    }

    @Test func commandEnterWithNothingToSendSaysWhy() async {
        let rig = await BatchRig().opened()

        rig.model.sendByPerson()
        await settle { rig.model.sendFailure != nil }

        #expect(rig.model.sendFailure == "there's nothing to send: no comment is queued")
        #expect(SendBar.note(failure: rig.model.sendFailure, presence: .absent, queued: 0, waiting: 0)
            == "there's nothing to send: no comment is queued")

        // A comment queued after it makes the refusal stale.
        _ = await rig.send(.commentAdd(text: "one", at: 1, region: nil))
        #expect(rig.model.sendFailure == nil)
    }

    @Test func commandEnterPressedTwiceSendsOnceAndSaysNothingFailed() async throws {
        let rig = await BatchRig().opened()
        await rig.queueTwo()

        rig.model.sendByPerson()
        rig.model.sendByPerson()
        await settle { rig.model.session?.batches.isEmpty == false }
        try? await Task.sleep(for: .milliseconds(50))

        #expect(rig.model.session?.batches.count == 1)
        #expect(rig.model.sendFailure == nil)
    }

    @Test func aCommentWithoutItsKeyframeHasItGrabbedOnceMoreWhenSent() async throws {
        let failures = FakeFrames.Count()
        let rig = await BatchRig(frames: FlakyFrames(failures: failures, failing: 1)).opened()
        // From the window, a comment whose frame couldn't be saved stays.
        rig.model.compose()
        #expect(rig.model.commitComposer(text: "no frame yet"))
        await settle { failures.value == 1 }
        #expect(rig.model.keyframeURL(for: "c1") == nil)

        #expect(await rig.send(.batchSend) == .done("sent b1 with 1 comment\n"))

        let batch = try payload(await rig.wait())
        #expect(batch.comments.map(\.keyframePath) == [rig.library.keyframeURL(batch.video.contentHash, comment: "c1").path])
    }

    @Test func aKeyframeThatStillCannotBeSavedNeverHoldsTheBatchBack() async throws {
        let failures = FakeFrames.Count()
        let rig = await BatchRig(frames: FlakyFrames(failures: failures, failing: .max)).opened()
        rig.model.compose()
        #expect(rig.model.commitComposer(text: "no frame at all"))

        #expect(await rig.send(.batchSend) == .done("sent b1 with 1 comment\n"))

        // The first grab, and one more at send time.
        #expect(failures.value == 2)
        let batch = try payload(await rig.wait())
        #expect(batch.comments.map(\.text) == ["no frame at all"])
        #expect(batch.comments.map(\.keyframePath) == [nil])
    }

    @Test func theSendBarSaysWhatHappensToABatchWithNoListener() {
        #expect(SendBar.note(failure: nil, presence: .absent, queued: 2, waiting: 0)
            == "No agent is listening. A batch you send waits for the next listener.")
        #expect(SendBar.note(failure: nil, presence: .absent, queued: 0, waiting: 1) == "1 batch waits for the next listener.")
        #expect(SendBar.note(failure: nil, presence: .absent, queued: 0, waiting: 2) == "2 batches wait for the next listener.")
        #expect(SendBar.note(failure: nil, presence: .absent, queued: 0, waiting: 0) == nil)
        #expect(SendBar.note(failure: nil, presence: .listening, queued: 2, waiting: 0) == nil)
    }
}

@MainActor
@Suite struct WaitTests {
    @Test func aBatchSentBeforeTheWaitIsReturnedByTheNextWait() async throws {
        let rig = await BatchRig().opened()
        await rig.queueTwo()
        _ = await rig.send(.batchSend)
        #expect(try await rig.presence() == "absent")

        let batch = try payload(await rig.wait())

        let hash = try #require(rig.model.video?.info.contentHash)
        #expect(batch.batch == BatchPayload.Header(id: "b1", sentAt: "2025-10-04T12:00:00Z"))
        #expect(batch.video == rig.model.video?.info)
        #expect(batch.context == nil)
        #expect(batch.comments == [
            BatchPayload.Item(
                id: "c2", time: 4.5, text: "this button",
                keyframePath: rig.library.keyframeURL(hash, comment: "c2").path,
                region: try Region(x: 0.5, y: 0, w: 0.5, h: 0.5),
                cropPath: rig.library.cropURL(hash, comment: "c2").path,
                transcript: []
            ),
            BatchPayload.Item(
                id: "c1", time: 10, text: "too fast",
                keyframePath: rig.library.keyframeURL(hash, comment: "c1").path,
                region: nil, cropPath: nil, transcript: []
            ),
        ])
        for path in batch.comments.flatMap({ [$0.keyframePath, $0.cropPath] }).compactMap({ $0 }) {
            #expect(FileManager.default.fileExists(atPath: path))
        }
        let batches = try #require(try await rig.state()["batches"] as? [[String: Any]])
        #expect(batches[0]["delivery"] as? String == "taken")
    }

    @Test func thePayloadIsOneLineOfJSONWithEveryKeyOfTheSpec() async throws {
        let rig = await BatchRig().opened()
        await rig.queueTwo()
        _ = await rig.send(.batchSend)

        let output = await rig.wait().reply.output

        #expect(output.hasSuffix("\n"))
        #expect(output.dropLast().allSatisfy { !$0.isNewline })
        let object = try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        #expect(Set(object.keys) == ["batch", "video", "context", "comments"])
        #expect(object["context"] is NSNull)
        #expect(Set(try #require(object["batch"] as? [String: Any]).keys) == ["id", "sentAt"])
        #expect(Set(try #require(object["video"] as? [String: Any]).keys) == ["path", "contentHash", "duration", "title"])
        let comments = try #require(object["comments"] as? [[String: Any]])
        for comment in comments {
            #expect(Set(comment.keys) == ["id", "time", "text", "keyframePath", "region", "cropPath", "transcript"])
        }
        #expect(comments[1]["region"] is NSNull)
        #expect(comments[1]["cropPath"] is NSNull)
    }

    @Test func aParkedWaitWakesWhenTheBatchIsSent() async throws {
        let rig = await BatchRig().opened()
        await rig.queueTwo()

        let waiting = await rig.park()
        #expect(try await rig.presence() == "listening")

        #expect(await rig.send(.batchSend) == .done("sent b1 with 2 comments\n"))
        let answer = await waiting.value

        #expect(try payload(answer).comments.map(\.id) == ["c2", "c1"])
        #expect(answer.batch == "b1")
        #expect(rig.server.listeners.waiting == 0)
        // Until the reply is written the wait is open; then the listener reads its batch.
        rig.server.written(answer, delivered: true)
        #expect(try await rig.presence() == "working")
    }

    @Test func aListenerNeedsNoLeaseAndTakesNone() async throws {
        let rig = await BatchRig().opened()
        _ = await rig.send(.commentAdd(text: "one", at: 1, region: nil))
        _ = await rig.send(.batchSend)

        // The operator holds the lease; the listener's wait is answered all the same.
        #expect(try payload(await rig.wait()).batch.id == "b1")
        #expect(rig.server.lease.current(at: rig.clock.now)?.holder.key == "operator")
    }

    @Test func presenceChangesWhenAWaitOpensAndCloses() async throws {
        let rig = await BatchRig().opened()
        #expect(try await rig.presence() == "absent")
        #expect(rig.model.presence == .absent)

        let ticket = UUID()
        let waiting = await rig.park(ticket: ticket)
        #expect(try await rig.presence() == "listening")
        let listenerState = try #require(try await rig.state()["listener"] as? [String: Any])
        #expect(listenerState["name"] as? String == "Claude Code")
        #expect((try await rig.object(.appStatus)["listener"] as? [String: Any])?["presence"] as? String == "listening")
        #expect(await rig.send(.state).output.contains("listener: listening (Claude Code)\n"))

        // The listener's command was stopped: its heartbeat can't be written.
        rig.server.dropped(ticket)

        #expect(await waiting.value.reply == .refused("the listener went away"))
        #expect(try await rig.presence() == "absent")
        #expect(await rig.send(.appStatus).output.contains("listener: absent\n"))
    }

    @Test func aWaitWhoseTimeRanOutIsDoneWithNothingToPrintAndTheListenerIsGone() async throws {
        let rig = await BatchRig().opened()

        let none = await rig.wait(timeout: 0)
        #expect(none.reply == .done("", note: "no batch came within 0 seconds\n"))
        #expect(try await rig.presence() == "absent")

        let waiting = await rig.park(timeout: 1)
        #expect(try await rig.presence() == "listening")
        #expect(await waiting.value.reply == .done("", note: "no batch came within 1 second\n"))
        #expect(try await rig.presence() == "absent")
        #expect(rig.server.listeners.waiting == 0)
    }

    @Test func aBatchWhoseReplyCouldNotBeWrittenGoesToTheNextWait() async throws {
        let rig = await BatchRig().opened()
        await rig.queueTwo()
        _ = await rig.send(.batchSend)

        let lost = await rig.server.reply(to: ControlMessage(.wait(timeoutSeconds: nil), holder: listener).encoded())
        #expect(lost.batch == "b1")
        rig.server.written(lost, delivered: false)

        #expect(try await rig.presence() == "absent")
        #expect(try payload(await rig.wait()).batch.id == "b1")
    }

    @Test func aListenerThatStartedAgainGetsTheBatchItTookAndDidNotFinish() async throws {
        let rig = await BatchRig().opened()
        await rig.queueTwo()
        _ = await rig.send(.batchSend)
        let first = try payload(await rig.wait())

        // The same session waiting again has its batch already.
        #expect(await rig.wait(timeout: 0).reply.output.isEmpty)

        let again = try payload(await rig.wait(by: restarted))

        #expect(again == first)
        #expect(try await rig.commentStates() == ["sent", "sent"])
        #expect(rig.model.outbox.parcel("b1")?.delivery == .taken(by: "listener-2", at: rig.clock.now))
    }

    @Test func anotherListenerTakingOverEndsTheEarlierOnesParkedWait() async throws {
        let rig = await BatchRig().opened()
        let earlier = await rig.park()

        let later = Task { await rig.server.reply(to: ControlMessage(.wait(timeoutSeconds: nil), holder: restarted).encoded()) }

        // The earlier wait ends in the same step the later one is parked in.
        #expect(await earlier.value.reply == .refused("another listener, Claude Code, took over"))
        #expect(rig.server.listeners.waiting == 1)
        #expect(try await rig.presence() == "listening")
        _ = await rig.send(.commentAdd(text: "one", at: 1, region: nil))
        _ = await rig.send(.batchSend)
        #expect(try payload(await later.value).batch.id == "b1")
    }

    @Test func twoBatchesComeOneWaitAtATimeOldestFirst() async throws {
        let rig = await BatchRig().opened()
        _ = await rig.send(.commentAdd(text: "one", at: 1, region: nil))
        _ = await rig.send(.batchSend)
        _ = await rig.send(.commentAdd(text: "two", at: 2, region: nil))
        _ = await rig.send(.batchSend)

        #expect(try payload(await rig.wait()).comments.map(\.id) == ["c1"])
        #expect(try payload(await rig.wait()).comments.map(\.id) == ["c2"])
    }

    @Test func aParkedWaitHearsTheAppQuit() async {
        let rig = await BatchRig().opened()
        let waiting = await rig.park()

        rig.server.stop()

        #expect(await waiting.value.reply == .refused("video-review is quitting"))
    }
}

/// The `wait` command and the server joined by a real socket: the heartbeat
/// keeps the connection, and the command prints the payload.
@MainActor
@Suite struct WaitSocketTests {
    @Test func theWaitCommandGetsABatchSentWhileItWaits() async throws {
        let support = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let rig = await BatchRig(socket: ControlSocket.url(in: support)).opened()
        try rig.server.start()
        defer { rig.server.stop() }
        await rig.queueTwo()

        let table = CommandTable.standard
        var environment = CommandEnvironment.system()
        environment.variables = [AppIdentity.supportVariable: support.path, Holder.keyVariable: "listener-socket"]
        // Off the main actor: the command blocks on the socket while the
        // server answers on the main actor.
        let waiting = Task.detached { [environment] in table.run(["wait", "--timeout", "30"], environment: environment) }
        await settle { rig.server.listeners.waiting == 1 }
        #expect(rig.model.presence == .listening)

        #expect(await rig.send(.batchSend) == .done("sent b1 with 2 comments\n"))
        let result = await waiting.value

        #expect(result.status == 0)
        #expect(result.error.isEmpty)
        let batch = try JSONDecoder().decode(BatchPayload.self, from: Data(result.output.utf8))
        #expect(batch.comments.map(\.id) == ["c2", "c1"])
        // The reply was written: the wait closed with its batch.
        await settle { rig.model.presence == .working }
        #expect(rig.model.presence == .working)

        let ranOut = await Task.detached { [environment] in table.run(["wait", "--timeout", "0"], environment: environment) }.value
        #expect(ranOut == CommandResult(error: "no batch came within 0 seconds\n", status: 3))
    }
}

/// Waits for work a task does in the background, at most 2 seconds.
@MainActor
private func settle(until done: () -> Bool) async {
    for _ in 0..<2_000 where !done() {
        try? await Task.sleep(for: .milliseconds(1))
    }
}
