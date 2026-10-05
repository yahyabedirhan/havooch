import Foundation
import Testing
import VRReview

@Suite struct RegionTests {
    @Test(arguments: [
        (0.0, 0.0, 1.0, 1.0), (0.48, 0.3, 0.28, 0.12), (0.7, 0.0, 0.3, 1.0), (0.0, 0.9, 0.1, 0.1), (0.999, 0.999, 0.001, 0.001),
    ])
    func aRectangleInsideTheFrameIsARegion(x: Double, y: Double, w: Double, h: Double) throws {
        let region = try #require(Region(x: x, y: y, w: w, h: h))
        #expect((region.x, region.y, region.w, region.h) == (x, y, w, h))
        #expect(try Region.checked(x: x, y: y, w: w, h: h) == region)
    }

    @Test(arguments: [
        (-0.01, 0.0, 0.5, 0.5), (0.0, -0.01, 0.5, 0.5), (0.2, 0.2, 0.0, 0.5), (0.2, 0.2, 0.5, 0.0), (0.2, 0.2, -0.1, 0.5),
        (0.6, 0.0, 0.5, 0.5), (0.0, 0.6, 0.5, 0.5), (1.0, 0.0, 0.1, 0.1), (0.0, 0.0, 1.01, 1.0), (48, 30, 28, 12),
        (Double.nan, 0.0, 0.5, 0.5), (0.0, 0.0, Double.infinity, 0.5),
    ])
    func aRectangleOutsideTheFrameOrWithoutAnAreaIsRefused(x: Double, y: Double, w: Double, h: Double) {
        #expect(Region(x: x, y: y, w: w, h: h) == nil)
        #expect(throws: ReviewError.regionOutsideFrame) { try Region.checked(x: x, y: y, w: w, h: h) }
    }

    @Test func theRefusalSaysWhatARegionIs() {
        #expect(ReviewError.regionOutsideFrame.message
            == "a region must lie inside the frame: x, y, w and h are parts of it from 0 to 1, w and h above 0, x + w and y + h at most 1")
    }

    @Test(arguments: [
        ((0.25, 0.5), (0.75, 0.75)), ((0.75, 0.75), (0.25, 0.5)), ((0.75, 0.5), (0.25, 0.75)), ((0.25, 0.75), (0.75, 0.5)),
    ] as [((Double, Double), (Double, Double))])
    func twoCornersInAnyOrderSpanTheSameRegion(one: (Double, Double), other: (Double, Double)) throws {
        let expected = try #require(Region(x: 0.25, y: 0.5, w: 0.5, h: 0.25))
        #expect(Region.spanning(from: one, to: other) == expected)
    }

    @Test func aCornerOutsideTheFrameIsBroughtOntoIt() {
        #expect(Region.spanning(from: (-0.5, -2), to: (0.5, 0.25)) == Region(x: 0, y: 0, w: 0.5, h: 0.25))
        #expect(Region.spanning(from: (0.5, 0.75), to: (3, 1.5)) == Region(x: 0.5, y: 0.75, w: 0.5, h: 0.25))
        #expect(Region.spanning(from: (-1, -1), to: (2, 2)) == Region(x: 0, y: 0, w: 1, h: 1))
    }

    @Test func cornersWithNoneOfTheFrameBetweenThemSpanNothing() {
        #expect(Region.spanning(from: (0.5, 0.5), to: (0.5, 0.9)) == nil)
        #expect(Region.spanning(from: (0.2, 0.3), to: (0.2, 0.3)) == nil)
        #expect(Region.spanning(from: (-0.5, 0.2), to: (-0.1, 0.8)) == nil)
        #expect(Region.spanning(from: (1.2, 1.2), to: (1.5, 1.5)) == nil)
        #expect(Region.spanning(from: (Double.nan, 0.2), to: (0, 0.8)) == nil)
    }

    @Test(arguments: [
        ((0.48, 0.3, 0.28, 0.12), (922, 324, 537, 130)),
        ((0.0, 0.0, 1.0, 1.0), (0, 0, 1920, 1080)),
        ((0.5, 0.5, 0.5, 0.5), (960, 540, 960, 540)),
        ((0.7, 0.0, 0.3, 1.0), (1344, 0, 576, 1080)),
        ((0.25, 0.25, 0.0001, 0.0001), (480, 270, 1, 1)),
        ((0.9999, 0.9999, 0.0001, 0.0001), (1919, 1079, 1, 1)),
    ])
    func aRegionsPixelsAreItsEdgesAtTheNearestPixelInsideTheFrame(
        region: (Double, Double, Double, Double), pixels: (Int, Int, Int, Int)
    ) throws {
        let region = try #require(Region(x: region.0, y: region.1, w: region.2, h: region.3))
        let found = region.pixels(in: (width: 1920, height: 1080))
        #expect((found.x, found.y, found.width, found.height) == pixels)
    }

    @Test(arguments: [(1920, 1080), (1280, 720), (640, 360), (1080, 1920)])
    func theSameRegionCutsTheSamePartOfAFrameOfAnySize(width: Int, height: Int) throws {
        let region = try #require(Region(x: 0.25, y: 0.5, w: 0.5, h: 0.25))
        let pixels = region.pixels(in: (width: width, height: height))
        #expect((pixels.x, pixels.y, pixels.width, pixels.height) == (width / 4, height / 2, width / 2, height / 4))
    }

    @Test func aRegionIsStoredAsItsFourNumbersAndAStoredOneOutsideTheFrameDoesNotRead() throws {
        let region = try #require(Region(x: 0.25, y: 0.5, w: 0.5, h: 0.25))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(region), as: UTF8.self)
        #expect(json == #"{"h":0.25,"w":0.5,"x":0.25,"y":0.5}"#)
        #expect(try JSONDecoder().decode(Region.self, from: Data(json.utf8)) == region)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Region.self, from: Data(#"{"h":0.5,"w":0.5,"x":0.75,"y":0.5}"#.utf8))
        }
    }
}
