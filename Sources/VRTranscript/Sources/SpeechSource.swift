import Foundation

/// Where a finished speech transcript is kept, so the next open of the
/// same video has it at once. `VRStore` implements it.
public protocol TranscriptCaching: Sendable {
    /// The lines kept for `video`; nil when none are.
    func load(for video: URL) -> [TimedLine]?
    func save(_ lines: [TimedLine], for video: URL)
}

/// Why speech recognition gave no transcript, or stopped short of one.
public struct SpeechProblem: Error, Equatable, Sendable {
    public var why: String

    public init(_ why: String) {
        self.why = why
    }
}

/// Speech recognition on this Mac, on the video's audio track: started in
/// the background when the video opens, with lines that grow as they are
/// recognised. It has an answer for every video, so it is the last source.
public actor SpeechSource: TranscriptSource {
    /// The recognised lines of a video, one by one as they are ready; the
    /// stream ends with the video's last line, or throws why it stopped.
    public typealias Recognize = @Sendable (URL) -> AsyncThrowingStream<TimedLine, any Error>

    public nonisolated let name = "speech"
    private let cache: any TranscriptCaching
    private let recognize: Recognize
    private var transcripts: [URL: SourceTranscript] = [:]
    private var running: Set<URL> = []

    /// `recognize` is Apple's SpeechAnalyzer unless a test gives its own.
    public init(cache: any TranscriptCaching, recognize: @escaping Recognize = SpeechRecognition.lines) {
        self.cache = cache
        self.recognize = recognize
    }

    /// Takes the video's lines from the cache, or starts recognising them.
    /// A recognition that runs, or that finished, isn't started again; one
    /// that stopped on a problem is.
    public func prepare(_ video: URL) {
        guard !running.contains(video), transcripts[video]?.complete != true else { return }
        if let cached = cache.load(for: video) {
            transcripts[video] = SourceTranscript(lines: cached)
            return
        }
        transcripts[video] = SourceTranscript(lines: [], complete: false)
        running.insert(video)
        let heard = recognize(video)
        Task(priority: .utility) {
            do {
                for try await line in heard {
                    self.add(line, to: video)
                }
                self.finish(video, problem: nil)
            } catch {
                self.finish(video, problem: (error as? SpeechProblem)?.why ?? error.localizedDescription)
            }
        }
    }

    /// The lines recognised so far.
    public func transcript(for video: URL) -> SourceTranscript? {
        transcripts[video] ?? SourceTranscript(lines: [], complete: false)
    }

    private func add(_ line: TimedLine, to video: URL) {
        transcripts[video]?.lines.append(line)
    }

    /// The recognition ended: a whole transcript is kept in the cache, and
    /// one that stopped short says why and isn't kept.
    private func finish(_ video: URL, problem: String?) {
        running.remove(video)
        transcripts[video]?.problem = problem
        guard problem == nil, let lines = transcripts[video]?.lines else { return }
        transcripts[video]?.complete = true
        cache.save(lines, for: video)
    }
}
