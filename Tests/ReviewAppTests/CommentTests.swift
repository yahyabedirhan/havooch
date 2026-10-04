import AVFoundation
import Foundation
import ImageIO
@testable import ReviewApp
import ReviewCore
import ReviewWire
import Testing

/// Comments through the app's model, on the fixture video, in a temporary
/// support folder: the path a click and a CLI command share. No window, no
/// socket.
@Suite("Comments on a video", .serialized)
@MainActor
struct CommentTests {
    static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/sample/sample.mp4")

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("video-review-tests-\(UUID().uuidString)", isDirectory: true)

    private func model() async throws -> AppModel {
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        try await model.open(Self.fixture)
        return model
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    private func size(of png: String) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: png) as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    /// Waits until `condition` holds: the person's gestures finish in a task.
    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("a comment from the CLI's path has an id, its time, its text and a keyframe PNG of the video's size")
    func add() async throws {
        defer { cleanUp() }
        let model = try await model()
        let comment = try await model.addComment(text: " Too fast here ", at: 10)

        #expect(ItemID(comment.id)?.kind == .comment)
        #expect(comment.time == 10)
        #expect(comment.text == "Too fast here")
        #expect(comment.state == "queued")
        let hash = try #require(model.video?.contentHash)
        #expect(comment.keyframePath == support.appendingPathComponent("videos/\(hash)/frames/\(comment.id).png").path)
        let size = try size(of: comment.keyframePath)
        let track = try #require(try await AVURLAsset(url: Self.fixture).loadTracks(withMediaType: .video).first)
        let natural = try await track.load(.naturalSize)
        #expect(size.width == Int(natural.width))
        #expect(size.height == Int(natural.height))

        // As a person would: paused at the comment's time, the comment selected.
        #expect(model.engine.time == 10)
        #expect(!model.engine.isPlaying)
        #expect(model.selection?.text == comment.id)
        #expect(model.state().comments == [comment])
        #expect(model.state().queue == [comment.id])
    }

    @Test("a comment without a time is at the player's time")
    func atPlayerTime() async throws {
        defer { cleanUp() }
        let model = try await model()
        try await model.seek(to: 4)
        let comment = try await model.addComment(text: "Here", at: nil)
        #expect(comment.time == 4)
    }

    @Test("a comment from the comment box goes the same way, and the box closes")
    func draft() async throws {
        defer { cleanUp() }
        let model = try await model()
        try await model.seek(to: 12.5)
        model.startDraft()
        #expect(model.draft == AppModel.Draft(time: 12.5, text: ""))
        #expect(model.state().draft == StateReport.Draft(time: 12.5, text: ""))

        // No words: Return leaves the box open.
        model.commitDraft()
        #expect(model.draft != nil)

        model.draft?.text = "From the box"
        model.commitDraft()
        #expect(model.draft == nil)
        await eventually { !model.comments.isEmpty }
        let comment = try #require(model.state().comments.first)
        #expect(comment.time == 12.5)
        #expect(comment.text == "From the box")
        #expect(try size(of: comment.keyframePath).width > 0)

        // Escape drops the draft.
        model.startDraft()
        model.draft?.text = "never mind"
        model.cancelDraft()
        #expect(model.draft == nil)
        #expect(model.comments.count == 1)
    }

    @Test("the keyframe is the frame at the comment's time: two times give two pictures, one time gives one")
    func rightFrame() async throws {
        defer { cleanUp() }
        let model = try await model()
        let early = try await model.addComment(text: "early", at: 2)
        let late = try await model.addComment(text: "late", at: 15)
        let again = try await model.addComment(text: "early again", at: 2)
        let pixels = try [early, late, again].map { try Self.pixels(of: $0.keyframePath) }
        #expect(pixels[0] != pixels[1])
        #expect(pixels[0] == pixels[2])
    }

    @Test("the last moment of the video still has a frame")
    func atTheEnd() async throws {
        defer { cleanUp() }
        let model = try await model()
        let comment = try await model.addComment(text: "the end", at: model.engine.duration)
        #expect(try size(of: comment.keyframePath).width > 0)
    }

