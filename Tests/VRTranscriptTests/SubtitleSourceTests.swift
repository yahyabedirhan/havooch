import Foundation
import Testing
import VRTranscript

/// A `.srt` or `.vtt` file with the video's base name: one line per cue.
@Suite struct SubtitleSourceTests {
    /// The lines of a video that has `text` as its subtitle file `name`.
    func lines(_ name: String, _ text: String) async throws -> [TimedLine]? {
        let folder = try Folder()
        let video = try folder.file("talk.mp4")
        try folder.file(name, text)
        return await SubtitleSource().transcript(for: video)?.lines
    }

    @Test func theFixturesSrtGivesTheSameLinesAsItsVoiceover() async throws {
        let transcript = await SubtitleSource().transcript(for: fixtureFolder.appendingPathComponent("sample.mp4"))

        #expect(transcript == SourceTranscript(lines: fixtureScenes, complete: true))
    }

    @Test func anSrtCueOfSeveralLinesIsOneLineWithoutItsTags() async throws {
        let srt = """
            1
            00:00:01,500 --> 00:00:04,250
            <i>First</i> line
            and its second line

            2
            01:02:03,004 --> 01:02:05,000
            An hour in.

            """

        #expect(try await lines("talk.srt", srt) == [
            TimedLine(start: 1.5, end: 4.25, text: "First line and its second line"),
            TimedLine(start: 3723.004, end: 3725, text: "An hour in."),
        ])
    }

    @Test func anSrtWithWindowsLineEndingsAndAByteOrderMarkReads() async throws {
        let srt = "\u{FEFF}1\r\n00:00:00,000 --> 00:00:02,000\r\nHello.\r\n\r\n2\r\n00:00:02,000 --> 00:00:04,000\r\nAgain.\r\n"

        #expect(try await lines("talk.srt", srt) == [
            TimedLine(start: 0, end: 2, text: "Hello."), TimedLine(start: 2, end: 4, text: "Again."),
        ])
    }

    @Test func aVttFileReadsWithItsHeaderNotesCueNamesAndSettings() async throws {
        let vtt = """
            WEBVTT - a talk

            NOTE
            This block is a note, not a cue.

            STYLE
            ::cue { color: white }

            intro
            00:01.000 --> 00:04.500 line:0 position:20% align:start
            <v Ada>Short times have no hours.</v>

            00:00:04.500 --> 00:00:09.000
            - Two speakers
            - in one cue

            """

        #expect(try await lines("talk.vtt", vtt) == [
            TimedLine(start: 1, end: 4.5, text: "Short times have no hours."),
            TimedLine(start: 4.5, end: 9, text: "- Two speakers - in one cue"),
        ])
    }

    @Test func theSrtIsUsedBeforeTheVtt() async throws {
        let folder = try Folder()
        let video = try folder.file("talk.mp4")
        try folder.file("talk.vtt", "WEBVTT\n\n00:00.000 --> 00:02.000\nfrom the vtt\n")
        #expect(await SubtitleSource().transcript(for: video)?.lines.map(\.text) == ["from the vtt"])

        try folder.file("talk.srt", "1\n00:00:00,000 --> 00:00:02,000\nfrom the srt\n")
        #expect(await SubtitleSource().transcript(for: video)?.lines.map(\.text) == ["from the srt"])
    }

    @Test func cuesThatDoNotReadAreSkippedAndAFileWithNoCueIsNoTranscript() async throws {
        let srt = """
            1
            00:00:05,000 --> 00:00:03,000
            Ends before it starts.

            2
            sometime --> later
            No times.

            3
            00:00:06,000 --> 00:00:08,000

            4
            00:00:08,000 --> 00:00:09,000
            The one good cue.
            """

        #expect(try await lines("talk.srt", srt) == [TimedLine(start: 8, end: 9, text: "The one good cue.")])
        #expect(try await lines("talk.srt", "nothing like subtitles\n") == nil)
        #expect(try await lines("talk.txt", srt) == nil)
    }
}
