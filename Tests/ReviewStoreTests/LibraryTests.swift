import Foundation
import ReviewCore
import ReviewStore
import Testing

/// What the library keeps on disk, in a temporary support folder.
@Suite("The library")
struct LibraryTests {
    static let hash = String(repeating: "a", count: 64)
    static let other = String(repeating: "b", count: 64)

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    private func id(_ text: String) throws -> ItemID { try #require(ItemID(text)) }

    /// A review with everything a review can hold: a queued comment, a sent
    /// batch of two comments (one on a region, with a question and its
    /// answer, done; one working), a batch message and a note.
    private func review(_ hash: String = hash, path: String = "/videos/sample.mp4", prefix: String = "0") throws -> VideoReview {
        var review = VideoReview(video: VideoInfo(contentHash: hash, title: "sample", duration: 21.233, path: path, frameRate: 30))
        let first = try id("c-\(prefix)0000001")
        let second = try id("c-\(prefix)0000002")
        let batch = try id("b-\(prefix)0000001")
        try review.addComment(id: first, time: 10, text: "Too fast here")
        try review.addComment(id: second, time: 12.5, text: "This box", region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25))
        try review.send(batchID: batch, at: at(1_800_000_000.25))
        try review.acknowledge(batch, text: "On it", messageID: try id("m-\(prefix)0000001"), at: at(1_800_000_001))
        try review.ask(second, question: "Which box?", messageID: try id("m-\(prefix)0000002"), at: at(1_800_000_002.5))
        try review.answer(second, text: "The left one", messageID: try id("m-\(prefix)0000003"), at: at(1_800_000_003))
        try review.reply(to: second, text: "Fixed in abc123", messageID: try id("m-\(prefix)0000004"), at: at(1_800_000_004))
        try review.setStatus(second, .done)
        try review.setStatus(first, .working)
        try review.addComment(id: try id("c-\(prefix)0000003"), time: 3, text: "Still queued")
        review.note = "The pricing page"
        return review
    }

    private func files(under folder: URL) -> [String] {
        ((try? FileManager.default.subpathsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    // MARK: - Reviews

    @Test("a review reads back the same in a new library: comments, the region, states, threads, batches, the note and the frame rate")
    func reviewRoundTrip() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let review = try review()
        #expect(try Library(support: scratch.folder).load(Self.hash) == nil)

        try Library(support: scratch.folder).save(review)

        let read = try #require(try Library(support: scratch.folder).load(Self.hash))
        #expect(read == review)
        #expect(read.comments.map(\.state) == [.queued, .working, .done])
        #expect(read.comments[2].thread.map(\.kind) == [.question, .answer, .message])
        #expect(read.batches.first?.messages.map(\.text) == ["On it"])
        #expect(read.video.frameRate == 30)
        // Only the one file, with nothing temporary left beside it.
        #expect(files(under: scratch.folder) == ["videos", "videos/\(Self.hash)", "videos/\(Self.hash)/review.json"])
    }

    @Test("review.json is JSON a person can read: a schema version, the review's own keys, times as ISO 8601")
    func reviewFile() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = Library(support: scratch.folder)
        try library.save(try review())
        #expect(library.reviewFile(of: Self.hash).path == scratch.folder.path + "/videos/\(Self.hash)/review.json")
        let text = try String(contentsOf: library.reviewFile(of: Self.hash), encoding: .utf8)
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(Set(object.keys) == ["schemaVersion", "video", "note", "comments", "batches"])
        #expect(text.contains("\"sentAt\" : \"2027-01-15T08:00:00.250Z\""))
        #expect(text.contains("\"path\" : \"/videos/sample.mp4\""))
    }

    @Test("a new library knows the video of every comment and batch on disk; a save keeps the index current")
    func index() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        var first = try review()
        let second = try review(Self.other, prefix: "1")
        try Library(support: scratch.folder).save(first)
        try Library(support: scratch.folder).save(second)

        let library = Library(support: scratch.folder)
        #expect(library.contentHash(of: try id("c-00000001")) == Self.hash)
        #expect(library.contentHash(of: try id("b-00000001")) == Self.hash)
        #expect(library.contentHash(of: try id("c-10000002")) == Self.other)
        #expect(library.contentHash(of: try id("b-10000001")) == Self.other)
        #expect(library.contentHash(of: try id("c-99999999")) == nil)
        // A message is found through its comment, not by its own id.
        #expect(library.contentHash(of: try id("m-00000001")) == nil)

        try first.deleteComment(try id("c-00000003"))
        try first.addComment(id: try id("c-00000009"), time: 1, text: "New")
        try library.save(first)
        #expect(library.contentHash(of: try id("c-00000003")) == nil)
        #expect(library.contentHash(of: try id("c-00000009")) == Self.hash)
        #expect(library.contentHash(of: try id("c-10000002")) == Self.other)
    }

