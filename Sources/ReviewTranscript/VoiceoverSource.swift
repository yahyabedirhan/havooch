import Foundation

/// The explainer studio's `voiceover.json` beside the video: the narration
/// of each scene, with how long it's spoken. One line a scene.
public struct VoiceoverSource: Transcriber {
    public init() {}

    /// The sidecar of `video`: `<base name>.voiceover.json`, else
    /// `voiceover.json`, in the video's folder.
    public static func file(for video: URL) -> URL? {
        let folder = video.deletingLastPathComponent()
        let base = video.deletingPathExtension().lastPathComponent
        return [folder.appendingPathComponent("\(base).voiceover.json"), folder.appendingPathComponent("voiceover.json")]
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func transcript(of video: VideoFile) -> Transcript? {
        guard let file = Self.file(for: video.url), let data = try? Data(contentsOf: file),
              let lines = Self.lines(from: data, frameRate: video.frameRate)
        else { return nil }
        return Transcript(source: .voiceover, lines: lines, complete: true)
    }

    private struct Voiceover: Decodable {
        struct Scene: Decodable {
            var text: String?
            var durationSeconds: Double
            var paddingSeconds: Double?
        }

        var scenes: [Scene]
    }

    /// The scenes of a `voiceover.json` as timed lines; nil when it isn't
    /// one. The file gives lengths, not times: a scene lasts
    /// `ceil((durationSeconds + paddingSeconds) × frameRate)` frames, as the
    /// studio renders it, and starts where the one before it ends. A scene
    /// with no narration takes its time and gives no line.
    public static func lines(from data: Data, frameRate: Double) -> [TranscriptLine]? {
        guard frameRate > 0, let voiceover = try? JSONDecoder().decode(Voiceover.self, from: data) else { return nil }
        var lines: [TranscriptLine] = []
        var frame = 0.0
        for scene in voiceover.scenes {
            // 247.5 frames are 248; 248 frames with a float's noise aren't 249.
            let frames = max(0, ((scene.durationSeconds + (scene.paddingSeconds ?? 0)) * frameRate - 1e-6).rounded(.up))
            let text = (scene.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                lines.append(TranscriptLine(
                    start: TranscriptLine.milliseconds(frame / frameRate),
                    end: TranscriptLine.milliseconds((frame + frames) / frameRate), text: text
                ))
            }
            frame += frames
        }
        return lines
    }
}
