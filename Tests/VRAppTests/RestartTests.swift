import Foundation
import Testing
@testable import VRApp
import VRLease
import VRReview
import VRStore
import VRWire

/// What one run of the app leaves for the next: a model on a temporary
/// support folder is changed and let go, and another is made on the same
/// folder, as a quit and a launch do. Requests are answered in memory, on
/// the fixture video. No window is opened and no sound is made.
@Suite(.serialized) @MainActor struct RestartTests {
    typealias Wait = ListenerWaitTests

    let clock = Wait.Clock()
    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
    var support: URL { folder.appendingPathComponent("support", isDirectory: true) }

    /// One run of the app.
    struct Run {
        var model: AppModel
        var server: ControlServer
    }

    /// A new run on `support`, as a launch makes it: nothing is opened yet.
    func launch(on support: URL? = nil) -> Run {
        let model = AppModel(environment: [SupportFolder.overrideVariable: (support ?? self.support).path], now: { [clock] in clock.now })
        model.player.player.isMuted = true
        let server = ControlServer(
            socket: folder.appendingPathComponent("control.sock"), model: model, screenshotter: Screenshotter(model: model),
            lease: ControlLease(), indicator: LeaseIndicator(), now: { [clock] in clock.now },
            timeZone: TimeZone(identifier: "UTC") ?? .gmt, heartbeat: .milliseconds(40), quit: {}
        )
        return Run(model: model, server: server)
    }

    /// A launch that finds the last run's video, as the app's does.
    func relaunch() async -> Run {
        let run = launch()
        await run.model.reopenLastVideo()
        return run
    }

    @discardableResult
    func ask(_ request: ControlRequest, of run: Run, by holder: Holder = Wait.operatorAgent) async -> ControlServer.Answer {
        await run.server.reply(to: Wait.sent(request, by: holder))
    }

    /// What `state` says, without the parts a restart rightly ends: the
    /// lease and the notice.
    func state(of run: Run) async throws -> NSDictionary {
        let reply = await ask(.state, of: run)
        var state = try #require(JSONSerialization.jsonObject(with: Data(reply.reply.output.utf8)) as? [String: Any])
        state["lease"] = nil
        state["notice"] = nil
        return state as NSDictionary
    }

    func comments(of run: Run) async throws -> [String: String] {
        let comments = try #require(try await state(of: run)["comments"] as? [[String: Any]])
        return Dictionary(uniqueKeysWithValues: comments.compactMap { comment in
            (comment["id"] as? String).flatMap { id in (comment["state"] as? String).map { (id, $0) } }
        })
    }

    func deliveries(of run: Run) async throws -> [String] {
        let batches = try #require(try await state(of: run)["batches"] as? [[String: Any]])
        return batches.compactMap { $0["delivery"] as? String }
    }

    /// A `wait` by `holder` whose reply reached it.
    func take(by holder: Holder, of run: Run) async throws -> BatchPayload {
        let answer = await ask(.wait(timeoutSeconds: 0), of: run, by: holder)
        run.server.written(answer)
        return try Wait.payload(answer)
    }

    /// A reviewed fixture: its ids, by the eight digits of its hash, and
    /// what `state` said right before the quit.
    struct Reviewed {
        var prefix: String
        var state: NSDictionary = [:]
        func c(_ number: Int) -> String { "\(prefix)-c\(number)" }
        func b(_ number: Int) -> String { "\(prefix)-b\(number)" }
    }

