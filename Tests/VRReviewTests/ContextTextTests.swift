import Foundation
import Testing
import VRReview

/// Where a video's context sidecar is looked for, and how its text and the
/// reviewer's note become the one text a listener gets.
@Suite struct ContextTextTests {
    @Test func theSidecarNamedAfterTheVideoIsLookedForBeforeAPlainContextFile() {
        let candidates = ContextText.candidates(for: URL(fileURLWithPath: "/videos/demo/lease walk.v2.mp4"))

        #expect(candidates.map(\.path) == ["/videos/demo/lease walk.v2.context.md", "/videos/demo/context.md"])
    }

    @Test(arguments: [
        // sidecar, note, the text
        ("# Context: sample\n\nThe topic.\n", "", "# Context: sample\n\nThe topic."),
        ("# Context: sample\n", "Look at the lease banner.", "# Context: sample\n\n## Note from the reviewer\n\nLook at the lease banner."),
        (nil, "  Look at the lease banner.\n", "## Note from the reviewer\n\nLook at the lease banner."),
        ("  \n", "a note", "## Note from the reviewer\n\na note"),
        ("# Context", " \n ", "# Context"),
        (nil, "", ""),
        ("\n\n", "   ", ""),
    ] as [(String?, String, String)])
    func theSidecarTextComesFirstThenTheNoteUnderItsHeading(sidecar: String?, note: String, text: String) {
        #expect(ContextText.compose(sidecar: sidecar, note: note) == text)
    }

    @Test func aReviewKeepsItsNoteWithoutTheBlankSpaceAroundIt() {
        var review = Review(video: VideoInfo(contentHash: String(repeating: "a", count: 64), path: "/v/sample.mp4", title: "sample", duration: 20))
        #expect(review.note == "")

        review.setNote("  the lease walk,\nfrom shipyard \n")
        #expect(review.note == "the lease walk,\nfrom shipyard")

        review.setNote(" \n")
        #expect(review.note == "")
    }
}
