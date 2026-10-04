import Foundation

/// The context of a video, as the listener gets it: where its sidecar is
/// looked for, and how the sidecar's text and the reviewer's note become
/// one text.
public enum ContextText {
    /// The heading the reviewer's note goes under.
    public static let noteHeading = "## Note from the reviewer"

    /// The files that may hold the context of `video`, in the order they
    /// are looked for: `<video base name>.context.md` beside the video,
    /// then a plain `context.md` in the same folder.
    public static func candidates(for video: URL) -> [URL] {
        let folder = video.deletingLastPathComponent()
        let base = video.deletingPathExtension().lastPathComponent
        return [
            folder.appendingPathComponent("\(base).context.md", isDirectory: false),
            folder.appendingPathComponent("context.md", isDirectory: false),
        ]
    }

    /// The sidecar's text, then the note under its heading, each without
    /// the blank space around it. Empty when both are.
    public static func compose(sidecar: String?, note: String) -> String {
        let sidecar = (sidecar ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !sidecar.isEmpty { parts.append(sidecar) }
        if !note.isEmpty { parts.append("\(noteHeading)\n\n\(note)") }
        return parts.joined(separator: "\n\n")
    }
}
