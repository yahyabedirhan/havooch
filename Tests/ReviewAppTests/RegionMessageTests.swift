import AVFoundation
import AppKit
import Foundation
import ImageIO
@testable import ReviewApp
import ReviewCore
import ReviewWire
import Testing

/// The way between the stage's points and a region's frame coordinates:
/// pure geometry, no window.
@Suite("A region on the stage")
struct VideoFrameGeometryTests {
    static let video = CGSize(width: 1920, height: 1080)

    @Test("the picture is fitted whole and centred: letterboxed on a tall stage, pillarboxed on a wide one")
    func frame() {
        #expect(VideoFrameGeometry(stage: CGSize(width: 960, height: 540), video: Self.video).frame
            == CGRect(x: 0, y: 0, width: 960, height: 540))
        #expect(VideoFrameGeometry(stage: CGSize(width: 960, height: 740), video: Self.video).frame
            == CGRect(x: 0, y: 100, width: 960, height: 540))
        #expect(VideoFrameGeometry(stage: CGSize(width: 1160, height: 540), video: Self.video).frame
            == CGRect(x: 100, y: 0, width: 960, height: 540))
        // Before the video's size is known the picture is the stage.
        #expect(VideoFrameGeometry(stage: CGSize(width: 800, height: 600), video: .zero).frame
            == CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    @Test("a region is on the same part of the picture at any window size", arguments: [
        CGSize(width: 960, height: 540), CGSize(width: 960, height: 740), CGSize(width: 1160, height: 540),
        CGSize(width: 480, height: 270), CGSize(width: 1733, height: 911), CGSize(width: 400, height: 900),
    ])
    func sameAtAnySize(stage: CGSize) throws {
        let region = try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        let geometry = VideoFrameGeometry(stage: stage, video: Self.video)
        let rect = geometry.rect(of: region)
        // The rectangle's place as fractions of the picture, not of the stage.
        #expect(abs((rect.minX - geometry.frame.minX) / geometry.frame.width - 0.25) < 1e-9)
        #expect(abs((rect.minY - geometry.frame.minY) / geometry.frame.height - 0.2) < 1e-9)
        #expect(abs(rect.width / geometry.frame.width - 0.3) < 1e-9)
        #expect(abs(rect.height / geometry.frame.height - 0.25) < 1e-9)
        // Drawn over that rectangle at this size, it's the same region again.
        #expect(geometry.region(from: rect.origin, to: CGPoint(x: rect.maxX, y: rect.maxY)) == region)
    }

    @Test("a drag gives the same region in any direction")
    func anyDirection() throws {
        let geometry = VideoFrameGeometry(stage: CGSize(width: 960, height: 740), video: Self.video)
        let region = try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        let corners = [CGPoint(x: 240, y: 208), CGPoint(x: 528, y: 343)]
        #expect(geometry.region(from: corners[0], to: corners[1]) == region)
        #expect(geometry.region(from: corners[1], to: corners[0]) == region)
        #expect(geometry.region(from: CGPoint(x: 528, y: 208), to: CGPoint(x: 240, y: 343)) == region)
    }

    @Test("a drag that leaves the picture is kept inside it")
    func clamped() throws {
        let geometry = VideoFrameGeometry(stage: CGSize(width: 960, height: 740), video: Self.video)
        // From the letterbox above the picture to past the stage's corner.
        #expect(geometry.region(from: CGPoint(x: 480, y: 20), to: CGPoint(x: 2000, y: 2000))
            == (try Region(x: 0.5, y: 0, w: 0.5, h: 1)))
        #expect(geometry.region(from: CGPoint(x: -50, y: -50), to: CGPoint(x: 96, y: 154))
            == (try Region(x: 0, y: 0, w: 0.1, h: 0.1)))
        // Wholly in the letterbox: nothing of the picture.
        #expect(geometry.region(from: CGPoint(x: 100, y: 10), to: CGPoint(x: 400, y: 90)) == nil)
    }

    @Test("a rectangle under 8 points either way isn't a region; a press that moves under 4 points is a click")
    func tooSmall() {
        let geometry = VideoFrameGeometry(stage: CGSize(width: 960, height: 540), video: Self.video)
        #expect(geometry.region(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 107, y: 300)) == nil)
        #expect(geometry.region(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 107)) == nil)
        #expect(geometry.region(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 108, y: 108)) != nil)
        #expect(!VideoFrameGeometry.isDrag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 102)))
        #expect(VideoFrameGeometry.isDrag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 104, y: 100)))
    }

    @Test("a drawn region's numbers have four decimals")
    func rounded() throws {
        let geometry = VideoFrameGeometry(stage: CGSize(width: 997, height: 561), video: Self.video)
        let region = try #require(geometry.region(from: CGPoint(x: 101, y: 33), to: CGPoint(x: 333, y: 222)))
        for value in [region.x, region.y, region.w, region.h] {
            #expect(abs(value * 10_000 - (value * 10_000).rounded()) < 1e-6)
        }
    }

    @Test("the comment box is right of the region, else left, else below, else above, and always inside the stage")
    func composerPlacement() {
        let stage = CGSize(width: 1000, height: 560)
        let box = CGSize(width: 340, height: 150)
        // Room on the right: beside the rectangle, level with its top.
        #expect(Composer.placement(beside: CGRect(x: 100, y: 80, width: 300, height: 200), box: box, stage: stage)
            == CGPoint(x: 412, y: 80))
        // None on the right: on the left.
        #expect(Composer.placement(beside: CGRect(x: 600, y: 80, width: 300, height: 200), box: box, stage: stage)
            == CGPoint(x: 248, y: 80))
        // A wide rectangle: below it.
        #expect(Composer.placement(beside: CGRect(x: 50, y: 40, width: 900, height: 200), box: box, stage: stage)
            == CGPoint(x: 50, y: 252))
        // Wide and low: above it.
        #expect(Composer.placement(beside: CGRect(x: 50, y: 300, width: 900, height: 240), box: box, stage: stage)
            == CGPoint(x: 50, y: 138))
        // The whole frame: the lower right corner.
        #expect(Composer.placement(beside: CGRect(origin: .zero, size: stage), box: box, stage: stage)
            == CGPoint(x: 648, y: 398))
        // A rectangle at the foot of the stage: the box stays inside.
        #expect(Composer.placement(beside: CGRect(x: 100, y: 500, width: 200, height: 50), box: box, stage: stage)
            == CGPoint(x: 312, y: 398))
        for rect in [CGRect(x: 0, y: 0, width: 20, height: 20), CGRect(x: 980, y: 540, width: 20, height: 20),
                     CGRect(x: 0, y: 540, width: 1000, height: 20), CGRect(x: 400, y: 200, width: 200, height: 100)] {
            let origin = Composer.placement(beside: rect, box: box, stage: stage)
            #expect(CGRect(origin: .zero, size: stage).contains(CGRect(origin: origin, size: box)), "\(rect)")
        }
    }
}

