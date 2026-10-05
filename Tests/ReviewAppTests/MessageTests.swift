import AVFoundation
import Foundation
import ImageIO
@testable import ReviewApp
import ReviewCore
import ReviewWire
import Testing

/// Messages on threads through the app's model, on the fixture video, in a
/// temporary support folder: the path a click and a CLI command share. No
/// window, no socket.
@Suite("Messages on threads", .serialized)
struct MessageTests {
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

    private func pngs() -> [String] {
        let videos = support.appendingPathComponent("videos")
        return ((try? FileManager.default.subpathsOfDirectory(atPath: videos.path)) ?? []).filter { $0.hasSuffix(".png") }.sorted()
    }

    @Test("a message from the CLI's path starts thread #1 with ids that carry the video, and a keyframe PNG of the video's size")
    func add() async throws {
        defer { cleanUp() }
        let model = try await model()
        let added = try await model.addMessage(text: " Too fast here ", at: 10)
        let hash = try #require(model.video?.contentHash)
        let hash8 = String(hash.prefix(8))

        #expect(added.message.id == "m-\(hash8)-1")
        #expect(added.thread.id == "t-\(hash8)-1")
        #expect(added.thread.number == 1)
        #expect(added.thread.time == 10)
        #expect(added.message.text == "Too fast here")
        #expect(added.message.state == "queued")
        #expect(added.message.author == "person" && added.message.kind == "message")
        let keyframe = try #require(added.thread.keyframePath)
        #expect(keyframe == support.appendingPathComponent("videos/\(hash)/frames/t-\(hash8)-1.png").path)
        let size = try size(of: keyframe)
        let track = try #require(try await AVURLAsset(url: Self.fixture).loadTracks(withMediaType: .video).first)
        let natural = try await track.load(.naturalSize)
        #expect(size.width == Int(natural.width))
        #expect(size.height == Int(natural.height))

        // As a person would: paused on the thread's frame, the thread selected.
        #expect(model.engine.time == 10)
        #expect(!model.engine.isPlaying)
        #expect(model.selection?.text == added.thread.id)
        let state = model.state()
        #expect(state.threads.map(\.number) == [0, 1])
        #expect(state.threads[1].messages == [added.message])
        #expect(state.threads[1].state == "queued")
        #expect(state.queue == [added.message.id])
        // Only the keyframe and nothing pending is left in the frames folder.
        #expect(pngs() == ["\(hash)/frames/t-\(hash8)-1.png"])
    }

    @Test("two messages at one frame are one thread, each region message with its own crop; another frame is a second thread")
    func oneThreadPerFrame() async throws {
        defer { cleanUp() }
        let model = try await model()
        let moment = try await model.addMessage(text: "The notes are small", at: 10)
        let box = try await model.addMessage(text: "This box", at: 10, region: try Region(x: 0.47, y: 0.27, w: 0.29, h: 0.15))
        let other = try await model.addMessage(text: "That box", at: nil, region: try Region(x: 0, y: 0, w: 0.5, h: 0.5))
        let later = try await model.addMessage(text: "Later", at: 12.5, region: try Region(x: 0.1, y: 0.1, w: 0.2, h: 0.2))

        #expect(moment.thread.id == box.thread.id && box.thread.id == other.thread.id)
        #expect(later.thread.number == 2)
        #expect(moment.message.cropPath == nil)
        let crop = try #require(box.message.cropPath)
        #expect(crop.hasSuffix("/crops/\(box.message.id).png"))
        // 0.29 × 0.15 of 1920 × 1080.
        #expect(try size(of: crop) == (557, 162))
        #expect(try size(of: #require(other.message.cropPath)) == (960, 540))
        let threads = model.state().threads
        #expect(threads.map(\.number) == [0, 1, 2])
        #expect(threads[1].messages.map(\.id) == [moment.message.id, box.message.id, other.message.id])
        // One keyframe per thread, one crop per region message.
        #expect(pngs().count == 2 + 3)
    }

