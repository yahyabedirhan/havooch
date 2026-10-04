import CoreGraphics
import Testing
@testable import VRApp
import VRReview

/// Where the frame sits in a view, and view points to regions and back: a
/// 1920 by 1080 frame in windows that fit it, are too tall for it
/// (letterboxed) and too wide for it (pillarboxed).
@Suite struct FrameGeometryTests {
    static let frame = CGSize(width: 1920, height: 1080)
    /// View sizes: the frame's own shape, taller ones, wider ones, a portrait one and a small one.
    static let views = [
        CGSize(width: 960, height: 540), CGSize(width: 1000, height: 800), CGSize(width: 640, height: 720),
        CGSize(width: 1600, height: 540), CGSize(width: 2400, height: 400), CGSize(width: 400, height: 1200),
        CGSize(width: 320, height: 181),
    ]
    static let regions = [
        Region(x: 0.48, y: 0.3, w: 0.28, h: 0.12)!, Region(x: 0, y: 0, w: 1, h: 1)!, Region(x: 0.9, y: 0.05, w: 0.1, h: 0.2)!,
        Region(x: 0, y: 0.75, w: 0.25, h: 0.25)!,
    ]

    private func geometry(_ view: CGSize) -> FrameGeometry {
        FrameGeometry(frame: Self.frame, view: view)
    }

