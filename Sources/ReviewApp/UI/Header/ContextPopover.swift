import ReviewCore
import SwiftUI

/// The words of the context popover: what the agent is told about the
/// video, and when.
struct ContextWords: Equatable {
    /// Where the sidecar's text comes from: the file's name, or that the
    /// video has none.
    var source: String
    /// When the agent gets the context.
    var delivery: String
    /// The toolbar button's tooltip.
    var help: String

    /// - Parameters:
    ///   - sidecar: the name of the sidecar file that serves the video.
    ///   - names: the names a sidecar of this video may have.
    ///   - hasContext: whether there's anything to tell: a sidecar's text or a note.
    ///   - isDue: whether the listener's next send carries the context.
    init(sidecar: String?, names: [String], hasContext: Bool, isDue: Bool) {
        source = sidecar ?? "No \(names.joined(separator: " or ")) beside this video"
        if !hasContext {
            delivery = "Nothing to tell the agent yet"
            help = "Tell the agent what this video is about"
        } else if isDue {
            delivery = "Goes to the agent with your next send"
            help = "What the agent is told about this video. It goes with your next send"
        } else {
            delivery = "The agent has this. It goes again when it changes"
            help = "What the agent is told about this video. The agent has it"
        }
    }
}

/// The toolbar's Context button, with the popover it opens. Its glyph is
/// filled while the video has a context to send, and pulses while this Mac
/// transcribes the video's speech.
struct ContextButton: View {
    @Bindable var model: AppModel
    /// The transcript's words, read again each second: speech arrives with
    /// no event.
    @State private var transcript: TranscriptChip?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    var body: some View {
        let words = ContextPopover.words(for: model)
        let isTranscribing = transcript?.isWorking == true
        Button {
            model.isContextShown.toggle()
        } label: {
            Label("Context", systemImage: model.contextText == nil ? "doc.text" : "doc.text.fill")
                .symbolEffect(.pulse, isActive: isTranscribing && !reduceMotion)
        }
        .pressedByKeys(in: model) { model.isContextShown.toggle() }
        .help(isTranscribing ? "\(words.help). \(transcript?.title ?? "")" : words.help)
        .popover(isPresented: $model.isContextShown, arrowEdge: .bottom) {
            ContextPopover(model: model)
                .tint(palette[.accent])
                .popoverSurface(palette)
        }
        .task {
            // Ends when the button leaves the toolbar with the video.
            while !Task.isCancelled {
                let now = model.transcript.map { TranscriptChip($0) }
                if now != transcript { transcript = now }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// What the agent is told about the video: the sidecar file's text, which
/// is read-only here, the person's own note under it, and where the
/// transcript around each message comes from. Save and Return keep the
/// note; Escape closes the popover and drops the change.
struct ContextPopover: View {
    let model: AppModel
    /// The note as it's being written; the model's until it's saved.
    @State private var note = ""

    static let width: CGFloat = 400
    /// The sidecar's text scrolls in a box of one height, so the popover
    /// doesn't change size with the file.
    static let sidecarHeight: CGFloat = 140
    @Environment(\.palette) private var palette
    private static let partShape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    static func words(for model: AppModel) -> ContextWords {
        ContextWords(
            sidecar: model.sidecar?.file.lastPathComponent,
            names: model.video.map { ContextReader.names(for: $0.url) } ?? [],
            hasContext: model.contextText != nil, isDue: model.isContextDue
        )
    }

    var body: some View {
        let words = Self.words(for: model)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Context for the agent")
                    .font(.headline)
                Text("Sent with the first send to a listening agent, and again when it changes.")
                    .font(.callout)
                    .foregroundStyle(palette[.textSecondary])
                    .fixedSize(horizontal: false, vertical: true)
            }
            sidecar(words)
            noteEditor
            transcriptPart
            HStack(spacing: 8) {
                Image(systemName: model.contextText == nil ? "circle.dashed" : (model.isContextDue ? "arrow.up.circle" : "checkmark.circle"))
                    .foregroundStyle(model.contextText != nil && !model.isContextDue ? palette.state(.done) : palette[.textSecondary])
                Text(words.delivery)
                    .font(.callout)
                    .foregroundStyle(palette[.textSecondary])
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Cancel") { model.isContextShown = false }
                    .controlSize(.small)
                Button("Save") { model.saveContextNote(note) }
                    .filledButton(palette)
                    .controlSize(.small)
                    .disabled(!isChanged)
            }
        }
        .padding(16)
        .frame(width: Self.width)
        .foregroundStyle(palette[.textPrimary])
        .onAppear {
            model.readSidecar()
            note = model.contextNote
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Context for the agent")
    }

    /// Whether the note in the editor differs from the saved one.
    private var isChanged: Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines) != model.contextNote
    }

    /// The sidecar's part: the file's name and folder, and its text.
    private func sidecar(_ words: ContextWords) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: model.sidecar == nil ? "doc.badge.ellipsis" : "doc.text")
                    .foregroundStyle(palette[.textSecondary])
                Text(words.source)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(model.sidecar == nil ? palette[.textSecondary] : palette[.textPrimary])
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if model.sidecar != nil {
                    Text("Read-only")
                        .font(.caption)
                        .foregroundStyle(palette[.textTertiary])
                }
            }
            if let sidecar = model.sidecar {
                ScrollView {
                    Text(sidecar.text.isEmpty ? "The file is empty." : sidecar.text)
                        .font(.callout)
                        .foregroundStyle(sidecar.text.isEmpty ? palette[.textTertiary] : palette[.textPrimary])
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                }
                .frame(height: Self.sidecarHeight)
                .background(palette[.well], in: Self.partShape)
                .help((sidecar.file.path as NSString).abbreviatingWithTildeInPath)
            }
        }
    }

    /// The person's note, in the same text view a message is written in.
    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(palette[.accent])
                Text("Your note")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
                Text("↩ saves · ⇧↩ new line")
                    .font(.caption)
                    .foregroundStyle(palette[.textTertiary])
            }
            MessageField(
                text: $note, placeholder: "Add a note for the agent…",
                commit: { model.saveContextNote(note) }, cancel: { model.isContextShown = false }
            )
            .frame(height: 84)
        }
    }

    /// Where the transcript around each message comes from, and how far it
    /// is. Read again each second, since speech arrives with no event.
    private var transcriptPart: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let transcript = model.transcript {
                let chip = TranscriptChip(transcript)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: chip.symbol)
                        .foregroundStyle(palette[.textSecondary])
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(chip.title)
                            .font(.callout.weight(.medium))
                        Text(chip.help)
                            .font(.caption)
                            .foregroundStyle(palette[.textSecondary])
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if chip.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette[.well], in: Self.partShape)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
