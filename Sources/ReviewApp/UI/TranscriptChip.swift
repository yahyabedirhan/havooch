import SwiftUI

/// The toolbar chip's words: where the open video's transcript comes from,
/// and how far it is. Pure, so its words are tested without a window.
struct TranscriptChip: Equatable {
    var title: String
    /// The SF Symbol beside the title.
    var symbol: String
    /// What the chip says when the pointer rests on it.
    var help: String
    /// Whether the transcript is still being made.
    var isWorking = false

    init(_ transcript: StateReport.Transcript) {
        let count = "\(transcript.lines) \(transcript.lines == 1 ? "line" : "lines")"
        switch transcript.source {
        case "voiceover":
            title = "Voiceover transcript"
            symbol = "captions.bubble"
            help = "The agent gets the narration around each comment, from voiceover.json (\(count))"
        case "subtitles":
            title = "Subtitle transcript"
            symbol = "captions.bubble"
            help = "The agent gets the subtitles around each comment, from the video's subtitle file (\(count))"
        default:
            if let problem = transcript.problem {
                title = transcript.lines == 0 ? "No transcript" : "Transcript stopped"
                symbol = "exclamationmark.triangle"
                help = "This Mac couldn't transcribe the video's speech: \(problem)"
            } else if !transcript.complete {
                title = transcript.lines == 0 ? "Transcribing…" : "Transcribing… \(count)"
                symbol = "waveform"
                help = "This Mac is transcribing the video's speech. A comment sent now gets the lines that are ready."
                isWorking = true
            } else if transcript.lines == 0 {
                title = "No speech"
                symbol = "waveform.slash"
                help = "This Mac found no speech in the video, so comments go without a transcript"
            } else {
                title = "Speech transcript"
                symbol = "waveform"
                help = "The agent gets the speech around each comment, transcribed on this Mac (\(count))"
            }
        }
    }
}

/// The chip in the toolbar. Speech arrives with no event, so it's drawn
/// again each second, as the presence pill is.
struct TranscriptChipView: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let transcript = model.transcript {
                let chip = TranscriptChip(transcript)
                Label(chip.title, systemImage: chip.symbol)
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative, isActive: chip.isWorking)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                    .help(chip.help)
                    .accessibilityLabel(chip.title)
            }
        }
    }
}
