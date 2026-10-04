import SwiftUI

/// The toolbar's button for the open video's context: its popover shows the
/// sidecar and holds the note. The button's glyph is filled once the video
/// has a sidecar or a note, so an empty context shows without opening it.
struct ContextButton: View {
    let model: ReviewModel
    @State private var isShown = false
    /// The sidecar as it was when the popover opened.
    @State private var sidecar: ContextSidecar?

    var body: some View {
        let found = model.sidecar
        Button {
            sidecar = model.sidecar
            isShown = true
        } label: {
            Label("Context", systemImage: Self.hasContext(sidecar: found != nil, note: model.note) ? "doc.text.fill" : "doc.text")
        }
        .help(Self.help(sidecar: found?.url.lastPathComponent, note: model.note))
        .accessibilityLabel("Video context")
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            ContextPopover(sidecar: sidecar, note: model.note) { model.noteByPerson($0) }
        }
    }

    nonisolated static func hasContext(sidecar: Bool, note: String) -> Bool {
        sidecar || !note.isEmpty
    }

    /// The button's tooltip: what the listener gets as this video's context.
    nonisolated static func help(sidecar: String?, note: String) -> String {
        switch (sidecar, note.isEmpty) {
        case (let name?, true): "Context for the agent: \(name)"
        case (let name?, false): "Context for the agent: \(name) and your note"
        case (nil, false): "Context for the agent: your note"
        case (nil, true): "No context for the agent yet. Add a note, or put a context.md beside the video."
        }
    }
}

/// The video's context as the listener gets it: the sidecar's text, read
/// only, and under it the person's note, kept when the popover closes.
struct ContextPopover: View {
    let sidecar: ContextSidecar?
    /// Keeps the note.
    let keep: (String) -> Void
    @State private var draft: String
    @Environment(\.dismiss) private var dismiss

    init(sidecar: ContextSidecar?, note: String, keep: @escaping (String) -> Void) {
        self.sidecar = sidecar
        self.keep = keep
        _draft = State(initialValue: note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Context")
                    .font(.headline)
                Text("The agent gets this with your first batch, and again when it changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label(sidecar?.url.lastPathComponent ?? "No context file", systemImage: "doc.text")
                    .font(.subheadline.weight(.medium))
                if let sidecar, !sidecar.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ScrollView {
                        Text(sidecar.text)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 150)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.cardCorner))
                } else {
                    Text(sidecar == nil
                        ? "Put a context.md, or a file named after the video and ending in .context.md, beside the video."
                        : "The file is empty.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("Your note", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.medium))
                TextEditor(text: $draft)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 96)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.cardCorner))
                    .accessibilityLabel("Your note about this video")
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.edge)
        .frame(width: 380)
        // Every way out keeps the note: Done, Escape, a click outside.
        .onDisappear { keep(draft) }
    }
}
