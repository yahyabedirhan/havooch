import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewTranscript
import ReviewWire
import Synchronization
import Testing

/// The transcript window in the payload: the app's model on the fixture
/// video and on copies of it with fewer sidecars, and the control server in
/// front of it. No window, no socket, and no real speech recognition.
@Suite("The transcript window of each thread", .serialized)
struct TranscriptDeliveryTests {
    nonisolated static let operatorAgent = Holder(key: "operator", name: "Claude Code", place: "/work")
    nonisolated static let listener = Holder(key: "listener-1", name: "Claude Code", place: "/shop")
    nonisolated static let restarted = Holder(key: "listener-2", name: "Claude Code", place: "/shop")

    static let pause: [String: AnyHashable] = [
        "start": 0, "end": 6.067, "text": "This is Havooch. Pause any video, or draw a box on the frame, and write a comment.",
    ]
    static let send: [String: AnyHashable] = [
        "start": 6.067, "end": 14.333,
        "text": "Your comments queue up. Press command enter, and they go to your agent as one batch, with the time, the frame, and the transcript.",
    ]
    static let answer: [String: AnyHashable] = [
        "start": 14.333, "end": 21.233,
        "text": "The agent reads your notes and answers right inside the player. No copying, and no screenshots.",
    ]

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    /// A copy of the fixture video in a folder of its own, with only the
    /// sidecars named.
    private func copy(sidecars: [String]) throws -> URL {
        let folder = support.appendingPathComponent("video", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["sample.mp4"] + sidecars {
            try FileManager.default.copyItem(
                at: MessageTests.fixture.deletingLastPathComponent().appendingPathComponent(name),
                to: folder.appendingPathComponent(name)
            )
        }
        return folder.appendingPathComponent("sample.mp4")
    }

    /// The model with `video` open, and the server in front of it.
    private func app(_ video: URL, speech: SlowRecognizer = SlowRecognizer()) async throws -> (AppModel, ControlServer) {
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path], speech: speech)
        try await model.open(video)
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: model, listeners: { model.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        return (model, server)
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Sends the queue and takes it as the listener: each thread's
    /// transcript in the payload `wait` prints, in time order.
    private func delivered(_ server: ControlServer, as listener: Holder = listener) async throws -> [[[String: AnyHashable]]] {
        let sent = await server.reply(to: ControlRequest.send.sent(by: Self.operatorAgent))
        #expect(sent.reply.ok)
        let wait = await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: listener))
        #expect(wait.reply.ok)
        let threads = try #require(try object(wait.reply.output)["threads"] as? [[String: Any]])
        return try threads.map { try #require($0["transcript"] as? [[String: AnyHashable]]) }
    }

    private func transcriptState(_ server: ControlServer) async throws -> [String: AnyHashable]? {
        let state = try object(await server.reply(to: ControlRequest.state.sent(by: Self.listener, json: true)).reply.output)
        #expect(state.keys.contains("transcript"))
        return state["transcript"] as? [String: AnyHashable]
    }

    // MARK: - Sidecars

    @Test("the fixture with voiceover.json: a comment gets the narration of its scene, with the scene's times, and of the scenes within 15 s")
    func voiceover() async throws {
        defer { cleanUp() }
        let (model, server) = try await app(MessageTests.fixture)
        _ = try await model.addMessage(text: "In the send scene", at: 10)
        _ = try await model.addMessage(text: "At the very end", at: 21.2)

        let transcripts = try await delivered(server)

        // 10 s is in the scene from 6.067 s to 14.333 s; the whole video is within 15 s of it.
        #expect(transcripts[0] == [Self.pause, Self.send, Self.answer])
        // At 21.2 s the first scene ended more than 15 s ago.
        #expect(transcripts[1] == [Self.send, Self.answer])
        #expect(try await transcriptState(server) == ["source": "voiceover", "complete": true, "lines": 3, "problem": NSNull()])
    }

