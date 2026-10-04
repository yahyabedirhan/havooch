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
    ///   - isDue: whether the listener's next batch carries the context.
    init(sidecar: String?, names: [String], hasContext: Bool, isDue: Bool) {
        source = sidecar ?? "No \(names.joined(separator: " or ")) beside this video"
        if !hasContext {
            delivery = "Nothing to tell the agent yet"
            help = "Tell the agent what this video is about"
        } else if isDue {
            delivery = "Goes to the agent with your next batch"
            help = "What the agent is told about this video. It goes with your next batch"
        } else {
            delivery = "The agent has this. It goes again when it changes"
            help = "What the agent is told about this video. The agent has it"
        }
    }
}

/// The toolbar's Context button, with the popover it opens. Its glyph is
/// filled while the video has a context to send.
struct ContextButton: View {
    @Bindable var model: AppModel

    var body: some View {
        Button {
            model.isContextShown.toggle()
        } label: {
            Label("Context", systemImage: model.contextText == nil ? "doc.text" : "doc.text.fill")
        }
        .help(ContextPopover.words(for: model).help)
        .popover(isPresented: $model.isContextShown, arrowEdge: .bottom) {
            ContextPopover(model: model)
        }
    }
}

/// What the agent is told about the video: the sidecar file's text, which
/// is read-only here, and the person's own note under it. Save and Return
/// keep the note; Escape closes the popover and drops the change.
struct ContextPopover: View {
    let model: AppModel
    /// The note as it's being written; the model's until it's saved.
    @State private var note = ""

    static let width: CGFloat = 400
    /// The sidecar's text scrolls in a box of one height, so the popover
    /// doesn't change size with the file.
    static let sidecarHeight: CGFloat = 140

    static func words(for model: AppModel) -> ContextWords {
        ContextWords(
            sidecar: model.sidecar?.file.lastPathComponent,
            names: model.video.map { ContextReader.names(for: $0.url) } ?? [],
            hasContext: model.contextText != nil, isDue: model.isContextDue
        )
    }

    var body: some View {
        let words = Self.words(for: model)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Context for the agent")
                    .font(.headline)
                Text("Sent with the first batch of a listening agent, and again when it changes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sidecar(words)
            noteEditor
            Divider()
            HStack(spacing: 8) {
                Image(systemName: model.contextText == nil ? "circle.dashed" : (model.isContextDue ? "arrow.up.circle" : "checkmark.circle"))
                    .foregroundStyle(model.contextText != nil && !model.isContextDue ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                Text(words.delivery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Cancel") { model.isContextShown = false }
                    .controlSize(.small)
                Button("Save") { model.saveContextNote(note) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!isChanged)
            }
        }
        .padding(16)
        .frame(width: Self.width)
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
                    .foregroundStyle(.secondary)
                Text(words.source)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(model.sidecar == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if model.sidecar != nil {
                    Text("Read-only")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if let sidecar = model.sidecar {
                ScrollView {
                    Text(sidecar.text.isEmpty ? "The file is empty." : sidecar.text)
                        .font(.callout)
                        .foregroundStyle(sidecar.text.isEmpty ? .tertiary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                }
                .frame(height: Self.sidecarHeight)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .help((sidecar.file.path as NSString).abbreviatingWithTildeInPath)
            }
        }
    }

    /// The person's note, in the same text view a comment is written in.
    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(.tint)
                Text("Your note")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
                Text("↩ saves · ⇧↩ new line")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            CommentField(
                text: $note, placeholder: "Add a note for the agent…",
                commit: { model.saveContextNote(note) }, cancel: { model.isContextShown = false }
            )
            .frame(height: 84)
        }
    }
}
