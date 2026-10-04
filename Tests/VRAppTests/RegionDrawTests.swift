import CoreGraphics
import Testing
@testable import VRApp
import VRReview

/// A rectangle drawn with the pointer, step by step, with no view.
@Suite struct RegionDrawTests {
    /// A 1920 by 1080 frame that fills a 960 by 540 view.
    let geometry = FrameGeometry(frame: CGSize(width: 1920, height: 1080), view: CGSize(width: 960, height: 540))

    @Test func aPressThatDoesNotMoveIsAClick() {
        var draw = RegionDraw()
        draw.begin(at: CGPoint(x: 100, y: 100))
        #expect(draw.phase == .pressed(at: CGPoint(x: 100, y: 100)))
        do { let found = draw.move(to: CGPoint(x: 104, y: 103)); #expect(found == .nothing) }
        #expect(!draw.isDrawing)
        #expect(draw.region(in: geometry) == nil)
        do { let found = draw.end(in: geometry); #expect(found == .click) }
        #expect(draw.phase == .idle)
    }

    @Test func aPressThatMovesPastTheClickDistanceDrawsARectangleThatFollowsThePointer() {
        var draw = RegionDraw()
        draw.begin(at: CGPoint(x: 240, y: 135))
        do { let found = draw.move(to: CGPoint(x: 245, y: 139)); #expect(found == .nothing) }
        do { let found = draw.move(to: CGPoint(x: 247, y: 141)); #expect(found == .began) }
        #expect(draw.isDrawing)
        do { let found = draw.move(to: CGPoint(x: 480, y: 270)); #expect(found == .moved) }
        #expect(draw.region(in: geometry) == Region(x: 0.25, y: 0.25, w: 0.25, h: 0.25))
        do { let found = draw.move(to: CGPoint(x: 720, y: 405)); #expect(found == .moved) }
        #expect(draw.region(in: geometry) == Region(x: 0.25, y: 0.25, w: 0.5, h: 0.5))
        do { let found = draw.end(in: geometry); #expect(found == .region(Region(x: 0.25, y: 0.25, w: 0.5, h: 0.5)!)) }
        #expect(draw.phase == .idle)
        #expect(draw.region(in: geometry) == nil)
    }

    @Test func aRectangleDrawnTowardsTheTopLeftIsTheSameRegion() {
        var draw = RegionDraw()
        draw.begin(at: CGPoint(x: 720, y: 405))
        do { let found = draw.move(to: CGPoint(x: 240, y: 135)); #expect(found == .began) }
        do { let found = draw.end(in: geometry); #expect(found == .region(Region(x: 0.25, y: 0.25, w: 0.5, h: 0.5)!)) }
    }

    @Test func aRectangleThatComesBackToItsStartIsStillARectangleNotAClick() {
        var draw = RegionDraw()
        draw.begin(at: CGPoint(x: 240, y: 135))
        do { let found = draw.move(to: CGPoint(x: 480, y: 270)); #expect(found == .began) }
        do { let found = draw.move(to: CGPoint(x: 240, y: 135)); #expect(found == .moved) }
        do { let found = draw.end(in: geometry); #expect(found == .empty) }
    }

    @Test func aRectangleWithNoneOfTheFrameInItEndsEmpty() {
        let pillarboxed = FrameGeometry(frame: CGSize(width: 1920, height: 1080), view: CGSize(width: 1600, height: 540))
        var draw = RegionDraw()
        draw.begin(at: CGPoint(x: 10, y: 10))
        do { let found = draw.move(to: CGPoint(x: 300, y: 500)); #expect(found == .began) }
        #expect(draw.region(in: pillarboxed) == nil)
        do { let found = draw.end(in: pillarboxed); #expect(found == .empty) }
    }

    @Test func escapeGivesUpTheRectangleAndTheRestOfTheDragDrawsNothing() {
        var draw = RegionDraw()
        draw.begin(at: CGPoint(x: 240, y: 135))
        do { let found = draw.move(to: CGPoint(x: 480, y: 270)); #expect(found == .began) }
        do { let cancelled = draw.cancel(); #expect(cancelled) }
        #expect(!draw.isDrawing)
        #expect(draw.region(in: geometry) == nil)
        // The button is still down: the drag goes on naming its start, and moves.
        draw.begin(at: CGPoint(x: 240, y: 135))
        do { let found = draw.move(to: CGPoint(x: 600, y: 300)); #expect(found == .nothing) }
        #expect(draw.region(in: geometry) == nil)
        do { let found = draw.end(in: geometry); #expect(found == .nothing) }
        #expect(draw.phase == .idle)
    }

    @Test func escapeBeforeThePressMovedGivesItUpTooAndIsNoClick() {
        var draw = RegionDraw()
        draw.begin(at: CGPoint(x: 240, y: 135))
        do { let cancelled = draw.cancel(); #expect(cancelled) }
        do { let found = draw.end(in: geometry); #expect(found == .nothing) }
    }

    @Test func escapeWithNothingUnderWayCancelsNothing() {
        var draw = RegionDraw()
        do { let cancelled = draw.cancel(); #expect(!cancelled) }
        draw.begin(at: CGPoint(x: 240, y: 135))
        _ = draw.move(to: CGPoint(x: 480, y: 270))
        do { let cancelled = draw.cancel(); #expect(cancelled) }
        do { let cancelled = draw.cancel(); #expect(!cancelled) }
    }

    @Test func aDragNamingItsStartWithEveryMoveKeepsItsRectangle() {
        var draw = RegionDraw()
        for point in [CGPoint(x: 300, y: 200), CGPoint(x: 400, y: 300), CGPoint(x: 480, y: 270)] {
            draw.begin(at: CGPoint(x: 240, y: 135))
            _ = draw.move(to: point)
        }
        #expect(draw.phase == .drawing(from: CGPoint(x: 240, y: 135), to: CGPoint(x: 480, y: 270)))
    }

    @Test func aNewPressAfterACancelledOneThatNeverEndedDrawsAgain() {
        var draw = RegionDraw()
        draw.begin(at: CGPoint(x: 240, y: 135))
        _ = draw.move(to: CGPoint(x: 480, y: 270))
        do { let cancelled = draw.cancel(); #expect(cancelled) }
        draw.begin(at: CGPoint(x: 480, y: 270))
        do { let found = draw.move(to: CGPoint(x: 720, y: 405)); #expect(found == .began) }
        do { let found = draw.end(in: geometry); #expect(found == .region(Region(x: 0.5, y: 0.5, w: 0.25, h: 0.25)!)) }
    }

    @Test func movesAndAReleaseWithNoPressDoNothing() {
        var draw = RegionDraw()
        do { let found = draw.move(to: CGPoint(x: 480, y: 270)); #expect(found == .nothing) }
        do { let found = draw.end(in: geometry); #expect(found == .nothing) }
        #expect(draw.phase == .idle)
    }
}
