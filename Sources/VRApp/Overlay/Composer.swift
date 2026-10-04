import SwiftUI

/// The comment box: it names the time the comment will be about, and has
/// the focus at once. `RegionOverlay` places it: over the foot of the frame,
/// or next to the region the comment points at. Return queues the comment,
/// Shift+Return makes a new line, Escape closes the box and gives its region
/// up. It is a standard text field, so dictation types into it like a
/// keyboard. What is typed is kept on the draft, not in the box, so a send
/// from anywhere queues it first.
struct Composer: View {
    let model: AppModel
    let time: Double
    /// Whether the comment is on a region of the frame.
    var pointsAtRegion = false

    @State private var selection: TextSelection?
    @State private var queueing = false
    @FocusState private var focused: Bool

    /// The draft's text, which the field edits in place.
    private var text: Binding<String> {
        Binding(get: { model.desk.draft?.text ?? "" }, set: { model.desk.typeDraft($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: pointsAtRegion ? "rectangle.dashed" : "bubble.left.fill").foregroundStyle(Color.accentColor)
                Text(pointsAtRegion ? "Region at \(TimeText.short(time))" : "Comment at \(TimeText.short(time))")
                    .font(.callout.weight(.semibold).monospacedDigit())
                Spacer()
                Text("Return to add  ·  Esc to cancel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField(pointsAtRegion ? "What about this part?" : "What about this moment?", text: text, selection: $selection, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title3)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(queue)
                .onExitCommand { model.discardDraft() }
                .onKeyPress(keys: [.return], phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    breakLine()
                    return .handled
                }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        .onAppear { focused = true }
    }

    /// Return: queues what was typed. Nothing typed, nothing happens.
    private func queue() {
        let typed = text.wrappedValue
        guard !queueing, !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        queueing = true
        Task {
            // Queued, the box closes with its draft; refused, it stays for another try.
            if await !model.commitDraftForPerson(text: typed) {
                queueing = false
                focused = true
            }
        }
    }

    /// Shift+Return: a new line where the insertion point is.
    private func breakLine() {
        var typed = text.wrappedValue
        if case .selection(let range) = selection?.indices, range.upperBound <= typed.endIndex {
            typed.replaceSubrange(range, with: "\n")
            text.wrappedValue = typed
            selection = TextSelection(insertionPoint: typed.index(after: range.lowerBound))
        } else {
            text.wrappedValue = typed + "\n"
        }
    }
}
