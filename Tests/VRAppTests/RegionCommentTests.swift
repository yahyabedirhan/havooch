import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import VRApp
import VRLease
import VRReview
import VRWire

/// A comment on a region, from the rectangle drawn on the frame and from
/// `comment add --region`, on the fixture video in a temporary folder. The
/// pointer's path is driven through the model's own methods, which the
/// overlay calls: no window is opened and no sound is made.
@Suite(.serialized) @MainActor struct RegionCommentTests {
    static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/sample/sample.mp4")
    nonisolated static let agent = Holder(key: "CLAUDE_CODE_SESSION_ID=agent", name: "Claude Code", place: "/work")

    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
    /// The 1920 by 1080 frame in a view too tall for it: bars above and below.
    let geometry = FrameGeometry(frame: CGSize(width: 1920, height: 1080), view: CGSize(width: 1000, height: 800))
    /// The same frame in a view too wide for it: bars at the sides.
    let wide = FrameGeometry(frame: CGSize(width: 1920, height: 1080), view: CGSize(width: 1600, height: 540))
    let keys = Region(x: 0.48, y: 0.3, w: 0.28, h: 0.12)!

    /// A model with the fixture open, paused at `time`, and silent.
    func model(at time: Double = 10) async throws -> AppModel {
        let model = AppModel(environment: [SupportFolder.overrideVariable: folder.path])
        model.player.player.isMuted = true
        try await model.open(Self.fixture)
        try await model.seek(to: time)
        return model
    }

    func server(on model: AppModel) -> ControlServer {
        ControlServer(
            socket: folder.appendingPathComponent("control.sock"), model: model, screenshotter: Screenshotter(model: model),
            lease: ControlLease(), indicator: LeaseIndicator(), quit: {}
        )
    }

    /// Draws `region` on the frame as `geometry` places it: press at its
    /// top left, drag to its bottom right, let go.
    func draw(_ region: Region, on model: AppModel, in geometry: FrameGeometry) {
        let rect = geometry.rect(of: region)
        model.beginRegion(at: rect.origin)
        model.dragRegion(to: CGPoint(x: rect.midX, y: rect.midY))
        model.dragRegion(to: CGPoint(x: rect.maxX, y: rect.maxY))
        model.endRegion(in: geometry)
    }

