import Foundation
import Testing
import VRReview
import VRStore

@Suite struct ContentHashTests {
    /// A folder of its own for one test, removed when the test ends.
    final class Folder {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vr-store-\(UUID().uuidString)", isDirectory: true)

        init() throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }

        func file(_ name: String, _ bytes: Data) throws -> URL {
            let file = url.appendingPathComponent(name)
            try bytes.write(to: file)
            return file
        }
    }

    /// `count` bytes that differ along the file.
    private func bytes(_ count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 >> 8) })
    }

    @Test func aRenamedCopyHasTheSameHash() throws {
        let folder = try Folder()
        let content = bytes(5_000)
        let hash = try ContentHash.of(folder.file("sample.mp4", content))
        #expect(try ContentHash.of(folder.file("renamed copy.mov", content)) == hash)
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test func otherContentHasAnotherHash() throws {
        let folder = try Folder()
        var content = bytes(5_000)
        let hash = try ContentHash.of(folder.file("a.mp4", content))
        content[2_500] ^= 1
        #expect(try ContentHash.of(folder.file("b.mp4", content)) != hash)
        #expect(try ContentHash.of(folder.file("c.mp4", content + [0])) != hash)
    }

    @Test func aLargeFileIsNamedByItsSizeAndThreeSamples() throws {
        let folder = try Folder()
        let size = 5 << 20
        var content = bytes(size)
        let hash = try ContentHash.of(folder.file("large.mp4", content))
        // A byte in each sample changes the hash: the start, the middle, the end.
        for index in [0, size / 2, size - 1] {
            var changed = content
            changed[index] ^= 1
            #expect(try ContentHash.of(folder.file("changed.mp4", changed)) != hash)
        }
        // One between two samples doesn't: that part isn't read.
        content[(1 << 20) + 10] ^= 1
        #expect(try ContentHash.of(folder.file("unread.mp4", content)) == hash)
    }

    @Test func aFileThatIsNotThereThrows() {
        #expect(throws: (any Error).self) { try ContentHash.of(URL(fileURLWithPath: "/nowhere/sample.mp4")) }
    }

    @Test func aKeyframeSitsInItsVideosFolderUnderItsCommentsId() {
        let layout = SupportLayout(root: URL(fileURLWithPath: "/support", isDirectory: true))
        let hash = "7f3a9c21" + String(repeating: "0", count: 56)
        #expect(layout.keyframe(CommentID(rawValue: "7f3a9c21-c3"), of: hash).path == "/support/videos/\(hash)/frames/7f3a9c21-c3.png")
    }
}
