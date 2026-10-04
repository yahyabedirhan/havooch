import SwiftUI
import VRReview

/// The toolbar's Context button and its popover: what the listener is told
/// about the open video. The popover names the sidecar file that was found
/// beside the video, or says that there is none, and holds the reviewer's
/// note, which counts as it is typed and is saved once the typing rests or
/// the popover closes. The button's icon is filled while
/// there is a context to send.
struct ContextNote: View {
    let model: AppModel

    @State private var shown = false
    /// The sidecar as it was when the popover opened, and the button last drew.
    @State private var sidecar: ContextSource.Sidecar?
    /// What is typed: the note itself is kept without the blank space
    /// around it, which typing must not lose.
    @State private var typed = ""
    @FocusState private var focused: Bool

    private var note: String { model.desk.open?.note ?? "" }

    var body: some View {
        let video = model.player.video
        Button {
            shown.toggle()
        } label: {
            Label("Context", systemImage: sidecar != nil || !note.isEmpty ? "doc.text.fill" : "doc.text")
        }
        .disabled(video == nil)
        .help(hint)
        .accessibilityLabel("Context for the agent")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            popover
        }
        .onChange(of: video?.url, initial: true) { read() }
        .onChange(of: shown) {
            read()
            if !shown { model.endNote() }
        }
        // A note set from the command line shows in an open popover too.
        .onChange(of: note) { read() }
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context for the agent")
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: sidecar == nil ? "doc.badge.ellipsis" : "doc.text.fill")
                    .foregroundStyle(sidecar == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                VStack(alignment: .leading, spacing: 2) {
                    Text(sidecar?.url.lastPathComponent ?? "No context file beside this video")
                        .font(.callout.weight(.medium))
                    Text(sidecarHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            Text("Your note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $typed)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 110)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if typed.isEmpty {
                        Text("What is this video about? Which repo?")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }
                .focused($focused)
                .onChange(of: typed) { model.attempt { () throws(ActionError) in try model.typeNote(typed) } }
                .accessibilityLabel("Context note")
            Text("The agent gets the file's text and your note with the next batch, and again only after either changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { focused = true }
    }

    /// Reads the sidecar again, and takes the note over when it isn't what
    /// was typed (another video, or `context set`).
    private func read() {
        sidecar = model.sidecar
        if typed.trimmingCharacters(in: .whitespacesAndNewlines) != note { typed = note }
    }

    private var sidecarHint: String {
        guard let video = model.player.video else { return "" }
        if sidecar != nil { return "Found beside the video. Its text goes to the agent." }
        let names = ContextText.candidates(for: video.url).map(\.lastPathComponent)
        return "Put \(names.joined(separator: " or ")) in the video's folder to send one."
    }

    private var hint: String {
        guard model.player.video != nil else { return "Open a video to give the agent its context" }
        switch (sidecar, note.isEmpty) {
        case (let sidecar?, true): return "Context: \(sidecar.url.lastPathComponent)"
        case (let sidecar?, false): return "Context: \(sidecar.url.lastPathComponent) and your note"
        case (nil, false): return "Context: your note"
        case (nil, true): return "No context for the agent yet. Click to write a note."
        }
    }
}
