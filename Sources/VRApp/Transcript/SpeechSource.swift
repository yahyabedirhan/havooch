import AVFoundation
import Foundation
import Speech
import VRTranscript

/// The transcript of a video's sound, recognized on this Mac by Apple's
/// SpeechAnalyzer with a SpeechTranscriber: one line per phrase the
/// recognizer ends. The whole file is recognized, then cut to the window.
///
/// The language is the person's first preferred language that the
/// recognizer knows, else US English. The sound never leaves the Mac. The
/// language's model is installed by the system when it isn't there yet.
struct SpeechSource: Transcriber {
    /// The language recognized when the person's own isn't known.
    static let fallbackLanguage = "en-US"

    func lines(for video: URL, in window: ClosedRange<Double>) async throws -> [TranscriptLine] {
        // A video without sound says nothing.
        guard try await !AVURLAsset(url: video).loadTracks(withMediaType: .audio).isEmpty else { return [] }
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptFailure("this Mac can't transcribe speech on the device")
        }
        let locale = try await Self.locale()
        let transcriber = SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange]
        )
        try await Self.install(transcriber, for: locale)

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: video)
        } catch {
            throw TranscriptFailure("couldn't read the sound of \(video.lastPathComponent): \(error.localizedDescription)")
        }
        // The results are read while the analyzer works through the file.
        let reading = Task {
            var lines: [TranscriptLine] = []
            for try await result in transcriber.results {
                let range = result.range
                if let line = TranscriptLine.tidy(start: range.start.seconds, end: range.end.seconds, text: String(result.text.characters)) {
                    lines.append(line)
                }
            }
            return lines
        }
        do {
            let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber], finishAfterFile: true)
            let lines = try await reading.value
            // The analyzer lives until its last result was read.
            withExtendedLifetime(analyzer) {}
            return TranscriptWindow.cut(lines, to: window)
        } catch {
            reading.cancel()
            throw error
        }
    }

    /// The language to recognize.
    private static func locale() async throws -> Locale {
        for language in Locale.preferredLanguages + [fallbackLanguage] {
            if let known = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) {
                return known
            }
        }
        throw TranscriptFailure("speech recognition knows neither your language nor \(fallbackLanguage)")
    }

    /// Has the system install the model of `locale` when it isn't on this
    /// Mac yet.
    private static func install(_ transcriber: SpeechTranscriber, for locale: Locale) async throws {
        let language = locale.identifier(.bcp47)
        guard await !SpeechTranscriber.installedLocales.contains(where: { $0.identifier(.bcp47) == language }) else { return }
        guard await AssetInventory.status(forModules: [transcriber]) != .unsupported else {
            throw TranscriptFailure("speech recognition has no model for \(language)")
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}
