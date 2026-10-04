import Foundation
import Testing
import VRTranscript

/// The repo's fixture folder: the video, its scene list and its subtitles.
private let fixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("fixtures/sample", isDirectory: true)
    .standardizedFileURL

private let pause = "This is Video Review. Pause any video, or draw a box on the frame, and write a comment."
private let send = "Your comments queue up. Press command enter, and they go to your agent as one batch, with the time, the frame, and the transcript."
private let answer = "The agent reads your notes and answers right inside the player. No copying, and no screenshots."

/// A folder of its own with a video's name in it and the sidecars asked
/// for, copied from the fixture. The sources look at the names only, so the
/// video is an empty file.
private func folder(with sidecars: [String]) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vr-transcript-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data().write(to: folder.appendingPathComponent("sample.mp4"))
    for name in sidecars {
        try FileManager.default.copyItem(at: fixture.appendingPathComponent(name), to: folder.appendingPathComponent(name))
    }
    return folder
}

/// A recognizer that says one line, for where the source order ends.
private struct OneLine: Transcriber {
    func lines(for video: URL, in window: ClosedRange<Double>) async throws -> [TranscriptLine] {
        [TranscriptLine(start: 0, end: 1, text: "spoken")]
    }
}

@Suite struct TranscriptWindowTests {
    private let lines = [
        TranscriptLine(start: 0, end: 10, text: "a"),
        TranscriptLine(start: 10, end: 20, text: "b"),
        TranscriptLine(start: 20, end: 40, text: "c"),
        TranscriptLine(start: 40, end: 50, text: "d"),
    ]

    @Test func theWindowIsFifteenSecondsEachSideKeptInsideTheVideo() {
        #expect(TranscriptWindow.around(100, duration: 300) == 85...115)
        #expect(TranscriptWindow.around(2, duration: 300) == 0...17)
        #expect(TranscriptWindow.around(295, duration: 300) == 280...300)
        #expect(TranscriptWindow.around(10, duration: 21.233) == 0...21.233)
    }

    @Test func theCutKeepsEveryLineThatReachesIntoTheWindowWhole() {
        // 15 to 45: b ends inside, c is inside, d starts inside. Each is whole.
        #expect(TranscriptWindow.cut(lines, to: 15...45).map(\.text) == ["b", "c", "d"])
        #expect(TranscriptWindow.cut(lines, to: 15...45).first == TranscriptLine(start: 10, end: 20, text: "b"))
        // One long line around a short window.
        #expect(TranscriptWindow.cut(lines, to: 25...30).map(\.text) == ["c"])
    }

    @Test func aLineThatOnlyTouchesTheWindowsEdgeIsOutside() {
        #expect(TranscriptWindow.cut(lines, to: 10...20).map(\.text) == ["b"])
        #expect(TranscriptWindow.cut(lines, to: 50...60).isEmpty)
    }

    @Test func theCutIsInTimeOrder() {
        #expect(TranscriptWindow.cut(lines.reversed(), to: 0...50).map(\.text) == ["a", "b", "c", "d"])
    }

    @Test func aCommentsWindowOnTheFixtureHoldsItsScene() throws {
        let lines = try VoiceoverSource.lines(of: Data(contentsOf: fixture.appendingPathComponent("voiceover.json")), frameRate: 30)

        // The fixture's own cases: a comment at 10 s is in `send`.
        let around = TranscriptWindow.cut(lines, to: TranscriptWindow.around(10, duration: 21.233))
        #expect(around.contains { $0.start <= 10 && 10 < $0.end && $0.text.contains("Press command enter") })
        // 5 s to 7 s spans the end of `pause` and the start of `send`.
        #expect(TranscriptWindow.cut(lines, to: 5...7).map(\.text) == [pause, send])
        #expect(TranscriptWindow.cut(lines, to: 15...16).map(\.text) == [answer])
    }
}

@Suite struct TranscriptSourcesTests {
    @Test func theVoiceoverComesFirstThenSubtitlesThenSpeech() throws {
        let both = try folder(with: ["voiceover.json", "sample.srt"])
        let subtitled = try folder(with: ["sample.srt"])
        let bare = try folder(with: [])
        defer { for folder in [both, subtitled, bare] { try? FileManager.default.removeItem(at: folder) } }

        #expect(TranscriptSources.candidates(for: both.appendingPathComponent("sample.mp4")) == [
            .voiceover(both.appendingPathComponent("voiceover.json")),
            .subtitles(both.appendingPathComponent("sample.srt")),
            .speech,
        ])
        #expect(TranscriptSources.best(for: both.appendingPathComponent("sample.mp4")).name == "voiceover")
        #expect(TranscriptSources.best(for: subtitled.appendingPathComponent("sample.mp4")) == .subtitles(subtitled.appendingPathComponent("sample.srt")))
        #expect(TranscriptSources.best(for: bare.appendingPathComponent("sample.mp4")) == .speech)
    }

    @Test func subtitlesNeedTheVideosBaseNameAndSrtComesBeforeVtt() throws {
        let folder = try folder(with: ["sample.srt"])
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("WEBVTT\n".utf8).write(to: folder.appendingPathComponent("sample.vtt"))
        try Data().write(to: folder.appendingPathComponent("other.mp4"))

        #expect(TranscriptSources.best(for: folder.appendingPathComponent("sample.mp4")) == .subtitles(folder.appendingPathComponent("sample.srt")))
        // Another video of the folder has no subtitles of its own.
        #expect(TranscriptSources.best(for: folder.appendingPathComponent("other.mp4")) == .speech)

        try FileManager.default.removeItem(at: folder.appendingPathComponent("sample.srt"))
        #expect(TranscriptSources.best(for: folder.appendingPathComponent("sample.mp4")) == .subtitles(folder.appendingPathComponent("sample.vtt")))
    }

    @Test func eachSourceIsReadByItsOwnTranscriber() async throws {
        let video = fixture.appendingPathComponent("sample.mp4")
        let spoken = try await TranscriptSources.speech.transcriber(frameRate: 30, speech: OneLine()).lines(for: video, in: 0...30)
        #expect(spoken.map(\.text) == ["spoken"])
        let scenes = try await TranscriptSources.best(for: video).transcriber(frameRate: 30, speech: OneLine()).lines(for: video, in: 0...30)
        #expect(scenes.map(\.text) == [pause, send, answer])
    }
}

