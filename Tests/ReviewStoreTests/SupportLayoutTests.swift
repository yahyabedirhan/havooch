import Foundation
import ReviewCore
import ReviewStore
import Testing

@Suite("Where the store keeps each file")
struct SupportLayoutTests {
    @Test("every file is under the root: each review's outbox in outboxes, the recent videos at the top, a video's files in its content hash's folder, a thread's keyframe and a message's crop by their ids")
    func paths() throws {
        let layout = SupportLayout(root: URL(fileURLWithPath: "/support", isDirectory: true))
        let thread = try #require(ItemID("t-f92cbb2a-1"))
        let message = try #require(ItemID("m-f92cbb2a-2"))

        #expect(layout.outboxFile(.video(contentHash: "abc")).path == "/support/outboxes/video-abc.json")
        #expect(layout.formerOutboxFile.path == "/support/outbox.json")
        #expect(layout.recentsFile.path == "/support/recents.json")
        #expect(layout.formerRecentFile.path == "/support/recent.json")
        #expect(layout.settingsFile.path == "/support/settings.json")
        #expect(layout.formerThemesFolder.path == "/support/Themes")
        #expect(layout.videosFolder.path == "/support/videos")
        #expect(layout.folder(.video(contentHash: "abc")).path == "/support/videos/abc")
        #expect(layout.reviewFile(.video(contentHash: "abc")).path == "/support/videos/abc/review.json")
        #expect(layout.transcriptFile("abc").path == "/support/videos/abc/transcript.json")
        #expect(layout.keyframe(thread, of: .video(contentHash: "abc")).path == "/support/videos/abc/frames/t-f92cbb2a-1.png")
        #expect(layout.crop(message, of: .video(contentHash: "abc")).path == "/support/videos/abc/crops/m-f92cbb2a-2.png")
        #expect(layout.pendingImage("x", of: .video(contentHash: "abc")).path == "/support/videos/abc/frames/.pending-x.png")
        // A project's review keeps its pictures in its own folder; the transcript stays the video's.
        let project = ReviewKey.project(slug: "launch-video")
        #expect(layout.reviewFile(project).path == "/support/projects/launch-video/review.json")
        #expect(layout.keyframe(thread, of: project).path == "/support/projects/launch-video/frames/t-f92cbb2a-1.png")
        #expect(layout.crop(message, of: project).path == "/support/projects/launch-video/crops/m-f92cbb2a-2.png")
        #expect(layout.outboxFile(project).path == "/support/outboxes/project-launch-video.json")
    }
}
