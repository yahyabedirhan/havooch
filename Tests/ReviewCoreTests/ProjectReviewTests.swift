import Foundation
import ReviewCore
import Testing

/// A project's review: a plain video's
/// review moves into a project with its ids, every thread anchored to v1;
/// threads are anchored to the version they were raised on and found by
/// frame per version; a path that left the list is a removed version; the
/// payload carries the project.
@Suite("A project's review")
struct ProjectReviewTests {
    static let cut1 = VersionAnchor(path: "/Movies/cut1.mp4")
    static let cut2 = VersionAnchor(path: "/Movies/cut2.mp4")
    static let video2 = VideoInfo(contentHash: "0badc0de99", title: "cut2.mp4", duration: 30, path: "/Movies/cut2.mp4")

    static let outline = ProjectOutline(
        slug: "launch-video", title: "Launch video",
        versions: [.init(path: cut1.path), .init(path: cut2.path, label: "tighter intro")]
    )

    /// The sample's review with one thread at 0:10, adopted into the project as v1.
    private func adopted() throws -> Review {
        var review = newReview()
        try review.write(text: "Too fast here", at: 10, now: now)
        return review.adoptedIntoProject("launch-video", anchor: Self.cut1)
    }

    @Test("moving into a project keeps the ids and anchors every thread on a frame to v1; General stays the project's")
    func adoption() throws {
        let plain = newReview()
        let review = try adopted()
        #expect(review.key == .project(slug: "launch-video"))
        #expect(review.hash8 == plain.hash8)
        #expect(review.threads.map(\.id) == [thread(0), thread(1)])
        #expect(review.threads.map(\.anchor) == [nil, Self.cut1])
        #expect(review.video.path == Self.cut1.path)
        #expect(review.versions.map(\.path) == [Self.cut1.path])
        #expect(review.nextThreadNumber == 2)
    }

    @Test("two versions each have their own thread at 0:10, and a new thread is anchored to the version on screen")
    func perVersion() throws {
        var review = try adopted()
        review.show(Self.video2)
        let written = try review.write(text: "Better, but the logo", at: 10, on: Self.cut2, now: now)
        #expect(written.startedThread)
        #expect(written.thread.id == thread(2))
        #expect(written.thread.anchor == Self.cut2)
        #expect(review.thread(atFrame: 10, on: Self.cut1)?.id == thread(1))
        #expect(review.thread(atFrame: 10, on: Self.cut2)?.id == thread(2))
        // A follow-up joins its thread wherever it's anchored.
        let followUp = try review.write(text: "Still too fast", at: nil, to: thread(1), on: Self.cut2, now: now)
        #expect(followUp.thread.id == thread(1))
        #expect(review.video(at: Self.cut2.path)?.contentHash == "0badc0de99")
        #expect(review.versions.map(\.path) == [Self.cut1.path, Self.cut2.path])
    }

    @Test("a thread's tag is its version's number in the list as it is now, or a removed version; the thread stays")
    func tags() {
        #expect(Self.outline.tag(Self.cut1) == .number(1))
        #expect(Self.outline.tag(Self.cut2) == .number(2))
        let edited = ProjectOutline(slug: "launch-video", title: "Launch video", versions: [.init(path: Self.cut2.path)])
        #expect(edited.tag(Self.cut1) == .removed)
        #expect(edited.tag(Self.cut1).label == "Removed version")
        #expect(edited.tag(Self.cut2).label == "v1")
    }

    @Test("a project's review reads back as it was kept, and one kept before projects is a plain video's")
    func coding() throws {
        var review = try adopted()
        review.show(Self.video2)
        try review.write(text: "Logo", at: 3, on: Self.cut2, now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(review)
        #expect(try decoder.decode(Review.self, from: data) == review)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["project"] as? String == "launch-video")
        #expect(object["hash8"] as? String == "f92cbb2a")

        var older = try #require(JSONSerialization.jsonObject(with: encoder.encode(newReview())) as? [String: Any])
        older["hash8"] = nil
        let read = try decoder.decode(Review.self, from: JSONSerialization.data(withJSONObject: older))
        #expect(read.key == .video(contentHash: hash))
        #expect(read.hash8 == "f92cbb2a")
    }

    @Test("a new project's review takes the prefix it's given, so a second project with the same video starts fresh")
    func freshProject() {
        let review = Review(project: "teaser", video: newReview().video, hash8: "0123abcd")
        #expect(review.threads.map(\.id.text) == ["t-0123abcd-0"])
        #expect(review.versions.count == 1)
    }

    @Test("the payload of a project's send carries the project, the version on screen and each thread's version")
    func payload() throws {
        var review = try adopted()
        review.show(Self.video2)
        try review.write(text: "Logo too small", at: 3, on: Self.cut2, now: now)
        try review.write(text: "Still too fast", at: nil, to: thread(1), on: Self.cut2, now: now)
        let sent = try review.send(at: now, onScreen: Self.cut2)
        let images = SendPayload.Images(keyframe: { "/frames/\($0.id.text).png" }, crop: { _ in nil })
        let payload = SendPayload.assemble(review: review, send: sent, context: nil, images: images, project: Self.outline)
        #expect(payload.video.path == Self.cut2.path)
        #expect(payload.video.contentHash == "0badc0de99")
        #expect(payload.project?.slug == "launch-video")
        #expect(payload.project?.title == "Launch video")
        #expect(payload.project?.onScreen == 2)
        #expect(payload.project?.versions.map(\.number) == [1, 2])
        #expect(payload.project?.versions.map(\.label) == [nil, "tighter intro"])
        #expect(payload.threads.map(\.version?.number) == [2, 1])

        // A path that left the list: the thread names its file with no number.
        let edited = ProjectOutline(slug: "launch-video", title: "Launch video", versions: [.init(path: Self.cut2.path)])
        let later = SendPayload.assemble(review: review, send: sent, context: nil, images: images, project: edited)
        #expect(later.threads.map(\.version?.number) == [1, nil])
        #expect(later.threads.last?.version?.path == Self.cut1.path)
        let json = try #require(JSONSerialization.jsonObject(with: Data(later.json.utf8)) as? [String: Any])
        let threads = try #require(json["threads"] as? [[String: Any]])
        #expect((threads.last?["version"] as? [String: Any])?["number"] is NSNull)
    }

    @Test("an outbox moved to the project names the project in its sends, keeps its session and its context")
    func rekeyedOutbox() throws {
        let video = ReviewKey.video(contentHash: hash)
        let project = ReviewKey.project(slug: "launch-video")
        var outbox = Outbox()
        outbox.enqueue(SendRef(sendID: send(1), review: video))
        outbox.waitOpened(by: ListenerSession(key: "claude-1", name: "Claude Code", place: "/shop"), at: now)
        _ = outbox.context(for: video.contextKey, text: "The launch film")
        let moved = outbox.rekeyed(from: video, to: project)
        #expect(moved.pending == [SendRef(sendID: send(1), review: project)])
        #expect(moved.session?.name == "Claude Code")
        #expect(moved.isWaitOpen)
        #expect(!moved.isContextDue(for: project.contextKey, text: "The launch film"))
        #expect(project.contextKey == "project-launch-video")
        #expect(project.holds(SendRef(sendID: send(1), review: project)))
        #expect(!video.holds(SendRef(sendID: send(1), review: project)))
    }
}
