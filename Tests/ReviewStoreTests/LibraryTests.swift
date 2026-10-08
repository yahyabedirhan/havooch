import Foundation
import ReviewCore
import ReviewStore
import Testing

/// What the library keeps on disk, in a temporary support folder.
@Suite("The library")
struct LibraryTests {
    static let hash = String(repeating: "a", count: 64)
    static let other = String(repeating: "b", count: 64)
    static let key = ReviewKey.video(contentHash: hash)

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
        #expect(library.loadOutbox(Self.key) == Outbox())
        #expect(library.recents().isEmpty)
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
        try library.save(outbox, of: Self.key)
        library.recordOpened(URL(fileURLWithPath: "/videos/sample.mp4"), contentHash: Self.hash, at: at(1_800_000_000))

        #expect(!FileManager.default.fileExists(atPath: real.path))
        let other = Library(layout: SupportLayout(root: real))
        #expect(try other.load(Self.hash) == nil)
        #expect(other.contentHash(of: try item("m", 1)) == nil)
        #expect(other.loadOutbox(Self.key) == Outbox())
        #expect(other.recents().isEmpty)
        #expect(files(under: demo).filter { !$0.hasPrefix("videos") } == ["outboxes", "outboxes/video-\(Self.hash).json", "recents.json"])
    }

    // MARK: - The outboxes

    static let otherKey = ReviewKey.video(contentHash: other)
    static let mate = ListenerSession(key: "listener-1", name: "Mate", place: "/shop")

    /// Two reviews on disk, each with unfinished sends: `s-1` of `hash`,
    /// and `s-1` and `s-2` of `other`, sent later.
    private func twoReviews(in folder: URL) throws {
        try Library(layout: SupportLayout(root: folder)).save(try review())
        var second = try review(Self.other)
        try second.send(at: at(1_800_000_100))
        try Library(layout: SupportLayout(root: folder)).save(second)
    }

    @Test("a review's outbox reads back with its line, its taken sends, its session and the context sent")
    func outboxRoundTrip() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try twoReviews(in: scratch.folder)
        let waiting = SendRef(sendID: try item("s", Self.other, 2), contentHash: Self.other)
        let taken = SendRef(sendID: try item("s", Self.other, 1), contentHash: Self.other)
        var outbox = Outbox()
        outbox.enqueue(taken)
        outbox.enqueue(waiting)
        outbox.waitOpened(by: Self.mate, at: at(0))
        #expect(outbox.deliver(at: at(0)) == taken)
        #expect(outbox.context(for: Self.other, text: "The topic") == "The topic")
        try Library(layout: SupportLayout(root: scratch.folder)).save(outbox, of: Self.otherKey)

        let read = Library(layout: SupportLayout(root: scratch.folder)).loadOutbox(Self.otherKey)
        #expect(read.pending == [waiting])
        #expect(read.taken == [taken])
        #expect(read.session == outbox.session)
        #expect(read.session?.since == at(0))
        #expect(read.contextSent == outbox.contextSent)
        #expect(!read.isContextDue(for: Self.other, text: "The topic"))
        // What belongs to one run isn't kept.
        #expect(!read.isWaitOpen)
        #expect(read.presence(at: at(1)) == .absent)
        let text = try String(contentsOf: SupportLayout(root: scratch.folder).outboxFile(Self.otherKey), encoding: .utf8)
        #expect(text.contains("\"schemaVersion\" : 1"))
        // The other review's listener has its own line, and none of these sends.
        let own = Library(layout: SupportLayout(root: scratch.folder)).loadOutbox(Self.key)
        #expect(own.pending == [SendRef(sendID: try item("s", 1), contentHash: Self.hash)])
        #expect(own.session == nil)
    }

    @Test("with no outbox file, or one that doesn't read, every unfinished send of the review is in line, in the order sent")
    func outboxRebuilt() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try twoReviews(in: scratch.folder)
        let third = String(repeating: "c", count: 64)
        var finished = try review(third)
        try finished.setState(try item("m", third, 1), .failed)
        try Library(layout: SupportLayout(root: scratch.folder)).save(finished)
        let expected = [
            SendRef(sendID: try item("s", Self.other, 1), contentHash: Self.other),
            SendRef(sendID: try item("s", Self.other, 2), contentHash: Self.other),
        ]

        #expect(Library(layout: SupportLayout(root: scratch.folder)).loadOutbox(Self.otherKey).pending == expected)
        #expect(Library(layout: SupportLayout(root: scratch.folder)).loadOutbox(Self.otherKey).taken.isEmpty)
        #expect(Library(layout: SupportLayout(root: scratch.folder)).loadOutbox(.video(contentHash: third)).pending.isEmpty)

        let file = SupportLayout(root: scratch.folder).outboxFile(Self.otherKey)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ \"pending\": [".utf8).write(to: file)
        #expect(Library(layout: SupportLayout(root: scratch.folder)).loadOutbox(Self.otherKey).pending == expected)
    }

    @Test("an outbox from a newer schema is never written over")
    func newerOutbox() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = Library(layout: SupportLayout(root: scratch.folder))
        let newer = Data("{ \"schemaVersion\": 9, \"lanes\": [] }".utf8)
        let file = library.layout.outboxFile(Self.key)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try newer.write(to: file)

        var outbox = library.loadOutbox(Self.key)
        #expect(outbox == Outbox())
        outbox.enqueue(SendRef(sendID: try item("s", 1), contentHash: Self.hash))
        #expect(throws: Library.Failure.self) { try library.save(outbox, of: Self.key) }
        #expect(try Data(contentsOf: file) == newer)
        // Another review's outbox is written as usual.
        try library.save(Outbox(), of: Self.otherKey)
    }

    /// The one outbox a build before a listener per review kept, as it
    /// wrote it: `s-1` of `hash` taken, `s-2` and `s-1` of `other` in
    /// line, and the context of both videos sent to `mate`.
    private func formerOutbox() throws -> Outbox {
        var outbox = Outbox()
        outbox.enqueue(SendRef(sendID: try item("s", 1), contentHash: Self.hash))
        outbox.enqueue(SendRef(sendID: try item("s", Self.other, 2), contentHash: Self.other))
        outbox.enqueue(SendRef(sendID: try item("s", Self.other, 1), contentHash: Self.other))
        outbox.waitOpened(by: Self.mate, at: at(0))
        _ = outbox.deliver(at: at(0))
        _ = outbox.context(for: Self.hash, text: "First")
        _ = outbox.context(for: Self.other, text: "Second")
        return outbox
    }

    @Test("the outbox of builds before a listener per review splits once into each review's, with its session and context, and goes")
    func formerOutboxSplits() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try twoReviews(in: scratch.folder)
        let layout = SupportLayout(root: scratch.folder)
        try Library(layout: layout).save(try formerOutbox(), of: Self.key)
        try FileManager.default.moveItem(at: layout.outboxFile(Self.key), to: layout.formerOutboxFile)

        Library(layout: layout).migrateFormerOutbox()

        #expect(!FileManager.default.fileExists(atPath: layout.formerOutboxFile.path))
        let first = Library(layout: layout).loadOutbox(Self.key)
        #expect(first.taken == [SendRef(sendID: try item("s", 1), contentHash: Self.hash)])
        #expect(first.pending.isEmpty)
        #expect(first.session?.key == Self.mate.key)
        #expect(first.session?.since == at(0))
        #expect(!first.isContextDue(for: Self.hash, text: "First"))
        #expect(first.contextSent.keys.sorted() == [Self.hash])
        let second = Library(layout: layout).loadOutbox(Self.otherKey)
        // The line keeps its own order, not the order sent.
        #expect(second.pending == [
            SendRef(sendID: try item("s", Self.other, 2), contentHash: Self.other),
            SendRef(sendID: try item("s", Self.other, 1), contentHash: Self.other),
        ])
        #expect(second.taken.isEmpty)
        #expect(second.session?.key == Self.mate.key)
        #expect(!second.isContextDue(for: Self.other, text: "Second"))

        // Once: a second run finds nothing to split, and a review's own outbox stays.
        try Library(layout: layout).save(Outbox(), of: Self.key)
        Library(layout: layout).migrateFormerOutbox()
        #expect(Library(layout: layout).loadOutbox(Self.key).taken.isEmpty)
    }

    @Test("an old outbox that doesn't read stays, and each review's line is rebuilt from the reviews")
    func formerOutboxUnread() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try twoReviews(in: scratch.folder)
        let layout = SupportLayout(root: scratch.folder)
        try Data("{ \"pending\": [".utf8).write(to: layout.formerOutboxFile)

        Library(layout: layout).migrateFormerOutbox()

        #expect(FileManager.default.fileExists(atPath: layout.formerOutboxFile.path))
        #expect(Library(layout: layout).loadOutbox(Self.otherKey).pending.count == 2)
        #expect(Library(layout: layout).loadOutbox(Self.key).pending.count == 1)
    }

    // MARK: - Recent videos

    /// The content hash numbered `number`: 64 hex digits.
    private func hash(_ number: Int) -> String {
        String(format: "%064x", number)
    }

    /// The library on `folder`, as a new run reads it.
    private func reread(_ folder: URL) -> Library {
        Library(layout: SupportLayout(root: folder))
    }

    @Test("an opened video goes first on the recent videos with its path, hash, time and no position, and reads back in a new library")
    func recentRoundTrip() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = reread(scratch.folder)
        #expect(library.recents().isEmpty)
        library.recordOpened(URL(fileURLWithPath: "/videos/a b/sample.mp4"), contentHash: hash(1), at: at(1_800_000_000))
        library.recordOpened(URL(fileURLWithPath: "/videos/other.mov"), contentHash: hash(2), at: at(1_800_000_060))

        let expected = [
            RecentVideo(path: "/videos/other.mov", contentHash: hash(2), openedAt: at(1_800_000_060), position: 0),
            RecentVideo(path: "/videos/a b/sample.mp4", contentHash: hash(1), openedAt: at(1_800_000_000), position: 0),
        ]
        #expect(library.recents() == expected)
        #expect(reread(scratch.folder).recents() == expected)
        #expect(files(under: scratch.folder) == ["recents.json"])
    }

    @Test("the recent videos keep the 10 newest, the newest first")
    func recentLimit() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = reread(scratch.folder)
        for number in 1...12 {
            library.recordOpened(
                URL(fileURLWithPath: "/videos/\(number).mp4"), contentHash: hash(number), at: at(1_800_000_000 + Double(number))
            )
        }
        #expect(Library.recentLimit == 10)
        #expect(reread(scratch.folder).recents().map(\.contentHash) == (3...12).reversed().map(hash))
    }

    @Test("a video opened again moves to the front, matched by its content hash: one entry, with the new path and time, and its position kept")
    func recentMovesToFront() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = reread(scratch.folder)
        library.recordOpened(URL(fileURLWithPath: "/videos/sample.mp4"), contentHash: hash(1), at: at(1_800_000_000))
        library.savePosition(12.5, of: hash(1))
        library.recordOpened(URL(fileURLWithPath: "/videos/other.mov"), contentHash: hash(2), at: at(1_800_000_010))
        library.recordOpened(URL(fileURLWithPath: "/moved/renamed take 2.mov"), contentHash: hash(1), at: at(1_800_000_020))

        #expect(reread(scratch.folder).recents() == [
            RecentVideo(path: "/moved/renamed take 2.mov", contentHash: hash(1), openedAt: at(1_800_000_020), position: 12.5),
            RecentVideo(path: "/videos/other.mov", contentHash: hash(2), openedAt: at(1_800_000_010), position: 0),
        ])
    }

    @Test("a saved position is kept on its entry only and leaves the order as it is; a video not on the list saves nothing")
    func recentPosition() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = reread(scratch.folder)
        library.recordOpened(URL(fileURLWithPath: "/videos/sample.mp4"), contentHash: hash(1), at: at(1_800_000_000))
        library.recordOpened(URL(fileURLWithPath: "/videos/other.mov"), contentHash: hash(2), at: at(1_800_000_010))
        library.savePosition(7.25, of: hash(1))
        library.savePosition(3, of: hash(9))

        #expect(reread(scratch.folder).recents().map(\.contentHash) == [hash(2), hash(1)])
        #expect(reread(scratch.folder).recents().map(\.position) == [0, 7.25])
    }

    @Test("removing a recent video takes it off the list only: its review stays on disk")
    func recentRemoval() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = reread(scratch.folder)
        try library.save(try review())
        library.recordOpened(URL(fileURLWithPath: "/videos/sample.mp4"), contentHash: Self.hash, at: at(1_800_000_000))
        library.recordOpened(URL(fileURLWithPath: "/videos/other.mov"), contentHash: Self.other, at: at(1_800_000_010))
        library.removeRecent(Self.hash)
        library.removeRecent(hash(9))

        #expect(reread(scratch.folder).recents().map(\.contentHash) == [Self.other])
        #expect(try reread(scratch.folder).load(Self.hash) == review())
    }

    @Test("on the first read, the last video of recent.json becomes the one recent video, by its review's hash, and recent.json goes")
    func recentMigration() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try reread(scratch.folder).save(try review(path: "/videos/sample.mp4"))
        let old = scratch.folder.appendingPathComponent("recent.json")
        try Data("{ \"schemaVersion\": 1, \"path\": \"/videos/sample.mp4\" }".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: at(1_800_000_000)], ofItemAtPath: old.path)

        let expected = [RecentVideo(path: "/videos/sample.mp4", contentHash: Self.hash, openedAt: at(1_800_000_000), position: 0)]
        #expect(reread(scratch.folder).recents() == expected)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(reread(scratch.folder).recents() == expected)
    }

    @Test("a video in recent.json with no review is hashed from its file; one that can't be read, or a recent.json that doesn't read, leaves no entry")
    func recentMigrationWithoutReview() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let support = scratch.folder.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let video = scratch.folder.appendingPathComponent("clip.mp4")
        try Data("not really a video".utf8).write(to: video)
        let old = support.appendingPathComponent("recent.json")
        try Data("{ \"schemaVersion\": 1, \"path\": \"\(video.path)\" }".utf8).write(to: old)

        let recents = reread(support).recents()
        #expect(recents.map(\.path) == [video.path])
        #expect(recents.map(\.contentHash) == [ContentHash.of(video)])
        #expect(!FileManager.default.fileExists(atPath: old.path))

        for text in ["{ \"schemaVersion\": 1, \"path\": \"/gone/clip.mp4\" }", "{"] {
            let fresh = try Scratch()
            defer { fresh.cleanUp() }
            try Data(text.utf8).write(to: fresh.folder.appendingPathComponent("recent.json"))
            #expect(reread(fresh.folder).recents().isEmpty)
            #expect(files(under: fresh.folder).isEmpty)
        }
    }

    @Test("a recents.json that doesn't read is no list; one a newer build wrote is never written over")
    func recentUnreadable() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let library = reread(scratch.folder)
        try Data("{".utf8).write(to: library.layout.recentsFile)
        #expect(reread(scratch.folder).recents().isEmpty)

        let newer = Data("{ \"schemaVersion\": 99, \"videos\": [] }".utf8)
        try newer.write(to: library.layout.recentsFile)
        let again = reread(scratch.folder)
        #expect(again.recents().isEmpty)
        again.recordOpened(URL(fileURLWithPath: "/videos/sample.mp4"), contentHash: hash(1), at: at(1_800_000_000))
        #expect(try Data(contentsOf: library.layout.recentsFile) == newer)
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
