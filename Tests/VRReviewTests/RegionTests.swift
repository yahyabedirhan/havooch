import Foundation
import Testing
import VRReview

private func refusal(x: Double, y: Double, w: Double, h: Double) -> String? {
    do throws(ReviewRefusal) {
        _ = try Region(x: x, y: y, w: w, h: h)
        return nil
    } catch {
        return error.reason
    }
}

@Suite struct RegionTests {
    @Test(arguments: [
        [0.0, 0, 1, 1],
        [0.1, 0.2, 0.3, 0.25],
        [0.5, 0.5, 0.5, 0.5],
        // Parts that add up to the edge but for rounding.
        [0.7, 0.9, 0.3, 0.1],
    ])
    func aRectangleInsideTheFrameIsARegion(parts: [Double]) {
        #expect(refusal(x: parts[0], y: parts[1], w: parts[2], h: parts[3]) == nil)
    }

    @Test(arguments: [
        ([-0.1, 0.0, 0.5, 0.5], "-0.1,0,0.5,0.5"),
        ([0.0, 0.0, 0.0, 0.5], "0,0,0,0.5"),
        ([0.0, 0.0, 0.5, -0.5], "0,0,0.5,-0.5"),
        ([0.9, 0.2, 0.3, 0.2], "0.9,0.2,0.3,0.2"),
        ([0.0, 0.6, 0.5, 0.5], "0,0.6,0.5,0.5"),
        ([0.0, 0.0, 2.0, 1.0], "0,0,2,1"),
        ([0.0, 0.0, Double.nan, 1.0], "0,0,nan,1"),
    ])
    func aRectangleOutsideTheFrameOrWithNoAreaIsRefused(parts: [Double], text: String) {
        #expect(refusal(x: parts[0], y: parts[1], w: parts[2], h: parts[3])
            == "the region \(text) isn't inside the frame: x,y,w,h are parts of the frame from 0 to 1, with w and h above 0, x + w and y + h at most 1")
    }

    @Test func aRegionCoversTheSamePartOfAFrameOfAnySize() throws {
        let quarter = try Region(x: 0.5, y: 0, w: 0.5, h: 0.5)
        #expect(quarter.pixelRect(in: CGSize(width: 1920, height: 1080)) == CGRect(x: 960, y: 0, width: 960, height: 540))
        #expect(quarter.pixelRect(in: CGSize(width: 1280, height: 720)) == CGRect(x: 640, y: 0, width: 640, height: 360))
        #expect(try Region(x: 0, y: 0, w: 1, h: 1).pixelRect(in: CGSize(width: 1920, height: 1080))
            == CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    @Test func thePixelsAreWholeRoundedOutwardAndInsideTheFrame() throws {
        // 0.101 × 1920 = 193.92 and 0.401 × 1920 = 769.92: from 193 to 770.
        let region = try Region(x: 0.101, y: 0.201, w: 0.3, h: 0.25)
        #expect(region.pixelRect(in: CGSize(width: 1920, height: 1080)) == CGRect(x: 193, y: 217, width: 577, height: 271))
        // The edge, but for rounding: never past the frame.
        #expect(try Region(x: 0.7, y: 0.9, w: 0.3, h: 0.1).pixelRect(in: CGSize(width: 1920, height: 1080))
            == CGRect(x: 1344, y: 972, width: 576, height: 108))
        // A sliver is still one pixel.
        #expect(try Region(x: 0.5, y: 0.5, w: 0.00001, h: 0.00001).pixelRect(in: CGSize(width: 100, height: 100))
            == CGRect(x: 50, y: 50, width: 1, height: 1))
    }

    @Test func aRegionReadsAsTheCommandLineTakesIt() throws {
        #expect(try Region(x: 0.1, y: 0.2, w: 0.3, h: 0.25).text == "0.1,0.2,0.3,0.25")
        #expect(try Region(x: 0, y: 0, w: 1, h: 1).text == "0,0,1,1")
    }
}

@Suite struct RegionCommentTests {
    private let video = VideoInfo(path: "/Users/me/sample.mp4", contentHash: "abc", duration: 21.233, title: "sample")

    @Test func aDraftKeepsItsRegionThroughTheQueue() throws {
        var session = ReviewSession(video: video)
        let region = try Region(x: 0.1, y: 0.2, w: 0.3, h: 0.25)

        session.draft(id: "c1", time: 10, region: region)
        session.draft(id: "c2", time: 5)
        try session.commit("c1", text: "this button")

        #expect(session.comment("c1")?.region == region)
        #expect(session.comment("c2")?.region == nil)
        #expect(session.queue.map(\.region) == [region])
    }

    @Test func aRegionIsKeptAsItsFourParts() throws {
        var session = ReviewSession(video: video)
        session.draft(id: "c1", time: 10, region: try Region(x: 0.5, y: 0, w: 0.25, h: 0.5))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let kept = try encoder.encode(session)

        #expect(String(decoding: kept, as: UTF8.self).contains(#""region":{"h":0.5,"w":0.25,"x":0.5,"y":0}"#))
        #expect(try JSONDecoder().decode(ReviewSession.self, from: kept) == session)
    }

    @Test func aCommentKeptWithoutARegionHasNone() throws {
        let json = """
            {"video":{"path":"/Users/me/sample.mp4","contentHash":"abc","duration":21.233,"title":"sample"},
             "comments":[{"id":"c1","time":10,"text":"too fast","state":"queued"}]}
            """
        let session = try JSONDecoder().decode(ReviewSession.self, from: Data(json.utf8))
        #expect(session.comment("c1")?.region == nil)
    }
}
