#if canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif
import Foundation
import ReviewCore
import ReviewStore
import Testing

/// A temporary folder, removed with `cleanUp()`.
struct Scratch {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("video-review-tests-\(UUID().uuidString)", isDirectory: true)

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }
}

#if canImport(CryptoKit)
@Suite("The content hash")
struct ContentHashTests {
    @Test("it's the SHA-256 of the file's bytes")
    func sha256() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let file = scratch.folder.appendingPathComponent("a.mp4")
        try Data("abc".utf8).write(to: file)
        #expect(ContentHash.of(file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("a renamed copy has the same hash, and other content another")
    func renamed() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let original = scratch.folder.appendingPathComponent("a.mp4")
        let copy = scratch.folder.appendingPathComponent("moved").appendingPathComponent("b.mov")
        let other = scratch.folder.appendingPathComponent("c.mp4")
        let bytes = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try bytes.write(to: original)
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: original, to: copy)
        try (bytes + [1]).write(to: other)
        let hash = try #require(ContentHash.of(original))
        #expect(hash.count == 64)
        #expect(ContentHash.of(copy) == hash)
        #expect(ContentHash.of(other) != hash)
    }

    @Test("a file that isn't there has no hash")
    func missing() {
        #expect(ContentHash.of(URL(fileURLWithPath: "/nowhere/a.mp4")) == nil)
    }
}
#endif

#if canImport(ImageIO)
@Suite("Image files")
struct ImageFilesTests {
    private func image(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test("a keyframe is in its video's folder, named after its comment")
    func paths() throws {
        let files = ImageFiles(support: URL(fileURLWithPath: "/support", isDirectory: true))
        let id = try #require(ItemID("c-7f3a9c2e"))
        #expect(files.keyframe(of: id, contentHash: "abc").path == "/support/videos/abc/frames/c-7f3a9c2e.png")
    }

    @Test("an image is written as a PNG of its own size, in a folder made for it, and removed again")
    func writes() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let id = try #require(ItemID("c-7f3a9c2e"))
        let file = ImageFiles(support: scratch.folder).keyframe(of: id, contentHash: "abc")
        try ImageFiles.write(try image(width: 320, height: 180), to: file)

        #expect(try Data(contentsOf: file).prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        let read = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(read.width == 320)
        #expect(read.height == 180)

        let thumbnail = try #require(ImageFiles.thumbnail(of: file, side: 96))
        #expect(thumbnail.width == 96)
        #expect(thumbnail.height == 54)

        ImageFiles.remove(file)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        ImageFiles.remove(file)
    }

    @Test("an image that can't be written is refused with the reason")
    func refused() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        // A file where the folder should be.
        let blocker = scratch.folder.appendingPathComponent("videos")
        try Data().write(to: blocker)
        let id = try #require(ItemID("c-7f3a9c2e"))
        let file = ImageFiles(support: scratch.folder).keyframe(of: id, contentHash: "abc")
        #expect(throws: ImageFiles.Failure.self) { try ImageFiles.write(try image(width: 4, height: 4), to: file) }
    }
}
#endif