    private func near(_ one: Region, _ other: Region) -> Bool {
        zip([one.x, one.y, one.w, one.h], [other.x, other.y, other.w, other.h]).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    @Test func aViewOfTheFramesShapeIsFilledByIt() {
        #expect(geometry(CGSize(width: 960, height: 540)).frameRect == CGRect(x: 0, y: 0, width: 960, height: 540))
    }

    @Test func aTallerViewHasBarsAboveAndBelowTheFrame() {
        #expect(geometry(CGSize(width: 1000, height: 800)).frameRect == CGRect(x: 0, y: 118.75, width: 1000, height: 562.5))
    }

    @Test func aWiderViewHasBarsAtTheFramesSides() {
        #expect(geometry(CGSize(width: 1600, height: 540)).frameRect == CGRect(x: 320, y: 0, width: 960, height: 540))
    }

    @Test func aPortraitFrameIsFittedTheSameWay() {
        let geometry = FrameGeometry(frame: CGSize(width: 1080, height: 1920), view: CGSize(width: 960, height: 960))
        #expect(geometry.frameRect == CGRect(x: 210, y: 0, width: 540, height: 960))
    }

    @Test func aViewOrAFrameWithoutAnAreaHoldsNoFrameAndNoRegion() {
        for geometry in [
            geometry(.zero), geometry(CGSize(width: 0, height: 500)), FrameGeometry(frame: .zero, view: CGSize(width: 960, height: 540)),
        ] {
            #expect(geometry.frameRect == .zero)
            #expect(geometry.region(from: .zero, to: CGPoint(x: 100, y: 100)) == nil)
        }
    }

    @Test func aRegionLiesOnTheSamePartOfTheFrameAtEveryWindowSize() {
        for view in Self.views {
            let geometry = geometry(view), frame = geometry.frameRect
            for region in Self.regions {
                let rect = geometry.rect(of: region)
                #expect(abs((rect.minX - frame.minX) / frame.width - region.x) < 1e-9)
                #expect(abs((rect.minY - frame.minY) / frame.height - region.y) < 1e-9)
                #expect(abs(rect.width / frame.width - region.w) < 1e-9)
                #expect(abs(rect.height / frame.height - region.h) < 1e-9)
                #expect(frame.insetBy(dx: -1e-6, dy: -1e-6).contains(rect))
            }
        }
    }

    @Test func aRegionsRectangleDrawnAgainGivesTheRegionBackAtEveryWindowSize() throws {
        for view in Self.views {
            let geometry = geometry(view)
            for region in Self.regions {
                let rect = geometry.rect(of: region)
                let back = try #require(geometry.region(from: rect.origin, to: CGPoint(x: rect.maxX, y: rect.maxY)))
                #expect(near(back, region), "\(view) \(region)")
                // From the opposite corners too.
                let mirrored = try #require(geometry.region(from: CGPoint(x: rect.maxX, y: rect.minY), to: CGPoint(x: rect.minX, y: rect.maxY)))
                #expect(near(mirrored, region))
            }
        }
    }

    @Test func aRegionDrawnInOneWindowSizeIsShownOnTheSamePixelsInAnother() throws {
        // Drawn in a letterboxed window, shown in a pillarboxed one: the frame's pixels under it are the same.
        let drawn = geometry(CGSize(width: 1000, height: 800)), shown = geometry(CGSize(width: 1600, height: 540))
        let region = try #require(drawn.region(from: CGPoint(x: 480, y: 287.5), to: CGPoint(x: 760, y: 355)))
        #expect(near(region, Region(x: 0.48, y: 0.3, w: 0.28, h: 0.12)!))
        let pixels = region.pixels(in: (width: 1920, height: 1080))
        #expect((pixels.x, pixels.y, pixels.width, pixels.height) == (922, 324, 537, 130))
        let rect = shown.rect(of: region)
        #expect(abs(rect.minX - (320 + 0.48 * 960)) < 1e-6)
        #expect(abs(rect.minY - 0.3 * 540) < 1e-6)
        #expect(abs(rect.width - 0.28 * 960) < 1e-6)
        #expect(abs(rect.height - 0.12 * 540) < 1e-6)
    }

    @Test func aDragThatRunsOverTheBarsKeepsOnlyWhatIsOnTheFrame() throws {
        let pillarboxed = geometry(CGSize(width: 1600, height: 540))
        #expect(pillarboxed.region(from: .zero, to: CGPoint(x: 800, y: 270)) == Region(x: 0, y: 0, w: 0.5, h: 0.5))
        #expect(pillarboxed.region(from: CGPoint(x: 800, y: 270), to: CGPoint(x: 1600, y: 900)) == Region(x: 0.5, y: 0.5, w: 0.5, h: 0.5))
        let letterboxed = geometry(CGSize(width: 1000, height: 800))
        #expect(letterboxed.region(from: CGPoint(x: 250, y: 0), to: CGPoint(x: 750, y: 400)) == Region(x: 0.25, y: 0, w: 0.5, h: 0.5))
    }

    @Test func aDragOnTheBarsAloneGivesNoRegion() {
        let pillarboxed = geometry(CGSize(width: 1600, height: 540))
        #expect(pillarboxed.region(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 300, y: 500)) == nil)
        #expect(pillarboxed.region(from: CGPoint(x: 1300, y: 10), to: CGPoint(x: 1590, y: 500)) == nil)
        let letterboxed = geometry(CGSize(width: 1000, height: 800))
        #expect(letterboxed.region(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 900, y: 100)) == nil)
    }

    // MARK: - The comment box next to a region

    static let box = CGSize(width: 360, height: 100)

    @Test func theBoxGoesToTheRightOfTheRegionWhenThereIsRoom() {
        let geometry = geometry(CGSize(width: 1200, height: 675))
        let origin = geometry.origin(ofBox: Self.box, beside: CGRect(x: 200, y: 150, width: 300, height: 120))
        #expect(origin == CGPoint(x: 512, y: 150))
    }

    @Test func theBoxGoesToTheLeftWhenTheRightHasNoRoom() {
        let geometry = geometry(CGSize(width: 1200, height: 675))
        let origin = geometry.origin(ofBox: Self.box, beside: CGRect(x: 800, y: 150, width: 300, height: 120))
        #expect(origin == CGPoint(x: 428, y: 150))
    }

    @Test func theBoxGoesBelowThenAboveAWideRegion() {
        let geometry = geometry(CGSize(width: 1200, height: 675))
        let below = geometry.origin(ofBox: Self.box, beside: CGRect(x: 100, y: 100, width: 1000, height: 200))
        #expect(below == CGPoint(x: 100, y: 312))
        let above = geometry.origin(ofBox: Self.box, beside: CGRect(x: 100, y: 400, width: 1000, height: 250))
        #expect(above == CGPoint(x: 100, y: 288))
    }

    @Test func theBoxStaysBesideARegionAtTheFootOfTheViewWithoutLeavingIt() {
        let geometry = geometry(CGSize(width: 1200, height: 675))
        let origin = geometry.origin(ofBox: Self.box, beside: CGRect(x: 200, y: 620, width: 300, height: 50))
        #expect(origin == CGPoint(x: 512, y: 567))
    }

    @Test func theBoxGoesOverARegionThatFillsTheView() {
        let geometry = geometry(CGSize(width: 1200, height: 675))
        let origin = geometry.origin(ofBox: Self.box, beside: CGRect(x: 0, y: 0, width: 1200, height: 675))
        #expect(origin == CGPoint(x: 832, y: 8))
    }

    @Test func theBoxIsWholeInTheViewForEveryRegionAtEveryWindowSize() {
        for view in Self.views where view.width >= Self.box.width + 16 && view.height >= Self.box.height + 16 {
            let geometry = geometry(view)
            let inside = CGRect(origin: .zero, size: view).insetBy(dx: 8 - 1e-6, dy: 8 - 1e-6)
            for region in Self.regions {
                let rect = geometry.rect(of: region)
                let box = CGRect(origin: geometry.origin(ofBox: Self.box, beside: rect), size: Self.box)
                #expect(inside.contains(box), "\(view) \(region)")
            }
        }
    }

    @Test func theBoxDoesNotCoverARegionThatLeavesItRoom() {
        let geometry = geometry(CGSize(width: 1200, height: 675))
        for region in [Self.regions[0], Self.regions[2], Self.regions[3]] {
            let rect = geometry.rect(of: region)
            let box = CGRect(origin: geometry.origin(ofBox: Self.box, beside: rect), size: Self.box)
            #expect(!box.intersects(rect), "\(region)")
        }
    }
}
