import Foundation
import ReviewTranscript
import Testing

@Suite("The transcript window")
struct TranscriptWindowTests {
    @Test("the window is 15 s each way from the comment's time, kept inside the video", arguments: [
        (10.0, 21.233, 0.0, 21.233), (2.0, 21.233, 0.0, 17.0), (20.0, 21.233, 5.0, 21.233), (0.0, 21.233, 0.0, 15.0),
        (40.0, 60.0, 25.0, 55.0), (60.0, 60.0, 45.0, 60.0),
    ])
    func range(time: Double, duration: Double, lower: Double, upper: Double) {
        #expect(TranscriptWindow.range(around: time, duration: duration) == lower...upper)
    }

    @Test("a line that overlaps the window is kept whole; one outside it, or only touching its edge, is dropped")
    func cut() {
        let lines = [
            TranscriptLine(start: 0, end: 10, text: "before"),
            TranscriptLine(start: 20, end: 25, text: "ends at the window's start"),
            TranscriptLine(start: 22, end: 26, text: "reaches into the window"),
            TranscriptLine(start: 30, end: 35, text: "inside"),
            TranscriptLine(start: 54, end: 70, text: "reaches out of the window"),
            TranscriptLine(start: 55, end: 60, text: "starts at the window's end"),
            TranscriptLine(start: 80, end: 90, text: "after"),
        ]
        let kept = TranscriptWindow.cut(lines, around: 40, duration: 120)
        #expect(kept.map(\.text) == ["reaches into the window", "inside", "reaches out of the window"])
        // Whole: with its own times, not the window's.
        #expect(kept.first == TranscriptLine(start: 22, end: 26, text: "reaches into the window"))
        #expect(kept.last == TranscriptLine(start: 54, end: 70, text: "reaches out of the window"))
    }

    @Test("a line longer than the window is kept, and no lines give no lines")
    func longAndNone() {
        let long = TranscriptLine(start: 0, end: 300, text: "one long line")
        #expect(TranscriptWindow.cut([long], around: 100, duration: 300) == [long])
        #expect(TranscriptWindow.cut([], around: 100, duration: 300).isEmpty)
    }

    @Test("the fixture: a comment at 10 s holds \"Press command enter\", and 5 s to 7 s spans two scenes")
    func fixtureWindows() {
        let atTen = TranscriptWindow.cut(Fixture.narration, around: 10, duration: 21.233)
        #expect(atTen.contains { $0.text.contains("Press command enter") })
        #expect(TranscriptWindow.cut(Fixture.narration, to: 5...7) == [Fixture.pause, Fixture.send])
        // Only at the very end is the first scene more than 15 s away.
        #expect(TranscriptWindow.cut(Fixture.narration, around: 21.2, duration: 21.233) == [Fixture.send, Fixture.answer])
    }
}

@Suite("voiceover.json")
struct VoiceoverSourceTests {
    @Test("the fixture's scenes get their times from their lengths: ceil((duration + padding) × 30) frames each, one after the other")
    func fixture() throws {
        let data = try Data(contentsOf: Fixture.folder.appendingPathComponent("voiceover.json"))
        #expect(VoiceoverSource.lines(from: data, frameRate: 30) == Fixture.narration)
    }