    /// A run that reviewed the fixture and quit: a note; `c1` at 10 s and
    /// `c2` (on a region) at 4 s sent as `b1`, taken and acknowledged by
    /// the listener `L1`; on `c2` a question the person answered, then
    /// `done`; on `c1` a message, `working`, and a question that still
    /// waits; `c3` sent as `b2`, which no listener took; `c4` queued; the
    /// playhead at 6 s.
    func reviewed() async throws -> Reviewed {
        let run = launch()
        try await run.model.open(RegionCommentTests.fixture)
        var names = Reviewed(prefix: String(try #require(run.model.desk.open).video.contentHash.prefix(8)))
        await ask(.contextSet(text: "The repo is video-review."), of: run)
        await ask(.commentAdd(text: "too fast", at: 10, region: nil), of: run)
        await ask(.commentAdd(text: "this box", at: 4, region: WireRegion(x: 0.1, y: 0.2, w: 0.3, h: 0.2)), of: run)
        await ask(.batchSend, of: run)
        #expect(try await take(by: Wait.first, of: run).context != nil)
        clock.now += 1
        await ask(.ack(id: names.b(1), text: "got it"), of: run, by: Wait.first)
        let second = names.c(2)
        let asking = Task { await ask(.ask(id: second, text: "Which box?", waitSeconds: 60), of: run, by: Wait.first) }
        for _ in 0..<500 where (try? run.model.desk.open?.comment(CommentID(rawValue: second)))?.openQuestion == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        clock.now += 1
        await ask(.threadAnswer(id: names.c(2), text: "The left one"), of: run)
        #expect(await asking.value.reply.output == "The left one\n")
        await ask(.status(id: names.c(2), state: "done"), of: run, by: Wait.first)
        await ask(.status(id: names.c(1), state: "working"), of: run, by: Wait.first)
        await ask(.reply(id: names.c(1), text: "slowing it down"), of: run, by: Wait.first)
        await ask(.ask(id: names.c(1), text: "Slower by how much?", waitSeconds: 0), of: run, by: Wait.first)
        clock.now += 1
        await ask(.commentAdd(text: "sent, not taken", at: 15, region: nil), of: run)
        await ask(.batchSend, of: run)
        await ask(.commentAdd(text: "still queued", at: 17, region: nil), of: run)
        await ask(.playerSeek(seconds: 6), of: run)
        names.state = try await state(of: run)
        // The quit.
        run.server.stop()
        run.model.leaving()
        return names
    }

    // MARK: - The same state

    @Test func aNewRunOnTheSameFolderShowsTheStateOfTheRunThatQuit() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let names = try await reviewed()

        let run = await relaunch()
        let after = try await state(of: run)

        #expect(after == names.state)
        #expect(try await comments(of: run) == [names.c(1): "working", names.c(2): "done", names.c(3): "sent", names.c(4): "queued"])
        #expect(try await deliveries(of: run) == ["taken", "pending"])
        #expect(after["queue"] as? [String] == [names.c(4)])
        #expect((after["context"] as? [String: Any])?["note"] as? String == "The repo is video-review.")
        #expect((after["player"] as? [String: Any])?["time"] as? Double == 6)
        let listed = try #require(after["comments"] as? [[String: Any]])
        let boxed = try #require(listed.first { $0["id"] as? String == names.c(2) })
        #expect(boxed["region"] as? [String: Double] == ["x": 0.1, "y": 0.2, "w": 0.3, "h": 0.2])
        #expect((boxed["thread"] as? [[String: String]])?.map { [$0["author"], $0["kind"], $0["text"]] } == [
            ["agent", "question", "Which box?"], ["person", "answer", "The left one"],
        ])
        let slow = try #require(listed.first { $0["id"] as? String == names.c(1) })
        #expect((slow["thread"] as? [[String: String]])?.map { [$0["author"], $0["kind"], $0["text"]] } == [
            ["agent", "message", "slowing it down"], ["agent", "question", "Slower by how much?"],
        ])
        // The keyframes and the crop the paths name are the files of the run before.
        for comment in listed {
            #expect(FileManager.default.fileExists(atPath: try #require(comment["keyframePath"] as? String)))
        }
        #expect(FileManager.default.fileExists(atPath: try #require(boxed["cropPath"] as? String)))
        // The question that waited still does, and takes its answer.
        #expect(await ask(.threadAnswer(id: names.c(1), text: "Half a second"), of: run).reply.ok)
        let again = await ask(.ask(id: names.c(1), text: "Slower by how much?", waitSeconds: 0), of: run, by: Wait.first)
        #expect(again.reply.output == "Half a second\n")
    }

    // MARK: - The listener

    @Test func aNewListenerGetsTheUnfinishedBatchAgainAndThenThePendingOne() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let names = try await reviewed()
        let run = await relaunch()

        let first = try await take(by: Wait.second, of: run)
        let second = try await take(by: Wait.second, of: run)

        #expect(first.batch.id == names.b(1))
        // Only what isn't finished, with the context a new session gets.
        #expect(first.comments.map(\.id) == [names.c(1)])
        #expect(first.context?.contains("The repo is video-review.") == true)
        #expect(second.batch.id == names.b(2))
        #expect(second.comments.map(\.id) == [names.c(3)])
        #expect(second.context == nil)
        #expect(try await comments(of: run)[names.c(1)] == "sent")
        #expect(try await comments(of: run)[names.c(2)] == "done")
        #expect(try await deliveries(of: run) == ["taken", "taken"])
    }

    @Test func theListenerOfTheRunBeforeKeepsItsBatchAndGetsNoContextTwice() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let names = try await reviewed()
        let run = await relaunch()

        let next = try await take(by: Wait.first, of: run)

        #expect(next.batch.id == names.b(2))
        #expect(next.context == nil)
        #expect(try await comments(of: run)[names.c(1)] == "working")
        #expect(await ask(.status(id: names.c(1), state: "done"), of: run, by: Wait.first).reply.ok)
        #expect(try await deliveries(of: run) == ["finished", "taken"])
    }

    @Test func aBatchWhoseLedgerWasLostIsPendingAgainWithItsUnfinishedCommentsSent() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let names = try await reviewed()
        // As when the app ends between the review's write and the ledger's.
        try FileManager.default.removeItem(at: SupportLayout(root: support).listenerFile)

        let run = await relaunch()

        #expect(try await deliveries(of: run) == ["pending", "pending"])
        #expect(try await comments(of: run) == [names.c(1): "sent", names.c(2): "done", names.c(3): "sent", names.c(4): "queued"])
        #expect(try await take(by: Wait.second, of: run).batch.id == names.b(1))
    }

    // MARK: - Ids

    @Test func aCommentAndABatchAfterTheRestartGetTheNextNumbers() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let names = try await reviewed()
        let run = await relaunch()
        let kept = try Data(contentsOf: run.model.desk.keyframe(of: CommentID(rawValue: names.c(1))))

        let comment = await ask(.commentAdd(text: "after the restart", at: 2, region: nil), of: run)
        let batch = await ask(.batchSend, of: run)

        #expect(comment.reply.output == names.c(5) + "\n")
        #expect(batch.reply.output == names.b(3) + "\n")
        // No file of the run before was written over.
        #expect(try Data(contentsOf: run.model.desk.keyframe(of: CommentID(rawValue: names.c(1)))) == kept)
    }

    // MARK: - The video's file, and other folders

    @Test func aRenamedCopyInAnotherFolderShowsTheSameHistory() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let names = try await reviewed()
        let moved = folder.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: true)
        let copy = moved.appendingPathComponent("renamed copy.mp4")
        try FileManager.default.copyItem(at: RegionCommentTests.fixture, to: copy)
        // Its transcript sidecar goes with it, so no speech recognition starts.
        try FileManager.default.copyItem(
            at: RegionCommentTests.fixture.deletingLastPathComponent().appendingPathComponent("voiceover.json"),
            to: moved.appendingPathComponent("voiceover.json")
        )

        let run = launch()
        #expect(await ask(.playerOpen(path: copy.path), of: run).reply.ok)
        let after = try await state(of: run)

        #expect((after["video"] as? [String: Any])?["path"] as? String == copy.path)
        #expect((after["video"] as? [String: Any])?["title"] as? String == "renamed copy")
        for part in ["comments", "queue", "batches"] {
            #expect(after[part] as? NSObject == names.state[part] as? NSObject, "\(part)")
        }
        #expect((after["context"] as? [String: Any])?["note"] as? String == "The repo is video-review.")
        #expect(try await comments(of: run).count == 4)
        // The next launch opens the copy: it is the file that was open last.
        let next = await relaunch()
        #expect(next.model.player.video?.url.path == copy.path)
        #expect(try await comments(of: next)[names.c(1)] == "working")
    }

    @Test func aVideoThatIsNoLongerWhereItWasIsNotOpenedAndKeepsItsHistory() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("talk.mp4")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: RegionCommentTests.fixture, to: copy)
        try FileManager.default.copyItem(
            at: RegionCommentTests.fixture.deletingLastPathComponent().appendingPathComponent("voiceover.json"),
            to: folder.appendingPathComponent("voiceover.json")
        )
        let first = launch()
        try await first.model.open(copy)
        await ask(.commentAdd(text: "too fast", at: 10, region: nil), of: first)
        first.model.leaving()
        let moved = folder.appendingPathComponent("moved talk.mp4")
        try FileManager.default.moveItem(at: copy, to: moved)

        let run = await relaunch()

        #expect(run.model.player.video == nil)
        #expect(try await state(of: run)["video"] is NSNull)
        #expect(await ask(.playerOpen(path: moved.path), of: run).reply.ok)
        #expect(try await comments(of: run).values.map { $0 } == ["queued"])
    }

    @Test func anotherSupportFolderShowsNoneOfIt() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try await reviewed()
        let other = folder.appendingPathComponent("other", isDirectory: true)

        let run = launch(on: other)
        await run.model.reopenLastVideo()

        #expect(run.model.player.video == nil)
        try await run.model.open(RegionCommentTests.fixture)
        let state = try await state(of: run)
        #expect((state["comments"] as? [Any])?.isEmpty == true)
        #expect((state["batches"] as? [Any])?.isEmpty == true)
        #expect((state["context"] as? [String: Any])?["note"] as? String == "")
        #expect((state["listener"] as? [String: Any])?["presence"] as? String == "absent")
        // And what this run adds stays out of the first folder.
        await ask(.commentAdd(text: "in the other folder", at: 1, region: nil), of: run)
        #expect(try await comments(of: await relaunch()).count == 4)
    }

    // MARK: - Files that don't read, and what is typed

    @Test func aReviewThatDoesNotReadIsMovedAsideAndTheVideoOpensWithNone() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try await reviewed()
        let layout = SupportLayout(root: support)
        let hash = try ContentHash.of(RegionCommentTests.fixture)
        try Data("not json".utf8).write(to: layout.reviewFile(hash))
        try Data("not json".utf8).write(to: layout.listenerFile)

        let run = await relaunch()

        #expect(run.model.player.video != nil)
        #expect(try await comments(of: run).isEmpty)
        #expect(try await deliveries(of: run).isEmpty)
        #expect(FileManager.default.fileExists(atPath: layout.folder(hash).appendingPathComponent("review.unreadable.json").path))
        #expect(FileManager.default.fileExists(atPath: support.appendingPathComponent("listener.unreadable.json").path))
    }

    @Test func aTypedNoteCountsAtOnceAndIsSavedWhenTheTypingRestsOrItsBoxCloses() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let run = launch()
        try await run.model.open(RegionCommentTests.fixture)
        let hash = try #require(run.model.desk.open).video.contentHash
        let store = ReviewStore(layout: SupportLayout(root: support))

        for typed in ["T", "Th", "The repo"] { try run.model.typeNote(typed) }

        // In the review at once, in no file yet: a key isn't a write.
        #expect(run.model.desk.open?.note == "The repo")
        #expect(store.loadReview(hash) == nil)
        run.model.endNote()
        #expect(store.loadReview(hash)?.note == "The repo")

        try run.model.typeNote("The repo is video-review.")
        #expect(store.loadReview(hash)?.note == "The repo")
        for _ in 0..<300 where store.loadReview(hash)?.note != "The repo is video-review." {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.loadReview(hash)?.note == "The repo is video-review.")

        // What is typed right before the quit is kept by the quit.
        try run.model.typeNote("Typed last.")
        run.model.leaving()
        #expect(store.loadReview(hash)?.note == "Typed last.")
    }
}
