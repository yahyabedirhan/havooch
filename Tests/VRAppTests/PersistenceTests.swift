import Foundation
import Testing
@testable import VRApp
import VRLease
import VRReview
import VRStore
import VRWire

private let listener = Holder(key: "listener-1", name: "Claude Code", place: "/Users/me/shop")

/// A support folder that outlives the rigs on it: each `launch()` is the app
/// started again on what the last one kept, the video that was open
/// included. Nothing is done at a quit, so every restart here is also a
/// crash.
@MainActor
private final class Support {
    let library = scratchLibrary()

    deinit {
        try? FileManager.default.removeItem(at: library.root)
    }

    func launch(frames: any FrameGrabbing = FakeFrames()) -> BatchRig {
        BatchRig(frames: frames, library: library)
    }

    /// A copy of the fixture video under another name, in a folder of its
    /// own with no sidecar beside it.
    func renamedCopy() throws -> URL {
        let folder = library.root.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent("renamed take 2.mp4")
        try FileManager.default.copyItem(at: fixtureVideo, to: copy)
        return copy
    }

    /// Has `rig` open another video, so that the fixture isn't the one a
    /// restart opens again.
    func leaveAnotherVideoOpen(in rig: BatchRig) async throws {
        let reply = await rig.send(.playerOpen(path: try otherVideo(in: library.root).path))
        #expect(reply.ok, "\(reply.error)")
    }
}

extension BatchRig {
    /// A listener's request: sent with no lease.
    fileprivate func answer(_ request: ControlRequest) async -> ControlReply {
        await send(request, by: listener)
    }

    /// An `ask` answered as the socket would: the reply counts as written.
    fileprivate func asked(_ id: String, _ question: String, wait seconds: Int? = nil) async -> ControlReply {
        let request = ControlRequest.ask(commentID: id, question: question, waitSeconds: seconds)
        let answer = await server.reply(to: ControlMessage(request, holder: listener).encoded())
        server.written(answer, delivered: true)
        return answer.reply
    }

    /// What `state --json` says of the review: everything but the run's own
    /// (the lease, the listener, the player, the notices).
    fileprivate func history() async throws -> [String: String] {
        let state = try await state()
        var history: [String: String] = [:]
        for key in ["video", "context", "queue", "comments", "batches"] {
            let value = try #require(state[key])
            history[key] = String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self)
        }
        return history
    }

    /// The fixture open with a full history: `b1` (`c2` at 4.5 s on a
    /// region, `c1` at 10 s) acknowledged with a message, `c1` asked about,
    /// answered and replied on and done, `c2` failed; `c3` queued; a note.
    fileprivate func reviewed() async -> BatchRig {
        _ = await opened()
        await queueTwo()
        _ = await send(.batchSend)
        _ = await wait(by: listener)
        _ = await answer(.ack(batchID: "b1", text: "on it"))
        _ = await asked("c1", "which part?", wait: 0)
        _ = await send(.threadAnswer(commentID: "c1", text: "the intro"))
        _ = await asked("c1", "which part?", wait: 0)
        _ = await answer(.reply(id: "c1", text: "slowed the intro down"))
        _ = await answer(.status(commentID: "c1", state: "done"))
        _ = await answer(.status(commentID: "c2", state: "failed"))
        _ = await send(.commentAdd(text: "and this", at: 15, region: nil))
        _ = await send(.contextSet(text: "Mind the pacing."))
        return self
    }
}

private func payload(_ answer: ControlServer.Answer) throws -> BatchPayload {
    #expect(answer.reply.ok, "\(answer.reply.error)")
    return try JSONDecoder().decode(BatchPayload.self, from: Data(answer.reply.output.utf8))
}

@MainActor
@Suite struct PersistenceTests {
    @Test func theVideoOpenAtTheQuitIsOpenAgainAfterARestartPausedAtItsStart() async throws {
        let support = Support()
        let first = await support.launch().reviewed()
        _ = await first.send(.playerSeek(seconds: 12))
        _ = await first.send(.playerPlay)
        let before = try await first.history()

        // No `player open` in this run.
        let second = support.launch()

        #expect(try await second.history() == before)
        #expect(try await second.commentStates() == ["failed", "done", "queued"])
        let player = try #require(try await second.state()["player"] as? [String: Any])
        #expect(player["time"] as? Double == 0)
        #expect(player["playing"] as? Bool == false)
        #expect(second.player.loaded == fixtureVideo)
        #expect(second.model.video?.info.path == fixtureVideo.path)
        #expect(second.model.openFailure == nil)
    }

