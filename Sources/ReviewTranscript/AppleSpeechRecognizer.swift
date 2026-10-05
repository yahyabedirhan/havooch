// Apple's speech frameworks exist on macOS only; elsewhere the module builds without them.
#if canImport(Speech)
import AVFoundation
import Foundation
import Speech

/// Apple's on-device SpeechAnalyzer, reading a video file's sound. One line
/// for each result the transcriber finalizes, with the time range of its
/// audio.
public struct AppleSpeechRecognizer: SpeechRecognizing {
    /// Why no transcript came, as the state report says it.
    public struct Problem: LocalizedError, Equatable {
        public var errorDescription: String?

        init(_ reason: String) {
            errorDescription = reason
        }
    }

    /// The language the speech is in. The nearest one the transcriber
    /// supports is used, else American English.
    public var locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    public func lines(of file: URL) -> AsyncThrowingStream<TranscriptLine, any Error> {
        AsyncThrowingStream { continuation in
            let work = Task(priority: .utility) { [locale] in
                do {
                    try await Self.transcribe(file, locale: locale) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    @concurrent
    private static func transcribe(_ file: URL, locale: Locale, line: @escaping @Sendable (TranscriptLine) -> Void) async throws {
        // A video with no sound has no speech: done, with no lines.
        guard try await !AVURLAsset(url: file).loadTracks(withMediaType: .audio).isEmpty else { return }
        guard SpeechTranscriber.isAvailable else {
            throw Problem("on-device speech transcription isn't available on this Mac")
        }
        let fallback = Locale(identifier: "en-US")
        var supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        if supported == nil { supported = await SpeechTranscriber.supportedLocale(equivalentTo: fallback) }
        guard let supported else {
            throw Problem("on-device speech transcription has no model for \(locale.identifier) or \(fallback.identifier)")
        }
        let transcriber = SpeechTranscriber(
            locale: supported, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange]
        )
        // The language's model is downloaded once per Mac, by the system.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let audio = try AVAudioFile(forReading: file)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let heard: Void = {
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                line(TranscriptLine(start: result.range.start.seconds, end: result.range.end.seconds, text: text))
            }
        }()
        do {
            if let last = try await analyzer.analyzeSequence(from: audio) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            throw error
        }
        try await heard
    }
}
#endif
