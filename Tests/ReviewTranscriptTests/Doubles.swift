import Foundation
import ReviewTranscript
import Synchronization

enum Fixture {
    static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/sample", isDirectory: true)

    static let pause = TranscriptLine(
        start: 0, end: 6.067, text: "This is Havooch. Pause any video, or draw a box on the frame, and write a comment."
    )
    static let send = TranscriptLine(
        start: 6.067, end: 14.333,
        text: "Your comments queue up. Press command enter, and they go to your agent as one batch, with the time, the frame, and the transcript."
    )
    static let answer = TranscriptLine(
        start: 14.333, end: 21.233,
        text: "The agent reads your notes and answers right inside the player. No copying, and no screenshots."
    )
    static let narration = [pause, send, answer]
}

struct VideoFolder {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-transcript-tests-\(UUID().uuidString)", isDirectory: true)

    init(sidecars: [String] = [], as names: [String: String] = [:]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("sample.mp4"))
        for sidecar in sidecars {
            try FileManager.default.copyItem(
                at: Fixture.folder.appendingPathComponent(sidecar), to: folder.appendingPathComponent(names[sidecar] ?? sidecar)
            )
        }
    }

    func write(_ text: String, to name: String) throws {
        try Data(text.utf8).write(to: folder.appendingPathComponent(name))
    }

    var video: VideoFile {
        VideoFile(url: folder.appendingPathComponent("sample.mp4"), contentHash: folder.lastPathComponent, frameRate: 30, duration: 21.233)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }
}

final class SlowRecognizer: SpeechRecognizing {
    private typealias Stream = AsyncThrowingStream<TranscriptLine, any Error>
    private struct State {
        var runs = 0
        var isTaken = false
        var stream: Stream
        var continuation: Stream.Continuation
    }

    private let state: Mutex<State>

    init() {
        let (stream, continuation) = Stream.makeStream()
        state = Mutex(State(stream: stream, continuation: continuation))
    }

    var runs: Int { state.withLock { $0.runs } }

    func lines(of file: URL) -> AsyncThrowingStream<TranscriptLine, any Error> {
        state.withLock {
            $0.runs += 1
            if $0.isTaken { ($0.stream, $0.continuation) = Stream.makeStream() }
            $0.isTaken = true
            return $0.stream
        }
    }

    func say(_ line: TranscriptLine) {
        state.withLock { _ = $0.continuation.yield(line) }
    }

    func finish(throwing error: (any Error)? = nil) {
        state.withLock { $0.continuation.finish(throwing: error) }
    }
}

final class Saved: Sendable {
    private let transcripts = Mutex<[String: Transcript]>([:])

    var all: [String: Transcript] { transcripts.withLock { $0 } }

    func keep(_ transcript: Transcript, of contentHash: String) {
        transcripts.withLock { $0[contentHash] = transcript }
    }

    var cache: SpeechSource.Cache {
        SpeechSource.Cache(load: { self.all[$0.contentHash] }, save: { self.keep($0, of: $1.contentHash) })
    }
}

struct NoModel: LocalizedError {
    var errorDescription: String? { "no model for this language" }
}

func eventually(_ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(60)
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}
