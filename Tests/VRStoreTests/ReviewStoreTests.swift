import Foundation
import Testing
import VRReview
import VRStore

/// The reviews, the ledger and the app's own state as files under a
/// support folder: what a run leaves for the next one.
@Suite struct ReviewStoreTests {
    typealias Folder = ContentHashTests.Folder

    static let hash = "7f3a9c21" + String(repeating: "0", count: 56)
    let now = Date(timeIntervalSince1970: 1_791_115_200.25)

    private func store(in folder: Folder, _ name: String = "support") -> ReviewStore {
        ReviewStore(layout: SupportLayout(root: folder.url.appendingPathComponent(name, isDirectory: true)))
    }

    private func id(_ number: Int) -> CommentID {
        CommentID(contentHash: Self.hash, number: number)
    }

    /// A review with a comment in every state a stored comment can have,
    /// one on a region, a thread of every kind with a question that still
    /// waits, two batches (one with a message and transcripts), a note,
    /// and a deleted comment behind its counter.
    private func full(hash: String = hash, path: String = "/videos/sample.mp4") throws -> Review {
        var review = Review(video: VideoInfo(contentHash: hash, path: path, title: "sample", duration: 21.233))
        let region = try #require(Region(x: 0.48, y: 0.3, w: 0.28, h: 0.12))
        for (index, time) in [10.0, 4, 6, 8, 12].enumerated() {
            try review.addComment(text: "comment \(index + 1)", time: time, region: index == 1 ? region : nil, now: now)
        }
        let c1 = CommentID(contentHash: hash, number: 1), c2 = CommentID(contentHash: hash, number: 2)
        let first = try review.sendBatch(
            transcripts: [c1: [.init(start: 9.5, end: 12, text: "Each key is one action.")], c2: []], now: now
        )
        try review.acknowledge(first.id, text: "on it", now: now.addingTimeInterval(1))
        try review.setStatus(c1, to: .working)
        try review.reply(toComment: c1, text: "slowing it down", now: now.addingTimeInterval(2))
        try review.ask(c2, question: "which box?", now: now.addingTimeInterval(3))
        try review.answer(c2, text: "the left one", now: now.addingTimeInterval(4))
        try review.ask(c2, question: "the whole of it?", now: now.addingTimeInterval(5))
        try review.setStatus(CommentID(contentHash: hash, number: 3), to: .done)
        try review.setStatus(CommentID(contentHash: hash, number: 4), to: .failed)
        try review.addComment(text: "sent, not taken", time: 15, now: now)
        try review.sendBatch(now: now.addingTimeInterval(6))
        try review.addComment(text: "deleted", time: 16, now: now)
        try review.deleteComment(CommentID(contentHash: hash, number: 7))
        try review.addComment(text: "still queued", time: 17, now: now)
        review.setNote("The repo is video-review.")
        return review
    }

    // MARK: - Reviews

    @Test func aFullReviewReadsBackAsItWasKeptAndItsCountersGoOn() throws {
        let folder = try Folder()
        let review = try full()
        #expect(Set(review.comments.map(\.state)) == [.queued, .sent, .acknowledged, .working, .done, .failed])

        try store(in: folder).save(review)
        // Another store on the same folder: what a new run reads.
        var back = try #require(store(in: folder).loadReview(Self.hash))

        #expect(back == review)
        #expect(try back.comment(id(2)).region == Region(x: 0.48, y: 0.3, w: 0.28, h: 0.12))
        #expect(try back.comment(id(2)).openQuestion?.text == "the whole of it?")
        #expect(try back.comment(id(2)).thread.map(\.kind) == [.question, .answer, .question])
        #expect(try back.comment(id(2)).thread.map(\.author) == [.agent, .person, .agent])
        #expect(back.batches.first?.thread.map(\.text) == ["on it"])
        #expect(back.note == "The repo is video-review.")
        // The numbers of the deleted comment and of the sent batches aren't given again.
        #expect(try back.addComment(text: "after the restart", time: 1, now: now).id == id(9))
        #expect(try back.sendBatch(now: now).id == BatchID(contentHash: Self.hash, number: 3))
    }

