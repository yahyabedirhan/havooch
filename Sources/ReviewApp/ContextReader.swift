import Foundation
import ReviewCore

enum ContextReader {
    struct Sidecar: Equatable {
        var file: URL
        var text: String
    }

    static let noteHeading = "## Note from the reviewer"

    static func names(for video: URL) -> [String] {
        ["\(video.deletingPathExtension().lastPathComponent).context.md", "context.md"]
    }

    static func sidecar(beside video: URL) -> Sidecar? {
        let folder = video.deletingLastPathComponent()
        for name in names(for: video) {
            let file = folder.appendingPathComponent(name)
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            return Sidecar(file: file, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func text(sidecar: String?, note: String) -> String? {
        let sidecar = sidecar?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [sidecar, note.isEmpty ? "" : "\(noteHeading)\n\n\(note)"].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    static func text(for review: Review) -> String? {
        text(sidecar: sidecar(beside: URL(fileURLWithPath: review.video.path))?.text, note: review.note)
    }
}
