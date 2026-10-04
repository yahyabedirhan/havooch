import Foundation
import Synchronization

/// What turns a file's sound into timed lines. `AppleSpeechRecognizer` is
/// the real one; tests give a slow one they control.
public protocol SpeechRecognizing: Sendable {
    /// The speech in `file`, a line at a time in time order. It ends when
    /// the whole file is done, and throws when it can't go on.
    func lines(of file: URL) -> AsyncThrowingStream<TranscriptLine, any Error>
}

/// The last source: the video's own sound, transcribed on this Mac in the
/// background from the moment the video opens. Lines arrive over time, and
/// it answers with the ones it has. A finished transcript is kept in the
/// cache it's given, so a video is transcribed once.
public final class SpeechSource: Transcriber {
    /// Where finished transcripts are kept between runs.
    public struct Cache: Sendable {
        public var load: @Sendable (VideoFile) -> Transcript?
        public var save: @Sendable (Transcript, VideoFile) -> Void

        public init(load: @escaping @Sendable (VideoFile) -> Transcript?, save: @escaping @Sendable (Transcript, VideoFile) -> Void) {
            self.load = load
            self.save = save
        }

        /// Keeps nothing.
        public static let none = Cache(load: { _ in nil }, save: { _, _ in })
    }

    private let recognizer: any SpeechRecognizing
    private let cache: Cache
    /// The transcripts of this run, by content hash.
    private let known = Mutex<[String: Transcript]>([:])

    public init(recognizer: any SpeechRecognizing, cache: Cache = .none) {
        self.recognizer = recognizer
        self.cache = cache
    }

    /// Speech serves every video: before any line has arrived it's an empty
    /// transcript that isn't complete.
    public func transcript(of video: VideoFile) -> Transcript? {
        known.withLock { $0[video.contentHash] } ?? Self.empty
    }

    private static let empty = Transcript(source: .speech, lines: [], complete: false)

    /// Starts the transcription of `video` in the background, once: not
    /// again while it runs or when it's done. One that gave up starts over.
    public func prepare(_ video: VideoFile) {
        let starts = known.withLock { known in
            if let transcript = known[video.contentHash], transcript.problem == nil { return false }
            known[video.contentHash] = Self.empty
            return true
        }
        guard starts else { return }
        Task.detached(priority: .utility) { [self] in await transcribe(video) }
    }

    private func transcribe(_ video: VideoFile) async {
        if let cached = cache.load(video), cached.complete, cached.source == .speech {
            known.withLock { $0[video.contentHash] = cached }
            return
        }
        do {
            for try await line in recognizer.lines(of: video.url) {
                let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let line = TranscriptLine(
                    start: TranscriptLine.milliseconds(line.start), end: TranscriptLine.milliseconds(line.end), text: text
                )
                known.withLock { $0[video.contentHash]?.lines.append(line) }
            }
            // Kept first: a transcript that reads as complete is on disk.
            guard var done = known.withLock({ $0[video.contentHash] }) else { return }
            done.complete = true
            cache.save(done, video)
            known.withLock { $0[video.contentHash] = done }
        } catch {
            // The lines that arrived stay; the rest never comes.
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            known.withLock { $0[video.contentHash]?.problem = reason }
        }
    }
}