    @Test("a message without a time is on the frame on screen: two moments inside one frame join one thread")
    func frameTime() async throws {
        defer { cleanUp() }
        let model = try await model()
        try await model.seek(to: 4)
        let first = try await model.addMessage(text: "Here", at: nil)
        // 4.02 s is still the frame that starts at 4 s, at 30 frames a second.
        try await model.seek(to: 4.02)
        let second = try await model.addMessage(text: "Same frame", at: nil)
        let third = try await model.addMessage(text: "Same frame by time", at: 4.03)
        #expect(first.thread.time == 4)
        #expect(second.thread.id == first.thread.id && third.thread.id == first.thread.id)
        let next = try await model.addMessage(text: "Next frame", at: 4.034)
        #expect(next.thread.number == 2)
        #expect(next.thread.time == 4.034)
    }

    @Test("--thread writes on that thread: a number or a full id, General with 0, and the player moves to the thread's frame")
    func onThread() async throws {
        defer { cleanUp() }
        let model = try await model()
        let first = try await model.addMessage(text: "first", at: 10)
        try await model.seek(to: 2)
        let byNumber = try await model.addMessage(text: "follow-up", at: nil, thread: "1")
        #expect(byNumber.thread.id == first.thread.id)
        #expect(model.engine.time == 10)
        let byID = try await model.addMessage(text: "again", at: nil, thread: first.thread.id)
        #expect(byID.thread.id == first.thread.id)
        let sameFrame = try await model.addMessage(text: "same frame", at: 10, thread: "1")
        #expect(sameFrame.thread.id == first.thread.id)

        try await model.seek(to: 5)
        let general = try await model.addMessage(text: "In general", at: nil, thread: "0")
        #expect(general.thread.number == 0)
        #expect(general.thread.time == nil)
        #expect(general.thread.keyframePath == nil)
        // General has no frame: the player stays.
        #expect(model.engine.time == 5)
        #expect(model.state().threads.map(\.number) == [0, 1])
    }