    @Test func aReviewIsOneVersionedFileInItsVideosFolderWithEachTranscriptUnderItsCommentsId() throws {
        let folder = try Folder()
        let store = store(in: folder)

        try store.save(try full())

        let file = store.layout.reviewFile(Self.hash)
        #expect(file.path.hasSuffix("/support/videos/\(Self.hash)/review.json"))
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        let batches = try #require((object["review"] as? [String: Any])?["batches"] as? [[String: Any]])
        let transcripts = try #require(batches.first?["transcripts"] as? [String: [[String: Any]]])
        #expect(Set(transcripts.keys) == ["7f3a9c21-c1", "7f3a9c21-c2"])
        #expect(transcripts["7f3a9c21-c1"]?.first?["text"] as? String == "Each key is one action.")
    }

    @Test func aRenamedCopyOfTheVideoFindsTheSameReview() throws {
        let folder = try Folder()
        let video = try folder.file("talk.mp4", Data("the talk".utf8))
        let renamed = try folder.file("renamed copy.mov", Data("the talk".utf8))
        let other = try folder.file("other.mp4", Data("another video".utf8))
        let store = store(in: folder)
        let review = try full(hash: ContentHash.of(video), path: video.path)

        try store.save(review)

        #expect(store.loadReview(try ContentHash.of(renamed)) == review)
        #expect(store.loadReview(try ContentHash.of(other)) == nil)
    }

    @Test func everyReviewUnderTheFolderIsRead() throws {
        let folder = try Folder()
        let store = store(in: folder)
        let other = "b2" + String(repeating: "1", count: 62)
        #expect(store.loadReviews().isEmpty)

        try store.save(try full())
        try store.save(try full(hash: other, path: "/videos/other.mp4"))
        // A video that only has a transcript has a folder and no review.
        try FileManager.default.createDirectory(at: store.layout.folder("c3" + String(repeating: "2", count: 62)), withIntermediateDirectories: true)

        #expect(store.loadReviews().map(\.video.contentHash) == [Self.hash, other])
    }

    // MARK: - The ledger and the app's state

    @Test func theLedgerReadsBackAsItWasKept() throws {
        let folder = try Folder()
        var ledger = ListenerLedger()
        ledger.enqueue(BatchID(rawValue: "7f3a9c21-b1"), video: Self.hash, sentAt: now)
        ledger.enqueue(BatchID(rawValue: "7f3a9c21-b2"), video: Self.hash, sentAt: now.addingTimeInterval(6))
        ledger.attach((key: "L1", name: "Claude Code", place: "/repo"), now: now.addingTimeInterval(7))
        ledger.delivered(BatchID(rawValue: "7f3a9c21-b1"), to: "L1", context: "# Context", now: now.addingTimeInterval(8))
        #expect(store(in: folder).loadLedger() == ListenerLedger())

        try store(in: folder).save(ledger)
        let back = store(in: folder).loadLedger()

        #expect(back == ledger)
        #expect(back.session?.contextSent == [Self.hash: "# Context"])
        #expect(back.standing(of: BatchID(rawValue: "7f3a9c21-b1")) == .taken)
        #expect(back.standing(of: BatchID(rawValue: "7f3a9c21-b2")) == .pending)
        #expect(store(in: folder).layout.listenerFile.path.hasSuffix("/support/listener.json"))
    }

    @Test func theLastVideoReadsBackAsItWasKept() throws {
        let folder = try Folder()
        let state = AppState(lastVideo: .init(path: "/videos/sample.mp4", contentHash: Self.hash, time: 10.5))
        #expect(store(in: folder).loadAppState() == AppState())

        try store(in: folder).save(state)

        #expect(store(in: folder).loadAppState() == state)
        #expect(store(in: folder).layout.appFile.path.hasSuffix("/support/app.json"))
    }

    // MARK: - Two folders, and files that don't read