    @Test func aLastVideoThatIsGoneOrChangedStartsWithNoVideoAndNoError() async throws {
        let support = Support()
        let copy = try support.renamedCopy()
        let first = support.launch()
        #expect(await first.send(.playerOpen(path: copy.path)).ok)
        _ = await first.send(.commentAdd(text: "kept", at: 10, region: nil))

        // The file is gone.
        try FileManager.default.removeItem(at: copy)
        let second = support.launch()
        var state = try await second.state()
        #expect(state["video"] is NSNull)
        #expect((state["comments"] as? [[String: Any]])?.isEmpty == true)
        #expect(second.model.openFailure == nil)
        #expect(second.player.loaded == nil)

        // Another video is at its path.
        try FileManager.default.moveItem(at: try otherVideo(in: support.library.root), to: copy)
        let third = support.launch()
        state = try await third.state()
        #expect(state["video"] is NSNull)
        #expect(third.model.openFailure == nil)

        // The history is still there for the video itself.
        _ = await third.opened()
        #expect(try await third.commentStates() == ["queued"])
    }

    @Test func theVideoOpenedLastIsTheOneARestartOpens() async throws {
        let support = Support()
        let first = await support.launch().opened()
        try await support.leaveAnotherVideoOpen(in: first)

        let second = support.launch()

        let video = try #require(try await second.state()["video"] as? [String: Any])
        #expect(video["title"] as? String == "other")
    }

    @Test func aVideoOpenedAfterARestartHasItsCommentsThreadsStatusesBatchesAndNote() async throws {
        let support = Support()
        let first = await support.launch().reviewed()
        let before = try await first.history()
        #expect(try await first.commentStates() == ["failed", "done", "queued"])

        let second = await support.launch().opened()

        #expect(try await second.history() == before)
        // The images of the last run are found again.
        let comments = try #require(try await second.state()["comments"] as? [[String: Any]])
        #expect(comments.map { $0["keyframePath"] is String } == [true, true, true])
        #expect(comments.map { $0["cropPath"] is String } == [true, false, false])
        #expect(second.model.note == "Mind the pacing.")
        #expect(second.model.outbox.parcels.isEmpty)
    }

    @Test func aRenamedCopyOfTheVideoShowsTheSameHistory() async throws {
        let support = Support()
        let before = try await support.launch().reviewed().history()
        let copy = try support.renamedCopy()

        let second = support.launch()
        #expect(await second.send(.playerOpen(path: copy.path)).ok)

        var history = try await second.history()
        // The review now names the copy, which has no sidecar beside it.
        #expect(history["video"]?.contains("renamed take 2") == true)
        #expect(history["context"]?.contains("Mind the pacing.") == true)
        history["video"] = before["video"]
        history["context"] = before["context"]
        #expect(history == before)
        // The review keeps the last path seen, across the next restart too.
        #expect(try support.library.session(for: try #require(second.model.video).info.contentHash)?.video.path == copy.path)
    }

    @Test func aChangeIsOnDiskBeforeItsCommandAnswers() async throws {
        let support = Support()
        let rig = await support.launch().opened()
        let hash = try #require(rig.model.video).info.contentHash

        _ = await rig.send(.commentAdd(text: "too fast", at: 10, region: nil))
        #expect(try support.library.session(for: hash)?.comments.map(\.state) == [.queued])
        _ = await rig.send(.commentEdit(id: "c1", text: "much too fast"))
        #expect(try support.library.session(for: hash)?.comments.map(\.text) == ["much too fast"])
        _ = await rig.send(.batchSend)
        #expect(try support.library.session(for: hash)?.comments.map(\.state) == [.sent])
        #expect(try support.library.outbox().parcels.map(\.delivery) == [.pending])
        _ = await rig.wait(by: listener)
        #expect(try support.library.outbox().parcels.map(\.delivery) == [.taken(by: "listener-1", at: rig.clock.now)])
        _ = await rig.answer(.status(commentID: "c1", state: "done"))
        #expect(try support.library.session(for: hash)?.comments.map(\.state) == [.done])
        #expect(try support.library.outbox().parcels.isEmpty)
    }

