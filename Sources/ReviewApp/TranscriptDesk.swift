import Foundation
import ReviewCore
import ReviewStore
import ReviewTranscript

final class TranscriptDesk {
    private let sources: any Transcriber
    private var videos: [String: VideoFile] = [:]

    init(sources: any Transcriber) {
        self.sources = sources
    }

    convenience init(layout: SupportLayout, speech: any SpeechRecognizing) {
        let files = TranscriptFiles(layout: layout)
        let cache = SpeechSource.Cache(
            load: { files.load($0.contentHash) }, save: { files.save($0, contentHash: $1.contentHash) }
        )
        self.init(sources: TranscriptSources.standard(speech: SpeechSource(recognizer: speech, cache: cache)))
    }

    func opened(_ video: VideoFile) {
        videos[video.contentHash] = video
        sources.prepare(video)
    }

    func lines(around time: Double, of info: VideoInfo) -> [SendPayload.Line] {
        guard let video = videos[info.contentHash] ?? Self.file(of: info) else { return [] }
        return sources.lines(for: video, in: TranscriptWindow.range(around: time, duration: video.duration))
            .map { SendPayload.Line(start: $0.start, end: $0.end, text: $0.text) }
    }

    static func file(of info: VideoInfo) -> VideoFile? {
        guard let frameRate = info.frameRate, frameRate > 0 else { return nil }
        return VideoFile(
            url: URL(fileURLWithPath: info.path), contentHash: info.contentHash, frameRate: frameRate, duration: info.duration
        )
    }

    func report(of contentHash: String) -> StateReport.Transcript? {
        guard let video = videos[contentHash], let transcript = sources.transcript(of: video) else { return nil }
        return StateReport.Transcript(
            source: transcript.source.rawValue, complete: transcript.complete, lines: transcript.lines.count,
            problem: transcript.problem
        )
    }
}
