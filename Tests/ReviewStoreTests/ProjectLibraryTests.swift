import Foundation
import ReviewCore
import ReviewStore
import Testing

/// A project's review on disk (ADR 0004): `project new` moves a plain
/// video's review, keyframes and crops to `projects/<slug>/`, its ids
/// still finding it; a new library reads both kinds of review; and when
/// each project was last opened is app state in `recents.json`.
@Suite("Projects in the library")
struct ProjectLibraryTests {
    static let hash = String(repeating: "a", count: 64)
    static let video = ReviewKey.video(contentHash: hash)
    static let project = ReviewKey.project(slug: "launch-video")
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("moving a video's review into a project moves its file and pictures, keeps the transcript, and its ids find it there")
    func move() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let layout = SupportLayout(root: scratch.folder)
        let library = Library(layout: layout)
        var review = Review(video: VideoInfo(contentHash: Self.hash, title: "cut1.mp4", duration: 21, path: "/Movies/cut1.mp4"))
        let written = try review.write(text: "Too fast", at: 10, now: Self.now)
        let sent = try review.send(at: Self.now)
        try library.save(review)
        for file in [layout.keyframe(written.thread.id, of: Self.video), layout.transcriptFile(Self.hash)] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("png".utf8).write(to: file)
        }

        let adopted = review.adoptedIntoProject("launch-video", anchor: VersionAnchor(path: "/Movies/cut1.mp4"))
        try library.move(adopted, from: Self.video)
        #expect(FileManager.default.fileExists(atPath: layout.reviewFile(Self.project).path))
        #expect(FileManager.default.fileExists(atPath: layout.keyframe(written.thread.id, of: Self.project).path))
        #expect(!FileManager.default.fileExists(atPath: layout.reviewFile(Self.video).path))
        #expect(!FileManager.default.fileExists(atPath: layout.keyframe(written.thread.id, of: Self.video).path))
        #expect(FileManager.default.fileExists(atPath: layout.transcriptFile(Self.hash).path))
        #expect(library.key(of: written.message.id) == Self.project)

        // A new library finds the project's review and its unfinished send.
        let again = Library(layout: layout)
        #expect(again.key(of: sent.id) == Self.project)
        #expect(try again.load(Self.project) == adopted)
        #expect(try again.load(Self.video) == nil)
        #expect(again.loadOutbox(Self.project).pending == [SendRef(sendID: sent.id, review: Self.project)])
        // The prefix is the project's now: a new plain review of the video needs another.
        #expect(again.isTaken("aaaaaaaa", by: Self.video))
        #expect(!again.isTaken("aaaaaaaa", by: Self.project))
    }

    @Test("when each project was last opened is kept beside the recent videos, and read back")
    func projectsUsed() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let layout = SupportLayout(root: scratch.folder)
        let library = Library(layout: layout)
        #expect(library.projectsUsed().isEmpty)
        library.recordOpened(URL(fileURLWithPath: "/Movies/plain.mp4"), contentHash: Self.hash, at: Self.now)
        library.recordProjectOpened("launch-video", at: Self.now)
        let again = Library(layout: layout)
        #expect(again.projectsUsed() == ["launch-video": Self.now])
        #expect(again.recents().map(\.path) == ["/Movies/plain.mp4"])
    }

    @Test("an outbox kept before projects names its review by content hash, and a project's by slug")
    func sendRefs() throws {
        let id = try #require(ItemID("s-aaaaaaaa-1"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let plain = SendRef(sendID: id, contentHash: Self.hash)
        #expect(String(decoding: try encoder.encode(plain), as: UTF8.self) == "{\"contentHash\":\"\(Self.hash)\",\"sendID\":\"s-aaaaaaaa-1\"}")
        let project = SendRef(sendID: id, review: Self.project)
        #expect(String(decoding: try encoder.encode(project), as: UTF8.self) == "{\"project\":\"launch-video\",\"sendID\":\"s-aaaaaaaa-1\"}")
        #expect(try JSONDecoder().decode(SendRef.self, from: encoder.encode(project)) == project)
        #expect(try JSONDecoder().decode(SendRef.self, from: encoder.encode(plain)) == plain)
    }
}
