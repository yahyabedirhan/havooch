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

    /// The id of `kind` and `number` on the video with `hash`.
    private func item(_ kind: String, _ number: Int) throws -> ItemID {
        try item(kind, Self.hash, number)
    }

    /// The id of `kind` and `number` on the video with `hash`.
    private func item(_ kind: String, _ hash: String, _ number: Int) throws -> ItemID {
        try id("\(kind)-\(hash.prefix(8))-\(number)")
    }

    /// A review with everything a review can hold: a send of two messages
    /// on two threads (one on a region, with a question and its answer and
    /// a reply, done; one working), the acknowledgement on General, a
    /// queued message on a third thread, a popover frame and a note.
    private func review(_ hash: String = hash, path: String = "/videos/sample.mp4") throws -> VideoReview {
        var review = VideoReview(video: VideoInfo(contentHash: hash, title: "sample", duration: 21.233, path: path, frameRate: 30))
        let first = try review.write(text: "Too fast here", at: 10, now: at(1_800_000_000)).message.id
        let boxed = try review.write(
            text: "This box", at: 12.5, region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25), now: at(1_800_000_000)
        )
        let send = try review.send(at: at(1_800_000_000.25))
        try review.acknowledge(send.id, text: "On it", now: at(1_800_000_001))
        try review.ask(on: boxed.thread.id, question: "Which box?", now: at(1_800_000_002.5))
        try review.answer(boxed.thread.id, text: "The left one", now: at(1_800_000_003))
        try review.reply(on: boxed.thread.id, text: "Fixed in abc123", now: at(1_800_000_004))
        try review.setState(boxed.message.id, .done)
        try review.setState(first, .working)
        try review.write(text: "Still queued", at: 3, now: at(1_800_000_005))
        try review.setPopoverFrame(boxed.thread.id, PopoverFrame(x: 0.5, y: 0.1, w: 0.4, h: 0.3))
        review.note = "The pricing page"
        return review
    }

    private func files(under folder: URL) -> [String] {
        ((try? FileManager.default.subpathsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    // MARK: - Reviews

    @Test("a review reads back the same in a new library: threads, messages, the region, states, sends, popover frames, the note and the frame rate")
    func reviewRoundTrip() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let review = try review()
        #expect(try Library(layout: SupportLayout(root: scratch.folder)).load(Self.hash) == nil)

        try Library(layout: SupportLayout(root: scratch.folder)).save(review)

        let read = try #require(try Library(layout: SupportLayout(root: scratch.folder)).load(Self.hash))
        #expect(read == review)
        #expect(read.threads.map(\.number) == [0, 3, 1, 2])
        #expect(read.threads.map(\.state) == [nil, .queued, .working, .done])
        #expect(read.thread(try item("t", 2))?.messages.map(\.kind) == [.message, .question, .answer, .message])
        #expect(read.thread(try item("t", 2))?.popoverFrame == PopoverFrame(x: 0.5, y: 0.1, w: 0.4, h: 0.3))
        #expect(read.general.messages.map(\.text) == ["On it"])
        let sent: [[ItemID]] = [[try item("m", 1), try item("m", 2)]]
        #expect(read.sends.map(\.messageIDs) == sent)
        // The counters come back too: the next thread is #4.
        var next = read
        #expect(try next.write(text: "New", at: 1, now: at(1_800_000_010)).thread.number == 4)
        #expect(read.video.frameRate == 30)
        // Only the one file, with nothing temporary left beside it.
        #expect(files(under: scratch.folder) == ["videos", "videos/\(Self.hash)", "videos/\(Self.hash)/review.json"])
    }

    @Test("review.json is JSON a person can read: a schema version, the review's own keys, times as ISO 8601")
    func reviewFile() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = Library(layout: SupportLayout(root: scratch.folder))
        try library.save(try review())
        #expect(library.layout.reviewFile(Self.hash).path == scratch.folder.path + "/videos/\(Self.hash)/review.json")
        let text = try String(contentsOf: library.layout.reviewFile(Self.hash), encoding: .utf8)
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(Set(object.keys) == ["schemaVersion", "video", "note", "threads", "sends", "counters"])
        #expect(text.contains("\"sentAt\" : \"2027-01-15T08:00:00.250Z\""))
        #expect(text.contains("\"path\" : \"/videos/sample.mp4\""))
    }

    @Test("a new library knows the video of every id on disk by its hash prefix; a save adds a new video")
    func index() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try Library(layout: SupportLayout(root: scratch.folder)).save(try review())

        let library = Library(layout: SupportLayout(root: scratch.folder))
        #expect(library.contentHash(prefix: "aaaaaaaa") == Self.hash)
        #expect(library.contentHash(of: try item("t", 2)) == Self.hash)
        #expect(library.contentHash(of: try item("m", 99)) == Self.hash)
        #expect(library.contentHash(of: try item("s", 1)) == Self.hash)
        #expect(library.contentHash(of: try item("t", Self.other, 1)) == nil)

        try library.save(try review(Self.other))
        #expect(library.contentHash(of: try item("t", Self.other, 1)) == Self.other)
    }

    @Test("a prototype's review, with comments and batches, doesn't read and is left as it is")
    func prototypeFile() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = Library(layout: SupportLayout(root: scratch.folder))
        let file = library.layout.reviewFile(Self.hash)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = Data("""
        { "video": { "contentHash": "\(Self.hash)", "title": "sample", "duration": 21.233, "path": "/videos/sample.mp4" },
          "comments": [ { "id": "c-00000001", "time": 10, "text": "Too fast", "state": "sent", "batchID": "b-00000001" } ],
          "batches": [ { "id": "b-00000001", "sentAt": "2026-10-04T19:02:11Z", "commentIDs": ["c-00000001"] } ] }
        """.utf8)
        try old.write(to: file)

        let failure = #expect(throws: Library.Failure.self) { try library.load(Self.hash) }
        #expect(failure?.reason.contains("doesn't read") == true)
        #expect(try Data(contentsOf: file) == old)
    }

    @Test("a review from a newer schema isn't read, is named in the reason, and is left as it is")
    func newerSchema() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let file = Library(layout: SupportLayout(root: scratch.folder)).layout.reviewFile(Self.hash)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let newer = Data("{ \"schemaVersion\": 2, \"video\": { \"contentHash\": \"\(Self.hash)\" }, \"shapes\": [] }".utf8)
        try newer.write(to: file)

        let library = Library(layout: SupportLayout(root: scratch.folder))
        let failure = #expect(throws: Library.Failure.self) { try library.load(Self.hash) }
        #expect(failure?.reason.contains("newer version of the app (schema 2, this one reads 1)") == true)
        #expect(failure?.reason.contains(file.path) == true)
        #expect(try Data(contentsOf: file) == newer)
    }

    @Test("a review that doesn't read (half a file, another video's) throws and is left as it is; a new library starts without it")
    func unreadable() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try Library(layout: SupportLayout(root: scratch.folder)).save(try review())
        let file = Library(layout: SupportLayout(root: scratch.folder)).layout.reviewFile(Self.hash)
        let half = try Data(contentsOf: file).prefix(200)
        try half.write(to: file)
        try Library(layout: SupportLayout(root: scratch.folder)).save(try review(Self.other))

        let library = Library(layout: SupportLayout(root: scratch.folder))
        let failure = #expect(throws: Library.Failure.self) { try library.load(Self.hash) }
        #expect(failure?.reason.contains("doesn't read") == true)
        #expect(try Data(contentsOf: file) == half)
        #expect(library.contentHash(of: try item("m", 1)) == nil)
        #expect(library.contentHash(of: try item("m", Self.other, 1)) == Self.other)

        // A folder copied by hand under another video's hash.
        let copied = library.layout.reviewFile(String(repeating: "c", count: 64))
        try FileManager.default.createDirectory(at: copied.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: library.layout.reviewFile(Self.other), to: copied)
        let wrong = #expect(throws: Library.Failure.self) { try library.load(String(repeating: "c", count: 64)) }
        #expect(wrong?.reason.contains("another video") == true)
    }

    /// Whether the tests run as root, which writes into a read-only folder
    /// (a Linux container's default user).
    static var runsAsRoot: Bool { geteuid() == 0 }

    @Test("a save that can't be written throws with the reason, and the old file stays whole",
          .disabled(if: runsAsRoot, "root writes into a read-only folder"))
    func unwritable() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = Library(layout: SupportLayout(root: scratch.folder))
        var review = try review()
        try library.save(review)
        let file = library.layout.reviewFile(Self.hash)
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
        let library = Library(layout: SupportLayout(root: support))
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
        let library = Library(layout: SupportLayout(root: demo))
        try library.save(try review())
        var outbox = Outbox()
        outbox.enqueue(SendRef(sendID: try item("s", 1), contentHash: Self.hash))
        try library.save(outbox)
        library.saveRecent(URL(fileURLWithPath: "/videos/sample.mp4"))

        #expect(!FileManager.default.fileExists(atPath: real.path))
        let other = Library(layout: SupportLayout(root: real))
        #expect(try other.load(Self.hash) == nil)
        #expect(other.contentHash(of: try item("m", 1)) == nil)
        #expect(other.loadOutbox() == Outbox())
        #expect(other.recent() == nil)
        #expect(files(under: demo).filter { !$0.hasPrefix("videos") } == ["outbox.json", "recent.json"])
    }

    // MARK: - The outbox

    @Test("the outbox reads back with its line, its taken sends, its session and the context sent")
    func outboxRoundTrip() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try Library(layout: SupportLayout(root: scratch.folder)).save(try review())
        var second = try review(Self.other)
        try second.send(at: at(1_800_000_100))
        try Library(layout: SupportLayout(root: scratch.folder)).save(second)
        let taken = SendRef(sendID: try item("s", 1), contentHash: Self.hash)
        let waiting = SendRef(sendID: try item("s", Self.other, 2), contentHash: Self.other)
        let alsoWaiting = SendRef(sendID: try item("s", Self.other, 1), contentHash: Self.other)
        var outbox = Outbox()
        outbox.enqueue(taken)
        outbox.enqueue(waiting)
        outbox.enqueue(alsoWaiting)
        outbox.waitOpened(by: ListenerSession(key: "listener-1", name: "Mate", place: "/shop"), at: at(0))
        #expect(outbox.deliver(at: at(0)) == taken)
        #expect(outbox.context(for: Self.hash, text: "The topic") == "The topic")
        try Library(layout: SupportLayout(root: scratch.folder)).save(outbox)

        let read = Library(layout: SupportLayout(root: scratch.folder)).loadOutbox()
        // The line keeps its own order, not the order sent.
        #expect(read.pending == [waiting, alsoWaiting])
        #expect(read.taken == [taken])
        #expect(read.session == ListenerSession(key: "listener-1", name: "Mate", place: "/shop"))
        #expect(read.contextSent == outbox.contextSent)
        #expect(!read.isContextDue(for: Self.hash, text: "The topic"))
        // What belongs to one run isn't kept.
        #expect(!read.isWaitOpen)
        #expect(read.presence(at: at(1)) == .absent)
        let text = try String(contentsOf: Library(layout: SupportLayout(root: scratch.folder)).layout.outboxFile, encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 1"))
    }

    @Test("with no outbox file, or one that doesn't read, every unfinished send on disk is in line, in the order sent")
    func outboxRebuilt() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        var later = try review(Self.other)
        try later.send(at: at(1_900_000_000))
        try Library(layout: SupportLayout(root: scratch.folder)).save(later)
        try Library(layout: SupportLayout(root: scratch.folder)).save(try review())
        let third = String(repeating: "c", count: 64)
        var finished = try review(third)
        try finished.setState(try item("m", third, 1), .failed)
        try Library(layout: SupportLayout(root: scratch.folder)).save(finished)
        let expected = [
            SendRef(sendID: try item("s", 1), contentHash: Self.hash),
            SendRef(sendID: try item("s", Self.other, 1), contentHash: Self.other),
            SendRef(sendID: try item("s", Self.other, 2), contentHash: Self.other),
        ]

        #expect(Set(Library(layout: SupportLayout(root: scratch.folder)).loadOutbox().pending.prefix(2)) == Set(expected.prefix(2)))
        #expect(Library(layout: SupportLayout(root: scratch.folder)).loadOutbox().pending.last == expected[2])
        #expect(Library(layout: SupportLayout(root: scratch.folder)).loadOutbox().taken.isEmpty)

        try Data("{ \"pending\": [".utf8).write(to: Library(layout: SupportLayout(root: scratch.folder)).layout.outboxFile)
        #expect(Library(layout: SupportLayout(root: scratch.folder)).loadOutbox().pending.count == 3)
    }

    @Test("an outbox from a newer schema is never written over")
    func newerOutbox() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = Library(layout: SupportLayout(root: scratch.folder))
        let newer = Data("{ \"schemaVersion\": 9, \"lanes\": [] }".utf8)
        try newer.write(to: library.layout.outboxFile)

        var outbox = library.loadOutbox()
        #expect(outbox == Outbox())
        outbox.enqueue(SendRef(sendID: try item("s", 1), contentHash: Self.hash))
        #expect(throws: Library.Failure.self) { try library.save(outbox) }
        #expect(try Data(contentsOf: library.layout.outboxFile) == newer)
    }

    // MARK: - The last video

    @Test("the last open video's path reads back; a file that doesn't read is no video")
    func recent() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = Library(layout: SupportLayout(root: scratch.folder))
        #expect(library.recent() == nil)
        library.saveRecent(URL(fileURLWithPath: "/videos/a b/sample.mp4"))
        #expect(Library(layout: SupportLayout(root: scratch.folder)).recent()?.path == "/videos/a b/sample.mp4")
        library.saveRecent(URL(fileURLWithPath: "/videos/other.mov"))
        #expect(Library(layout: SupportLayout(root: scratch.folder)).recent()?.path == "/videos/other.mov")

        try Data("{".utf8).write(to: library.layout.recentFile)
        #expect(library.recent() == nil)
        try Data("{ \"schemaVersion\": 1, \"path\": \"relative.mp4\" }".utf8).write(to: library.layout.recentFile)
        #expect(library.recent() == nil)
    }
}

extension Outbox {
    /// Hands the next send to the open `wait` and has its reply written.
    fileprivate mutating func deliver(at now: Date) -> SendRef? {
        guard let ref = handOut(at: now) else { return nil }
        written(ref)
        return ref
    }
}
