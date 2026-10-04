import Foundation
import Testing
@testable import VRApp
import VRLease
import VRReview
import VRStore
import VRTranscript
import VRWire

private let operatorHolder = Holder(key: "operator", name: "Claude Code", place: "/Users/me/repo")
private let listener = Holder(key: "listener-1", name: "Claude Code", place: "/Users/me/shop")

private let pause = "This is Video Review. Pause any video, or draw a box on the frame, and write a comment."
private let send = "Your comments queue up. Press command enter, and they go to your agent as one batch, with the time, the frame, and the transcript."
private let answer = "The agent reads your notes and answers right inside the player. No copying, and no screenshots."

/// A recognizer the test holds back: it answers once the test lets it, and
/// counts how often it was asked.
private final class HeldSpeech: Transcriber, @unchecked Sendable {
    struct Failure: LocalizedError {
        var errorDescription: String? { "no model for this language" }
    }

    let asked = FakeFrames.Count()
    var said: [TranscriptLine] = [
        TranscriptLine(start: 0, end: 5.1, text: "This is video review."),
        TranscriptLine(start: 5.16, end: 13.2, text: "Your comments queue up."),
    ]
    var fails = false
    private let gate = AsyncStream<Void>.makeStream()

    /// Lets every answer through, now and later.
    func release() {
        gate.continuation.finish()
    }

    func lines(for video: URL, in window: ClosedRange<Double>) async throws -> [TranscriptLine] {
        asked.add()
        for await _ in gate.stream {}
        if fails { throw Failure() }
        return TranscriptWindow.cut(said, to: window)
    }
}

/// A control server over a fake player and a library of its own, with a
/// recognizer the test holds: an operator and a listener.
@MainActor
private final class TranscriptRig {
    let speech = HeldSpeech()
    let library: Library
    let model: ReviewModel
    let server: ControlServer
    /// The folders this rig made, removed with it.
    private var folders: [URL] = []

    init(library: Library = scratchLibrary()) {
        self.library = library
        let model = ReviewModel(player: FakePlayer(), frames: FakeFrames(), library: library, speech: speech)
        self.model = model
        server = ControlServer(
            socket: URL(fileURLWithPath: "/tmp/vr-unused/control.sock"),
            model: model,
            desk: OperatorDesk(model: model) { _, _ in .captured },
            quit: {}
        )
        folders.append(library.root)
    }

    deinit {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
    }

    /// The fixture video copied alone into a folder of its own, with the
    /// sidecars asked for beside it.
    func copy(with sidecars: [String] = []) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vr-video-\(UUID().uuidString)", isDirectory: true)
        folders.append(folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["sample.mp4"] + sidecars {
            try FileManager.default.copyItem(
                at: fixtureVideo.deletingLastPathComponent().appendingPathComponent(name), to: folder.appendingPathComponent(name)
            )
        }
        return folder.appendingPathComponent("sample.mp4")
    }

    func send(_ request: ControlRequest, by holder: Holder = operatorHolder, json: Bool = false) async -> ControlReply {
        await server.reply(to: ControlMessage(request, holder: holder, json: json).encoded()).reply
    }

    /// The `transcript` of `state --json`.
    func transcript() async throws -> [String: Any] {
        let reply = await send(.state, json: true)
        let state = try #require(try JSONSerialization.jsonObject(with: Data(reply.output.utf8)) as? [String: Any])
        return try #require(state["transcript"] as? [String: Any])
    }

    /// A comment at `time`, sent as a batch of its own, as a `wait` gets it.
    func commentAndWait(at time: Double) async throws -> BatchPayload.Item {
        #expect(await send(.commentAdd(text: "look here", at: time, region: nil)).ok)
        #expect(await send(.batchSend).ok)
        let answer = await server.reply(to: ControlMessage(.wait(timeoutSeconds: 0), holder: listener).encoded())
        server.written(answer, delivered: true)
        #expect(answer.reply.ok, "\(answer.reply.error)")
        let payload = try JSONDecoder().decode(BatchPayload.self, from: Data(answer.reply.output.utf8))
        return try #require(payload.comments.first)
    }
}

