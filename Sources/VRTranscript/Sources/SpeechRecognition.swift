import AVFoundation
import Foundation
import Speech

/// Apple's SpeechAnalyzer with a SpeechTranscriber, on the audio track of
/// a video file: what `SpeechSource` runs outside of tests.
public enum SpeechRecognition {
    /// The lines of `video`, each as soon as the transcriber is sure of it.
    public static let lines: SpeechSource.Recognize = { video in
        AsyncThrowingStream { continuation in
            let task = Task(priority: .utility) {
                do {
                    try await recognize(video) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func recognize(_ video: URL, line: @escaping @Sendable (TimedLine) -> Void) async throws {
        guard SpeechTranscriber.isAvailable else { throw SpeechProblem("speech recognition isn't available on this Mac") }
        let asset = AVURLAsset(url: video)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw SpeechProblem("the video has no audio track")
        }
        guard let locale = await locale() else { throw SpeechProblem("speech recognition supports none of this Mac's languages") }
        // Final results only: a line is given once, when it no longer changes.
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        try await installModel(for: transcriber, locale: locale)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechProblem("speech recognition names no audio format it reads")
        }
        let audio = try AudioTrack(track, of: asset, as: format)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            async let heard: Void = {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    let start = result.range.start.seconds
                    let end = result.range.end.seconds
                    guard !text.isEmpty, start.isFinite, end.isFinite else { continue }
                    line(TimedLine(start: TimedLine.milliseconds(start), end: TimedLine.milliseconds(end), text: text))
                }
            }()
            // The analyzer asks for each buffer when it is ready for it, so
            // a long video is never decoded ahead into memory.
            _ = try await analyzer.analyzeSequence(AsyncStream(unfolding: { Task.isCancelled ? nil : audio.next() }))
            try Task.checkCancellation()
            try audio.check()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try await heard
        } catch {
            // Ends `results`, so nothing is left waiting on it.
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    /// The language to recognise: the first of the person's languages the
    /// transcriber supports, exactly or as another region's form of it;
    /// American English when none is.
    private static func locale() async -> Locale? {
        let supported = await SpeechTranscriber.supportedLocales
        for identifier in Locale.preferredLanguages + ["en-US"] {
            let wanted = Locale(identifier: identifier)
            if let exact = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) { return exact }
            if let language = wanted.language.languageCode,
                let other = supported.first(where: { $0.language.languageCode == language })
            {
                return other
            }
        }
        return nil
    }

    /// Downloads the language's model when this Mac doesn't have it yet.
    private static func installModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return
        case .unsupported:
            throw SpeechProblem("speech recognition has no model for \(locale.identifier) on this Mac")
        default:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }
    }
}

/// A video's audio track, decoded buffer by buffer in the format the
/// analyzer reads. One caller at a time reads it.
private final class AudioTrack: @unchecked Sendable {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let format: AVAudioFormat

    init(_ track: AVAssetTrack, of asset: AVAsset, as format: AVAudioFormat) throws {
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: format.settings)
        output.alwaysCopiesSampleData = false
        self.format = format
        guard reader.canAdd(output) else { throw SpeechProblem("the video's audio track can't be read") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? SpeechProblem("the video's audio track can't be read") }
    }

    /// The next stretch of audio; nil at the track's end, and when reading fails.
    func next() -> AnalyzerInput? {
        while let sample = output.copyNextSampleBuffer() {
            let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
            guard frames > 0 else { continue }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
            buffer.frameLength = frames
            let copied = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
            guard copied == noErr else { return nil }
            return AnalyzerInput(buffer: buffer)
        }
        return nil
    }

    /// Throws when the track ended because it couldn't be read on.
    func check() throws {
        if reader.status == .failed { throw reader.error ?? SpeechProblem("the video's audio track can't be read") }
    }
}
