import Foundation
import Observation
import VRStore
import VRTranscript

/// What the videos opened in this run say, kept in memory so a batch's
/// payload reads its lines without waiting. On open it finds the video's
/// source in the spec's order; a sidecar is read at once, and speech runs in
/// the background, with its result kept on disk.
@MainActor
@Observable
final class TranscriptService {
    /// One video's transcript as `state` reports it.
    struct Status: Equatable {
        /// `voiceover`, `subtitles` or `speech`.
        var source: String
        /// False while speech is still being recognized.
        var ready: Bool
        /// How many lines are known now.
        var lines: Int
        /// Why speech gave no transcript, or nil.
        var failure: String?
    }

    private struct Entry {
        var source: String
        var ready = true
        var lines: [TranscriptLine] = []
        var failure: String?
    }

    private var entries: [String: Entry] = [:]
    /// The speech runs on their way, by content hash.
    @ObservationIgnored private var runs: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let speech: any Transcriber
    @ObservationIgnored private let cache: TranscriptCache

    /// `speech` is the recognizer for a video without a sidecar.
    init(speech: any Transcriber, cache: TranscriptCache) {
        self.speech = speech
        self.cache = cache
    }

    /// Finds the transcript of `video`, which was just opened. Returns once
    /// a sidecar's lines are known, or once speech has started in the
    /// background.
    func start(_ video: VideoFile) async {
        let hash = video.info.contentHash
        let whole = 0...max(0, video.info.duration)
        let speechName = TranscriptSources.speech.name
        for source in TranscriptSources.candidates(for: video.url) where source != .speech {
            let sidecar = source.transcriber(frameRate: video.frameRate, speech: speech)
            // A sidecar that can't be read, or says nothing, gives way to the next source.
            guard let lines = try? await sidecar.lines(for: video.url, in: whole), !lines.isEmpty else { continue }
            // A sidecar that appeared since the last open replaces speech.
            runs.removeValue(forKey: hash)?.cancel()
            entries[hash] = Entry(source: source.name, lines: lines)
            return
        }
        // Speech already on its way, or already done in this run, stays.
        if runs[hash] != nil { return }
        if let known = entries[hash], known.source == speechName, known.failure == nil { return }
        if let kept = cache.load(hash) {
            entries[hash] = Entry(source: speechName, lines: kept)
            return
        }
        entries[hash] = Entry(source: speechName, ready: false)
        let url = video.url
        runs[hash] = Task { [weak self, speech, cache] in
            // The recognizer isn't the main actor's: the window stays live.
            let result: Result<[TranscriptLine], any Error>
            do {
                result = .success(try await speech.lines(for: url, in: whole))
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled, let self else { return }
            self.runs[hash] = nil
            switch result {
            case .success(let lines):
                self.entries[hash] = Entry(source: speechName, lines: lines)
                // A transcript that can't be kept is made again next run.
                try? cache.save(lines, for: hash)
            case .failure(let error):
                self.entries[hash] = Entry(source: speechName, failure: error.localizedDescription)
            }
        }
    }

    /// The lines of the video `hash` known now that are inside the window
    /// around `time`: none while speech is still running.
    func lines(of hash: String, around time: Double, duration: Double) -> [TranscriptLine] {
        TranscriptWindow.cut(entries[hash]?.lines ?? [], to: TranscriptWindow.around(time, duration: duration))
    }

    /// The transcript of the video `hash` as `state` reports it, or nil for
    /// a video not opened in this run.
    func status(of hash: String) -> Status? {
        entries[hash].map { Status(source: $0.source, ready: $0.ready, lines: $0.lines.count, failure: $0.failure) }
    }

    /// Returns once the speech run of the video `hash` has ended, at once
    /// when there's none.
    func settled(_ hash: String) async {
        await runs[hash]?.value
    }
}
