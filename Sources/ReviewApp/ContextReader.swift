import Foundation
import ReviewCore

/// The video context the listener is told: the text of the sidecar file in
/// the video's folder, then the person's note under its own heading. It's
/// read when a `wait` takes a batch, so nothing watches the file.
enum ContextReader {
    /// The sidecar file that serves a video, and its text.
    struct Sidecar: Equatable {
        var file: URL
        /// The file's text without the space around it; empty for a blank file.
        var text: String
    }

    /// The heading the person's note stands under in the context.
    static let noteHeading = "## Note from the reviewer"

    /// The names a video's sidecar may have, in the order they're looked
    /// for: `<video base name>.context.md`, then `context.md`.
    static func names(for video: URL) -> [String] {
        ["\(video.deletingPathExtension().lastPathComponent).context.md", "context.md"]
    }

    /// The sidecar in `video`'s folder: the first of its names that's a
    /// file there and reads as text. A blank file with the video's own name
    /// still serves it, so a video can opt out of its folder's `context.md`.
    static func sidecar(beside video: URL) -> Sidecar? {
        let folder = video.deletingLastPathComponent()
        for name in names(for: video) {
            let file = folder.appendingPathComponent(name)
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            return Sidecar(file: file, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    /// The context as the payload carries it: `sidecar`, then `note` under
    /// its heading, each without the space around it. Nil when both are
    /// empty.
    static func text(sidecar: String?, note: String) -> String? {
        let sidecar = sidecar?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [sidecar, note.isEmpty ? "" : "\(noteHeading)\n\n\(note)"].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// The context of `review`'s video as it is now: the sidecar where the
    /// video was last opened, and the review's note.
    static func text(for review: VideoReview) -> String? {
        text(sidecar: sidecar(beside: URL(fileURLWithPath: review.video.path))?.text, note: review.note)
    }
}
