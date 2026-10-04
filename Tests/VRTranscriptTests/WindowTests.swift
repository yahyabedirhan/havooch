import Foundation
import Testing
import VRTranscript

/// The cut a comment's transcript is made with, on the fixture's scenes.
@Suite struct WindowTests {
    @Test func theWindowIsFifteenSecondsEachSideOfTheComment() {
        #expect(TranscriptWindow.around(100) == 85...115)
    }

    @Test func aCommentNearTheStartHasAWindowThatStartsAtZero() {
        #expect(TranscriptWindow.around(4) == 0...19)
        #expect(TranscriptWindow.around(0) == 0...15)
    }

    @Test func aCommentAtTenSecondsOfTheFixtureGetsTheLineWithPressCommandEnter() {
        let lines = TranscriptWindow.cut(fixtureScenes, to: TranscriptWindow.around(10))

        #expect(lines == fixtureScenes)
        #expect(lines.contains { $0.text.contains("Press command enter") })
    }

    @Test func aLineThatCrossesAnEdgeOfTheWindowIsKeptWhole() {
        // 5 s to 7 s spans the end of `pause` and the start of `send`.
        #expect(TranscriptWindow.cut(fixtureScenes, to: 5...7) == Array(fixtureScenes[0...1]))
        // Inside one line: that line, with its own times.
        #expect(TranscriptWindow.cut(fixtureScenes, to: 8...9) == [fixtureScenes[1]])
    }

    @Test func aLineThatOnlyTouchesTheWindowIsLeftOut() {
        let lines = [
            TimedLine(start: 0, end: 10, text: "ends where the window begins"),
            TimedLine(start: 10, end: 20, text: "inside"),
            TimedLine(start: 20, end: 30, text: "begins where the window ends"),
        ]

        #expect(TranscriptWindow.cut(lines, to: 10...20).map(\.text) == ["inside"])
    }

    @Test func aCommentNearTheEndGetsTheLinesUpToTheLastOne() {
        // A minute of ten-second lines, and a comment two seconds before the end.
        let lines = (0..<6).map { TimedLine(start: Double($0) * 10, end: Double($0 + 1) * 10, text: "line \($0)") }

        #expect(TranscriptWindow.cut(lines, to: TranscriptWindow.around(58)).map(\.text) == ["line 4", "line 5"])
        #expect(TranscriptWindow.cut(lines, to: TranscriptWindow.around(2)).map(\.text) == ["line 0", "line 1"])
    }

    @Test func theLinesComeInTimeOrderAndNoLinesGiveNone() {
        #expect(TranscriptWindow.cut(fixtureScenes.reversed(), to: 0...30) == fixtureScenes)
        #expect(TranscriptWindow.cut([], to: 0...30) == [])
        #expect(TranscriptWindow.cut(fixtureScenes, to: 40...70) == [])
    }
}
