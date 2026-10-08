import Foundation
@testable import ReviewApp
import ReviewStore
import ReviewWire
import Testing

/// The home screen: when the stage shows it, what each recent-video card
/// says, which frame its thumbnail is, and what a click on a card does.
/// No window: the views are checked through app control.
@Suite("The home screen", .serialized)
struct HomeScreenTests {
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private var environment: [String: String] { [SupportFolder.overrideVariable: support.path] }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// A recent video whose file is not on the disk.
    private func gone(_ hash: String = "gone") -> StateReport.Recent {
        StateReport.Recent(RecentVideo(path: "/nowhere/\(hash).mp4", contentHash: hash, openedAt: Date(), position: 4))
    }

    @Test("the stage shows the player with a video, the home screen with recent videos, else the empty state")
    func stageContent() {
        #expect(StageContent(hasVideo: true, hasRecents: true) == .player)
        #expect(StageContent(hasVideo: true, hasRecents: false) == .player)
        #expect(StageContent(hasVideo: false, hasRecents: true) == .home)
        #expect(StageContent(hasVideo: false, hasRecents: false) == .empty)
    }

    @Test("the sidebar shows beside the player only")
    func sidebarOnPlayerOnly() {
        #expect(StageContent.player.showsSidebar)
        #expect(!StageContent.home.showsSidebar)
        #expect(!StageContent.empty.showsSidebar)
    }

    @Test("a first launch shows the empty state, and a launch after a video was opened shows the home screen")
    func launchShowsHome() async throws {
        defer { cleanUp() }
        let first = AppModel(environment: environment).makeWindow()
        #expect(StageContent(first) == .empty)
        try await first.open(MessageTests.fixture)
        #expect(StageContent(first) == .player)
        first.savePosition()

        let next = AppModel(environment: environment).makeWindow()
        #expect(next.video == nil)
        #expect(StageContent(next) == .home)
        next.removeRecent(try #require(next.recents.first).contentHash)
        #expect(StageContent(next) == .empty)
    }

    @Test("a thumbnail is the frame at the saved position, or at 1 second with no position")
    func thumbnailTime() {
        #expect(RecentCard.thumbnailTime(position: 12.5) == 12.5)
        #expect(RecentCard.thumbnailTime(position: 0) == 1)
        #expect(RecentCard.thumbnailTime(position: -3) == 1)
    }

    @Test("a card says when the video was last opened, relative to now")
    func openedLabel() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let locale = Locale(identifier: "en_US")
        #expect(RecentCard.openedLabel(now.addingTimeInterval(-20), now: now, locale: locale) == "Just now")
        #expect(RecentCard.openedLabel(now.addingTimeInterval(-2 * 3600), now: now, locale: locale) == "2 hours ago")
        #expect(RecentCard.openedLabel(now.addingTimeInterval(-3 * 86400), now: now, locale: locale) == "3 days ago")
        // A clock that went back reads as now, never as the future.
        #expect(RecentCard.openedLabel(now.addingTimeInterval(600), now: now, locale: locale) == "Just now")
    }

    @Test("a click on an available card opens its video")
    func openAvailable() async throws {
        defer { cleanUp() }
        let first = AppModel(environment: environment).makeWindow()
        try await first.open(MessageTests.fixture)

        let model = AppModel(environment: environment).makeWindow()
        let recent = try #require(model.recents.first)
        #expect(recent.available)
        model.openRecent(recent)
        await eventually { model.video != nil }
        #expect(model.video?.url == MessageTests.fixture.standardizedFileURL)
        #expect(model.problem == nil)
    }

    @Test("a click on an unavailable card does nothing; its trash button removes it")
    func unavailableCard() {
        defer { cleanUp() }
        let model = AppModel(environment: environment).makeWindow()
        model.desk.library.recordOpened(URL(fileURLWithPath: "/nowhere/gone.mp4"), contentHash: "gone", at: Date())
        #expect(model.recents.first?.available == false)
        #expect(StageContent(model) == .home)

        model.openRecent(gone())
        #expect(model.video == nil)
        #expect(model.problem == nil)
        #expect(model.recents.map(\.contentHash) == ["gone"])

        model.removeRecent("gone")
        #expect(model.recents.isEmpty)
        #expect(StageContent(model) == .empty)
    }

    @Test("a thumbnail is made once for a video and a position, and kept in memory")
    func thumbnails() async throws {
        defer { cleanUp() }
        let model = AppModel(environment: environment).makeWindow()
        try await model.open(MessageTests.fixture)
        try await model.seek(to: 2)
        model.savePosition()
        let recent = try #require(model.recents.first)
        #expect(recent.position >= 2)

        let thumbnails = Thumbnails()
        #expect(thumbnails.image(for: recent) == nil)
        await thumbnails.load(recent)
        let image = try #require(thumbnails.image(for: recent))
        #expect(image.size.width > 0)
        // A second load keeps the same image.
        await thumbnails.load(recent)
        #expect(thumbnails.image(for: recent) === image)
        // Another position is another frame.
        var moved = recent
        moved.position = 4
        #expect(thumbnails.image(for: moved) == nil)
        // Nothing is written to the support folder.
        let written = (try? FileManager.default.contentsOfDirectory(atPath: support.path)) ?? []
        #expect(!written.contains { $0.lowercased().contains("thumb") })
    }

    @Test("an unavailable video has no thumbnail")
    func noThumbnailWhenGone() async {
        let thumbnails = Thumbnails()
        await thumbnails.load(gone())
        #expect(thumbnails.image(for: gone()) == nil)
    }
}
