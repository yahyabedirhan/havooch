import AVFoundation
import Foundation

/// The explainer studio's `voiceover.json`, in the video's folder: one
/// line per scene, with the scene's narration.
public struct VoiceoverSource: TranscriptSource {
    public static let fileName = "voiceover.json"

    public let name = "voiceover"
    private let frameRate: @Sendable (URL) async -> Double

    /// `frameRate` gives a video's frames per second: the scene times are
    /// counted in its frames.
    public init(frameRate: @escaping @Sendable (URL) async -> Double = VoiceoverSource.nominalFrameRate) {
        self.frameRate = frameRate
    }

    public func prepare(_ video: URL) async {}

    public func transcript(for video: URL) async -> SourceTranscript? {
        let file = video.deletingLastPathComponent().appendingPathComponent(Self.fileName)
        guard let data = try? Data(contentsOf: file) else { return nil }
        guard let lines = Self.lines(of: data, frameRate: await frameRate(video)), !lines.isEmpty else { return nil }
        return SourceTranscript(lines: lines)
    }

    /// The studio's scene list, as far as the times and the words need it.
    private struct Voiceover: Decodable {
        struct Scene: Decodable {
            var text: String
            var durationSeconds: Double
            var paddingSeconds: Double?
        }

        var scenes: [Scene]
    }

    /// One line per scene of the `voiceover.json` in `data`; nil when it
    /// doesn't read as one. A scene lasts
    /// `ceil((durationSeconds + paddingSeconds) × frameRate)` frames, as
    /// the studio counts it, and starts where the previous one ends. A
    /// scene with no narration takes its time and gives no line.
    static func lines(of data: Data, frameRate: Double) -> [TimedLine]? {
        guard frameRate > 0, let voiceover = try? JSONDecoder().decode(Voiceover.self, from: data) else { return nil }
        var frames = 0.0
        var lines: [TimedLine] = []
        for scene in voiceover.scenes {
            let start = frames
            frames += max(0, ((scene.durationSeconds + (scene.paddingSeconds ?? 0)) * frameRate).rounded(.up))
            let text = scene.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, frames > start else { continue }
            lines.append(
                TimedLine(start: TimedLine.milliseconds(start / frameRate), end: TimedLine.milliseconds(frames / frameRate), text: text)
            )
        }
        return lines
    }

    /// The video track's nominal frame rate; 30, the studio's own, when
    /// the file doesn't say.
    public static let nominalFrameRate: @Sendable (URL) async -> Double = { video in
        let track = try? await AVURLAsset(url: video).loadTracks(withMediaType: .video).first
        let rate = (try? await track?.load(.nominalFrameRate)).map(Double.init) ?? 0
        return rate > 0 ? rate : 30
    }
}
