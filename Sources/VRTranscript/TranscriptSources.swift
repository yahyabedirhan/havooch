import Foundation

/// The source order: where a video's transcript comes from, best first.
///
/// 1. `voiceover.json` from the explainer studio, in the video's folder.
/// 2. A `.srt`, else a `.vtt`, with the video's base name, beside it.
/// 3. Speech recognition on this Mac.
public enum TranscriptSources: Equatable, Sendable {
    case voiceover(URL)
    case subtitles(URL)
    case speech

    /// The name of the studio's scene list.
    public static let voiceoverName = "voiceover.json"
    /// The subtitle formats read, in the order they're looked for.
    public static let subtitleExtensions = ["srt", "vtt"]

    /// The sources `video` has, in order. Speech is always the last one.
    public static func candidates(for video: URL) -> [TranscriptSources] {
        var found: [TranscriptSources] = []
        let folder = video.deletingLastPathComponent()
        let voiceover = folder.appendingPathComponent(voiceoverName)
        if isFile(voiceover) { found.append(.voiceover(voiceover)) }
        let base = video.deletingPathExtension()
        if let subtitles = subtitleExtensions.map({ base.appendingPathExtension($0) }).first(where: isFile) {
            found.append(.subtitles(subtitles))
        }
        return found + [.speech]
    }

    /// The source `video`'s transcript comes from.
    public static func best(for video: URL) -> TranscriptSources {
        candidates(for: video)[0]
    }

    /// The source as `state` names it.
    public var name: String {
        switch self {
        case .voiceover: "voiceover"
        case .subtitles: "subtitles"
        case .speech: "speech"
        }
    }

    /// What reads this source. `frameRate` is the video's, which the scene
    /// times of a voiceover are counted in; `speech` is the recognizer.
    public func transcriber(frameRate: Double, speech: any Transcriber) -> any Transcriber {
        switch self {
        case .voiceover(let file): VoiceoverSource(file: file, frameRate: frameRate)
        case .subtitles(let file): SubtitleSource(file: file)
        case .speech: speech
        }
    }

    private static func isFile(_ url: URL) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && !isFolder.boolValue
    }
}
