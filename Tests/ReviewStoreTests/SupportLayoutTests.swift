import Foundation
import ReviewCore
import ReviewStore
import Testing

@Suite("Where the store keeps each file")
struct SupportLayoutTests {
    @Test("every file is under the root: the outbox and the last video at the top, a video's files in its content hash's folder")
    func paths() throws {
        let layout = SupportLayout(root: URL(fileURLWithPath: "/support", isDirectory: true))
        let id = try #require(ItemID("c-7f3a9c2e"))

        #expect(layout.outboxFile.path == "/support/outbox.json")
        #expect(layout.recentFile.path == "/support/recent.json")
        #expect(layout.videosFolder.path == "/support/videos")
        #expect(layout.folder("abc").path == "/support/videos/abc")
        #expect(layout.reviewFile("abc").path == "/support/videos/abc/review.json")
        #expect(layout.transcriptFile("abc").path == "/support/videos/abc/transcript.json")
        #expect(layout.keyframe(id, of: "abc").path == "/support/videos/abc/frames/c-7f3a9c2e.png")
        #expect(layout.crop(id, of: "abc").path == "/support/videos/abc/crops/c-7f3a9c2e.png")
    }
}
