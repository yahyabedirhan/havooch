import Foundation
import Testing
@testable import VRApp
import VRLease
import VRReview
import VRTranscript
import VRWire

/// The transcript in a batch and in `state`: from the fixture's sidecars,
/// and from a speech recognition the test runs by hand. No window is
/// opened and no sound is made.
@Suite(.serialized) @MainActor struct TranscriptBatchTests {
    /// The fixture's three scenes, as a payload carries them.
    nonisolated static let scenes: [BatchPayload.Line] = [
        .init(start: 0, end: 6.067, text: "This is Video Review. Pause any video, or draw a box on the frame, and write a comment."),
        .init(
            start: 6.067, end: 14.333,
            text: "Your comments queue up. Press command enter, and they go to your agent as one batch, with the time, the frame, and the transcript."
        ),
        .init(start: 14.333, end: 21.233, text: "The agent reads your notes and answers right inside the player. No copying, and no screenshots."),
    ]

    /// A speech recognition that gives each line when the test says so.
    final class Recognition: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: AsyncThrowingStream<TimedLine, any Error>.Continuation?

        var recognize: SpeechSource.Recognize {
            { _ in
                AsyncThrowingStream { continuation in
                    self.lock.withLock { self.continuation = continuation }
                }
            }
        }

        func hear(_ line: TimedLine) {
            lock.withLock { continuation }?.yield(line)
        }