    static func near(_ one: Region?, _ other: Region) -> Bool {
        guard let one else { return false }
        return zip([one.x, one.y, one.w, one.h], [other.x, other.y, other.w, other.h]).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    static func image(at file: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// The pixels of `image`, or of `part` of it (origin top left), as RGBA bytes.
    static func pixels(of image: CGImage, part: CGRect? = nil) throws -> [UInt8] {
        let part = part ?? CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let width = Int(part.width), height = Int(part.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // The context's origin is at the bottom left: the image is placed so that `part` fills it.
        context.draw(image, in: CGRect(
            x: -part.minX, y: -(CGFloat(image.height) - part.maxY), width: CGFloat(image.width), height: CGFloat(image.height)
        ))
        return bytes
    }

    // MARK: - Drawing

    @Test func drawingARectanglePausesTheVideoAndOpensTheCommentBoxOnItsRegion() async throws {
        let model = try await model(at: 4)
        try model.play()
        #expect(model.player.playing)

        let rect = geometry.rect(of: keys)
        model.beginRegion(at: rect.origin)
        #expect(model.player.playing)
        model.dragRegion(to: CGPoint(x: rect.midX, y: rect.midY))
        #expect(!model.player.playing)
        #expect(model.draw.isDrawing)
        #expect(model.desk.draft == nil)
        model.dragRegion(to: CGPoint(x: rect.maxX, y: rect.maxY))
        #expect(Self.near(model.draw.region(in: geometry), keys))
        model.endRegion(in: geometry)

        let draft = try #require(model.desk.draft)
        #expect(Self.near(draft.region, keys))
        #expect(draft.time == model.player.time)
        #expect(draft.resumes)
        #expect(!model.player.playing)
        #expect(!model.draw.isDrawing)
        let shown = model.snapshot(lease: nil)
        #expect(shown.draft?.time == draft.time)
        #expect(shown.draft?.region == draft.region)
        #expect(shown.json.contains(#""draft":{"region":{"h":"#))
        model.discardDraft()
    }

    @Test func aPressThatDoesNotMoveOnlyPlaysOrPauses() async throws {
        let model = try await model()
        model.beginRegion(at: CGPoint(x: 500, y: 400))
        model.dragRegion(to: CGPoint(x: 502, y: 401))
        model.endRegion(in: geometry)
        #expect(model.player.playing)
        #expect(model.desk.draft == nil)
        model.beginRegion(at: CGPoint(x: 500, y: 400))
        model.endRegion(in: geometry)
        #expect(!model.player.playing)
        #expect(model.desk.draft == nil)
    }

    @Test func escapeWhileDrawingGivesTheRectangleUpAndThePlayingVideoPlaysOn() async throws {
        let model = try await model(at: 4)
        try model.play()
        let rect = geometry.rect(of: keys)
        model.beginRegion(at: rect.origin)
        model.dragRegion(to: CGPoint(x: rect.midX, y: rect.midY))
        #expect(!model.player.playing)

        #expect(model.cancelRegion())
        #expect(!model.draw.isDrawing)
        #expect(model.player.playing)
        // The button is still down: the rest of the drag draws nothing and opens no box.
        model.beginRegion(at: rect.origin)
        model.dragRegion(to: CGPoint(x: rect.maxX, y: rect.maxY))
        #expect(model.draw.region(in: geometry) == nil)
        model.endRegion(in: geometry)
        #expect(model.desk.draft == nil)
        #expect(model.player.playing)
        #expect(!model.cancelRegion())
        try model.pause()
    }

    @Test func escapeInTheCommentBoxCancelsTheRegionAndKeepsNothing() async throws {
        let model = try await model()
        draw(keys, on: model, in: geometry)
        #expect(model.desk.draft?.region != nil)

        model.discardDraft()
        #expect(model.desk.draft == nil)
        #expect(model.desk.open?.comments.isEmpty == true)
        #expect(model.snapshot(lease: nil).json.contains(#""draft":null"#))
        await #expect(throws: ActionError.noDraft) { try await model.commitDraft(text: "too late") }
        #expect(!FileManager.default.fileExists(atPath: model.desk.layout.videosFolder.path))
    }

    @Test func aRectangleWithNoneOfTheFrameInItOpensNoBox() async throws {
        let model = try await model()
        model.beginRegion(at: CGPoint(x: 10, y: 10))
        model.dragRegion(to: CGPoint(x: 300, y: 500))
        model.endRegion(in: wide)
        #expect(model.desk.draft == nil)
        #expect(!model.player.playing)
    }

    @Test func aSecondRectangleWhileTheBoxIsOpenMovesTheSameCommentsRegion() async throws {
        let model = try await model()
        try model.startDraft()
        let first = try #require(model.desk.draft)
        #expect(first.region == nil)
        draw(keys, on: model, in: geometry)
        #expect(Self.near(model.desk.draft?.region, keys))
        let other = Region(x: 0.1, y: 0.6, w: 0.2, h: 0.3)!
        draw(other, on: model, in: wide)
        let draft = try #require(model.desk.draft)
        #expect(Self.near(draft.region, other))
        #expect(draft.time == first.time)
        #expect(draft.frame == first.frame)
        model.discardDraft()
    }

    // MARK: - The comment and its crop

    @Test func theSameRegionDrawnAtTwoWindowSizesAndGivenOnTheCommandLineKeepsTheSameCrop() async throws {
        let model = try await model()
        let server = server(on: model)

        // The person, in a letterboxed window.
        draw(keys, on: model, in: geometry)
        let tall = try await model.commitDraft(text: "drawn in a tall window")
        // The person again, after the window became wide.
        draw(keys, on: model, in: wide)
        let broad = try await model.commitDraft(text: "drawn in a wide window")
        // An agent.
        let answer = await server.reply(to: ControlMessage(
            .commentAdd(text: "from the command line", at: 10, region: WireRegion(x: 0.48, y: 0.3, w: 0.28, h: 0.12)),
            holder: Self.agent, json: true
        ).encoded())
        #expect(answer.reply.ok)

        let comments = try #require(model.desk.open?.comments)
        #expect(comments.map(\.text) == ["drawn in a tall window", "drawn in a wide window", "from the command line"])
        #expect(comments.allSatisfy { $0.time == 10 && Self.near($0.region, keys) })
        #expect(comments[2].region == keys)
        #expect(model.desk.draft == nil)

        // The three comments keep the same frame and the same part of it:
        // every pixel equal, with no tolerance. The decoded pixels are
        // compared and not the files' bytes, because each read of a frame
        // gets a colour profile stamped with the second it was made in, and
        // the PNG carries it: the files of one frame read either side of a
        // second's tick differ in that one byte and in nothing else.
        let frames = try comments.map { try Self.pixels(of: Self.image(at: model.desk.keyframe(of: $0.id))) }
        #expect(frames[0] == frames[2])
        #expect(frames[1] == frames[2])
        let crops = try comments.map { try Self.pixels(of: Self.image(at: model.desk.crop(of: $0.id))) }
        #expect(crops[0] == crops[2])
        #expect(crops[1] == crops[2])
        #expect(tall.id != broad.id)

        // The crop is that part of the keyframe, pixel for pixel.
        let keyframe = try Self.image(at: model.desk.keyframe(of: comments[2].id))
        let crop = try Self.image(at: model.desk.crop(of: comments[2].id))
        #expect((keyframe.width, keyframe.height) == (1920, 1080))
        #expect((crop.width, crop.height) == (537, 130))
        let part = CGRect(x: 922, y: 324, width: 537, height: 130)
        #expect(try Self.pixels(of: crop) == Self.pixels(of: keyframe, part: part))
        // And not just any part of it.
        #expect(try Self.pixels(of: crop) != Self.pixels(of: keyframe, part: part.offsetBy(dx: 0, dy: 300)))

        // What `comment add --json` and `state` say of it.
        let cropPath = folder.appendingPathComponent("videos/\(try #require(model.desk.open).video.contentHash)/crops/\(comments[2].id.rawValue).png").path
        #expect(answer.reply.output.contains(#""region":{"h":0.12,"w":0.28,"x":0.48,"y":0.3}"#))
        #expect(answer.reply.output.contains(#""cropPath":"\#(cropPath)""#))
        #expect(model.snapshot(lease: nil).comments.map(\.cropPath) == comments.map { model.desk.crop(of: $0.id).path })
        #expect(model.selection == comments[2].id)
    }

    @Test func aCommentWithoutARegionHasNoCrop() async throws {
        let model = try await model()
        let comment = try await model.addComment(text: "the whole frame", at: 10)
        #expect(comment.region == nil)
        #expect(FileManager.default.fileExists(atPath: model.desk.keyframe(of: comment.id).path))
        #expect(!FileManager.default.fileExists(atPath: model.desk.crop(of: comment.id).path))
        let shown = model.shown(comment)
        #expect(shown.region == nil)
        #expect(shown.cropPath == nil)
        #expect(JSONText.line(shown).contains(#""cropPath":null"#))
        #expect(JSONText.line(shown).contains(#""region":null"#))
    }

    @Test func aRegionOutsideTheFrameIsRefusedInWordsAndAddsNothing() async throws {
        let model = try await model()
        let server = server(on: model)
        for region in [WireRegion(x: 0.9, y: 0.9, w: 0.3, h: 0.3), WireRegion(x: -0.1, y: 0, w: 0.5, h: 0.5), WireRegion(x: 0, y: 0, w: 0, h: 1)] {
            let answer = await server.reply(to: ControlMessage(.commentAdd(text: "off", at: 10, region: region), holder: Self.agent, json: false).encoded())
            #expect(answer.reply == .refused(ReviewError.regionOutsideFrame.message))
        }
        #expect(model.desk.open?.comments.isEmpty == true)
    }

    @Test func deletingACommentTakesItsCropWithIt() async throws {
        let model = try await model()
        let comment = try await model.addComment(text: "this key", at: 10, region: keys)
        let crop = model.desk.crop(of: comment.id), keyframe = model.desk.keyframe(of: comment.id)
        #expect(FileManager.default.fileExists(atPath: crop.path))
        try model.deleteComment(comment.id)
        #expect(!FileManager.default.fileExists(atPath: crop.path))
        #expect(!FileManager.default.fileExists(atPath: keyframe.path))
    }
}
