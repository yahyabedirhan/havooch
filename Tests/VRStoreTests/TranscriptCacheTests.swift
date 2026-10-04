import Foundation
import Testing
import VRStore
import VRTranscript

@Suite struct TranscriptCacheTests {
    @Test func aSavedTranscriptIsReadBackByItsVideosHash() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vr-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lines = [TranscriptLine(start: 0, end: 1.56, text: "This is video review."), TranscriptLine(start: 1.56, end: 5.1, text: "Pause any video.")]

        #expect(TranscriptCache(root: root).load("abc") == nil)
        try TranscriptCache(root: root).save(lines, for: "abc")

        // Another value on the same folder, as after a relaunch.
        #expect(TranscriptCache(root: root).load("abc") == lines)
        #expect(TranscriptCache(root: root).load("other") == nil)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("videos/abc/transcript.json").path))
    }

    @Test func aTranscriptWithoutLinesIsKeptToo() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vr-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try TranscriptCache(root: root).save([], for: "silent")

        #expect(TranscriptCache(root: root).load("silent") == [])
    }
}
