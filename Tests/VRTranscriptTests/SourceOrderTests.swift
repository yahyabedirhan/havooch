import Foundation
import Testing
import VRTranscript

/// Which source a video's transcript comes from: `voiceover.json`, then a
/// `.srt` or `.vtt` sidecar, then speech recognition.
@Suite struct SourceOrderTests {
    static let video = URL(fileURLWithPath: "/videos/talk.mp4")
    static let spoken = TimedLine(start: 1, end: 3, text: "recognised")

    /// The spec's sources on `video`, with speech recognition run by the test.
    func transcriber(recognition: Recognition, cache: MemoryCache = MemoryCache()) -> OrderedTranscriber {
        OrderedTranscriber(sources: [
            VoiceoverSource(frameRate: { _ in 30 }), SubtitleSource(), SpeechSource(cache: cache, recognize: recognition.recognize),
        ])
    }

    @Test func theFirstSourceThatHasTheVideoIsUsedAndTheOnesAfterItAreNotPrepared() async {
        let nothing = FixedSource("voiceover", nil)
        let subtitles = FixedSource("subtitles", SourceTranscript(lines: fixtureScenes))
        let speech = FixedSource("speech", SourceTranscript(lines: [Self.spoken]))
        let transcriber = OrderedTranscriber(sources: [nothing, subtitles, speech])

        await transcriber.prepare(Self.video)

        #expect(await transcriber.status(for: Self.video) == TranscriptStatus(source: "subtitles", complete: true, lines: 3))
        #expect(await transcriber.lines(for: Self.video, in: 0...30) == fixtureScenes)
        #expect(await nothing.prepared == 1)
        #expect(await subtitles.prepared == 1)
        #expect(await speech.prepared == 0)
    }

    @Test func withVoiceoverAndSubtitlesBesideTheVideoTheVoiceoverIsUsed() async throws {
        let folder = try Folder()
        let video = try folder.file("sample.mp4")
        try folder.fixture("voiceover.json")
        try folder.file("sample.srt", "1\n00:00:00,000 --> 00:00:05,000\nfrom the subtitles\n")
        let recognition = Recognition()
        let transcriber = transcriber(recognition: recognition)

        await transcriber.prepare(video)

        #expect(await transcriber.status(for: video) == TranscriptStatus(source: "voiceover", complete: true, lines: 3))
        #expect(await transcriber.lines(for: video, in: TranscriptWindow.around(10)) == fixtureScenes)
        #expect(recognition.started == 0)
    }

    @Test func withOnlySubtitlesBesideTheVideoTheyAreUsedAndGiveTheSameLinesAsTheVoiceover() async throws {
        let folder = try Folder()
        let video = try folder.file("sample.mp4")
        try folder.fixture("sample.srt")
        let recognition = Recognition()
        let transcriber = transcriber(recognition: recognition)

        await transcriber.prepare(video)

        #expect(await transcriber.status(for: video) == TranscriptStatus(source: "subtitles", complete: true, lines: 3))
        #expect(await transcriber.lines(for: video, in: TranscriptWindow.around(10)) == fixtureScenes)
        #expect(recognition.started == 0)
    }

    @Test func aSubtitleFileOfAnotherVideoIsNotThisVideosTranscript() async throws {
        let folder = try Folder()
        let video = try folder.file("other.mp4")
        try folder.fixture("sample.srt")
        let recognition = Recognition()
        let transcriber = transcriber(recognition: recognition)

        await transcriber.prepare(video)

        #expect(await transcriber.status(for: video).source == "speech")
        #expect(recognition.started == 1)
    }

    @Test func withNoSidecarSpeechRecognitionIsUsedAndALineIsThereAsSoonAsItIsRecognised() async throws {
        let folder = try Folder()
        let video = try folder.file("silent.mp4")
        let recognition = Recognition()
        let transcriber = transcriber(recognition: recognition)

        await transcriber.prepare(video)

        #expect(await transcriber.status(for: video) == TranscriptStatus(source: "speech", complete: false, lines: 0))
        #expect(await transcriber.lines(for: video, in: 0...30) == [])

        recognition.hear(Self.spoken)
        await until("the first line") { await transcriber.status(for: video).lines == 1 }
        // Still running: the lines that exist now, and not complete.
        #expect(await transcriber.status(for: video) == TranscriptStatus(source: "speech", complete: false, lines: 1))
        #expect(await transcriber.lines(for: video, in: 0...30) == [Self.spoken])

        recognition.hear(TimedLine(start: 40, end: 42, text: "later"))
        recognition.end()
        await until("the end") { await transcriber.status(for: video).complete }
        #expect(await transcriber.status(for: video) == TranscriptStatus(source: "speech", complete: true, lines: 2))
        #expect(await transcriber.lines(for: video, in: 0...30) == [Self.spoken])
    }

    @Test func aSidecarAddedSinceTheLastOpenIsUsedAtTheNextOpen() async throws {
        let folder = try Folder()
        let video = try folder.file("sample.mp4")
        let recognition = Recognition()
        let transcriber = transcriber(recognition: recognition)
        await transcriber.prepare(video)
        #expect(await transcriber.status(for: video).source == "speech")

        try folder.fixture("sample.srt")
        #expect(await transcriber.status(for: video).source == "speech")
        await transcriber.prepare(video)

        #expect(await transcriber.status(for: video) == TranscriptStatus(source: "subtitles", complete: true, lines: 3))
    }

    @Test func aVideoThatWasNeverPreparedIsPreparedWhenItsLinesAreAsked() async throws {
        let folder = try Folder()
        let video = try folder.file("sample.mp4")
        try folder.fixture("voiceover.json")
        let transcriber = transcriber(recognition: Recognition())

        #expect(await transcriber.lines(for: video, in: 5...7) == Array(fixtureScenes[0...1]))
    }

    @Test func withNoSourceThereIsNoTranscript() async {
        let transcriber = OrderedTranscriber(sources: [FixedSource("voiceover", nil)])

        #expect(await transcriber.status(for: Self.video) == TranscriptStatus(source: nil, complete: false, lines: 0))
        #expect(await transcriber.lines(for: Self.video, in: 0...30) == [])
    }
}
