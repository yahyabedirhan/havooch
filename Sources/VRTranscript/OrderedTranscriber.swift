import Foundation

/// The transcript from the first source that has the video, asked in
/// order. A source is prepared only when every source before it has
/// nothing, so a video with a sidecar never starts speech recognition.
public actor OrderedTranscriber: Transcriber {
    private let sources: [any TranscriptSource]
    /// The source each prepared video uses, with its transcript once that
    /// is complete, so a sidecar is read once per open.
    private var chosen: [URL: Choice] = [:]

    private struct Choice {
        var source: any TranscriptSource
        var settled: SourceTranscript?
    }

    public init(sources: [any TranscriptSource]) {
        self.sources = sources
    }

    /// The sources in the spec's order: `voiceover.json`, then a `.srt` or
    /// `.vtt` sidecar, then speech recognition on this Mac, which keeps
    /// its finished result in `cache`.
    public init(cache: any TranscriptCaching) {
        self.init(sources: [VoiceoverSource(), SubtitleSource(), SpeechSource(cache: cache)])
    }

    /// Chooses the video's source again, so a sidecar added or removed
    /// since the last open counts.
    public func prepare(_ video: URL) async {
        chosen[video] = nil
        for source in sources {
            await source.prepare(video)
            if let transcript = await source.transcript(for: video) {
                chosen[video] = Choice(source: source, settled: transcript.complete ? transcript : nil)
                return
            }
        }
    }

    public func lines(for video: URL, in window: ClosedRange<TimeInterval>) async -> [TimedLine] {
        TranscriptWindow.cut(await current(video)?.transcript.lines ?? [], to: window)
    }

    public func status(for video: URL) async -> TranscriptStatus {
        guard let (name, transcript) = await current(video) else { return TranscriptStatus() }
        return TranscriptStatus(source: name, complete: transcript.complete, lines: transcript.lines.count, problem: transcript.problem)
    }

    /// The video's source and what it has now. A video that was never
    /// prepared is prepared first.
    private func current(_ video: URL) async -> (name: String, transcript: SourceTranscript)? {
        if chosen[video] == nil { await prepare(video) }
        guard let choice = chosen[video] else { return nil }
        if let settled = choice.settled { return (choice.source.name, settled) }
        guard let transcript = await choice.source.transcript(for: video) else { return nil }
        if transcript.complete { chosen[video]?.settled = transcript }
        return (choice.source.name, transcript)
    }
}