    @Test func twoSupportFoldersNeverSeeEachOthersData() throws {
        let folder = try Folder()
        let real = store(in: folder, "real"), demo = store(in: folder, "demo")
        var ledger = ListenerLedger()
        ledger.enqueue(BatchID(rawValue: "7f3a9c21-b1"), video: Self.hash, sentAt: now)

        try demo.save(try full())
        try demo.save(ledger)
        try demo.save(AppState(lastVideo: .init(path: "/videos/sample.mp4", contentHash: Self.hash, time: 3)))

        #expect(real.loadReview(Self.hash) == nil)
        #expect(real.loadReviews().isEmpty)
        #expect(real.loadLedger() == ListenerLedger())
        #expect(real.loadAppState() == AppState())
        // Reading made nothing in the other folder.
        #expect(!FileManager.default.fileExists(atPath: real.layout.root.path))
        #expect(demo.loadReviews().count == 1)
    }

    @Test func aReviewANewerBuildWroteIsMovedAsideNotReadAndNotWrittenOver() throws {
        let folder = try Folder()
        let store = store(in: folder)
        try store.save(try full())
        let file = store.layout.reviewFile(Self.hash)
        let newer = String(decoding: try Data(contentsOf: file), as: UTF8.self).replacingOccurrences(of: #""version":1}"#, with: #""version":2}"#)
        try Data(newer.utf8).write(to: file)

        #expect(newer.hasSuffix(#""version":2}"#))
        #expect(store.loadReview(Self.hash) == nil)
        let aside = store.layout.folder(Self.hash).appendingPathComponent("review.unreadable.json")
        #expect(String(decoding: try Data(contentsOf: aside), as: UTF8.self) == newer)
    }

    @Test(arguments: ["not json", #"{"lastVideo":[],"ledger":[],"review":[],"version":1}"#, #"{"version":2}"#])
    func aFileThatDoesNotReadOrIsFromANewerBuildIsMovedAsideAndCountsAsNone(kept: String) throws {
        let folder = try Folder()
        let store = store(in: folder)
        try FileManager.default.createDirectory(at: store.layout.folder(Self.hash), withIntermediateDirectories: true)
        let files = [store.layout.reviewFile(Self.hash), store.layout.listenerFile, store.layout.appFile]
        for file in files { try Data(kept.utf8).write(to: file) }

        #expect(store.loadReview(Self.hash) == nil)
        #expect(store.loadReviews().isEmpty)
        #expect(store.loadLedger() == ListenerLedger())
        #expect(store.loadAppState() == AppState())

        for file in files {
            let aside = file.deletingPathExtension().appendingPathExtension("unreadable.json")
            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(String(decoding: try Data(contentsOf: aside), as: UTF8.self) == kept)
        }
        // The next save writes a new file, and leaves the one moved aside.
        try store.save(try full())
        #expect(store.loadReview(Self.hash) == (try full()))
        let aside = store.layout.folder(Self.hash).appendingPathComponent("review.unreadable.json")
        #expect(String(decoding: try Data(contentsOf: aside), as: UTF8.self) == kept)
    }

    @Test func aReviewKeptInAnotherVideosFolderDoesNotRead() throws {
        let folder = try Folder()
        let store = store(in: folder)
        let other = "b2" + String(repeating: "1", count: 62)
        try store.save(try full())
        try FileManager.default.createDirectory(at: store.layout.folder(other), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: store.layout.reviewFile(Self.hash), to: store.layout.reviewFile(other))

        #expect(store.loadReview(other) == nil)
        #expect(store.loadReviews().map(\.video.contentHash) == [Self.hash])
    }

    @Test func aSaveReplacesTheFileWholeAndOneThatFailsLeavesItAsItWas() throws {
        let folder = try Folder()
        let store = store(in: folder)
        var review = try full()
        try store.save(review)
        let file = store.layout.reviewFile(Self.hash)
        let first = try Data(contentsOf: file)

        review.setNote("Another note.")
        try store.save(review)

        // One file, with nothing left beside it by the write.
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.layout.folder(Self.hash).path) == ["review.json"])
        #expect(store.loadReview(Self.hash)?.note == "Another note.")

        // The folder can't be written in: the save throws, and the file is the one before.
        let second = try Data(contentsOf: file)
        #expect(second != first)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: store.layout.folder(Self.hash).path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: store.layout.folder(Self.hash).path) }
        review.setNote("A note that can't be kept.")
        #expect(throws: (any Error).self) { try store.save(review) }
        #expect(try Data(contentsOf: file) == second)
    }
}
