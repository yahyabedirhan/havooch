import Foundation
import Testing
import VRStore

@Suite struct LibraryTests {
    private func scratchFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vr-library-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func commentIdsCountUpAndGoOnAfterARelaunch() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        // The folder isn't there yet: the first id makes it.
        #expect(try Library(root: root).nextCommentID() == "c1")
        #expect(try Library(root: root).nextCommentID() == "c2")
        // Another value on the same folder, as after a relaunch.
        #expect(try Library(root: root).nextCommentID() == "c3")
    }

    @Test func batchIdsCountUpBesideTheCommentIds() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(try Library(root: root).nextCommentID() == "c1")
        #expect(try Library(root: root).nextBatchID() == "b1")
        #expect(try Library(root: root).nextBatchID() == "b2")
        #expect(try Library(root: root).nextCommentID() == "c2")
    }

    @Test func anIndexWrittenBeforeBatchesWereNumberedStillReads() throws {
        let root = scratchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"nextComment":7}"#.utf8).write(to: root.appendingPathComponent("index.json"))

        #expect(try Library(root: root).nextBatchID() == "b1")
        #expect(try Library(root: root).nextCommentID() == "c7")
    }

    @Test func aKeyframeIsNamedByItsVideoAndItsComment() {
        let library = Library(root: URL(fileURLWithPath: "/Users/me/support", isDirectory: true))

        #expect(library.keyframeURL("abc", comment: "c1").path == "/Users/me/support/videos/abc/frames/c1.png")
    }
}
