import Foundation
import Testing
import VRTranscript

/// `voiceover.json` in the video's folder: scene times from scene lengths.
@Suite struct VoiceoverSourceTests {
    @Test func theFixturesScenesStartAndEndAsItsReadmeSays() async throws {
        let source = VoiceoverSource(frameRate: { _ in 30 })

        let transcript = try #require(await source.transcript(for: fixtureFolder.appendingPathComponent("sample.mp4")))

        #expect(transcript == SourceTranscript(lines: fixtureScenes, complete: true))
        #expect(transcript.lines.map(\.start) == [0, 6.067, 14.333])
        #expect(transcript.lines.map(\.end) == [6.067, 14.333, 21.233])
    }

    @Test func theFrameRateIsReadFromTheVideoWhenNoneIsGiven() async throws {
        // The fixture is at 30 frames a second: the same times as above.
        let transcript = await VoiceoverSource().transcript(for: fixtureFolder.appendingPathComponent("sample.mp4"))

        #expect(transcript?.lines == fixtureScenes)
    }

    @Test func aSceneLastsAWholeNumberOfFramesAtTheVideosFrameRate() async throws {
        let folder = try Folder()
        let video = try folder.file("talk.mp4")
        try folder.file(
            "voiceover.json",
            #"{"scenes":[{"id":"a","text":"One.","durationSeconds":1.01,"paddingSeconds":0.4},"#
                + #"{"id":"b","text":"Two.","durationSeconds":2,"paddingSeconds":0}]}"#
        )

        // 1.41 s is 35.25 frames at 25 a second: 36 frames, 1.44 s. Then 50 frames more.
        let at25 = await VoiceoverSource(frameRate: { _ in 25 }).transcript(for: video)
        // At 60 a second it is 84.6 frames: 85 frames, 1.417 s. Then 120 frames more.
        let at60 = await VoiceoverSource(frameRate: { _ in 60 }).transcript(for: video)

        #expect(at25?.lines == [TimedLine(start: 0, end: 1.44, text: "One."), TimedLine(start: 1.44, end: 3.44, text: "Two.")])
        #expect(at60?.lines == [TimedLine(start: 0, end: 1.417, text: "One."), TimedLine(start: 1.417, end: 3.417, text: "Two.")])
    }

    @Test func aSceneWithNoNarrationTakesItsTimeAndGivesNoLine() async throws {
        let folder = try Folder()
        let video = try folder.file("talk.mp4")
        try folder.file(
            "voiceover.json",
            #"{"scenes":[{"text":"","durationSeconds":2,"paddingSeconds":0},{"text":"After the title.","durationSeconds":3}]}"#
        )

        let transcript = await VoiceoverSource(frameRate: { _ in 30 }).transcript(for: video)

        #expect(transcript?.lines == [TimedLine(start: 2, end: 5, text: "After the title.")])
    }

    @Test func aFolderWithoutTheFileOrWithOneThatDoesNotReadHasNoVoiceover() async throws {
        let folder = try Folder()
        let video = try folder.file("talk.mp4")
        let source = VoiceoverSource(frameRate: { _ in 30 })

        #expect(await source.transcript(for: video) == nil)

        try folder.file("voiceover.json", "not json")
        #expect(await source.transcript(for: video) == nil)

        try folder.file("voiceover.json", #"{"scenes":[]}"#)
        #expect(await source.transcript(for: video) == nil)
    }
}
