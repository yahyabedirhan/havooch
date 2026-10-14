import SwiftUI

struct TranscriptChip: Equatable {
    var title: String
    var symbol: String
    var help: String
    var isWorking = false

    init(_ transcript: StateReport.Transcript) {
        let count = "\(transcript.lines) \(transcript.lines == 1 ? "line" : "lines")"
        switch transcript.source {
        case "voiceover":
            title = "Voiceover transcript"
            symbol = "captions.bubble"
            help = "The agent gets the narration around each message, from voiceover.json (\(count))"
        case "subtitles":
            title = "Subtitle transcript"
            symbol = "captions.bubble"
            help = "The agent gets the subtitles around each message, from the video's subtitle file (\(count))"
        default:
            if let problem = transcript.problem {
                title = transcript.lines == 0 ? "No transcript" : "Transcript stopped"
                symbol = "exclamationmark.triangle"
                help = "This Mac couldn't transcribe the video's speech: \(problem)"
            } else if !transcript.complete {
                title = transcript.lines == 0 ? "Transcribing…" : "Transcribing… \(count)"
                symbol = "waveform"
                help = "This Mac is transcribing the video's speech. A message sent now gets the lines that are ready."
                isWorking = true
            } else if transcript.lines == 0 {
                title = "No speech"
                symbol = "waveform.slash"
                help = "This Mac found no speech in the video, so messages go without a transcript"
            } else {
                title = "Speech transcript"
                symbol = "waveform"
                help = "The agent gets the speech around each message, transcribed on this Mac (\(count))"
            }
        }
    }
}
