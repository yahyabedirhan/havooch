import Foundation
import ImageIO
import Testing
@testable import VRApp
import VRReview
import VRWire

private func region(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Region {
    try! Region(x: x, y: y, w: w, h: h)
}

private func close(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 0.001 && abs(a.minY - b.minY) < 0.001
        && abs(a.width - b.width) < 0.001 && abs(a.height - b.height) < 0.001
}

/// The 16:9 fixture frame.
private let video = CGSize(width: 1920, height: 1080)

@Suite struct FrameFitTests {
    @Test(arguments: [
        // The stage has the frame's shape: the frame fills it.
        (CGSize(width: 960, height: 540), CGRect(x: 0, y: 0, width: 960, height: 540)),
        // A taller stage: bars above and below.
        (CGSize(width: 800, height: 600), CGRect(x: 0, y: 75, width: 800, height: 450)),
        // A wider stage: bars left and right.
        (CGSize(width: 1400, height: 540), CGRect(x: 220, y: 0, width: 960, height: 540)),
        // Smaller than the smallest window's stage.
        (CGSize(width: 480, height: 368), CGRect(x: 0, y: 49, width: 480, height: 270)),
    ])
    func theFrameIsFittedWholeAndCentredInTheStage(stage: CGSize, frame: CGRect) {
        #expect(FrameFit(video: video, stage: stage).frame == frame)
    }

    @Test func aPortraitVideoHasItsBarsAtTheSides() {
        let fit = FrameFit(video: CGSize(width: 1080, height: 1920), stage: CGSize(width: 800, height: 640))
        #expect(fit.frame == CGRect(x: 220, y: 0, width: 360, height: 640))
    }

    @Test func withNoVideoOrNoRoomThereIsNoFrame() {
        #expect(FrameFit(video: .zero, stage: CGSize(width: 800, height: 600)).frame == .zero)
        #expect(FrameFit(video: video, stage: .zero).frame == .zero)
        #expect(FrameFit(video: .zero, stage: CGSize(width: 800, height: 600)).region(from: .zero, to: CGPoint(x: 100, y: 100)) == nil)
    }

    /// The acceptance criterion "the region stays correct when the window
    /// size changes": one stored region, drawn in stages of several sizes,
    /// is always on the same part of the frame.
    @Test(arguments: [
        CGSize(width: 960, height: 540),
        CGSize(width: 800, height: 600),
        CGSize(width: 1400, height: 540),
        CGSize(width: 480, height: 368),
        CGSize(width: 2560, height: 1300),
    ])
    func aStoredRegionIsOnTheSamePartOfTheFrameAtAnyWindowSize(stage: CGSize) {
        let fit = FrameFit(video: video, stage: stage)
        let stored = region(0.5, 0.25, 0.25, 0.5)

        let drawn = fit.rect(for: stored)

        // The same parts of the frame's rectangle, wherever it is.
        #expect(abs((drawn.minX - fit.frame.minX) / fit.frame.width - 0.5) < 1e-9)
        #expect(abs((drawn.minY - fit.frame.minY) / fit.frame.height - 0.25) < 1e-9)
        #expect(abs(drawn.width / fit.frame.width - 0.25) < 1e-9)
        #expect(abs(drawn.height / fit.frame.height - 0.5) < 1e-9)
        #expect(fit.frame.contains(drawn))
        // Drawn again over that rectangle, it's the stored region.
        #expect(fit.region(from: CGPoint(x: drawn.minX, y: drawn.minY), to: CGPoint(x: drawn.maxX, y: drawn.maxY)) == stored)
    }

    @Test func aRegionDrawnInOneWindowSizeShowsOnTheSamePictureInAnother() throws {
        let small = FrameFit(video: video, stage: CGSize(width: 800, height: 600))
        let large = FrameFit(video: video, stage: CGSize(width: 1400, height: 540))

        // In the small stage the frame is at (0, 75), 800 × 450.
        let drawn = try #require(small.region(from: CGPoint(x: 200, y: 165), to: CGPoint(x: 600, y: 300)))

        #expect(drawn == region(0.25, 0.2, 0.5, 0.3))
        // In the large one it's at (220, 0), 960 × 540.
        #expect(close(large.rect(for: drawn), CGRect(x: 460, y: 108, width: 480, height: 162)))
        #expect(drawn.pixelRect(in: video) == CGRect(x: 480, y: 216, width: 960, height: 324))
    }

    @Test func aDragInAnyDirectionGivesTheSameRegion() {
        let fit = FrameFit(video: video, stage: CGSize(width: 960, height: 540))
        let a = CGPoint(x: 96, y: 108)
        let b = CGPoint(x: 384, y: 243)
        let expected = region(0.1, 0.2, 0.3, 0.25)

        #expect(fit.region(from: a, to: b) == expected)
        #expect(fit.region(from: b, to: a) == expected)
        #expect(fit.region(from: CGPoint(x: a.x, y: b.y), to: CGPoint(x: b.x, y: a.y)) == expected)
    }

    @Test func aDragThatStartsOrEndsOutsideTheFrameIsKeptOnItsEdge() {
        // The frame is at (0, 75), 800 × 450: the bars are above and below.
        let fit = FrameFit(video: video, stage: CGSize(width: 800, height: 600))

        // From the top bar to past the stage's right edge.
        #expect(fit.region(from: CGPoint(x: 400, y: 10), to: CGPoint(x: 900, y: 300)) == region(0.5, 0, 0.5, 0.5))
        // From inside to the bottom bar and past the left edge.
        #expect(fit.region(from: CGPoint(x: 400, y: 300), to: CGPoint(x: -50, y: 590)) == region(0, 0.5, 0.5, 0.5))
        #expect(close(fit.selection(from: CGPoint(x: 400, y: 10), to: CGPoint(x: 900, y: 300)), CGRect(x: 400, y: 75, width: 400, height: 225)))
        // Wholly inside a bar: nothing of the frame was drawn on.
        #expect(fit.region(from: CGPoint(x: 100, y: 10), to: CGPoint(x: 300, y: 60)) == nil)
    }

    @Test func aRectangleUnderEightPointsOnASideIsAClickNotARegion() {
        let fit = FrameFit(video: video, stage: CGSize(width: 960, height: 540))
        let start = CGPoint(x: 100, y: 100)

        #expect(fit.region(from: start, to: start) == nil)
        #expect(fit.region(from: start, to: CGPoint(x: 107, y: 300)) == nil)
        #expect(fit.region(from: start, to: CGPoint(x: 300, y: 107)) == nil)
        #expect(fit.region(from: start, to: CGPoint(x: 108, y: 108)) != nil)
    }
}

@Suite struct ComposerPlacementTests {
    private let stage = CGSize(width: 960, height: 540)
    private let box = CGSize(width: 320, height: 180)

    private func origin(beside rect: CGRect) -> CGPoint {
        let centre = ComposerPlacement.centre(of: box, beside: rect, in: stage)
        return CGPoint(x: centre.x - box.width / 2, y: centre.y - box.height / 2)
    }

    @Test func theBoxOpensRightOfTheRectangleLevelWithItsTop() {
        #expect(origin(beside: CGRect(x: 100, y: 100, width: 200, height: 150)) == CGPoint(x: 312, y: 100))
    }

    @Test func withNoRoomOnTheRightItOpensOnTheLeft() {
        #expect(origin(beside: CGRect(x: 600, y: 100, width: 300, height: 150)) == CGPoint(x: 268, y: 100))
    }

    @Test func withNoRoomBesideItOpensBelow() {
        // Centred under the rectangle.
        #expect(origin(beside: CGRect(x: 200, y: 40, width: 560, height: 200)) == CGPoint(x: 320, y: 252))
        // Kept inside the stage when the rectangle is near its edge.
        #expect(origin(beside: CGRect(x: 0, y: 40, width: 700, height: 200)) == CGPoint(x: 190, y: 252))
    }

    @Test func withNoRoomAnywhereItOpensAtTheBottomCentre() {
        #expect(origin(beside: CGRect(x: 0, y: 0, width: 960, height: 540)) == CGPoint(x: 320, y: 348))
    }

    @Test func theBoxStaysInsideTheStageBesideALowOrHighRectangle() {
        #expect(origin(beside: CGRect(x: 100, y: 480, width: 200, height: 50)) == CGPoint(x: 312, y: 348))
        #expect(origin(beside: CGRect(x: 100, y: 0, width: 200, height: 50)) == CGPoint(x: 312, y: 12))
    }

    @Test func theBoxNeverCoversTheRectangleWhileASideHasRoom() {
        for rect in [
            CGRect(x: 100, y: 100, width: 200, height: 150),
            CGRect(x: 600, y: 100, width: 300, height: 150),
            CGRect(x: 200, y: 40, width: 560, height: 200),
            CGRect(x: 100, y: 480, width: 200, height: 50),
        ] {
            let placed = CGRect(origin: origin(beside: rect), size: box)
            #expect(!placed.intersects(rect), "\(placed) covers \(rect)")
            #expect(CGRect(origin: .zero, size: stage).contains(placed))
        }
    }
}

@Suite struct RegionMarkTests {
    private let comments = [
        Comment(id: "c1", time: 3, text: "no region", state: .queued),
        Comment(id: "c2", time: 10, text: "this", region: region(0.1, 0.2, 0.3, 0.25), state: .queued),
        Comment(id: "c3", time: 15, text: "that", region: region(0.5, 0.5, 0.5, 0.5), state: .sent),
        Comment(id: "c4", time: 15.2, region: region(0, 0, 0.2, 0.2), state: .draft),
    ]

    private func shown(selection: String? = nil, composing: String? = nil, time: Double) -> [String] {
        RegionMark.shown(of: comments, selection: selection, composing: composing, time: time).map(\.id)
    }

    @Test func theFrameIsCleanAwayFromEveryRegionComment() {
        #expect(shown(time: 0).isEmpty)
        #expect(shown(selection: "c1", time: 3).isEmpty)
        #expect(shown(time: 10.6).isEmpty)
    }

    @Test func aRegionShowsWhileItsCommentIsSelectedOrThePlayheadIsNearIt() {
        #expect(shown(selection: "c2", time: 0) == ["c2"])
        #expect(shown(time: 10) == ["c2"])
        #expect(shown(time: 9.5) == ["c2"])
        #expect(shown(time: 10.5) == ["c2"])
        #expect(shown(selection: "c2", time: 15) == ["c2", "c3"])
    }

    @Test func aDraftsRegionShowsOnlyWhileTheCommentBoxIsOpenOnIt() {
        #expect(shown(time: 15.2) == ["c3"])
        let marks = RegionMark.shown(of: comments, selection: nil, composing: "c4", time: 0)
        #expect(marks == [RegionMark(id: "c4", region: region(0, 0, 0.2, 0.2), isDraft: true)])
    }
}

@MainActor
@Suite struct RegionCommentTests {
    @Test func aCommentWithARegionFromTheCommandLineKeepsItsRegionAndItsCrop() async throws {
        let rig = await CommentRig().opened()

        let reply = await rig.send(
            .commentAdd(text: "this button", at: 10, region: ControlRequest.WireRegion(x: 0.5, y: 0.25, w: 0.25, h: 0.5)),
            json: true
        )

        #expect(reply.output == #"{"batchId":null,"cropPath":"\#(rig.crop("c1").path)","id":"c1","keyframePath":"\#(rig.keyframe("c1").path)","#
            + #""region":{"h":0.5,"w":0.25,"x":0.5,"y":0.25},"state":"queued","text":"this button","thread":[],"time":10}"# + "\n")
        // The crop is on disk by the time the command answers, cut from the
        // comment's keyframe.
        #expect(try String(contentsOf: rig.crop("c1"), encoding: .utf8) == "crop 0.5,0.25,0.25,0.5 of c1.png")
        let comment = try #require(try await rig.comments().first)
        #expect(comment["region"] as? [String: Double] == ["x": 0.5, "y": 0.25, "w": 0.25, "h": 0.5])
        #expect(comment["cropPath"] as? String == rig.crop("c1").path)
        // Its card is selected, so the stage draws the region.
        #expect(rig.model.marks == [RegionMark(id: "c1", region: try Region(x: 0.5, y: 0.25, w: 0.25, h: 0.5), isDraft: false)])
    }

    @Test func aCommentWithoutARegionHasNullForItsRegionAndItsCrop() async throws {
        let rig = await CommentRig().opened()
        _ = await rig.send(.commentAdd(text: "whole frame", at: 10, region: nil))

        let comment = try #require(try await rig.comments().first)

        #expect(comment["region"] is NSNull)
        #expect(comment["cropPath"] is NSNull)
        #expect(!FileManager.default.fileExists(atPath: rig.crop("c1").path))
        #expect(rig.model.marks.isEmpty)
    }

    @Test(arguments: [
        (ControlRequest.WireRegion(x: 0.9, y: 0.2, w: 0.3, h: 0.2), "0.9,0.2,0.3,0.2"),
        (ControlRequest.WireRegion(x: 0, y: 0, w: 0, h: 0.5), "0,0,0,0.5"),
        (ControlRequest.WireRegion(x: 0, y: 0, w: 1920, h: 1080), "0,0,1920,1080"),
    ])
    func aRegionOutsideTheFrameIsRefusedAndLeavesNoComment(wire: ControlRequest.WireRegion, text: String) async throws {
        let rig = await CommentRig().opened()
        _ = await rig.send(.playerSeek(seconds: 4))

        let reply = await rig.send(.commentAdd(text: "x", at: 10, region: wire))

        #expect(reply == .refused(
            "the region \(text) isn't inside the frame: x,y,w,h are parts of the frame from 0 to 1, with w and h above 0, x + w and y + h at most 1"
        ))
        #expect(try await rig.comments().isEmpty)
        #expect(rig.player.time == 4)
    }

    @Test func aCommentWhoseCropCannotBeSavedIsRefusedAndLeavesNoFiles() async throws {
        let rig = await CommentRig(frames: FakeFrames(failsCrop: true)).opened()

        let reply = await rig.send(.commentAdd(text: "x", at: 10, region: ControlRequest.WireRegion(x: 0, y: 0, w: 0.5, h: 0.5)))

        #expect(reply == .refused("couldn't save the frame at 0:10.000: the disk is full"))
        #expect(try await rig.comments().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: rig.keyframe("c1").path))
    }

    @Test func drawingARectanglePausesTheVideoAndOpensTheCommentBoxOnIt() async throws {
        let rig = await CommentRig().opened()
        _ = await rig.send(.playerSeek(seconds: 4))
        _ = await rig.send(.playerPlay)
        let drawn = try Region(x: 0.1, y: 0.2, w: 0.3, h: 0.25)

        // The drag starts: the video pauses on the frame pointed at.
        #expect(rig.model.beginDrawing())
        #expect(!rig.player.isPlaying)
        #expect(rig.model.composing == nil)
        // The drag ends: the comment box opens on the rectangle.
        rig.model.compose(region: drawn)

        let draft = try #require(rig.model.composing)
        #expect(rig.model.session?.comment(draft) == Comment(id: draft, time: 4, region: drawn, state: .draft))
        #expect(rig.model.marks == [RegionMark(id: draft, region: drawn, isDraft: true)])
        // While the box is open, another drag doesn't start a second draft.
        #expect(!rig.model.beginDrawing())

        #expect(rig.model.commitComposer(text: "this button"))
        await settle { rig.model.cropURL(for: draft) != nil }
        let comment = try #require(try await rig.comments().first)
        #expect(comment["state"] as? String == "queued")
        #expect(comment["region"] as? [String: Double] == ["x": 0.1, "y": 0.2, "w": 0.3, "h": 0.25])
        #expect(comment["cropPath"] as? String == rig.crop(draft).path)
        #expect(rig.model.marks == [RegionMark(id: draft, region: drawn, isDraft: false)])
    }

    @Test func escapeCancelsTheRegionWithItsDraftAndItsImages() async throws {
        let rig = await CommentRig().opened()
        rig.model.compose(region: try Region(x: 0.1, y: 0.2, w: 0.3, h: 0.25))
        let draft = try #require(rig.model.composing)
        await settle { rig.model.cropURL(for: draft) != nil }
        #expect(FileManager.default.fileExists(atPath: rig.crop(draft).path))

        // What Escape does, in the comment box and on the player.
        rig.model.cancelComposer()

        #expect(rig.model.composing == nil)
        #expect(rig.model.marks.isEmpty)
        #expect(try await rig.comments().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: rig.crop(draft).path))
        #expect(!FileManager.default.fileExists(atPath: rig.keyframe(draft).path))
        // The video stays paused, and the frame can be drawn on again.
        #expect(!rig.player.isPlaying)
        #expect(rig.model.beginDrawing())
    }

    @Test func aRegionCancelledWhileItsImagesAreWrittenLeavesNoFiles() async throws {
        let written = FakeFrames.Count()
        let rig = await CommentRig(frames: FakeFrames(crops: written)).opened()
        rig.model.compose(region: try Region(x: 0.1, y: 0.2, w: 0.3, h: 0.25))
        let draft = try #require(rig.model.composing)

        rig.model.cancelComposer()
        // The images land after the cancel, and remove themselves.
        await settle { written.value == 1 }
        await settle { !FileManager.default.fileExists(atPath: rig.keyframe(draft).path) }

        #expect(!FileManager.default.fileExists(atPath: rig.crop(draft).path))
        #expect(!FileManager.default.fileExists(atPath: rig.keyframe(draft).path))
        #expect(rig.model.cropURL(for: draft) == nil)
    }

    @Test func deletingACommentTakesItsCropWithIt() async throws {
        let rig = await CommentRig().opened()
        _ = await rig.send(.commentAdd(text: "x", at: 10, region: ControlRequest.WireRegion(x: 0, y: 0, w: 0.5, h: 0.5)))
        #expect(FileManager.default.fileExists(atPath: rig.crop("c1").path))

        _ = await rig.send(.commentDelete(id: "c1"))

        #expect(!FileManager.default.fileExists(atPath: rig.crop("c1").path))
        #expect(rig.model.marks.isEmpty)
    }

    @Test func escapeIsThePlayersKeyOutsideATextView() {
        #expect(PlayerKey(characters: "\u{1B}", keyCode: 53, hasCommandModifiers: false) == .cancel)
        #expect(PlayerKey.routed(characters: "\u{1B}", keyCode: 53, hasCommandModifiers: false, focus: KeyFocus()) == .cancel)
        // In the comment box, Escape is the box's own.
        #expect(PlayerKey.routed(characters: "\u{1B}", keyCode: 53, hasCommandModifiers: false, focus: KeyFocus(inText: true)) == nil)
    }
}