    @Test("state lists comments in time order; edit and delete change the queue")
    func editAndDelete() async throws {
        defer { cleanUp() }
        let model = try await model()
        let late = try await model.addComment(text: "late", at: 15)
        let early = try await model.addComment(text: "early", at: 2)
        #expect(model.state().comments.map(\.id) == [early.id, late.id])
        #expect(model.state().queue == [early.id, late.id])

        #expect(try model.editComment(early.id, text: "earlier").text == "earlier")
        #expect(model.state().comments.map(\.text) == ["earlier", "late"])

        #expect(try model.deleteComment(late.id).id == late.id)
        #expect(model.state().queue == [early.id])
        #expect(!FileManager.default.fileExists(atPath: late.keyframePath))
        #expect(FileManager.default.fileExists(atPath: early.keyframePath))
    }

    @Test("what can't be done is refused before anything changes")
    func refusals() async throws {
        defer { cleanUp() }
        let model = try await model()
        await #expect(throws: AppRefusal("0:40 is outside the video (0:00 to 0:21.233)")) {
            try await model.addComment(text: "late", at: 40)
        }
        await #expect(throws: AppRefusal("a comment needs text")) { try await model.addComment(text: "  ", at: 1) }
        #expect(throws: AppRefusal.self) { try model.editComment("c-00000000", text: "x") }
        #expect(throws: AppRefusal.self) { try model.deleteComment("nope") }
        #expect(model.comments.isEmpty)
        #expect(model.engine.time == 0)
        let frames = support.appendingPathComponent("videos")
        #expect((try? FileManager.default.subpathsOfDirectory(atPath: frames.path))?.contains { $0.hasSuffix(".png") } != true)

        let empty = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        await #expect(throws: AppRefusal.self) { try await empty.addComment(text: "no video", at: nil) }
    }

    @Test("selecting a comment moves the player to it; Up and Down walk the markers")
    func markers() async throws {
        defer { cleanUp() }
        let model = try await model()
        let first = try await model.addComment(text: "first", at: 2)
        let second = try await model.addComment(text: "second", at: 15)
        let firstID = try #require(ItemID(first.id))

        model.select(firstID)
        await eventually { model.engine.time == 2 }
        #expect(model.engine.time == 2)
        #expect(model.selection == firstID)

        model.jumpToMarker(forward: true)
        await eventually { model.engine.time == 15 }
        #expect(model.selection?.text == second.id)
        // No marker after the last one.
        model.jumpToMarker(forward: true)
        #expect(model.selection?.text == second.id)
        model.jumpToMarker(forward: false)
        await eventually { model.engine.time == 2 }
        #expect(model.selection == firstID)
    }

    @Test("a video that opens again in the same run has its comments back")
    func reopen() async throws {
        defer { cleanUp() }
        let model = try await model()
        let comment = try await model.addComment(text: "kept", at: 2)
        try await model.open(Self.fixture)
        #expect(model.state().comments == [comment])
        #expect(model.selection == nil)
    }

    @Test("a comment's time is the player's to the millisecond, never before the frame on screen")
    func commentTime() {
        // A frame at 30 a second starts at 7.2333… s: 7.233 would name the frame before it.
        #expect(AppModel.commentTime(player: 217.0 / 30, duration: 21.233) == 7.234)
        #expect(AppModel.commentTime(player: 10, duration: 21.233) == 10)
        #expect(AppModel.commentTime(player: 10.000_000_000_2, duration: 21.233) == 10)
        #expect(AppModel.commentTime(player: 21.2331, duration: 21.233) == 21.233)
        #expect(AppModel.commentTime(player: -0.01, duration: 21.233) == 0)
    }

    @Test("the comment box stays inside the stage, with its notch on the playhead")
    func composerPlacement() {
        let middle = Composer.placement(fraction: 0.5, stageWidth: 1000)
        #expect(middle.leading == 500 - Composer.width / 2)
        #expect(middle.notch == Composer.width / 2)
        let start = Composer.placement(fraction: 0, stageWidth: 1000)
        #expect(start.leading == 10)
        #expect(start.notch == 22)
        let end = Composer.placement(fraction: 1, stageWidth: 1000)
        #expect(end.leading == 1000 - Composer.width - 10)
        #expect(end.notch == Composer.width - 22)
    }

    /// The picture's bytes, decoded.
    private static func pixels(of png: String) throws -> Data {
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: png) as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try #require(image.dataProvider?.data) as Data
    }
}