    @Test("the frame rate decides where a scene ends")
    func frameRate() throws {
        let data = Data(#"{"scenes":[{"text":"One","durationSeconds":1.01,"paddingSeconds":0.5},{"text":"Two","durationSeconds":2}]}"#.utf8)
        // 1.51 s is 46 frames at 30 a second (1.533 s) and 16 at 10 (1.6 s). No padding is none.
        #expect(VoiceoverSource.lines(from: data, frameRate: 30) == [
            TranscriptLine(start: 0, end: 1.533, text: "One"), TranscriptLine(start: 1.533, end: 3.533, text: "Two"),
        ])
        #expect(VoiceoverSource.lines(from: data, frameRate: 10) == [
            TranscriptLine(start: 0, end: 1.6, text: "One"), TranscriptLine(start: 1.6, end: 3.6, text: "Two"),
        ])
    }

    @Test("a length that is a whole number of frames isn't raised by a float's noise, and a silent scene takes its time")
    func wholeFramesAndSilence() {
        // 0.1 + 0.2 is 0.30000000000000004: 9 frames at 30, not 10.
        let data = Data(#"{"scenes":[{"text":"","durationSeconds":0.1,"paddingSeconds":0.2},{"text":"Said","durationSeconds":1,"paddingSeconds":0}]}"#.utf8)
        #expect(VoiceoverSource.lines(from: data, frameRate: 30) == [TranscriptLine(start: 0.3, end: 1.3, text: "Said")])
    }

    @Test("a file that isn't a voiceover.json gives nothing")
    func notVoiceover() {
        #expect(VoiceoverSource.lines(from: Data("not json".utf8), frameRate: 30) == nil)
        #expect(VoiceoverSource.lines(from: Data(#"{"topic":"x"}"#.utf8), frameRate: 30) == nil)
        #expect(VoiceoverSource.lines(from: Data(#"{"scenes":[]}"#.utf8), frameRate: 0) == nil)
    }
}

@Suite("Subtitle sidecars")
struct SubtitleSourceTests {
    @Test("the fixture's .srt gives the same lines as its voiceover.json")
    func fixtureSRT() throws {
        let text = try String(contentsOf: Fixture.folder.appendingPathComponent("sample.srt"), encoding: .utf8)
        #expect(SubtitleSource.parse(text) == Fixture.narration)
    }

    @Test("SubRip: numbers are dropped, a cue's rows are joined, markup is removed, Windows line ends and a byte order mark are fine")
    func srt() {
        let text = "\u{FEFF}1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Hello</i>\r\nthere\r\n\r\n2\r\n01:00:03,250 --> 01:00:04,000\r\n{\\an8}Up top\r\n"
        #expect(SubtitleSource.parse(text) == [
            TranscriptLine(start: 1, end: 2.5, text: "Hello there"), TranscriptLine(start: 3603.25, end: 3604, text: "Up top"),
        ])
    }

    @Test("WebVTT: the header, notes and styles are no cues; times may leave out the hours; cue names, settings and tags are dropped")
    func vtt() {
        let text = """
        WEBVTT - a title

        NOTE
        A note, with --> nothing to say.

        STYLE
        ::cue { color: red }

        intro
        00:01.000 --> 00:04.500 position:50% align:middle
        <v Narrator>This is <b>Video Review</b>.

        00:00:06.067 --> 00:00:14.333
        Your comments <00:00:07.000>queue up.
        """
        #expect(SubtitleSource.parse(text) == [
            TranscriptLine(start: 1, end: 4.5, text: "This is Video Review."),
            TranscriptLine(start: 6.067, end: 14.333, text: "Your comments queue up."),
        ])
    }

    @Test("cues come back in time order, and a cue with a bad time or no text is skipped")
    func orderAndBadCues() {
        let text = """
        1
        00:00:05,000 --> 00:00:06,000
        Second

        2
        00:00:01,000 --> 00:00:02,000
        First

        3
        soon --> later
        Never

        4
        00:00:07,000 --> 00:00:08,000

        5
        00:00:09,000 --> 00:00:08,000
        Backwards
        """
        #expect(SubtitleSource.parse(text).map(\.text) == ["First", "Second"])
        #expect(SubtitleSource.parse("just some words").isEmpty)
    }
}

@Suite("The source order")
struct TranscriptSourcesTests {
    /// The standard sources, with a speech source that never says a line.
    private func standard(_ recognizer: SlowRecognizer = SlowRecognizer()) -> TranscriptSources {
        TranscriptSources.standard(speech: SpeechSource(recognizer: recognizer))
    }

