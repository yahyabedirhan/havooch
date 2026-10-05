import Foundation
import Testing
@testable import VRApp

/// A player whose seeks land only when the test lets them, so a test can
/// ask for more while one is on its way.
@MainActor
final class HeldPlayer: Playing {
    var time = 0.0
    var isPlaying = false
    /// Every time a seek was started to, in order.
    private(set) var seeks: [Double] = []
    private var landing: [CheckedContinuation<Void, Never>] = []

    /// How many seeks wait to land.
    var waiting: Int { landing.count }

    func load(_ url: URL) async throws {
        time = 0
        isPlaying = false
    }

    func play() { isPlaying = true }
    func pause() { isPlaying = false }

    func seek(to seconds: Double) async {
        seeks.append(seconds)
        await withCheckedContinuation { landing.append($0) }
        time = seconds
    }

    /// Lets the oldest seek on its way land.
    func land() {
        guard !landing.isEmpty else { return }
        landing.removeFirst().resume()
    }
}

@MainActor
@Suite struct ScrubTests {
    let player = HeldPlayer()
    let model: ReviewModel

    init() {
        model = ReviewModel(player: player, frames: FakeFrames(), library: scratchLibrary())
    }

    func opened() async throws -> ScrubTests {
        try await model.open(fixtureVideo)
        return self
    }

    @Test func aDragsManySeeksEndWhereThePointerStopped() async throws {
        let rig = try await opened()

        let seeking = try #require(rig.model.scrub(to: 2))
        await settle(until: { rig.player.waiting == 1 })
        // Asked while the first is on its way: only the last is kept.
        rig.model.scrub(to: 4)
        rig.model.scrub(to: 6)
        rig.model.scrub(to: 8)
        #expect(rig.model.shownTime == 8)
        rig.player.land()
        await settle(until: { rig.player.waiting == 1 })
        rig.player.land()
        await seeking.value

        #expect(rig.player.seeks == [2, 8])
        #expect(rig.player.time == 8)
        #expect(rig.model.shownTime == 8)
    }

    @Test func aScrubIsKeptInsideTheVideo() async throws {
        let rig = try await opened()

        let seeking = try #require(rig.model.scrub(to: -3))
        await settle(until: { rig.player.waiting == 1 })
        rig.model.scrub(to: 500)
        rig.player.land()
        await settle(until: { rig.player.waiting == 1 })
        rig.player.land()
        await seeking.value

        #expect(rig.player.seeks == [0, rig.model.duration])
    }

    @Test func aDragPausesThePlayingVideoAndPlaysItAgainOnceTheLastSeekLands() async throws {
        let rig = try await opened()
        rig.player.isPlaying = true

        rig.model.beginScrub()
        #expect(!rig.player.isPlaying)
        let seeking = try #require(rig.model.scrub(to: 5))
        await settle(until: { rig.player.waiting == 1 })
        rig.model.endScrub()
        // Not before the player is where the drag stopped.
        #expect(!rig.player.isPlaying)
        rig.player.land()
        await seeking.value

        #expect(rig.player.isPlaying)
        #expect(rig.player.time == 5)
    }

    @Test func aDragOnAPausedVideoLeavesItPaused() async throws {
        let rig = try await opened()

        rig.model.beginScrub()
        let seeking = try #require(rig.model.scrub(to: 5))
        await settle(until: { rig.player.waiting == 1 })
        rig.player.land()
        await seeking.value
        rig.model.endScrub()

        #expect(!rig.player.isPlaying)
    }

    @Test func skipsFasterThanTheSeeksAddUp() async throws {
        let rig = try await opened()

        rig.model.skip(by: 5)
        await settle(until: { rig.player.waiting == 1 })
        rig.model.skip(by: 5)
        #expect(rig.model.shownTime == 10)
        rig.player.land()
        await settle(until: { rig.player.waiting == 1 })
        rig.player.land()
        await settle(until: { rig.player.time == 10 })

        #expect(rig.player.seeks == [5, 10])
    }

    @Test func thereIsNothingToScrubWithNoVideo() {
        #expect(model.scrub(to: 5) == nil)
        model.beginScrub()
        model.endScrub()
        #expect(player.seeks.isEmpty)
    }
}
