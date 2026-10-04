import Foundation
import VRReview

/// Reads the context sidecar of a video from its folder.
enum ContextSource {
    /// A sidecar that was found: where it is and what it says.
    struct Sidecar: Equatable, Sendable {
        var url: URL
        var text: String
    }

    /// The sidecar of `video`: the first of `ContextText.candidates` that
    /// is there and reads as text, or nil when none does. Read each time,
    /// so a change to the file is seen by the next batch.
    static func read(for video: URL) -> Sidecar? {
        for url in ContextText.candidates(for: video) {
            if let text = try? String(contentsOf: url, encoding: .utf8) { return Sidecar(url: url, text: text) }
        }
        return nil
    }

    /// The context of `review`'s video as a listener gets it: its
    /// sidecar's text and the reviewer's note. Empty when there is neither.
    static func text(for review: Review) -> String {
        ContextText.compose(sidecar: read(for: URL(fileURLWithPath: review.video.path))?.text, note: review.note)
    }
}
