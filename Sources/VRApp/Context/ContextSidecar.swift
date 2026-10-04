import Foundation
import VRReview

/// A video's context file: Markdown beside the video that says what the
/// video is about, for the listener. `<base>.context.md` for the video
/// `<base>.<ext>`, else `context.md` for every video of the folder.
struct ContextSidecar: Equatable, Sendable {
    /// The heading the person's note goes under in the context's text.
    static let noteHeading = "## Reviewer's note"

    var url: URL
    /// The file's text as it was on disk when it was found.
    var text: String

    /// The names a context file of `video` may have; the first one wins.
    static func names(for video: URL) -> [String] {
        ["\(video.deletingPathExtension().lastPathComponent).context.md", "context.md"]
    }

    /// The context file of `video`, read now: the first of `names` that is
    /// a file that reads, even an empty one. Nil with none.
    static func find(beside video: URL) -> ContextSidecar? {
        let folder = video.deletingLastPathComponent()
        for name in names(for: video) {
            let url = folder.appendingPathComponent(name)
            // A folder of that name, or a file that can't be read, isn't one.
            guard let data = try? Data(contentsOf: url) else { continue }
            return ContextSidecar(url: url, text: String(decoding: data, as: UTF8.self))
        }
        return nil
    }

    /// The context as the listener gets it: the sidecar's text, then the
    /// note under `noteHeading`, each without the white space around it.
    /// Nil when both are empty.
    static func text(sidecar: String?, note: String) -> String? {
        let sidecar = ReviewSession.trimmed(sidecar ?? "")
        let note = ReviewSession.trimmed(note)
        var parts: [String] = []
        if !sidecar.isEmpty { parts.append(sidecar) }
        if !note.isEmpty { parts.append("\(noteHeading)\n\n\(note)") }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n") + "\n"
    }
}