    @Test("with voiceover.json and a .srt beside the video, voiceover.json serves it")
    func voiceoverFirst() throws {
        let folder = try VideoFolder(sidecars: ["voiceover.json", "sample.srt"])
        defer { folder.cleanUp() }
        #expect(standard().transcript(of: folder.video) == Transcript(source: .voiceover, lines: Fixture.narration, complete: true))
    }

    @Test("with only the .srt, the subtitles serve it, with the same text")
    func subtitlesSecond() throws {
        let folder = try VideoFolder(sidecars: ["sample.srt"])
        defer { folder.cleanUp() }
        #expect(standard().transcript(of: folder.video) == Transcript(source: .subtitles, lines: Fixture.narration, complete: true))
    }

    @Test("a .srt is asked before a .vtt, and a .vtt alone serves the video")
    func srtBeforeVTT() throws {
        let folder = try VideoFolder(sidecars: ["sample.srt"])
        defer { folder.cleanUp() }
        try folder.write("WEBVTT\n\n00:01.000 --> 00:02.000\nFrom the vtt\n", to: "sample.vtt")
        #expect(standard().transcript(of: folder.video)?.lines == Fixture.narration)

        let alone = try VideoFolder()
        defer { alone.cleanUp() }
        try alone.write("WEBVTT\n\n00:01.000 --> 00:02.000\nFrom the vtt\n", to: "sample.vtt")
        #expect(standard().transcript(of: alone.video) == Transcript(
            source: .subtitles, lines: [TranscriptLine(start: 1, end: 2, text: "From the vtt")], complete: true
        ))
    }

    @Test("the video's own <base name>.voiceover.json is asked before the folder's voiceover.json")
    func namedVoiceover() throws {
        let folder = try VideoFolder(sidecars: ["voiceover.json"])
        defer { folder.cleanUp() }
        try folder.write(#"{"scenes":[{"text":"Mine","durationSeconds":1,"paddingSeconds":0}]}"#, to: "sample.voiceover.json")
        #expect(standard().transcript(of: folder.video)?.lines == [TranscriptLine(start: 0, end: 1, text: "Mine")])
    }

    @Test("a voiceover.json that doesn't read, or a subtitle file with no cue, leaves the video to the next source")
    func brokenSidecars() throws {
        let folder = try VideoFolder(sidecars: ["sample.srt"])
        defer { folder.cleanUp() }
        try folder.write("{", to: "voiceover.json")
        #expect(standard().transcript(of: folder.video)?.source == .subtitles)

        let empty = try VideoFolder()
        defer { empty.cleanUp() }
        try empty.write("", to: "sample.srt")
        #expect(standard().transcript(of: empty.video) == Transcript(source: .speech, lines: [], complete: false))
    }

    @Test("with no sidecar, speech serves the video, and only then is the video's sound transcribed")
    func speechLast() async throws {
        let bare = try VideoFolder()
        let narrated = try VideoFolder(sidecars: ["voiceover.json"])
        defer {
            bare.cleanUp()
            narrated.cleanUp()
        }
        let recognizer = SlowRecognizer()
        let sources = standard(recognizer)

        sources.prepare(narrated.video)
        try await Task.sleep(for: .milliseconds(50))
        #expect(recognizer.runs == 0)

        #expect(sources.transcript(of: bare.video) == Transcript(source: .speech, lines: [], complete: false))
        sources.prepare(bare.video)
        await eventually { recognizer.runs == 1 }
        #expect(recognizer.runs == 1)
    }

    @Test("lines(for:in:) gives the lines of the window from the source that serves the video")
    func linesInWindow() throws {
        let folder = try VideoFolder(sidecars: ["sample.srt"])
        defer { folder.cleanUp() }
        #expect(standard().lines(for: folder.video, in: 5...7) == [Fixture.pause, Fixture.send])
        #expect(standard().lines(for: folder.video, in: 15...21.233) == [Fixture.answer])
    }
}

