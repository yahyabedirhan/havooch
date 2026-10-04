import Foundation
import ReviewCore
import ReviewStore
import ReviewTranscript

/// The app's way to the transcripts: it remembers the videos opened in
/// this run, starts a video's source when the video opens, and gives a
/// comment its lines at the moment they're asked for.
@MainActor
final class TranscriptDesk {
    private let sources: any Transcriber
    /// The videos opened in this run, by content hash: a batch of a video
    /// that's no longer the open one still gets its lines.
    private var videos: [String: VideoFile] = [:]

    init(sources: any Transcriber) {
        self.sources = sources
    }

    /// The sources in the spec's order, with speech kept under `support`.
    convenience init(support: URL, speech: any SpeechRecognizing) {
        let files = TranscriptFiles(support: support)
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

    /// The lines from 15 s before `time` to 15 s after, of the video with
    /// `contentHash`, as the source has them now.
    func lines(around time: Double, of contentHash: String) -> [BatchPayload.Line] {
        guard let video = videos[contentHash] else { return [] }
        return sources.lines(for: video, in: TranscriptWindow.range(around: time, duration: video.duration))
            .map { BatchPayload.Line(start: $0.start, end: $0.end, text: $0.text) }
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
