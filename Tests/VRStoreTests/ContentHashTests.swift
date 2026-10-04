import Foundation
import Testing
@testable import VRStore

private func scratchFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vr-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Suite struct ContentHashTests {
    @Test func aRenamedCopyHasTheSameHash() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("talk.mp4")
        let copy = folder.appendingPathComponent("renamed.mov")
        try Data("the same bytes".utf8).write(to: original)
        try FileManager.default.copyItem(at: original, to: copy)

        let hash = try ContentHash.of(original)
        #expect(try ContentHash.of(copy) == hash)
        #expect(hash.wholeMatch(of: /[0-9a-f]{64}/) != nil)
    }

    @Test func otherContentHasAnotherHash() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = folder.appendingPathComponent("one.mp4")
        let two = folder.appendingPathComponent("two.mp4")
        try Data("one".utf8).write(to: one)
        try Data("two".utf8).write(to: two)

        #expect(try ContentHash.of(one) != ContentHash.of(two))
    }

    @Test func aLargeFileIsNamedByItsSizeAndItsTwoEnds() throws {
        let folder = try scratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let size = 2 * ContentHash.edge + 1024
        var bytes = Data(repeating: 7, count: size)
        let file = folder.appendingPathComponent("large.mp4")
        try bytes.write(to: file)
        let hash = try ContentHash.of(file)

        // The last byte is inside the last 4 MiB.
        bytes[size - 1] = 8
        try bytes.write(to: file)
        #expect(try ContentHash.of(file) != hash)

        // One byte more changes the size.
        try Data(repeating: 7, count: size + 1).write(to: file)
        #expect(try ContentHash.of(file) != hash)
    }

    @Test func aMissingFileThrows() {
        #expect(throws: (any Error).self) {
            try ContentHash.of(URL(fileURLWithPath: "/nonexistent/video.mp4"))
        }
    }
}