    @Test("what can't be done is refused before the player moves or a picture is written")
    func refusals() async throws {
        defer { cleanUp() }
        let model = try await model()
        await #expect(throws: AppRefusal("0:40 is outside the video (0:00 to 0:21.233)")) {
            try await model.addMessage(text: "late", at: 40)
        }
        await #expect(throws: AppRefusal("a message needs text")) { try await model.addMessage(text: "  ", at: 1) }
        await #expect(throws: AppRefusal(ReviewRefusal.unknownID("t-\(model.video!.contentHash.prefix(8))-3").line)) {
            try await model.addMessage(text: "x", at: nil, thread: "3")
        }
        await #expect(throws: AppRefusal(ReviewRefusal.otherVideo("t-0a1b2c3d-1").line)) {
            try await model.addMessage(text: "x", at: nil, thread: "t-0a1b2c3d-1")
        }
        await #expect(throws: AppRefusal.self) { try await model.addMessage(text: "x", at: nil, thread: "first") }
        await #expect(throws: AppRefusal(ReviewRefusal.noFrame.line)) {
            try await model.addMessage(text: "x", at: nil, region: try Region(x: 0, y: 0, w: 1, h: 1), thread: "0")
        }
        #expect(pngs().isEmpty)

        let first = try await model.addMessage(text: "first", at: 10)
        try await model.seek(to: 3)
        await #expect(throws: AppRefusal(ReviewRefusal.frameMismatch(try #require(ItemID(first.thread.id)), time: 15).line)) {
            try await model.addMessage(text: "x", at: 15, thread: "1")
        }
        #expect(model.engine.time == 3)
        #expect(pngs().count == 1)
        #expect(throws: AppRefusal.self) { try model.editMessage(first.thread.id, text: "x") }
        #expect(throws: AppRefusal.self) { try model.deleteMessage("nope") }

        let empty = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        await #expect(throws: AppRefusal.self) { try await empty.addMessage(text: "no video", at: nil) }
    }

    @Test("a message from the popover goes the same way, and the popover stays open on its thread with an empty field")
    func draft() async throws {
        defer { cleanUp() }
        let model = try await model()
        try await model.seek(to: 12.5)
        model.startDraft()
        #expect(model.draft == AppModel.Draft(time: 12.5, text: ""))
        #expect(model.state().popover == StateReport.Popover(thread: 1, time: 12.5, text: ""))

        // No words: Return leaves the popover open.
        model.commitDraft()
        #expect(model.draft != nil)

        model.draft?.text = "From the popover"
        model.commitDraft()
        #expect(model.draft == AppModel.Draft(time: 12.5, text: ""))
        await eventually { model.state().queue.count == 1 }
        let thread = try #require(model.state().threads.last)
        #expect(thread.time == 12.5)
        #expect(thread.messages.map(\.text) == ["From the popover"])
        #expect(try size(of: #require(thread.keyframePath)).width > 0)

        // The popover still open names the thread it now continues.
        #expect(model.state().popover?.thread == 1)
        #expect(model.draftThread?.messages.map(\.text) == ["From the popover"])
        model.draft?.text = "never mind"
        model.closePopover(.discard)
        #expect(model.draft == nil)
        #expect(model.state().queue.count == 1)
    }

    @Test("edit and delete change a queued message; deleting a thread's last message removes it and its keyframe")
    func editAndDelete() async throws {
        defer { cleanUp() }
        let model = try await model()
        let late = try await model.addMessage(text: "late", at: 15)
        let early = try await model.addMessage(text: "early", at: 2, region: try Region(x: 0, y: 0, w: 0.5, h: 0.5))
        let alsoEarly = try await model.addMessage(text: "also early", at: 2)
        #expect(model.state().queue == [early.message.id, alsoEarly.message.id, late.message.id])

        #expect(try model.editMessage(early.message.id, text: "earlier").text == "earlier")
        #expect(model.state().threads[1].messages.map(\.text) == ["earlier", "also early"])

        // The region message goes with its crop; its thread stays with its keyframe.
        #expect(try model.deleteMessage(early.message.id).id == early.message.id)
        #expect(!FileManager.default.fileExists(atPath: try #require(early.message.cropPath)))
        #expect(FileManager.default.fileExists(atPath: try #require(early.thread.keyframePath)))

        // The last message of #1 (at 15 s) goes, and the thread with it.
        try model.deleteMessage(late.message.id)
        #expect(model.state().threads.map(\.number) == [0, 2])
        #expect(!FileManager.default.fileExists(atPath: try #require(late.thread.keyframePath)))
        // Its number isn't given again.
        #expect(try await model.addMessage(text: "new", at: 15).thread.number == 3)
    }

    @Test("selecting a thread moves the player to its frame; Up and Down walk the pins")
    func markers() async throws {
        defer { cleanUp() }
        let model = try await model()
        let first = try await model.addMessage(text: "first", at: 2)
        let second = try await model.addMessage(text: "second", at: 15)
        try await model.addMessage(text: "general", at: nil, thread: "0")
        let firstID = try #require(ItemID(first.thread.id))

        model.select(firstID)
        await eventually { model.engine.time == 2 }
        #expect(model.engine.time == 2)
        #expect(model.selection == firstID)

        model.jumpToMarker(forward: true)
        await eventually { model.engine.time == 15 }
        #expect(model.selection?.text == second.thread.id)
        // No pin after the last one; General has none.
        model.jumpToMarker(forward: true)
        #expect(model.selection?.text == second.thread.id)
        model.jumpToMarker(forward: false)
        await eventually { model.engine.time == 2 }
        #expect(model.selection == firstID)
    }

    @Test("the popover frame of a thread is kept")
    func popoverFrame() async throws {
        defer { cleanUp() }
        let model = try await model()
        let added = try await model.addMessage(text: "first", at: 2)
        let frame = PopoverFrame(x: 0.6, y: 0.1, w: 0.3, h: 0.4)
        try model.movePopover(try #require(ItemID(added.thread.id)), to: frame)
        #expect(model.state().threads[1].popoverFrame == frame)
    }

    @Test("a video that opens again in the same run has its threads back")
    func reopen() async throws {
        defer { cleanUp() }
        let model = try await model()
        let added = try await model.addMessage(text: "kept", at: 2)
        try await model.open(Self.fixture)
        #expect(model.state().threads.last?.messages == [added.message])
        #expect(model.selection == nil)
    }

    @Test("a thread's key is the start of the frame on screen, raised to the next millisecond")
    func frameTimes() {
        let thirty = 1.0 / 30
        // A frame at 30 a second starts at 7.2333… s: 7.233 would name the frame before it.
        #expect(PlayerEngine.frameTime(of: 217.0 / 30, frameDuration: thirty, duration: 21.233) == 7.234)
        #expect(PlayerEngine.frameTime(of: 7.25, frameDuration: thirty, duration: 21.233) == 7.234)
        #expect(PlayerEngine.frameTime(of: 10, frameDuration: thirty, duration: 21.233) == 10)
        #expect(PlayerEngine.frameTime(of: 10.000_000_000_2, frameDuration: thirty, duration: 21.233) == 10)
        #expect(PlayerEngine.frameTime(of: 10.033, frameDuration: thirty, duration: 21.233) == 10)
        // The end is past the last frame (637 frames), which it names.
        #expect(PlayerEngine.frameTime(of: 21.233, frameDuration: thirty, duration: 21.233) == 21.2)
        #expect(PlayerEngine.frameTime(of: -0.01, frameDuration: thirty, duration: 21.233) == 0)
        // At 29.97 frames a second the third frame starts at 0.066733… s.
        #expect(PlayerEngine.frameTime(of: 0.07, frameDuration: 1001.0 / 30000, duration: 10) == 0.067)
    }

    @Test("the last moment of the video still has a frame")
    func atTheEnd() async throws {
        defer { cleanUp() }
        let model = try await model()
        let added = try await model.addMessage(text: "the end", at: model.engine.duration)
        #expect(try size(of: #require(added.thread.keyframePath)).width > 0)
    }

    @Test("the player and the keyframe are asked for a time to the millisecond, so both show the thread's frame")
    func exactTime() {
        // At 29.97 frames a second the third frame starts at 0.066733… s, and
        // its thread is at 0.067 s. A coarser time (0.0666… s in 600ths)
        // would name the frame before it.
        let frameStart = 2 * 1001.0 / 30000
        #expect(PlayerEngine.exact(0.067) == CMTime(value: 4020, timescale: 60_000))
        #expect(PlayerEngine.exact(0.067).seconds >= frameStart)
        #expect(PlayerEngine.exact(7.234) == CMTime(value: 434_040, timescale: 60_000))
        #expect(PlayerEngine.exact(21.233).seconds == 21.233)
    }

    @Test("the comment popover stays inside the stage, with its notch on the player bar's playhead")
    func composerPlacement() {
        let middle = Composer.placement(playhead: 500, stageWidth: 1000)
        #expect(middle.leading == 500 - Composer.width / 2)
        #expect(middle.notch == Composer.width / 2)
        let start = Composer.placement(playhead: 0, stageWidth: 1000)
        #expect(start.leading == 10)
        #expect(start.notch == 22)
        let end = Composer.placement(playhead: 1000, stageWidth: 1000)
        #expect(end.leading == 1000 - Composer.width - 10)
        #expect(end.notch == Composer.width - 22)

        // The track sits in the bar between its buttons, not under the
        // stage's whole width: the playhead is on the track.
        let stage = CGRect(x: 12, y: 40, width: 1000, height: 560)
        let track = CGRect(x: 160, y: 620, width: 700, height: 30)
        #expect(Composer.playhead(fraction: 0, track: track, stage: stage) == 148)
        #expect(Composer.playhead(fraction: 0.5, track: track, stage: stage) == 498)
        #expect(Composer.playhead(fraction: 1, track: track, stage: stage) == 848)
        // Before the track is laid out, the stage stands for it.
        #expect(Composer.playhead(fraction: 0.5, track: .zero, stage: stage) == 500)
    }
}
