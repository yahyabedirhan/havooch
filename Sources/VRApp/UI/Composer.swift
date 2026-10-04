import SwiftUI

/// The comment box: opens focused over the stage, so the person types (or
/// dictates) at once. Enter queues the comment, Shift+Enter adds a line,
/// Escape cancels.
struct Composer: View {
    /// The time the comment is at.
    let time: Double
    /// Queues the text; false when it's refused, and the box stays.
    let commit: (String) -> Bool
    let cancel: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Comment at \(TimeText.short(time))", systemImage: "plus.bubble")
                    .font(.headline)
                Spacer()
                Text("Enter queues · Shift+Enter adds a line · Esc cancels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 72)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                .focused($isFocused)
                .onKeyPress(.return, phases: .down) { press in
                    // Shift+Enter is the text view's: a new line.
                    guard !press.modifiers.contains(.shift) else { return .ignored }
                    _ = commit(text)
                    return .handled
                }
                .onKeyPress(.escape, phases: .down) { _ in
                    cancel()
                    return .handled
                }
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Queue") { _ = commit(text) }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBlank)
            }
        }
        .padding(Theme.gap)
        .frame(maxWidth: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardCorner + 2))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .onAppear { isFocused = true }
    }
}
