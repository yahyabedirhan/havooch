import Foundation
import Testing
import VRReview
import VRStore

@Suite struct LibraryTests {
    private func scratchFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vr-library-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func commentIdsCountUpAndGoOnAfterARelaunch() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        // The folder isn't there yet: the first id makes it.
        #expect(try Library(root: root).nextCommentID() == "c1")
        #expect(try Library(root: root).nextCommentID() == "c2")
        // Another value on the same folder, as after a relaunch.
        #expect(try Library(root: root).nextCommentID() == "c3")
    }

    @Test func batchIdsCountUpBesideTheCommentIds() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try Library(root: root).nextCommentID() == "c1")
        #expect(try Library(root: root).nextBatchID() == "b1")
        #expect(try Library(root: root).nextBatchID() == "b2")
        #expect(try Library(root: root).nextCommentID() == "c2")
    }

    @Test func anIndexWrittenBeforeBatchesWereNumberedStillReads() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"nextComment":7}"#.utf8).write(to: root.appendingPathComponent("index.json"))

        #expect(try Library(root: root).nextBatchID() == "b1")
        #expect(try Library(root: root).nextCommentID() == "c7")
    }

    @Test func aKeyframeIsNamedByItsVideoAndItsComment() {
        let library = Library(root: URL(fileURLWithPath: "/Users/me/support", isDirectory: true))

        #expect(library.keyframeURL("abc", comment: "c1").path == "/Users/me/support/videos/abc/frames/c1.png")
    }

    /// A review of the video `hash`: `c1` sent in `b1` with a thread and an
    /// answer no `ask` heard, `c2` queued on a region, and a note.
    private func review(of hash: String = "abc") throws -> ReviewSession {
        let at = Date(timeIntervalSince1970: 1_759_579_200)
        var review = ReviewSession(video: VideoInfo(path: "/Users/me/sample.mp4", contentHash: hash, duration: 21.233, title: "sample"))
        review.draft(id: "c1", time: 10)
        try review.commit("c1", text: "too fast")
        _ = try review.send(batchID: "b1", at: at)
        try review.acknowledge("b1", text: "on it", at: at)
        try review.ask("c1", question: "which part?", at: at)
        try review.answer("c1", text: "the intro", at: at)
        try review.setStatus("c1", to: .working)
        review.draft(id: "c2", time: 4.5, region: try Region(x: 0.5, y: 0, w: 0.5, h: 0.5))
        try review.commit("c2", text: "this button")
        review.setNote("Mind the pacing.")
        return review
    }

    @Test func aReviewComesBackAsItWasKept() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let review = try review()

        #expect(try Library(root: root).session(for: "abc") == nil)
        try Library(root: root).save(review)

        // Another value on the same folder, as after a relaunch.
        let kept = try #require(try Library(root: root).session(for: "abc"))
        #expect(kept == review)
        #expect(kept.unheardAnswer(on: "c1")?.answer.text == "the intro")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("videos/abc/review.json").path))
        // Another video has none.
        #expect(try Library(root: root).session(for: "def") == nil)
    }

    @Test func aDraftIsNotKept() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        var review = try review()
        review.draft(id: "c3", time: 1)

        try Library(root: root).save(review)

        #expect(try Library(root: root).session(for: "abc")?.comments.map(\.id) == ["c2", "c1"])
        #expect(Library(root: root).videoHash(forComment: "c3") == nil)
    }

    @Test func theIndexSaysWhichVideoACommentAndABatchBelongTo() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(root: root)
        #expect(library.videoHash(forComment: "c1") == nil)
        var first = try review(of: "abc")
        try library.save(first)
        var second = ReviewSession(video: VideoInfo(path: "/Users/me/other.mp4", contentHash: "def", duration: 5, title: "other"))
        second.draft(id: "c7", time: 1)
        try second.commit("c7", text: "here")
        try library.save(second)

        #expect(Library(root: root).videoHash(forComment: "c1") == "abc")
        #expect(Library(root: root).videoHash(forComment: "c7") == "def")
        #expect(Library(root: root).videoHash(forBatch: "b1") == "abc")
        #expect(Library(root: root).videoHash(forBatch: "b9") == nil)

        // A deleted comment leaves the index; the numbers go on.
        _ = try library.nextCommentID()
        try first.delete("c2")
        try library.save(first)
        #expect(library.videoHash(forComment: "c2") == nil)
        #expect(library.videoHash(forComment: "c1") == "abc")
        #expect(library.videoHash(forComment: "c7") == "def")
        #expect(try library.nextCommentID() == "c2")
    }

    @Test func theOutboxsParcelsComeBackAndItsListenerDoesNot() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let at = Date(timeIntervalSince1970: 1_759_579_200)
        #expect(try Library(root: root).outbox() == Outbox())
        var outbox = Outbox()
        outbox.post(batchID: "b1", videoHash: "abc")
        outbox.post(batchID: "b2", videoHash: "def")
        outbox.arrive(key: "one", name: "Claude Code", at: at)
        _ = outbox.take(at: at)

        try Library(root: root).save(outbox)

        let kept = try Library(root: root).outbox()
        #expect(kept.parcels == [
            Outbox.Parcel(batchID: "b1", videoHash: "abc", delivery: .taken(by: "one", at: at)),
            Outbox.Parcel(batchID: "b2", videoHash: "def", delivery: .pending),
        ])
        #expect(kept.listener == nil)
        #expect(kept.presence(at: at) == .absent)
    }

    @Test func imagesOfNoCommentAreRemovedAndTheOthersStay() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = Library(root: root)
        let files = [
            library.keyframeURL("abc", comment: "c1"), library.cropURL("abc", comment: "c1"),
            library.keyframeURL("abc", comment: "c2"), library.cropURL("abc", comment: "c2"),
            library.keyframeURL("def", comment: "c2"),
        ]
        for file in files {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("png".utf8).write(to: file)
        }

        library.removeImages(of: "abc", keeping: ["c1"])
        // A video with no folder yet has nothing to remove.
        library.removeImages(of: "none", keeping: [])

        #expect(files.map { FileManager.default.fileExists(atPath: $0.path) } == [true, true, false, false, true])
    }

    @Test func theLastOpenVideoComesBackAndTheLatestOneWins() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(Library(root: root).lastVideo() == nil)

        try Library(root: root).keep(lastVideo: .init(path: "/Users/me/sample.mp4", contentHash: "abc"))
        try Library(root: root).keep(lastVideo: .init(path: "/Users/me/other.mp4", contentHash: "def"))

        // Another value on the same folder, as after a relaunch.
        #expect(Library(root: root).lastVideo() == Library.LastVideo(path: "/Users/me/other.mp4", contentHash: "def"))
    }

    @Test func aLastOpenVideoThatCannotBeReadIsNone() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: root.appendingPathComponent("last-video.json"))

        #expect(Library(root: root).lastVideo() == nil)
    }

    @Test func twoLibrariesShareNothing() throws {
        let real = scratchFolder()
        // A demo run's folder is inside the normal one.
        let demo = real.appendingPathComponent("d-1a2b3c4d", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: real) }

        try Library(root: demo).save(try review())
        _ = try Library(root: demo).nextCommentID()
        try Library(root: demo).keep(lastVideo: .init(path: "/demo/sample.mp4", contentHash: "abc"))

        #expect(Library(root: real).lastVideo() == nil)
        #expect(try Library(root: real).session(for: "abc") == nil)
        #expect(Library(root: real).videoHash(forComment: "c1") == nil)
        #expect(try Library(root: real).nextCommentID() == "c1")
        #expect(try Library(root: demo).nextCommentID() == "c2")
    }
}