    @Test("the fixture with only the .srt gives the same text, from the subtitles")
    func subtitlesOnly() async throws {
        defer { cleanUp() }
        let speech = SlowRecognizer()
        let (model, server) = try await app(try copy(sidecars: ["sample.srt"]), speech: speech)
        _ = try await model.addMessage(text: "In the send scene", at: 10)
        _ = try await model.addMessage(text: "At the very end", at: 21.2)

        let transcripts = try await delivered(server)

        #expect(transcripts[0] == [Self.pause, Self.send, Self.answer])
        #expect(transcripts[1] == [Self.send, Self.answer])
        #expect(try await transcriptState(server) == ["source": "subtitles", "complete": true, "lines": 3, "problem": NSNull()])
        // A video with a sidecar is never transcribed from its sound.
        #expect(speech.runs == 0)
    }

    // MARK: - Speech

    @Test("a video with no sidecar is transcribed in the background; a comment sent before that's done gets the lines that exist then")
    func beforeTheTranscriptIsReady() async throws {
        defer { cleanUp() }
        let speech = SlowRecognizer()
        let (model, server) = try await app(try copy(sidecars: []), speech: speech)
        await eventually { speech.runs == 1 }
        #expect(speech.runs == 1)
        #expect(try await transcriptState(server) == ["source": "speech", "complete": false, "lines": 0, "problem": NSNull()])

        // Nothing is transcribed yet: the comment isn't held back, and gets no lines.
        _ = try await model.addMessage(text: "Right away", at: 3)
        #expect(try await delivered(server) == [[]])

        // The first line is there, the rest isn't.
        speech.say(TranscriptLine(start: 0.2, end: 5.1, text: "This is Havooch."))
        await eventually { model.transcript?.lines == 1 }
        _ = try await model.addMessage(text: "A little later", at: 4)
        #expect(try await delivered(server) == [[["start": 0.2, "end": 5.1, "text": "This is Havooch."]]])
        #expect(try await transcriptState(server) == ["source": "speech", "complete": false, "lines": 1, "problem": NSNull()])

        // A send made now and taken only once the transcript is whole gets
        // the lines of its window as they were when it was sent: the window
        // is cut at send time and kept.
        _ = try await model.addMessage(text: "Taken later", at: 5)
        _ = await server.reply(to: ControlRequest.send.sent(by: Self.operatorAgent))
        speech.say(TranscriptLine(start: 6.4, end: 13.4, text: "Your comments queue up."))
        speech.say(TranscriptLine(start: 20.5, end: 21, text: "The end."))
        speech.finish()
        await eventually { model.transcript?.complete == true }
        let wait = await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener))
        let thread = try #require((try object(wait.reply.output)["threads"] as? [[String: Any]])?.first)
        #expect((thread["transcript"] as? [[String: AnyHashable]])?.map { $0["text"] } == ["This is Havooch."])
        #expect(try await transcriptState(server) == ["source": "speech", "complete": true, "lines": 3, "problem": NSNull()])

        // A new listener session gets the three unfinished sends again, each
        // with the lines it kept.
        var kept: [[[String: AnyHashable]]] = []
        for _ in 0..<3 {
            let again = await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.restarted))
            let redelivered = try #require((try object(again.reply.output)["threads"] as? [[String: Any]])?.first)
            kept.append(try #require(redelivered["transcript"] as? [[String: AnyHashable]]))
        }
        #expect(kept == [[], [["start": 0.2, "end": 5.1, "text": "This is Havooch."]], try #require(thread["transcript"] as? [[String: AnyHashable]])])

        // The next send cuts its window from the whole transcript.
        _ = try await model.addMessage(text: "Sent once it's whole", at: 6)
        #expect(try await delivered(server, as: Self.restarted) == [[
            ["start": 0.2, "end": 5.1, "text": "This is Havooch."], ["start": 6.4, "end": 13.4, "text": "Your comments queue up."],
            ["start": 20.5, "end": 21, "text": "The end."],
        ]])
    }

    @Test("a finished speech transcript is kept under the video's content hash, and the next run reads it instead of transcribing again")
    func cached() async throws {
        defer { cleanUp() }
        let video = try copy(sidecars: [])
        let speech = SlowRecognizer()
        let (model, _) = try await app(video, speech: speech)
        speech.say(TranscriptLine(start: 0.2, end: 5.1, text: "This is Havooch."))
        speech.finish()
        await eventually { model.transcript?.complete == true }

        let hash = try #require(model.video?.contentHash)
        let whole = Transcript(source: .speech, lines: [TranscriptLine(start: 0.2, end: 5.1, text: "This is Havooch.")], complete: true)
        #expect(TranscriptFiles(layout: SupportLayout(root: support)).load(hash) == whole)
        #expect(TranscriptFiles(layout: SupportLayout(root: support)).layout.transcriptFile(hash).path == support.path + "/videos/\(hash)/transcript.json")

        let later = SlowRecognizer()
        let (again, server) = try await app(video, speech: later)
        await eventually { again.transcript?.complete == true }
        _ = try await again.addMessage(text: "After a restart", at: 3)
        #expect(try await delivered(server) == [[["start": 0.2, "end": 5.1, "text": "This is Havooch."]]])
        #expect(later.runs == 0)
    }

    @Test("a transcription that gives up says why in the state, and comments still go out")
    func givesUp() async throws {
        defer { cleanUp() }
        let speech = SlowRecognizer()
        let (model, server) = try await app(try copy(sidecars: []), speech: speech)
        speech.finish(throwing: NoModel())
        await eventually { model.transcript?.problem != nil }

        #expect(try await transcriptState(server) == [
            "source": "speech", "complete": false, "lines": 0, "problem": "no model for this language",
        ])
        _ = try await model.addMessage(text: "Still sent", at: 3)
        #expect(try await delivered(server) == [[]])
        let lines = await server.reply(to: ControlRequest.state.sent(by: Self.listener)).reply.output
        #expect(lines.contains("transcript: speech, 0 lines, stopped: no model for this language\n"))
    }

    // MARK: - The state report and the chip

    @Test("state has transcript null with no video, and one line for it")
    func state() async throws {
        defer { cleanUp() }
        let empty = AppModel(environment: [SupportFolder.overrideVariable: support.path], speech: SlowRecognizer())
        #expect(empty.state().transcript == nil)
        #expect(try object(empty.state().json)["transcript"] is NSNull)
        #expect(empty.state().lines.contains("transcript: none\n"))

        let (model, _) = try await app(MessageTests.fixture)
        #expect(model.state().lines.contains("transcript: voiceover, 3 lines, complete\n"))
    }

    @Test("the chip names the source, and for speech how far it is")
    func chip() {
        func chip(_ source: String, complete: Bool = true, lines: Int = 3, problem: String? = nil) -> TranscriptChip {
            TranscriptChip(StateReport.Transcript(source: source, complete: complete, lines: lines, problem: problem))
        }
        #expect(chip("voiceover").title == "Voiceover transcript")
        #expect(chip("voiceover").help.contains("voiceover.json (3 lines)"))
        #expect(chip("subtitles").title == "Subtitle transcript")
        #expect(chip("speech").title == "Speech transcript")
        #expect(!chip("speech").isWorking)
        #expect(chip("speech", complete: false, lines: 0).title == "Transcribing…")
        #expect(chip("speech", complete: false, lines: 1).title == "Transcribing… 1 line")
        #expect(chip("speech", complete: false, lines: 1).isWorking)
        #expect(chip("speech", lines: 0).title == "No speech")
        #expect(chip("speech", complete: false, lines: 0, problem: "no model").title == "No transcript")
        #expect(chip("speech", complete: false, lines: 0, problem: "no model").help.contains("no model"))
        #expect(chip("speech", complete: false, lines: 2, problem: "no model").title == "Transcript stopped")
        #expect(!chip("speech", complete: false, lines: 2, problem: "no model").isWorking)
    }
}

/// A recognizer the test drives: lines arrive when the test says them.
final class SlowRecognizer: SpeechRecognizing {
    private typealias Stream = AsyncThrowingStream<TranscriptLine, any Error>
    private struct State {
        var runs = 0
        /// Whether a run already reads `stream`: the next run gets a new one.
        var isTaken = false
        var stream: Stream
        var continuation: Stream.Continuation
    }

    private let state: Mutex<State>

    init() {
        let (stream, continuation) = Stream.makeStream()
        state = Mutex(State(stream: stream, continuation: continuation))
    }

    /// How many times a transcription started.
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

    /// Ends the run, with `error` when it fails.
    func finish(throwing error: (any Error)? = nil) {
        state.withLock { $0.continuation.finish(throwing: error) }
    }
}

struct NoModel: LocalizedError {
    var errorDescription: String? { "no model for this language" }
}