    @Test func aDraftIsNotKeptAndItsFrameGoesWhenTheVideoOpensAgain() async throws {
        let support = Support()
        let first = await support.launch().opened()
        _ = await first.send(.commentAdd(text: "kept", at: 10, region: nil))
        // The app quits with the comment box open.
        first.model.compose(region: try Region(x: 0.1, y: 0.2, w: 0.3, h: 0.25))
        let draft = try #require(first.model.composing)
        await settle { first.model.cropURL(for: draft) != nil }
        let hash = try #require(first.model.video).info.contentHash
        let left = [support.library.keyframeURL(hash, comment: draft), support.library.cropURL(hash, comment: draft)]
        #expect(left.map { FileManager.default.fileExists(atPath: $0.path) } == [true, true])

        let second = await support.launch().opened()

        #expect(try await second.commentStates() == ["queued"])
        #expect(left.map { FileManager.default.fileExists(atPath: $0.path) } == [false, false])
        #expect(FileManager.default.fileExists(atPath: support.library.keyframeURL(hash, comment: "c1").path))
        // The draft's id isn't given again.
        #expect(await second.send(.commentAdd(text: "next", at: 1, region: nil)).output.hasPrefix("c3 at "))
    }

    @Test func aBatchSentWithNoListenerIsStillPendingAfterARestartAndGoesToTheNextWait() async throws {
        let support = Support()
        let first = await support.launch().opened()
        await first.queueTwo()
        _ = await first.send(.batchSend)
        try await support.leaveAnotherVideoOpen(in: first)

        // The batch's video isn't the open one in this run.
        let second = support.launch()
        #expect(second.model.outbox.parcels.map(\.delivery) == [.pending])

        let batch = try payload(await second.wait(by: listener))
        #expect(batch.batch.id == "b1")
        #expect(batch.comments.map(\.id) == ["c2", "c1"])
        // With its images, the transcript around each comment and the context.
        #expect(batch.comments.map { $0.keyframePath != nil } == [true, true])
        #expect(batch.comments.map { $0.cropPath != nil } == [true, false])
        #expect(batch.comments.allSatisfy { !$0.transcript.isEmpty })
        #expect(batch.context?.hasPrefix("# Context: sample\n") == true)
    }

    @Test func aBatchTakenAndNotFinishedGoesToTheNextWaitAfterARestart() async throws {
        let support = Support()
        let first = await support.launch().opened()
        await first.queueTwo()
        _ = await first.send(.batchSend)
        #expect(try payload(await first.wait(by: listener)).context != nil)
        _ = await first.answer(.ack(batchID: "b1", text: nil))
        _ = await first.answer(.status(commentID: "c1", state: "done"))
        _ = await first.answer(.status(commentID: "c2", state: "working"))
        try await support.leaveAnotherVideoOpen(in: first)

        let second = support.launch()

        // Back in the queue: pending, its unfinished comment back to sent.
        #expect(second.model.outbox.parcels.map(\.delivery) == [.pending])
        #expect(try support.library.outbox().parcels.map(\.delivery) == [.pending])
        #expect(try await second.presence() == "absent")
        // The same listener session runs `wait` again and gets what is left
        // of the batch, with the context once more.
        let again = try payload(await second.wait(by: listener))
        #expect(again.batch.id == "b1")
        #expect(again.comments.map(\.id) == ["c2"])
        #expect(again.context != nil)
        _ = await second.opened()
        #expect(try await second.commentStates() == ["sent", "done"])
        #expect(try await second.presence() == "working")
    }