@MainActor
@Suite struct TranscriptTests {
    @Test func theFixturesVoiceoverGivesTheNarrationOfTheCommentsScene() async throws {
        let rig = TranscriptRig()
        #expect(await rig.send(.playerOpen(path: fixtureVideo.path)).ok)

        let comment = try await rig.commentAndWait(at: 10)

        // 10 s is in `send`; the window, 0 s to 21.233 s, holds its neighbours too.
        #expect(comment.transcript == [
            BatchPayload.Line(start: 0, end: 6.067, text: pause),
            BatchPayload.Line(start: 6.067, end: 14.333, text: send),
            BatchPayload.Line(start: 14.333, end: 21.233, text: answer),
        ])
        let transcript = try await rig.transcript()
        #expect(transcript["source"] as? String == "voiceover")
        #expect(transcript["ready"] as? Bool == true)
        #expect(transcript["lines"] as? Int == 3)
        #expect(transcript["failure"] is NSNull)
        // The recognizer isn't asked when a sidecar is there.
        #expect(rig.speech.asked.value == 0)
    }

    @Test func theFixtureWithOnlyItsSrtGivesTheSameText() async throws {
        let rig = TranscriptRig()
        #expect(await rig.send(.playerOpen(path: try rig.copy(with: ["sample.srt"]).path)).ok)

        let comment = try await rig.commentAndWait(at: 10)

        #expect(comment.transcript.map(\.text) == [pause, send, answer])
        #expect(comment.transcript.map(\.start) == [0, 6.067, 14.333])
        #expect(try await rig.transcript()["source"] as? String == "subtitles")
        #expect(rig.speech.asked.value == 0)
    }

    @Test func aCommentSentBeforeSpeechIsReadyHasTheLinesThatExistThen() async throws {
        let rig = TranscriptRig()
        #expect(await rig.send(.playerOpen(path: try rig.copy().path)).ok)
        let hash = try #require(rig.model.video?.info.contentHash)

        // Speech is still running: the comment is taken and sent as it is.
        var transcript = try await rig.transcript()
        #expect(transcript["source"] as? String == "speech")
        #expect(transcript["ready"] as? Bool == false)
        #expect(transcript["lines"] as? Int == 0)
        #expect(try await rig.commentAndWait(at: 3).transcript == [])
        #expect((await rig.send(.state)).output.contains("transcript: speech, transcribing\n"))

        rig.speech.release()
        await rig.model.transcripts.settled(hash)

        transcript = try await rig.transcript()
        #expect(transcript["ready"] as? Bool == true)
        #expect(transcript["lines"] as? Int == 2)
        // The next comment has them: 3 s reaches from 0 s to 18 s.
        #expect(try await rig.commentAndWait(at: 3).transcript == [
            BatchPayload.Line(start: 0, end: 5.1, text: "This is video review."),
            BatchPayload.Line(start: 5.16, end: 13.2, text: "Your comments queue up."),
        ])
        #expect((await rig.send(.state)).output.contains("transcript: speech, 2 lines\n"))
    }

    @Test func aSpeechTranscriptIsKeptAndNotMadeAgain() async throws {
        let rig = TranscriptRig()
        let video = try rig.copy()
        rig.speech.release()
        #expect(await rig.send(.playerOpen(path: video.path)).ok)
        let hash = try #require(rig.model.video?.info.contentHash)
        await rig.model.transcripts.settled(hash)
        #expect(TranscriptCache(root: rig.library.root).load(hash) == rig.speech.said)

        // The same video opened again in this run, and after a relaunch.
        #expect(await rig.send(.playerOpen(path: video.path)).ok)
        let relaunched = TranscriptRig(library: rig.library)
        #expect(await relaunched.send(.playerOpen(path: video.path)).ok)

        #expect(rig.speech.asked.value == 1)
        #expect(relaunched.speech.asked.value == 0)
        let transcript = try await relaunched.transcript()
        #expect(transcript["source"] as? String == "speech")
        #expect(transcript["ready"] as? Bool == true)
        #expect(transcript["lines"] as? Int == 2)
    }

    @Test func speechThatFailsSaysWhyAndIsTriedAgainOnTheNextOpen() async throws {
        let rig = TranscriptRig()
        let video = try rig.copy()
        rig.speech.fails = true
        rig.speech.release()
        #expect(await rig.send(.playerOpen(path: video.path)).ok)
        let hash = try #require(rig.model.video?.info.contentHash)
        await rig.model.transcripts.settled(hash)

        let transcript = try await rig.transcript()
        #expect(transcript["ready"] as? Bool == true)
        #expect(transcript["lines"] as? Int == 0)
        #expect(transcript["failure"] as? String == "no model for this language")
        #expect(try await rig.commentAndWait(at: 3).transcript == [])
        #expect(TranscriptCache(root: rig.library.root).load(hash) == nil)

        rig.speech.fails = false
        #expect(await rig.send(.playerOpen(path: video.path)).ok)
        await rig.model.transcripts.settled(hash)
        #expect(try await rig.transcript()["lines"] as? Int == 2)
        #expect(rig.speech.asked.value == 2)
    }

    @Test func aSidecarThatCantBeReadGivesWayToTheNextSource() async throws {
        let rig = TranscriptRig()
        let video = try rig.copy(with: ["sample.srt"])
        try Data("not a scene list".utf8).write(to: video.deletingLastPathComponent().appendingPathComponent("voiceover.json"))

        #expect(await rig.send(.playerOpen(path: video.path)).ok)

        let transcript = try await rig.transcript()
        #expect(transcript["source"] as? String == "subtitles")
        #expect(transcript["lines"] as? Int == 3)
    }

    @Test func thereIsNoTranscriptWithoutAVideo() async throws {
        let rig = TranscriptRig()

        let reply = await rig.send(.state, json: true)

        let state = try #require(try JSONSerialization.jsonObject(with: Data(reply.output.utf8)) as? [String: Any])
        #expect(state["transcript"] is NSNull)
    }
}
