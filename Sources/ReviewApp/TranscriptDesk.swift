import Foundation
import ReviewCore
import ReviewStore
import ReviewTranscript

/// The app's way to the transcripts: it remembers the videos opened in
/// this run, starts a video's source when the video opens, and gives a
/// thread its lines at the moment they're asked for, also for a video
/// that was last opened in an earlier run.
final class TranscriptDesk {
    private let sources: any Transcriber
    /// The videos opened in this run, by content hash: a send of a video
    /// that's no longer the open one still gets its lines.
    private var videos: [String: VideoFile] = [:]

    init(sources: any Transcriber) {
        self.sources = sources
    }

    /// The sources in the spec's order, with speech kept where `layout` says.
    convenience init(layout: SupportLayout, speech: any SpeechRecognizing) {
        let files = TranscriptFiles(layout: layout)
        let cache = SpeechSource.Cache(
            load: { files.load($0.contentHash) }, save: { files.save($0, contentHash: $1.contentHash) }
        )
        self.init(sources: TranscriptSources.standard(speech: SpeechSource(recognizer: speech, cache: cache)))
    }

    /// The video opened: its source starts. With no sidecar that's the
    /// transcription of its sound, in the background.
    func opened(_ video: VideoFile) {
        videos[video.contentHash] = video
        sources.prepare(video)
    }

    /// The lines from 15 s before `time` to 15 s after, of `info`'s video,
    /// as the source has them now. A video that wasn't opened in this run
    /// is read where it was last opened, at the frame rate kept with it;
    /// one kept with no frame rate has no lines.
    func lines(around time: Double, of info: VideoInfo) -> [SendPayload.Line] {
        guard let video = videos[info.contentHash] ?? Self.file(of: info) else { return [] }
        return sources.lines(for: video, in: TranscriptWindow.range(around: time, duration: video.duration))
            .map { SendPayload.Line(start: $0.start, end: $0.end, text: $0.text) }
    }

    /// The video file `info` names, when its frame rate was kept.
    static func file(of info: VideoInfo) -> VideoFile? {
        guard let frameRate = info.frameRate, frameRate > 0 else { return nil }
        return VideoFile(
            url: URL(fileURLWithPath: info.path), contentHash: info.contentHash, frameRate: frameRate, duration: info.duration
        )
    }

    /// The transcript of the video with `contentHash` as `state` reports it.
    func report(of contentHash: String) -> StateReport.Transcript? {
        guard let video = videos[contentHash], let transcript = sources.transcript(of: video) else { return nil }
        return StateReport.Transcript(
            source: transcript.source.rawValue, complete: transcript.complete, lines: transcript.lines.count,
            problem: transcript.problem
        )
    }
}