    @Test func aListenerAnswersOnAVideoNotOpenedSinceTheRestart() async throws {
        let support = Support()
        let first = await support.launch().opened()
        await first.queueTwo()
        _ = await first.send(.batchSend)
        _ = await first.wait(by: listener)
        try await support.leaveAnotherVideoOpen(in: first)

        let second = support.launch()
        _ = await second.wait(by: listener)

        #expect(await second.answer(.ack(batchID: "b1", text: "on it")) == .done("acknowledged b1\n"))
        #expect(await second.answer(.reply(id: "c1", text: "fixed")) == .done("replied on c1\n"))
        #expect(await second.answer(.status(commentID: "c1", state: "done")) == .done("c1 is done\n"))
        #expect(await second.answer(.status(commentID: "c2", state: "failed")) == .done("c2 is failed\n"))
        #expect(await second.answer(.status(commentID: "c9", state: "done")) == .refused("there's no comment c9"))
        #expect(await second.answer(.ack(batchID: "b9", text: nil)) == .refused("there's no batch b9"))
        // The batch is finished: it left the outbox, on disk too.
        #expect(try support.library.outbox().parcels.isEmpty)

        let third = await support.launch().opened()
        #expect(try await third.commentStates() == ["failed", "done"])
        #expect(third.model.comments.map { $0.thread.map(\.text) } == [[], ["fixed"]])
        #expect(third.model.session?.batches.first?.thread.map(\.text) == ["on it"])
    }

    @Test func anAnswerNoAskHeardIsStillOwedToTheNextAskAfterARestart() async throws {
        let support = Support()
        let first = await support.launch().opened()
        await first.queueTwo()
        _ = await first.send(.batchSend)
        _ = await first.wait(by: listener)
        _ = await first.asked("c1", "which part?", wait: 0)
        #expect(await first.send(.threadAnswer(commentID: "c1", text: "the intro")).ok)

        let second = support.launch()

        #expect(await second.asked("c1", "which part?", wait: 0) == .done("the intro\n"))
        // Given once, across the next restart too.
        let third = support.launch()
        #expect(await third.asked("c1", "and then?", wait: 0) == .done("", note: "no answer came within 0 seconds\n"))
    }

    @Test func aQuestionLeftOpenStaysOpenWithItsAnswerBoxAfterARestart() async throws {
        let support = Support()
        let first = await support.launch().opened()
        await first.queueTwo()
        _ = await first.send(.batchSend)
        _ = await first.wait(by: listener)
        _ = await first.asked("c1", "which part?", wait: 0)

        let second = await support.launch().opened()

        #expect(second.model.comments.map { $0.openQuestion?.text } == [nil, "which part?"])
        // The answer box's call still answers it.
        #expect(second.model.answerByPerson("c1", text: "the intro"))
        #expect(await second.asked("c1", "which part?", wait: 0) == .done("the intro\n"))
    }

    @Test func aParcelACrashLeftOfAFinishedOrMissingBatchIsDroppedAtLaunch() async throws {
        let support = Support()
        let first = await support.launch().opened()
        await first.queueTwo()
        _ = await first.send(.batchSend)
        _ = await first.wait(by: listener)
        let taken = try support.library.outbox()
        _ = await first.answer(.status(commentID: "c1", state: "done"))
        _ = await first.answer(.status(commentID: "c2", state: "done"))
        // The review said the batch was finished, and the app died before
        // the outbox was written; and a parcel was kept for a batch the
        // review never got.
        var crashed = taken
        crashed.post(batchID: "b7", videoHash: taken.parcels[0].videoHash)
        try support.library.save(crashed)

        let second = support.launch()

        #expect(second.model.outbox.parcels.isEmpty)
        #expect(try support.library.outbox().parcels.isEmpty)
        #expect(await second.wait(by: listener, timeout: 0).reply.output.isEmpty)
    }

    @Test func aReviewThatCannotBeReadRefusesTheOpenAndIsLeftAsItIs() async throws {
        let support = Support()
        let first = await support.launch().opened()
        let hash = try #require(first.model.video).info.contentHash
        let file = support.library.root.appendingPathComponent("videos/\(hash)/review.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a review".utf8).write(to: file)

        let second = support.launch()
        let reply = await second.send(.playerOpen(path: fixtureVideo.path))

        #expect(!reply.ok)
        #expect(reply.error.hasPrefix("couldn't read the review kept for \(fixtureVideo.path): "))
        #expect(second.model.video == nil)
        #expect(try String(contentsOf: file, encoding: .utf8) == "not a review")
    }
}