    @Test("a review written before a note, threads, messages and the frame rate existed still reads")
    func olderFile() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = Library(support: scratch.folder)
        let file = library.reviewFile(of: Self.hash)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
        { "video": { "contentHash": "\(Self.hash)", "title": "sample", "duration": 21.233, "path": "/videos/sample.mp4" },
          "comments": [ { "id": "c-00000001", "time": 10, "text": "Too fast", "state": "sent", "batchID": "b-00000001" } ],
          "batches": [ { "id": "b-00000001", "sentAt": "2026-10-04T19:02:11Z", "commentIDs": ["c-00000001"] } ] }
        """.utf8).write(to: file)

        let review = try #require(try library.load(Self.hash))
        #expect(review.note == "")
        #expect(review.comments.first?.thread == [])
        #expect(review.batches.first?.sentAt == at(1_791_140_531))
        #expect(review.video.frameRate == nil)
    }

    @Test("a review from a newer schema isn't read, is named in the reason, and is left as it is")
    func newerSchema() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let file = Library(support: scratch.folder).reviewFile(of: Self.hash)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let newer = Data("{ \"schemaVersion\": 2, \"video\": { \"contentHash\": \"\(Self.hash)\" }, \"shapes\": [] }".utf8)
        try newer.write(to: file)

        let library = Library(support: scratch.folder)
        let failure = #expect(throws: Library.Failure.self) { try library.load(Self.hash) }
        #expect(failure?.reason.contains("newer version of the app (schema 2, this one reads 1)") == true)
        #expect(failure?.reason.contains(file.path) == true)
        #expect(try Data(contentsOf: file) == newer)
    }

    @Test("a review that doesn't read (half a file, another video's) throws and is left as it is; a new library starts without it")
    func unreadable() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try Library(support: scratch.folder).save(try review())
        let file = Library(support: scratch.folder).reviewFile(of: Self.hash)
        let half = try Data(contentsOf: file).prefix(200)
        try half.write(to: file)
        try Library(support: scratch.folder).save(try review(Self.other, prefix: "1"))

        let library = Library(support: scratch.folder)
        let failure = #expect(throws: Library.Failure.self) { try library.load(Self.hash) }
        #expect(failure?.reason.contains("doesn't read") == true)
        #expect(try Data(contentsOf: file) == half)
        #expect(library.contentHash(of: try id("c-00000001")) == nil)
        #expect(library.contentHash(of: try id("c-10000001")) == Self.other)

        // A folder copied by hand under another video's hash.
        let copied = library.reviewFile(of: String(repeating: "c", count: 64))
        try FileManager.default.createDirectory(at: copied.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: library.reviewFile(of: Self.other), to: copied)
        let wrong = #expect(throws: Library.Failure.self) { try library.load(String(repeating: "c", count: 64)) }
        #expect(wrong?.reason.contains("another video") == true)
    }

    @Test("a save that can't be written throws with the reason, and the old file stays whole")
    func unwritable() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = Library(support: scratch.folder)
        var review = try review()
        try library.save(review)
        let file = library.reviewFile(of: Self.hash)
        let before = try Data(contentsOf: file)
        let folder = file.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        review.note = "Changed"
        let failure = #expect(throws: Library.Failure.self) { try library.save(review) }
        #expect(failure?.reason.hasPrefix("couldn't write \(file.path)") == true)
        #expect(try Data(contentsOf: file) == before)
    }

    @Test("a library on a folder that isn't there reads nothing and writes nothing")
    func empty() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let support = scratch.folder.appendingPathComponent("support", isDirectory: true)
        let library = Library(support: support)
        #expect(try library.load(Self.hash) == nil)
        #expect(library.loadOutbox() == Outbox())
        #expect(library.recent() == nil)
        #expect(!FileManager.default.fileExists(atPath: support.path))
    }

    @Test("two support folders never see each other's reviews, outbox or last video")
    func separateFolders() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let real = scratch.folder.appendingPathComponent("real", isDirectory: true)
        let demo = scratch.folder.appendingPathComponent("demo", isDirectory: true)
        let library = Library(support: demo)
        try library.save(try review())
        var outbox = Outbox()
        outbox.enqueue(BatchRef(batchID: try id("b-00000001"), contentHash: Self.hash))
        try library.save(outbox)
        library.saveRecent(URL(fileURLWithPath: "/videos/sample.mp4"))

        #expect(!FileManager.default.fileExists(atPath: real.path))
        let other = Library(support: real)
        #expect(try other.load(Self.hash) == nil)
        #expect(other.contentHash(of: try id("c-00000001")) == nil)
        #expect(other.loadOutbox() == Outbox())
        #expect(other.recent() == nil)
        #expect(files(under: demo).filter { !$0.hasPrefix("videos") } == ["outbox.json", "recent.json"])
    }

    // MARK: - The outbox

    @Test("the outbox reads back with its line, its taken batches, its session and the context sent")
    func outboxRoundTrip() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try Library(support: scratch.folder).save(try review())
        var second = try review(Self.other, prefix: "1")
        try second.send(batchID: try id("b-10000002"), at: at(1_800_000_100))
        try Library(support: scratch.folder).save(second)
        let taken = BatchRef(batchID: try id("b-00000001"), contentHash: Self.hash)
        let waiting = BatchRef(batchID: try id("b-10000002"), contentHash: Self.other)
        let alsoWaiting = BatchRef(batchID: try id("b-10000001"), contentHash: Self.other)
        var outbox = Outbox()
        outbox.enqueue(taken)
        outbox.enqueue(waiting)
        outbox.enqueue(alsoWaiting)
        outbox.waitOpened(by: ListenerSession(key: "listener-1", name: "Mate", place: "/shop"), at: at(0))
        #expect(outbox.deliverNext(at: at(0)) == taken)
        #expect(outbox.context(for: Self.hash, text: "The topic") == "The topic")
        try Library(support: scratch.folder).save(outbox)

        let read = Library(support: scratch.folder).loadOutbox()
        // The line keeps its own order, not the order sent.
        #expect(read.pending == [waiting, alsoWaiting])
        #expect(read.taken == [taken])
        #expect(read.session == ListenerSession(key: "listener-1", name: "Mate", place: "/shop"))
        #expect(read.contextSent == outbox.contextSent)
        #expect(!read.isContextDue(for: Self.hash, text: "The topic"))
        // What belongs to one run isn't kept.
        #expect(!read.isWaitOpen)
        #expect(read.presence(at: at(1)) == .absent)
        let text = try String(contentsOf: Library(support: scratch.folder).outboxFile, encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 1"))
    }

    @Test("with no outbox file, or one that doesn't read, every unfinished batch on disk is in line, in the order sent")
    func outboxRebuilt() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        var later = try review(Self.other, prefix: "1")
        try later.send(batchID: try id("b-10000002"), at: at(1_900_000_000))
        try Library(support: scratch.folder).save(later)
        try Library(support: scratch.folder).save(try review())
        var finished = try review(String(repeating: "c", count: 64), prefix: "2")
        try finished.setStatus(try id("c-20000001"), .failed)
        try Library(support: scratch.folder).save(finished)
        let expected = [
            BatchRef(batchID: try id("b-00000001"), contentHash: Self.hash),
            BatchRef(batchID: try id("b-10000001"), contentHash: Self.other),
            BatchRef(batchID: try id("b-10000002"), contentHash: Self.other),
        ]

        #expect(Set(Library(support: scratch.folder).loadOutbox().pending.prefix(2)) == Set(expected.prefix(2)))
        #expect(Library(support: scratch.folder).loadOutbox().pending.last == expected[2])
        #expect(Library(support: scratch.folder).loadOutbox().taken.isEmpty)

        try Data("{ \"pending\": [".utf8).write(to: Library(support: scratch.folder).outboxFile)
        #expect(Library(support: scratch.folder).loadOutbox().pending.count == 3)
    }

    @Test("an outbox from a newer schema is never written over")
    func newerOutbox() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = Library(support: scratch.folder)
        let newer = Data("{ \"schemaVersion\": 9, \"lanes\": [] }".utf8)
        try newer.write(to: library.outboxFile)

        var outbox = library.loadOutbox()
        #expect(outbox == Outbox())
        outbox.enqueue(BatchRef(batchID: try id("b-00000001"), contentHash: Self.hash))
        #expect(throws: Library.Failure.self) { try library.save(outbox) }
        #expect(try Data(contentsOf: library.outboxFile) == newer)
    }

    // MARK: - The last video

    @Test("the last open video's path reads back; a file that doesn't read is no video")
    func recent() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = Library(support: scratch.folder)
        #expect(library.recent() == nil)
        library.saveRecent(URL(fileURLWithPath: "/videos/a b/sample.mp4"))
        #expect(Library(support: scratch.folder).recent()?.path == "/videos/a b/sample.mp4")
        library.saveRecent(URL(fileURLWithPath: "/videos/other.mov"))
        #expect(Library(support: scratch.folder).recent()?.path == "/videos/other.mov")

        try Data("{".utf8).write(to: library.recentFile)
        #expect(library.recent() == nil)
        try Data("{ \"schemaVersion\": 1, \"path\": \"relative.mp4\" }".utf8).write(to: library.recentFile)
        #expect(library.recent() == nil)
    }
}
