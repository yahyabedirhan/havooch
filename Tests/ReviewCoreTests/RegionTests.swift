import Foundation
import ReviewCore
import Testing

@Suite("A region of the frame")
struct RegionTests {
    static let video = VideoInfo(contentHash: "abc", title: "sample", duration: 21.233, path: "/videos/sample.mp4")

    @Test("a rectangle inside the frame is a region", arguments: [
        [0.25, 0.2, 0.3, 0.25], [0, 0, 1, 1], [0.7, 0.9, 0.3, 0.1], [0.999, 0.999, 0.001, 0.001],
    ])
    func inside(numbers: [Double]) throws {
        let region = try Region(x: numbers[0], y: numbers[1], w: numbers[2], h: numbers[3])
        #expect([region.x, region.y, region.w, region.h] == numbers)
    }

    @Test("a value outside 0 to 1, a rectangle that leaves the frame, and no width or height are refused", arguments: [
        [-0.1, 0.2, 0.3, 0.25], [0.25, 1.2, 0.3, 0.25], [0.25, 0.2, 1.5, 0.25], [0.9, 0.2, 0.3, 0.25],
        [0.25, 0.9, 0.3, 0.25], [0.25, 0.2, 0, 0.25], [0.25, 0.2, 0.3, 0], [0.25, 0.2, -0.3, 0.25],
        [Double.nan, 0.2, 0.3, 0.25], [0.25, 0.2, .infinity, 0.25],
    ])
    func refused(numbers: [Double]) {
        #expect(throws: ReviewRefusal.self) { try Region(x: numbers[0], y: numbers[1], w: numbers[2], h: numbers[3]) }
    }

    @Test("the refusal names the numbers and what a region is")
    func refusalLine() {
        #expect(ReviewRefusal.badRegion(x: 0.9, y: 0.2, w: 0.3, h: 0.25).line.hasPrefix(
            "the region 0.9,0.2,0.3,0.25 isn't a rectangle inside the frame; give x,y,w,h from 0 to 1"
        ))
    }

    @Test("a region reads back from JSON, and one that isn't inside the frame doesn't")
    func json() throws {
        let region = try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        #expect(try JSONDecoder().decode(Region.self, from: JSONEncoder().encode(region)) == region)
        #expect(region.text == "0.25,0.2,0.3,0.25")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Region.self, from: Data(#"{"x": 0.9, "y": 0.2, "w": 0.3, "h": 0.25}"#.utf8))
        }
    }

    @Test("a region's pixels are whole, inside the picture, and the same part of it at any size")
    func pixels() throws {
        let region = try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        #expect(region.pixels(width: 1920, height: 1080) == (480, 216, 576, 270))
        #expect(region.pixels(width: 960, height: 540) == (240, 108, 288, 135))
        #expect(try Region(x: 0, y: 0, w: 1, h: 1).pixels(width: 1920, height: 1080) == (0, 0, 1920, 1080))
        // A sliver still has a pixel, and the last pixel is still inside.
        #expect(try Region(x: 0.5, y: 0.5, w: 0.0001, h: 0.0001).pixels(width: 100, height: 100) == (50, 50, 1, 1))
        #expect(try Region(x: 0.999, y: 0.999, w: 0.001, h: 0.001).pixels(width: 100, height: 100) == (99, 99, 1, 1))
    }

    @Test("a comment keeps its region, and a comment without one has none")
    func comment() throws {
        var review = VideoReview(video: Self.video)
        let region = try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        let pointed = try review.addComment(id: ItemID("c-00000001")!, time: 12.5, text: "This box", region: region)
        let plain = try review.addComment(id: ItemID("c-00000002")!, time: 3, text: "Too fast")
        #expect(pointed.region == region)
        #expect(plain.region == nil)
        #expect(try JSONDecoder().decode(VideoReview.self, from: JSONEncoder().encode(review)) == review)
    }
}
