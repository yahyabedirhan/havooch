import Foundation
import Testing
import VRTranscript

/// Speech recognition as a source, with the recognition run by the test:
/// lines that grow, the cache, and what a failure leaves.
@Suite struct SpeechSourceTests {
    static let video = URL(fileURLWithPath: "/videos/talk.mp4")
    static let first = TimedLine(start: 0.5, end: 3, text: "First sentence.")
    static let second = TimedLine(start: 3.2, end: 6, text: "Second sentence.")

    @Test func beforeItIsPreparedItHasNoLinesAndIsNotComplete() async {
        let source = SpeechSource(cache: MemoryCache(), recognize: Recognition().recognize)

        #expect(await source.transcript(for: Self.video) == SourceTranscript(lines: [], complete: false))
    }

    @Test func itsLinesGrowWhileItRunsAndTheWholeTranscriptIsCachedWhenItEnds() async {
        let cache = MemoryCache()
        let recognition = Recognition()
        let source = SpeechSource(cache: cache, recognize: recognition.recognize)

        await source.prepare(Self.video)
        await until("the recognition starts") { recognition.started == 1 }
        recognition.hear(Self.first)
        await until("the first line") { await source.transcript(for: Self.video)?.lines.count == 1 }

        #expect(await source.transcript(for: Self.video) == SourceTranscript(lines: [Self.first], complete: false))
        #expect(cache.load(for: Self.video) == nil)

        recognition.hear(Self.second)
        recognition.end()
        await until("the end") { await source.transcript(for: Self.video)?.complete == true }

        #expect(await source.transcript(for: Self.video) == SourceTranscript(lines: [Self.first, Self.second], complete: true))
        #expect(cache.load(for: Self.video) == [Self.first, Self.second])
    }

    @Test func aCachedTranscriptIsThereAtOnceAndNothingIsRecognised() async {
        let recognition = Recognition()
        let source = SpeechSource(cache: MemoryCache([Self.video: [Self.first]]), recognize: recognition.recognize)

        await source.prepare(Self.video)

        #expect(await source.transcript(for: Self.video) == SourceTranscript(lines: [Self.first], complete: true))
        #expect(recognition.started == 0)
    }

    @Test func aVideoWithNoSpeechEndsCompleteWithNoLines() async {
        let cache = MemoryCache()
        let recognition = Recognition()
        let source = SpeechSource(cache: cache, recognize: recognition.recognize)

        await source.prepare(Self.video)
        await until("the recognition starts") { recognition.started == 1 }
        recognition.end()
        await until("the end") { await source.transcript(for: Self.video)?.complete == true }

        #expect(await source.transcript(for: Self.video) == SourceTranscript(lines: [], complete: true))
        #expect(cache.load(for: Self.video) == [])
    }

    @Test func aRecognitionThatFailsKeepsItsLinesSaysWhyAndIsNotCached() async {
        let cache = MemoryCache()
        let recognition = Recognition()
        let source = SpeechSource(cache: cache, recognize: recognition.recognize)

        await source.prepare(Self.video)
        await until("the recognition starts") { recognition.started == 1 }
        recognition.hear(Self.first)
        recognition.end(throwing: SpeechProblem("the video has no audio track"))
        await until("the failure") { await source.transcript(for: Self.video)?.problem != nil }

        #expect(
            await source.transcript(for: Self.video)
                == SourceTranscript(lines: [Self.first], complete: false, problem: "the video has no audio track")
        )
        #expect(cache.load(for: Self.video) == nil)
    }

    @Test func openingTheVideoAgainStartsNoSecondRecognitionWhileOneRunsOrAfterItEnded() async {
        let recognition = Recognition()
        let source = SpeechSource(cache: MemoryCache(), recognize: recognition.recognize)

        await source.prepare(Self.video)
        await source.prepare(Self.video)
        await until("the recognition starts") { recognition.started == 1 }
        recognition.hear(Self.first)
        recognition.end()
        await until("the end") { await source.transcript(for: Self.video)?.complete == true }
        await source.prepare(Self.video)

        #expect(recognition.started == 1)
        #expect(await source.transcript(for: Self.video)?.lines == [Self.first])
    }

    @Test func openingTheVideoAgainAfterAFailureRecognisesItAgain() async {
        let recognition = Recognition()
        let source = SpeechSource(cache: MemoryCache(), recognize: recognition.recognize)

        await source.prepare(Self.video)
        await until("the recognition starts") { recognition.started == 1 }
        recognition.hear(Self.first)
        recognition.end(throwing: SpeechProblem("the model isn't there"))
        await until("the failure") { await source.transcript(for: Self.video)?.problem != nil }
        await source.prepare(Self.video)
        await until("the second recognition starts") { recognition.started == 2 }

        #expect(await source.transcript(for: Self.video) == SourceTranscript(lines: [], complete: false))
    }
}