@Suite struct VoiceoverSourceTests {
    @Test func theFixturesScenesGetTheirTimesFromTheirLengths() async throws {
        let source = VoiceoverSource(file: fixture.appendingPathComponent("voiceover.json"), frameRate: 30)

        let lines = try await source.lines(for: fixture.appendingPathComponent("sample.mp4"), in: 0...21.233)

        // Frames 0 to 182, 182 to 430 and 430 to 637, at 30 a second.
        #expect(lines == [
            TranscriptLine(start: 0, end: 6.067, text: pause),
            TranscriptLine(start: 6.067, end: 14.333, text: send),
            TranscriptLine(start: 14.333, end: 21.233, text: answer),
        ])
    }

    @Test func aSceneLastsWholeFramesOfTheVideosFrameRate() throws {
        let list = Data(#"{"scenes":[{"text":"one","durationSeconds":1.01,"paddingSeconds":0.5},{"text":"two","durationSeconds":2}]}"#.utf8)

        // 1.51 s is 37.75 frames at 25 a second: 38 frames, 1.52 s.
        #expect(try VoiceoverSource.lines(of: list, frameRate: 25) == [
            TranscriptLine(start: 0, end: 1.52, text: "one"),
            TranscriptLine(start: 1.52, end: 3.52, text: "two"),
        ])
    }

    @Test func aSceneWithoutNarrationHasNoLineAndStillTakesItsTime() throws {
        let list = Data(#"{"scenes":[{"text":"  ","durationSeconds":2,"paddingSeconds":0},{"text":"after","durationSeconds":1,"paddingSeconds":0}]}"#.utf8)

        #expect(try VoiceoverSource.lines(of: list, frameRate: 30) == [TranscriptLine(start: 2, end: 3, text: "after")])
    }

    @Test func aFileThatIsNoSceneListIsRefused() {
        #expect(throws: TranscriptFailure.self) { try VoiceoverSource.lines(of: Data("{}".utf8), frameRate: 30) }
        #expect(throws: TranscriptFailure.self) { try VoiceoverSource.lines(of: Data(#"{"scenes":[]}"#.utf8), frameRate: 0) }
    }
}

@Suite struct SubtitleSourceTests {
    @Test func theFixturesSrtGivesTheSameTextAndTimesAsItsVoiceover() async throws {
        let video = fixture.appendingPathComponent("sample.mp4")

        let cues = try await SubtitleSource(file: fixture.appendingPathComponent("sample.srt")).lines(for: video, in: 0...21.233)
        let scenes = try await VoiceoverSource(file: fixture.appendingPathComponent("voiceover.json"), frameRate: 30).lines(for: video, in: 0...21.233)

        #expect(cues == scenes)
    }

    @Test func srtCuesMayHaveSeveralLinesTagsAndWindowsLineEnds() {
        let text = "\u{FEFF}1\r\n00:00:01,500 --> 00:00:04,000\r\n<i>Hello</i>\r\nthere.\r\n\r\n2\r\n01:00:00,000 --> 01:00:02,250\r\nAn hour in.\r\n"

        #expect(SubtitleSource.lines(of: text) == [
            TranscriptLine(start: 1.5, end: 4, text: "Hello there."),
            TranscriptLine(start: 3600, end: 3602.25, text: "An hour in."),
        ])
    }

    @Test func vttCuesAreReadWithoutTheirHeaderNotesNamesAndSettings() {
        let text = """
        WEBVTT - made by hand

        NOTE
        This note is not a cue.

        intro
        00:01.000 --> 00:03.500 align:start position:10%
        <v Narrator>Short times have no hours.</v>

        00:00:03.500 --> 00:00:06.000
        A &amp; B
        on two lines
        """

        #expect(SubtitleSource.lines(of: text) == [
            TranscriptLine(start: 1, end: 3.5, text: "Short times have no hours."),
            TranscriptLine(start: 3.5, end: 6, text: "A & B on two lines"),
        ])
    }

    @Test func textThatIsNoSubtitleFileHasNoCue() {
        #expect(SubtitleSource.lines(of: "").isEmpty)
        #expect(SubtitleSource.lines(of: "just words\n\nand --> more words\n").isEmpty)
        // A cue that ends before it starts is dropped.
        #expect(SubtitleSource.lines(of: "00:00:05,000 --> 00:00:01,000\nbackwards\n").isEmpty)
    }

    @Test func aWindowCutsTheCues() async throws {
        let source = SubtitleSource(file: fixture.appendingPathComponent("sample.srt"))

        let lines = try await source.lines(for: fixture.appendingPathComponent("sample.mp4"), in: 5...7)

        #expect(lines.map(\.text) == [pause, send])
    }
}
