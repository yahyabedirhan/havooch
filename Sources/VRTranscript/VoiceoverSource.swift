import Foundation

/// The explainer studio's `voiceover.json`: one line per scene, with the
/// scene's narration. The file has no times, only each scene's length, so a
/// scene's times are computed as the studio lays the video out: a scene
/// lasts `ceil((durationSeconds + paddingSeconds) × fps)` frames and starts
/// where the one before it ends.
public struct VoiceoverSource: Transcriber {
    public var file: URL
    /// The video's frames per second.
    public var frameRate: Double

    public init(file: URL, frameRate: Double) {
        self.file = file
        self.frameRate = frameRate
    }

    public func lines(for video: URL, in window: ClosedRange<Double>) async throws -> [TranscriptLine] {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw TranscriptFailure("couldn't read \(file.lastPathComponent): \(error.localizedDescription)")
        }
        return TranscriptWindow.cut(try Self.lines(of: data, frameRate: frameRate), to: window)
    }

    /// Every scene of the scene list `data` as a line, for a video of
    /// `frameRate` frames per second. A scene without narration has no line,
    /// and still takes its time.
    public static func lines(of data: Data, frameRate: Double) throws(TranscriptFailure) -> [TranscriptLine] {
        guard frameRate > 0 else {
            throw TranscriptFailure("\(TranscriptSources.voiceoverName) needs the video's frame rate for its scene times")
        }
        let list: SceneList
        do {
            list = try JSONDecoder().decode(SceneList.self, from: data)
        } catch {
            throw TranscriptFailure("\(TranscriptSources.voiceoverName) isn't a scene list: \(error.localizedDescription)")
        }
        var lines: [TranscriptLine] = []
        var frame = 0.0
        for scene in list.scenes {
            let length = ((scene.durationSeconds + (scene.paddingSeconds ?? 0)) * frameRate).rounded(.up)
            let end = frame + max(0, length)
            if let line = TranscriptLine.tidy(start: frame / frameRate, end: end / frameRate, text: scene.text ?? "") {
                lines.append(line)
            }
            frame = end
        }
        return lines
    }

    /// What is read of the studio's file; its other keys are left alone.
    private struct SceneList: Decodable {
        var scenes: [Scene]

        struct Scene: Decodable {
            var text: String?
            var durationSeconds: Double
            var paddingSeconds: Double?
        }
    }
}
