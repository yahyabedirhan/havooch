import Foundation
import ImageIO
import Testing
@testable import VRApp

/// The picture in the PNG at `file`.
func image(_ file: URL) throws -> CGImage {
    let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
    #expect(CGImageSourceGetType(source) as String? == "public.png")
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
}

/// An image's pixels as RGBA bytes, row by row from the top: what it shows,
/// however its file keeps them.
func pixels(_ image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = try #require(CGContext(
        data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return bytes
}

/// The grabber against the fixture video: 1920x1080 at 30 fps, 637 frames.
@Suite struct FrameGrabberTests {
    private func scratchFolder() -> URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    @Test func aKeyframeIsAPNGOfTheWholeFrameInAFolderMadeForIt() async throws {
        let folder = scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("videos/abc/frames/c1.png")

        let size = try await FrameGrabber().writeKeyframe(of: fixtureVideo, at: 10, to: file)

        #expect(size == CGSize(width: 1920, height: 1080))
        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.png")
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 1920)
        #expect(image.height == 1080)
    }

    @Test(arguments: [
        (0.0, 0.0),
        (10.0, 10.0),
        // Between two frames: the one on screen, which started before.
        (10.01, 10.0),
        (9.99, 299.0 / 30),
        // The video's very end, after its last frame: the last frame.
        (21.233, 636.0 / 30),
    ])
    func theFrameIsTheOneShownAtTheTime(asked: Double, shown: Double) async throws {
        let frame = try await FrameGrabber.frame(of: fixtureVideo, at: asked)

        #expect(abs(frame.time - shown) < 0.001, "asked \(asked), got the frame at \(frame.time)")
    }

    @Test func theSameTimeGivesTheSamePixelsAndAnotherSceneGivesOthers() async throws {
        let folder = scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let grabber = FrameGrabber()
        let first = folder.appendingPathComponent("first.png")
        let again = folder.appendingPathComponent("again.png")
        let other = folder.appendingPathComponent("other.png")

        _ = try await grabber.writeKeyframe(of: fixtureVideo, at: 10, to: first)
        _ = try await grabber.writeKeyframe(of: fixtureVideo, at: 10, to: again)
        _ = try await grabber.writeKeyframe(of: fixtureVideo, at: 2, to: other)

        // What the files show, not their bytes: two PNGs of one frame
        // sometimes differ in their bytes and never in what they show.
        let shown = try pixels(try image(first))
        #expect(try pixels(try image(again)) == shown)
        #expect(try pixels(try image(other)) != shown)
    }

    @Test func aFileThatIsNotAVideoFails() async {
        let notVideo = fixtureVideo.deletingLastPathComponent().appendingPathComponent("sample.srt")
        await #expect(throws: (any Error).self) {
            try await FrameGrabber().writeKeyframe(of: notVideo, at: 1, to: scratchFolder().appendingPathComponent("c1.png"))
        }
    }
}