        func end() {
            lock.withLock { continuation }?.finish()
        }
    }

    /// A cache that keeps nothing.
    struct NoCache: TranscriptCaching {
        func load(for video: URL) -> [TimedLine]? { nil }
        func save(_ lines: [TimedLine], for video: URL) {}
    }

    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)

    /// A model with `video` open and silent.
    func model(_ video: URL = RegionCommentTests.fixture, transcriber: (any Transcriber)? = nil) async throws -> AppModel {
        let model = AppModel(environment: [SupportFolder.overrideVariable: folder.appendingPathComponent("support").path], transcriber: transcriber)
        model.player.player.isMuted = true
        try await model.open(video)
        return model
    }

    func server(on model: AppModel) -> ControlServer {
        ControlServer(
            socket: folder.appendingPathComponent("control.sock"), model: model, screenshotter: Screenshotter(model: model),
            lease: ControlLease(), indicator: LeaseIndicator(), quit: {}
        )
    }

    /// The fixture video alone in a folder of its own, under another name.
    func videoWithoutSidecars() throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let video = folder.appendingPathComponent("talk.mp4")
        try FileManager.default.copyItem(at: RegionCommentTests.fixture, to: video)
        return video
    }

    /// The `transcript` part of what `state` says.
    func transcriptState(of server: ControlServer) async throws -> [String: Any] {
        let reply = await server.reply(to: ListenerWaitTests.sent(.state))
        let state = try #require(JSONSerialization.jsonObject(with: Data(reply.reply.output.utf8)) as? [String: Any])
        return try #require(state["transcript"] as? [String: Any])
    }

    /// Sends the queue and gives the payload a `wait` then takes.
    func sendAndWait(on server: ControlServer) async throws -> BatchPayload {
        _ = await server.reply(to: ListenerWaitTests.sent(.batchSend))
        let answer = await server.reply(to: ListenerWaitTests.sent(.wait(timeoutSeconds: nil), by: ListenerWaitTests.first))
        server.written(answer)
        return try ListenerWaitTests.payload(answer)
    }

    @Test func aCommentAtTenSecondsOfTheFixtureCarriesTheNarrationAroundItFromTheVoiceover() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = try await model()
        let server = server(on: model)
        _ = await server.reply(to: ListenerWaitTests.sent(.commentAdd(text: "too fast", at: 10, region: nil)))

        let transcript = try await transcriptState(of: server)
        let payload = try await sendAndWait(on: server)

        #expect(transcript["source"] as? String == "voiceover")
        #expect(transcript["complete"] as? Bool == true)
        #expect(transcript["lines"] as? Int == 3)
        #expect(transcript["problem"] is NSNull)
        #expect(payload.comments.map(\.transcript) == [Self.scenes])
        #expect(payload.comments[0].transcript.contains { $0.text.contains("Press command enter") })
    }

    /// A transcriber with no lines, which tells `look` each video it is
    /// asked to prepare.
    struct Looking: Transcriber {
        let look: @MainActor @Sendable (URL) -> Void

        func prepare(_ video: URL) async { await look(video) }
        func lines(for video: URL, in window: ClosedRange<TimeInterval>) async -> [TimedLine] { [] }
        func status(for video: URL) async -> TranscriptStatus { TranscriptStatus() }
    }

    /// Which review was open each time a transcript was prepared.
    @MainActor final class Seen {
        var model: AppModel?
        var reviews: [String?] = []
    }

    @Test func theOpenReviewIsTheVideosOwnWhileItsTranscriptIsPrepared() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let seen = Seen()
        let model = AppModel(
            environment: [SupportFolder.overrideVariable: folder.appendingPathComponent("support").path],
            transcriber: Looking { _ in seen.reviews.append(seen.model?.desk.open?.video.path) }
        )
        seen.model = model
        model.player.player.isMuted = true

        try await model.open(RegionCommentTests.fixture)

        // The player has the video by then, so a comment made meanwhile needs its review.
        #expect(seen.reviews == [RegionCommentTests.fixture.path])
    }

    @Test func withNoVideoOpenStateHasNoTranscript() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = AppModel(environment: [SupportFolder.overrideVariable: folder.appendingPathComponent("support").path])
        let reply = await server(on: model).reply(to: ListenerWaitTests.sent(.state))

        #expect(reply.reply.output.contains(#""transcript":{"complete":false,"lines":0,"problem":null,"source":null}"#))
    }

    @Test func aBatchSentWhileSpeechRecognitionRunsCarriesTheLinesThatExistAtTheSend() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let recognition = Recognition()
        let transcriber = OrderedTranscriber(sources: [
            VoiceoverSource(), SubtitleSource(), SpeechSource(cache: NoCache(), recognize: recognition.recognize),
        ])
        let model = try await model(try videoWithoutSidecars(), transcriber: transcriber)
        let server = server(on: model)
        let first = TimedLine(start: 0.4, end: 5.6, text: "This is Video Review.")
        let second = TimedLine(start: 6.3, end: 13.9, text: "Your comments queue up.")

        // Sent before any line is recognised: an empty transcript.
        _ = await server.reply(to: ListenerWaitTests.sent(.commentAdd(text: "before any line", at: 10, region: nil)))
        let nothingYet = try await transcriptState(of: server)
        let early = try await sendAndWait(on: server)

        // Sent after the first line: that line alone.
        recognition.hear(first)
        for _ in 0..<500 where try await transcriptState(of: server)["lines"] as? Int != 1 {
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = await server.reply(to: ListenerWaitTests.sent(.commentAdd(text: "after the first line", at: 10, region: nil)))
        let running = try await transcriptState(of: server)
        let midway = try await sendAndWait(on: server)

        // The rest arrives: `state` shows it, and the batches keep what they were sent with.
        recognition.hear(second)
        recognition.end()
        for _ in 0..<500 where try await transcriptState(of: server)["complete"] as? Bool != true {
            try await Task.sleep(for: .milliseconds(10))
        }
        let finished = try await transcriptState(of: server)

        #expect(nothingYet["source"] as? String == "speech")
        #expect(nothingYet["complete"] as? Bool == false)
        #expect(nothingYet["lines"] as? Int == 0)
        #expect(early.comments.map(\.transcript) == [[]])
        #expect(running["complete"] as? Bool == false)
        #expect(running["lines"] as? Int == 1)
        #expect(midway.comments.map(\.transcript) == [[.init(start: 0.4, end: 5.6, text: "This is Video Review.")]])
        #expect(finished["complete"] as? Bool == true)
        #expect(finished["lines"] as? Int == 2)
        #expect(model.desk.open?.batches.map { $0.transcripts.values.map(\.count) } == [[0], [1]])
    }
}