/// Region messages through the app's model, on the fixture video, in a
/// temporary support folder. No window, no socket.
@Suite("Messages on a region", .serialized)
struct RegionMessageTests {
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("video-review-tests-\(UUID().uuidString)", isDirectory: true)

    private func model() async throws -> AppModel {
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        try await model.open(MessageTests.fixture)
        return model
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    private func image(_ png: String) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: png) as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// The picture's pixels as RGBA bytes, whatever the file's layout.
    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("a message on a region keeps the region and a crop PNG that is that part of its thread's keyframe")
    func crop() async throws {
        defer { cleanUp() }
        let model = try await model()
        let region = try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        let added = try await model.addMessage(text: "This box", at: 12.5, region: region)
        let comment = added.message

        #expect(comment.region == region)
        let hash = try #require(model.video?.contentHash)
        let cropPath = try #require(comment.cropPath)
        #expect(cropPath == support.appendingPathComponent("videos/\(hash)/crops/\(comment.id).png").path)

        let keyframe = try image(try #require(added.thread.keyframePath))
        let crop = try image(cropPath)
        let part = region.pixels(width: keyframe.width, height: keyframe.height)
        #expect(crop.width == part.width)
        #expect(crop.height == part.height)
        let same = try #require(keyframe.cropping(to: CGRect(x: part.x, y: part.y, width: part.width, height: part.height)))
        #expect(try pixels(crop) == pixels(same))
        // It's a part of the picture, not the picture made small.
        #expect(crop.width < keyframe.width)
        #expect(model.state().threads.last?.messages == [comment])

        // A message on the whole frame has neither.
        let plain = try await model.addMessage(text: "Too fast", at: 3).message
        #expect(plain.region == nil)
        #expect(plain.cropPath == nil)
    }

    @Test("the crop is the same picture from the popover and from the CLI's path")
    func sameFromBoth() async throws {
        defer { cleanUp() }
        let model = try await model()
        let region = try Region(x: 0.1, y: 0.55, w: 0.42, h: 0.3)
        let fromCLI = try await model.addMessage(text: "from the CLI", at: 12.5, region: region).message

        // As a person does: at the same moment, drag, write, Return.
        try await model.seek(to: 12.5)
        model.beginRegion()
        model.endRegion(region)
        #expect(model.draft == AppModel.Draft(time: 12.5, text: "", region: region))
        #expect(model.state().popover == StateReport.Popover(thread: 1, time: 12.5, text: "", region: region))
        model.draft?.text = "from the box"
        model.commitDraft()
        await eventually { model.state().queue.count == 2 }
        let thread = try #require(model.state().threads.last)
        let fromBox = try #require(thread.messages.first { $0.text == "from the box" })

        // One frame, one thread.
        #expect(thread.messages.count == 2)
        #expect(fromBox.region == fromCLI.region)
        let (a, b) = (try image(try #require(fromCLI.cropPath)), try image(try #require(fromBox.cropPath)))
        #expect(a.width == b.width)
        #expect(a.height == b.height)
        #expect(try pixels(a) == pixels(b))
    }

    @Test("starting to drag pauses the video; letting go opens the comment box on the region")
    func dragPauses() async throws {
        defer { cleanUp() }
        let model = try await model()
        try model.play()
        await eventually { model.engine.isPlaying }
        #expect(model.engine.isPlaying)

        model.beginRegion()
        #expect(model.isDrawingRegion)
        await eventually { !model.engine.isPlaying }
        #expect(!model.engine.isPlaying)
        // No comment box until the pointer lets go.
        #expect(model.draft == nil)

        let region = try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        model.endRegion(region)
        #expect(!model.isDrawingRegion)
        #expect(model.draft?.region == region)
        #expect(model.draft?.text == "")
        #expect(model.state().popover?.region == region)
        #expect(!model.engine.isPlaying)
    }

    @Test("Escape cancels the region: while it's drawn, and once the comment box is open")
    func escape() async throws {
        defer { cleanUp() }
        let model = try await model()
        let region = try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)

        // While the rectangle is drawn: letting go afterwards opens nothing.
        model.beginRegion()
        #expect(model.escape())
        #expect(!model.isDrawingRegion)
        model.endRegion(region)
        #expect(model.draft == nil)

        // With the comment box open: the box and the region go, and nothing is queued.
        model.beginRegion()
        model.endRegion(region)
        model.draft?.text = "never mind"
        #expect(model.escape())
        #expect(model.draft == nil)
        #expect(model.state().popover == nil)
        #expect(model.state().queue.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("videos").path))

        // With nothing to cancel, Escape isn't taken.
        #expect(!model.escape())
        // The key itself: Escape cancels unless a text view has it, where it's the editor's cancel.
        #expect(Shortcuts.action(keyCode: 53, modifiers: []) == .cancel)
        #expect(Shortcuts.action(keyCode: 53, modifiers: [], isTyping: true) == nil)
        #expect(MessageEditor.keyAction(for: #selector(NSResponder.cancelOperation(_:)), shift: false) == .cancel)
    }

    @Test("a rectangle too small to be a region opens nothing, and a click still plays and pauses")
    func tooSmallAndClick() async throws {
        defer { cleanUp() }
        let model = try await model()
        model.beginRegion()
        model.endRegion(nil)
        #expect(model.draft == nil)
        #expect(!model.isDrawingRegion)

        model.clickFrame()
        await eventually { model.engine.isPlaying }
        #expect(model.engine.isPlaying)
        model.clickFrame()
        await eventually { !model.engine.isPlaying }
        #expect(!model.engine.isPlaying)

        // While the popover is open, a click on the frame is a click
        // outside it: the popover closes and the frame stays where it is.
        model.startDraft()
        model.clickFrame()
        #expect(model.draft == nil)
        #expect(!model.engine.isPlaying)
    }

    @Test("drawing again while the popover is open is a click outside it: words are queued on their region, an empty popover just closes")
    func redraw() async throws {
        defer { cleanUp() }
        let model = try await model()
        let first = try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        let second = try Region(x: 0.5, y: 0.5, w: 0.2, h: 0.2)
        let third = try Region(x: 0.1, y: 0.1, w: 0.2, h: 0.2)
        model.beginRegion()
        model.endRegion(first)
        // An empty popover goes with its region; the new one opens on the new region.
        model.beginRegion()
        #expect(model.draft == nil)
        model.endRegion(second)
        #expect(model.draft == AppModel.Draft(time: 0, text: "", region: second))
        // C with the popover open changes nothing.
        model.startDraft()
        #expect(model.draft?.region == second)

        model.draft?.text = "this one"
        model.beginRegion()
        model.endRegion(third)
        #expect(model.draft == AppModel.Draft(time: 0, text: "", region: third))
        await eventually { model.state().queue.count == 1 }
        let queued = try #require(model.state().threads.last?.messages.last)
        #expect(queued.text == "this one")
        #expect(queued.region == second)
    }

    @Test("the threads on the frame on screen show their region outlines and their badge, and only on that frame")
    func frameMarks() async throws {
        defer { cleanUp() }
        let model = try await model()
        let region = try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        let other = try Region(x: 0.6, y: 0.6, w: 0.2, h: 0.2)
        let plain = try await model.addMessage(text: "Too fast", at: 3)
        let pointed = try await model.addMessage(text: "This box", at: 12.5, region: region)
        _ = try await model.addMessage(text: "And this one", at: 12.5, region: other)
        _ = try await model.addMessage(text: "The whole frame", at: 12.5)
        let pointedID = try #require(ItemID(pointed.thread.id))
        // The player is on #2's frame: one badge, two outlines.
        #expect(model.frameMarks == [AppModel.FrameMark(thread: pointedID, number: 2, state: .queued, regions: [region, other])])

        model.select(try #require(ItemID(plain.thread.id)))
        await eventually { model.engine.time == 3 }
        #expect(model.frameMarks.map(\.number) == [1])
        #expect(model.frameMarks.first?.regions == [])

        // Another frame isn't the one the threads were written on.
        try await model.seek(to: 14)
        #expect(model.frameMarks.isEmpty)
        // One frame later is another frame too.
        try await model.seek(to: 12.5 + model.engine.frameDuration)
        #expect(model.frameMarks.isEmpty)
    }

    @Test("the size of a rectangle being drawn is in the video's pixels, at any size the picture is shown at")
    func sizeLabel() {
        let video = CGSize(width: 1920, height: 1080)
        let small = CGRect(x: 0, y: 0, width: 960, height: 540)
        #expect(RegionOverlay.size(of: CGRect(x: 10, y: 10, width: 206, height: 118), within: small, video: video) == "412 × 236")
        let large = CGRect(x: 100, y: 0, width: 1920, height: 1080)
        #expect(RegionOverlay.size(of: CGRect(x: 300, y: 10, width: 412, height: 236), within: large, video: video) == "412 × 236")
        #expect(RegionOverlay.size(of: small, within: small, video: .zero) == nil)
    }

    @Test("deleting the only message, on a region, removes its crop, and its thread's keyframe with the thread")
    func delete() async throws {
        defer { cleanUp() }
        let model = try await model()
        let added = try await model.addMessage(text: "This box", at: 12.5, region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25))
        let crop = try #require(added.message.cropPath)
        #expect(FileManager.default.fileExists(atPath: crop))
        _ = try model.deleteMessage(added.message.id)
        #expect(!FileManager.default.fileExists(atPath: crop))
        #expect(!FileManager.default.fileExists(atPath: try #require(added.thread.keyframePath)))
    }

    @Test("the player knows the picture's size")
    func videoSize() async throws {
        defer { cleanUp() }
        let model = try await model()
        let track = try #require(try await AVURLAsset(url: MessageTests.fixture).loadTracks(withMediaType: .video).first)
        #expect(model.engine.videoSize == (try await track.load(.naturalSize)))
    }
}