@Suite("Speech in the background")
struct SpeechSourceTests {
    private let video = VideoFile(url: URL(fileURLWithPath: "/videos/talk.mp4"), contentHash: "abc", frameRate: 30, duration: 60)

    @Test("lines arrive over time: it answers at once with the ones it has, and is complete when the recognizer ends")
    func linesOverTime() async {
        let recognizer = SlowRecognizer()
        let source = SpeechSource(recognizer: recognizer)
        source.prepare(video)
        #expect(source.transcript(of: video) == Transcript(source: .speech, lines: [], complete: false))
        #expect(source.lines(for: video, in: 0...30).isEmpty)

        recognizer.say(TranscriptLine(start: 0.00049, end: 4.9996, text: " Hello there. "))
        await eventually { source.transcript(of: video)?.lines.count == 1 }
        // Times to the millisecond, text without the space around it.
        #expect(source.transcript(of: video) == Transcript(
            source: .speech, lines: [TranscriptLine(start: 0, end: 5, text: "Hello there.")], complete: false
        ))

        recognizer.say(TranscriptLine(start: 5, end: 6, text: "  "))
        recognizer.say(TranscriptLine(start: 40, end: 44, text: "Much later."))
        await eventually { source.transcript(of: video)?.lines.count == 2 }
        #expect(source.lines(for: video, in: 0...30).map(\.text) == ["Hello there."])
        #expect(source.transcript(of: video)?.complete == false)

        recognizer.finish()
        await eventually { source.transcript(of: video)?.complete == true }
        #expect(source.transcript(of: video)?.lines.map(\.text) == ["Hello there.", "Much later."])
        #expect(source.transcript(of: video)?.problem == nil)
    }

    @Test("a video is transcribed once: not again while it runs, when it's done, or when the cache has it")
    func once() async {
        let recognizer = SlowRecognizer()
        let saved = Saved()
        let source = SpeechSource(recognizer: recognizer, cache: saved.cache)
        source.prepare(video)
        source.prepare(video)
        recognizer.say(TranscriptLine(start: 1, end: 2, text: "Only line."))
        // Nothing is kept until the transcript is whole.
        await eventually { source.transcript(of: video)?.lines.count == 1 }
        #expect(saved.all.isEmpty)
        recognizer.finish()
        await eventually { source.transcript(of: video)?.complete == true }
        source.prepare(video)
        #expect(recognizer.runs == 1)
        let whole = Transcript(source: .speech, lines: [TranscriptLine(start: 1, end: 2, text: "Only line.")], complete: true)
        #expect(saved.all == ["abc": whole])

        // The next run of the app: the cache answers, the recognizer isn't asked.
        let later = SlowRecognizer()
        let again = SpeechSource(recognizer: later, cache: saved.cache)
        again.prepare(video)
        await eventually { again.transcript(of: video)?.complete == true }
        #expect(again.transcript(of: video) == whole)
        #expect(later.runs == 0)
    }

    @Test("a recognizer that gives up leaves the lines it gave and says why; the video's next opening tries again")
    func givesUp() async {
        let recognizer = SlowRecognizer()
        let source = SpeechSource(recognizer: recognizer)
        source.prepare(video)
        recognizer.say(TranscriptLine(start: 1, end: 2, text: "One line."))
        recognizer.finish(throwing: NoModel())
        await eventually { source.transcript(of: video)?.problem != nil }
        #expect(source.transcript(of: video) == Transcript(
            source: .speech, lines: [TranscriptLine(start: 1, end: 2, text: "One line.")], complete: false,
            problem: "no model for this language"
        ))

        source.prepare(video)
        await eventually { recognizer.runs == 2 }
        recognizer.finish()
        await eventually { source.transcript(of: video)?.complete == true }
        #expect(source.transcript(of: video) == Transcript(source: .speech, lines: [], complete: true))
    }
}
