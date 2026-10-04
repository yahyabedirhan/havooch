import Darwin
import Foundation
import Testing
@testable import VRApp
import VRLease
import VRReview
import VRWire

/// A batch from `batch send` to `wait`: requests answered in memory at
/// times the test sets, and over the real socket in a temporary folder, on
/// the fixture video. No window is opened and no sound is made.
@Suite(.serialized) @MainActor struct ListenerWaitTests {
    /// The time the app sends a batch and judges presence at, moved by the test.
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_791_115_200)
    }

    nonisolated static let operatorAgent = Holder(key: "operator", name: "Claude Code", place: "/work")
    nonisolated static let first = Holder(key: "L1", name: "Claude Code", place: "/repo")
    nonisolated static let second = Holder(key: "L2", name: "codex", place: "Herdr pane w1-2")

    let clock = Clock()
    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
    var socket: URL { folder.appendingPathComponent("control.sock") }

    /// A model with the fixture open and silent, at the clock's time.
    func model() async throws -> AppModel {
        let model = AppModel(environment: [SupportFolder.overrideVariable: folder.path], now: { [clock] in clock.now })
        model.player.player.isMuted = true
        try await model.open(RegionCommentTests.fixture)
        return model
    }

    func server(on model: AppModel, heartbeat: Duration = .milliseconds(40)) -> ControlServer {
        ControlServer(
            socket: socket, model: model, screenshotter: Screenshotter(model: model), lease: ControlLease(), indicator: LeaseIndicator(),
            now: { [clock] in clock.now }, timeZone: TimeZone(identifier: "UTC") ?? .gmt, heartbeat: heartbeat, quit: {}
        )
    }

    static func sent(_ request: ControlRequest, by holder: Holder = operatorAgent, json: Bool = false) -> Data {
        ControlMessage(request, holder: holder, json: json).encoded()
    }

    /// Queues a comment at 10 s and one on a region at 4 s.
    func queueTwo(on server: ControlServer) async {
        _ = await server.reply(to: Self.sent(.commentAdd(text: "too fast", at: 10, region: nil)))
        _ = await server.reply(to: Self.sent(.commentAdd(text: "this box", at: 4, region: WireRegion(x: 0.1, y: 0.2, w: 0.3, h: 0.2))))
    }

    /// What `state` says, as JSON.
    func state(of server: ControlServer) async throws -> [String: Any] {
        let reply = await server.reply(to: Self.sent(.state, by: Self.second))
        return try #require(JSONSerialization.jsonObject(with: Data(reply.reply.output.utf8)) as? [String: Any])
    }

    func presence(of server: ControlServer) async throws -> String? {
        (try await state(of: server)["listener"] as? [String: Any])?["presence"] as? String
    }

    /// Where the first batch stands, as `state` names it.
    func delivery(of server: ControlServer) async throws -> String? {
        (try await state(of: server)["batches"] as? [[String: Any]])?.first?["delivery"] as? String
    }

    /// Waits until `state` shows the listener as `wanted`.
    func until(_ wanted: String, on server: ControlServer) async throws {
        for _ in 0..<500 {
            if try await presence(of: server) == wanted { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the listener never became \(wanted)")
    }

    static func payload(_ answer: ControlServer.Answer) throws -> BatchPayload {
        try JSONDecoder().decode(BatchPayload.self, from: Data(answer.reply.output.utf8))
    }

    /// Runs `body`, which blocks on the socket, off the main actor.
    static func sending<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: body()) }
        }
    }

    // MARK: - Sending

    @Test func batchSendSendsEveryQueuedCommentAsOneBatchAndTheyShowAsSent() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        let server = server(on: model)
        await queueTwo(on: server)

        let sent = await server.reply(to: Self.sent(.batchSend, json: true))
        let again = await server.reply(to: Self.sent(.batchSend))

        let review = try #require(model.desk.open)
        let prefix = review.video.contentHash.prefix(8)
        #expect(sent == .init(reply: .done(#"{"batchId":"\#(prefix)-b1","commentIds":["\#(prefix)-c2","\#(prefix)-c1"]}"# + "\n")))
        #expect(again == .init(reply: .refused("the queue is empty: there is no comment to send")))
        #expect(review.comments.map(\.state) == [.sent, .sent])
        let state = try await state(of: server)
        #expect((state["comments"] as? [[String: Any]])?.map { $0["state"] as? String } == ["sent", "sent"])
        #expect((state["comments"] as? [[String: Any]])?.map { $0["batchId"] as? String } == ["\(prefix)-b1", "\(prefix)-b1"])
        #expect((state["queue"] as? [String]) == [])
        let batch = try #require((state["batches"] as? [[String: Any]])?.first)
        #expect(batch["id"] as? String == "\(prefix)-b1")
        #expect(batch["sentAt"] as? String == "2026-10-04T12:00:00Z")
        #expect(batch["commentIds"] as? [String] == ["\(prefix)-c2", "\(prefix)-c1"])
        // Nobody listens: it waits for the next listener.
        #expect(batch["delivery"] as? String == "pending")
        #expect(try await presence(of: server) == "absent")
    }

    @Test func sendingQueuesWhatIsTypedInTheCommentBoxFirst() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        try await model.seek(to: 6)
        try model.startDraft()
        model.desk.typeDraft("  ")
        #expect(!model.canSend)
        model.desk.typeDraft("typed, not yet queued")
        #expect(model.canSend)

        let batch = try await model.sendBatch()

        let review = try #require(model.desk.open)
        #expect(model.desk.draft == nil)
        #expect(batch.comments.count == 1)
        #expect(review.comments.map(\.text) == ["typed, not yet queued"])
        #expect(review.comments.map(\.time) == [6])
        #expect(review.comments.map(\.state) == [.sent])
        #expect(!model.canSend)
    }

    @Test func sendingWithNoVideoOpenIsRefused() async {
        let model = AppModel(environment: [SupportFolder.overrideVariable: folder.path])
        let server = server(on: model)

        let refused = await server.reply(to: Self.sent(.batchSend))

        #expect(refused == .init(reply: .refused("no video is open")))
    }

    // MARK: - Waiting

    @Test func aBatchSentBeforeAWaitIsReturnedByTheNextWaitWithEveryFieldOfThePayload() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        let server = server(on: model)
        await queueTwo(on: server)
        _ = await server.reply(to: Self.sent(.batchSend))
        clock.now += 30

        let answer = await server.reply(to: Self.sent(.wait(timeoutSeconds: nil), by: Self.first))

        let review = try #require(model.desk.open)
        let hash = review.video.contentHash
        let prefix = hash.prefix(8)
        let frames = folder.appendingPathComponent("videos/\(hash)/frames").path
        let crops = folder.appendingPathComponent("videos/\(hash)/crops").path
        let payload = try Self.payload(answer)
        #expect(answer.reply.output.hasSuffix("}\n"))
        #expect(payload.batch == .init(id: "\(prefix)-b1", sentAt: "2026-10-04T12:00:00Z"))
        #expect(payload.video == .init(path: RegionCommentTests.fixture.path, contentHash: hash, duration: 21.233, title: "sample"))
        // The fixture's sidecar: this listener's first batch of the video.
        let context = try String(contentsOf: ContextText.candidates(for: RegionCommentTests.fixture)[0], encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(context.hasPrefix("# Context: sample"))
        #expect(payload.context == context)
        #expect(payload.comments == [
            .init(
                id: "\(prefix)-c2", time: 4, text: "this box", keyframePath: "\(frames)/\(prefix)-c2.png",
                region: Region(x: 0.1, y: 0.2, w: 0.3, h: 0.2), cropPath: "\(crops)/\(prefix)-c2.png",
                transcript: TranscriptBatchTests.scenes
            ),
            .init(
                id: "\(prefix)-c1", time: 10, text: "too fast", keyframePath: "\(frames)/\(prefix)-c1.png", region: nil, cropPath: nil,
                transcript: TranscriptBatchTests.scenes
            ),
        ])
        for path in payload.comments.map(\.keyframePath) + payload.comments.compactMap(\.cropPath) {
            #expect(path.hasPrefix("/"))
            #expect(FileManager.default.fileExists(atPath: path))
        }
        #expect(answer.delivery == .init(batch: BatchID(rawValue: "\(prefix)-b1"), listener: "L1", context: context))
    }

    @Test func aBatchIsTakenOnlyOnceItsReplyWasWrittenAndIsNotHandedOutTwice() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        let server = server(on: model)
        await queueTwo(on: server)
        _ = await server.reply(to: Self.sent(.batchSend))

        let answer = await server.reply(to: Self.sent(.wait(timeoutSeconds: nil), by: Self.first))
        // Its reply is still being written: not taken yet, and not for a second wait either.
        let meanwhile = try await delivery(of: server)
        let second = await server.reply(to: Self.sent(.wait(timeoutSeconds: 0), by: Self.first))
        server.written(answer)
        let after = try await delivery(of: server)
        let third = await server.reply(to: Self.sent(.wait(timeoutSeconds: 0), by: Self.first))

        #expect(answer.delivery != nil)
        #expect(meanwhile == "pending")
        // A wait whose timeout ran out answers with nothing to print: the command exits 3.
        #expect(second == .init(reply: .done("")))
        #expect(after == "taken")
        #expect(third == .init(reply: .done("")))
    }

    @Test func aBatchWhoseReplyCouldNotBeWrittenIsStillThereForTheNextWait() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        let server = server(on: model)
        await queueTwo(on: server)
        _ = await server.reply(to: Self.sent(.batchSend))

        let lost = await server.reply(to: Self.sent(.wait(timeoutSeconds: nil), by: Self.first))
        server.undelivered(lost)
        let standing = try await delivery(of: server)
        let again = await server.reply(to: Self.sent(.wait(timeoutSeconds: 0), by: Self.first))

        #expect(standing == "pending")
        #expect(try Self.payload(again) == Self.payload(lost))
    }

    @Test func anOpenWaitMakesTheListenerPresentAndReturnsWhenABatchIsSent() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        let server = server(on: model)
        await queueTwo(on: server)
        #expect(try await presence(of: server) == "absent")

        let waiting = Task { await server.reply(to: Self.sent(.wait(timeoutSeconds: nil), by: Self.first)) }
        try await until("listening", on: server)
        let listener = try await state(of: server)["listener"] as? [String: Any]
        // The main actor is free while the wait is open: the send is answered.
        let sent = await server.reply(to: Self.sent(.batchSend))
        let answer = await waiting.value
        server.written(answer)

        #expect(listener?["name"] as? String == "Claude Code")
        #expect(listener?["place"] as? String == "/repo")
        #expect(sent.reply.ok)
        #expect(try Self.payload(answer).comments.map(\.text) == ["this box", "too fast"])
        // The wait has closed, and its listener has a batch to work on.
        #expect(try await presence(of: server) == "working")
        #expect(model.listener.presenceRunsOut)
    }

    @Test func aWaitThatRunsOutLeavesTheListenerAbsentAndABatchSentLaterPending() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        let server = server(on: model)
        await queueTwo(on: server)

        let ranOut = await server.reply(to: Self.sent(.wait(timeoutSeconds: 1), by: Self.first))
        let presence = try await presence(of: server)
        _ = await server.reply(to: Self.sent(.batchSend))

        #expect(ranOut == .init(reply: .done("")))
        #expect(presence == "absent")
        #expect(try await delivery(of: server) == "pending")
    }

    @Test func aListenerWithABatchAndNoWaitCountsAsWorkingForTwoMinutesAfterItsLastCommand() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        let server = server(on: model)
        await queueTwo(on: server)
        _ = await server.reply(to: Self.sent(.batchSend))
        server.written(await server.reply(to: Self.sent(.wait(timeoutSeconds: nil), by: Self.first)))

        clock.now += 119
        let still = try await presence(of: server)
        clock.now += 1
        let gone = try await state(of: server)["listener"] as? [String: Any]

        #expect(still == "working")
        #expect(gone?["presence"] as? String == "absent")
        // An absent listener isn't named.
        #expect(gone?["name"] is NSNull)
    }

    @Test func aWaitFromAnotherListenerWhileOneIsOpenIsRefused() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        let server = server(on: model)
        let waiting = Task { await server.reply(to: Self.sent(.wait(timeoutSeconds: nil), by: Self.first)) }
        try await until("listening", on: server)

        let refused = await server.reply(to: Self.sent(.wait(timeoutSeconds: nil), by: Self.second))
        let session = model.listener.session?.key
        server.stop()

        #expect(refused == .init(reply: .refused("Claude Code in /repo is already listening; one listener at a time")))
        // The refused listener didn't become the session.
        #expect(session == "L1")
        // The open wait hears that the app quits, and a later one is refused.
        #expect(await waiting.value == .init(reply: .refused("video-review is quitting")))
        #expect(await server.reply(to: Self.sent(.wait(timeoutSeconds: nil), by: Self.first)) == .init(reply: .refused("video-review is quitting")))
    }

    @Test func aNewListenerGetsTheBatchTheOneBeforeTookAndDidNotFinish() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        let server = server(on: model)
        await queueTwo(on: server)
        _ = await server.reply(to: Self.sent(.batchSend))
        let taken = await server.reply(to: Self.sent(.wait(timeoutSeconds: nil), by: Self.first))
        server.written(taken)

        // The same listener asking again gets nothing twice.
        let same = await server.reply(to: Self.sent(.wait(timeoutSeconds: 0), by: Self.first))
        // Another key is the listener restarted: the batch goes out again.
        let requeued = await server.reply(to: Self.sent(.wait(timeoutSeconds: 0), by: Self.second))
        server.written(requeued)

        #expect(same == .init(reply: .done("")))
        #expect(try Self.payload(requeued) == Self.payload(taken))
        #expect(requeued.delivery?.listener == "L2")
        #expect(model.listener.session?.key == "L2")
        #expect(try await delivery(of: server) == "taken")
        #expect(model.desk.open?.comments.map(\.state) == [.sent, .sent])
    }

    // MARK: - The socket

    @Test func overTheSocketAnOpenWaitIsKeptAliveByTheHeartbeatAndPrintsTheBatchWhenItIsSent() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        let server = server(on: model)
        try server.start()
        defer { server.stop() }
        await queueTwo(on: server)
        let socket = socket
        // A client that accepts a silence of a quarter second only: the heartbeat breaks it.
        let listener = ControlClient(socket: socket, holder: Self.first, transport: UnixSocketTransport(), idleTimeout: 0.25)
        let driver = ControlClient(socket: socket, holder: Self.operatorAgent, transport: UnixSocketTransport())

        let waiting = Task { await Self.sending { listener.send(.wait(timeoutSeconds: nil)) } }
        try await until("listening", on: server)
        try await Task.sleep(for: .milliseconds(600))
        let sent = await Self.sending { driver.send(.batchSend) }
        let answer = await waiting.value

        guard case .success(let reply) = answer else { Issue.record("no batch: \(answer)"); return }
        #expect(reply.ok)
        let payload = try JSONDecoder().decode(BatchPayload.self, from: Data(reply.output.utf8))
        #expect(payload.comments.map(\.text) == ["this box", "too fast"])
        guard case .success(let batch) = sent else { Issue.record("not sent: \(sent)"); return }
        #expect(batch.output == payload.batch.id + "\n")
        // The reply was written: the batch is taken.
        try await until("working", on: server)
        #expect(try await delivery(of: server) == "taken")
    }

    @Test func overTheSocketABatchSentBeforeTheWaitIsReturnedAndATimeoutThatRanOutAnswersWithNothing() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        let server = server(on: model)
        try server.start()
        defer { server.stop() }
        await queueTwo(on: server)
        let socket = socket
        let listener = ControlClient(socket: socket, holder: Self.first, transport: UnixSocketTransport())
        let driver = ControlClient(socket: socket, holder: Self.operatorAgent, transport: UnixSocketTransport())

        let nothing = await Self.sending { listener.send(.wait(timeoutSeconds: 1)) }
        _ = await Self.sending { driver.send(.batchSend) }
        let answer = await Self.sending { listener.send(.wait(timeoutSeconds: 1)) }

        // What the command turns into exit 3.
        #expect(nothing == .success(.done("")))
        guard case .success(let reply) = answer else { Issue.record("no batch: \(answer)"); return }
        #expect(try JSONDecoder().decode(BatchPayload.self, from: Data(reply.output.utf8)).comments.count == 2)
    }

    @Test func overTheSocketAWaitWhoseClientHasGoneIsFoundOutByTheHeartbeatAndTakesNoBatch() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        let server = server(on: model)
        try server.start()
        defer { server.stop() }
        await queueTwo(on: server)
        let socket = socket

        // A listener that waits, then goes (killed, or its shell closed).
        let gone = UnixSocket.make()
        try #require(UnixSocket.connectSocket(gone, to: try #require(UnixSocket.address(socket.path))) == 0)
        _ = UnixSocket.writeAll(gone, Self.sent(.wait(timeoutSeconds: nil), by: Self.first))
        UnixSocket.finishWriting(gone)
        try await until("listening", on: server)
        close(gone)
        // The next heartbeat can't be written: the wait is over.
        try await until("absent", on: server)
        _ = await server.reply(to: Self.sent(.batchSend))
        let standing = try await delivery(of: server)
        let next = await Self.sending {
            ControlClient(socket: socket, holder: Self.first, transport: UnixSocketTransport()).send(.wait(timeoutSeconds: 0))
        }

        #expect(standing == "pending")
        guard case .success(let reply) = next else { Issue.record("no batch: \(next)"); return }
        #expect(try JSONDecoder().decode(BatchPayload.self, from: Data(reply.output.utf8)).comments.count == 2)
    }

    @Test func overTheSocketABatchHandedToAWaitWhoseClientHasJustGoneStaysPending() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        // A heartbeat too slow to find the client gone before the batch is sent.
        let server = server(on: model, heartbeat: .seconds(60))
        try server.start()
        defer { server.stop() }
        await queueTwo(on: server)
        let socket = socket

        let gone = UnixSocket.make()
        try #require(UnixSocket.connectSocket(gone, to: try #require(UnixSocket.address(socket.path))) == 0)
        _ = UnixSocket.writeAll(gone, Self.sent(.wait(timeoutSeconds: nil), by: Self.first))
        UnixSocket.finishWriting(gone)
        try await until("listening", on: server)
        close(gone)
        // The batch is handed to the dead wait: its reply can't be written.
        _ = await server.reply(to: Self.sent(.batchSend))
        try await until("absent", on: server)
        let next = await Self.sending {
            ControlClient(socket: socket, holder: Self.first, transport: UnixSocketTransport()).send(.wait(timeoutSeconds: 1))
        }

        guard case .success(let reply) = next else { Issue.record("no batch: \(next)"); return }
        #expect(try JSONDecoder().decode(BatchPayload.self, from: Data(reply.output.utf8)).comments.count == 2)
        try await until("working", on: server)
        #expect(try await delivery(of: server) == "taken")
    }
}
