import Foundation
import ReviewCore
import ReviewStore
import Testing

@Suite("Where the store keeps each file")
struct SupportLayoutTests {
    @Test("every file is under the root: the outbox and the last video at the top, a video's files in its content hash's folder, a thread's keyframe and a message's crop by their ids")
    func paths() throws {
        let layout = SupportLayout(root: URL(fileURLWithPath: "/support", isDirectory: true))
        let thread = try #require(ItemID("t-f92cbb2a-1"))
        let message = try #require(ItemID("m-f92cbb2a-2"))

        #expect(layout.outboxFile.path == "/support/outbox.json")
        #expect(layout.recentsFile.path == "/support/recents.json")
        #expect(layout.formerRecentFile.path == "/support/recent.json")
        #expect(layout.settingsFile.path == "/support/settings.json")
        #expect(layout.formerThemesFolder.path == "/support/Themes")
        #expect(layout.videosFolder.path == "/support/videos")
        #expect(layout.folder("abc").path == "/support/videos/abc")
        #expect(layout.reviewFile("abc").path == "/support/videos/abc/review.json")
        #expect(layout.transcriptFile("abc").path == "/support/videos/abc/transcript.json")
        #expect(layout.keyframe(thread, of: "abc").path == "/support/videos/abc/frames/t-f92cbb2a-1.png")
        #expect(layout.crop(message, of: "abc").path == "/support/videos/abc/crops/m-f92cbb2a-2.png")
        #expect(layout.pendingImage("x", of: "abc").path == "/support/videos/abc/frames/.pending-x.png")
    }
}
