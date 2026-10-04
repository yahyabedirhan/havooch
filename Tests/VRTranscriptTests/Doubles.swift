import Foundation
import Testing
import VRTranscript

/// The fixture video, with its `voiceover.json` and its `sample.srt`.
let fixtureFolder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("fixtures/sample", isDirectory: true)

/// The fixture's three scenes, as its README's table times them.
let fixtureScenes = [
    TimedLine(start: 0, end: 6.067, text: "This is Video Review. Pause any video, or draw a box on the frame, and write a comment."),
    TimedLine(
        start: 6.067, end: 14.333,
        text: "Your comments queue up. Press command enter, and they go to your agent as one batch, with the time, the frame, and the transcript."
    ),
    TimedLine(start: 14.333, end: 21.233, text: "The agent reads your notes and answers right inside the player. No copying, and no screenshots."),
]

/// A folder of its own for one test, removed when the test ends.
final class Folder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("vr-transcript-\(UUID().uuidString)", isDirectory: true)

    init() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes `text` as the file `name`, and gives where it is.
    @discardableResult
    func file(_ name: String, _ text: String = "") throws -> URL {
        let file = url.appendingPathComponent(name)
        try Data(text.utf8).write(to: file)
        return file
    }

    /// Copies the fixture's file `name` here, as `newName` when given.
    @discardableResult
    func fixture(_ name: String, as newName: String? = nil) throws -> URL {
        let file = url.appendingPathComponent(newName ?? name)
        try FileManager.default.copyItem(at: fixtureFolder.appendingPathComponent(name), to: file)
        return file
    }
}

/// A source with a fixed answer, which counts how often it was prepared.
actor FixedSource: TranscriptSource {
    nonisolated let name: String
    private let answer: SourceTranscript?
    private(set) var prepared = 0

    init(_ name: String, _ answer: SourceTranscript?) {
        self.name = name
        self.answer = answer
    }

    func prepare(_ video: URL) {
        prepared += 1
    }

    func transcript(for video: URL) -> SourceTranscript? {
        answer
    }
}

/// A cache in memory.
final class MemoryCache: TranscriptCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [URL: [TimedLine]] = [:]

    init(_ kept: [URL: [TimedLine]] = [:]) {
        self.kept = kept
    }

    func load(for video: URL) -> [TimedLine]? {
        lock.withLock { kept[video] }
    }

    func save(_ lines: [TimedLine], for video: URL) {
        lock.withLock { kept[video] = lines }
    }
}

/// A speech recognition the test runs by hand: it gives each line when
/// the test says so, and ends, or fails, when the test says so.
final class Recognition: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<TimedLine, any Error>.Continuation] = []

    /// How many recognitions were started.
    var started: Int { lock.withLock { continuations.count } }

    var recognize: SpeechSource.Recognize {
        { _ in
            AsyncThrowingStream { continuation in
                self.lock.withLock { self.continuations.append(continuation) }
            }
        }
    }

    func hear(_ line: TimedLine) {
        lock.withLock { continuations.last }?.yield(line)
    }

    func end(throwing error: (any Error)? = nil) {
        lock.withLock { continuations.last }?.finish(throwing: error)
    }
}

/// Waits until `condition` holds; a condition that never holds is a failure.
func until(_ what: String, _ condition: () async -> Bool) async {
    for _ in 0..<500 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("never happened: \(what)")
}