/// The real frame grabber against the fixture video.
@MainActor
@Suite struct CropTests {
    @Test func aCropIsThePixelsOfItsRegionOfTheKeyframe() async throws {
        let folder = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let grabber = FrameGrabber()
        let keyframe = folder.appendingPathComponent("frames/c1.png")
        let crop = folder.appendingPathComponent("crops/c1.png")
        _ = try await grabber.writeKeyframe(of: fixtureVideo, at: 10, to: keyframe)

        // The right half of the top half.
        try await grabber.writeCrop(of: keyframe, region: try Region(x: 0.5, y: 0, w: 0.5, h: 0.5), to: crop)

        let frame = try pixels(try image(keyframe))
        let cut = try image(crop)
        #expect(cut.width == 960)
        #expect(cut.height == 540)
        let cutPixels = try pixels(cut)
        // Every row of the crop is the right half of the same row of the
        // frame, counted from the top.
        var same = true
        for row in 0..<540 where same {
            let from = (row * 1920 + 960) * 4
            same = cutPixels[(row * 960 * 4)..<((row + 1) * 960 * 4)] == frame[from..<(from + 960 * 4)]
        }
        #expect(same)
    }

    @Test func aCropOfAFileThatIsNotAPictureFails() async {
        let notPicture = fixtureVideo.deletingLastPathComponent().appendingPathComponent("sample.srt")
        await #expect(throws: (any Error).self) {
            try await FrameGrabber().writeCrop(
                of: notPicture, region: try Region(x: 0, y: 0, w: 1, h: 1),
                to: URL(fileURLWithPath: "/tmp/vr-\(UUID().uuidString.prefix(8))/c1.png")
            )
        }
    }

    /// The acceptance criterion "the crop PNG shows the same part of the
    /// frame for the UI and the CLI".
    @Test func aRegionDrawnInTheWindowAndOneFromTheCommandLineGiveTheSameCrop() async throws {
        let rig = await CommentRig(frames: FrameGrabber()).opened()
        _ = await rig.send(.playerSeek(seconds: 10))
        // The window: a drag over a stage of 800 × 600, then Enter.
        let fit = FrameFit(video: try #require(rig.model.video?.size), stage: CGSize(width: 800, height: 600))
        let drawn = try #require(fit.region(from: CGPoint(x: 200, y: 165), to: CGPoint(x: 600, y: 300)))
        #expect(rig.model.beginDrawing())
        rig.model.compose(region: drawn)
        let fromWindow = try #require(rig.model.composing)
        #expect(rig.model.commitComposer(text: "from the window"))
        await settle { rig.model.cropURL(for: fromWindow) != nil }

        // The command line: the same time and region.
        let reply = await rig.send(.commentAdd(text: "from the command line", at: 10, region: ControlRequest.WireRegion(x: 0.25, y: 0.2, w: 0.5, h: 0.3)))
        #expect(reply == .done("c2 at 0:10.000\n"))

        let window = try image(rig.crop(fromWindow))
        #expect(window.width == 960)
        #expect(window.height == 324)
        let command = try image(rig.crop("c2"))
        #expect(command.width == 960)
        #expect(command.height == 324)
        // The same pixels. The files' bytes are not compared: two PNGs of
        // one frame sometimes differ in their bytes and never in what they
        // show.
        let shown = try pixels(command)
        #expect(try pixels(window) == shown)
        // Another region gives other pixels.
        _ = await rig.send(.commentAdd(text: "elsewhere", at: 10, region: ControlRequest.WireRegion(x: 0, y: 0.2, w: 0.5, h: 0.3)))
        #expect(try pixels(try image(rig.crop("c3"))) != shown)
    }
}
