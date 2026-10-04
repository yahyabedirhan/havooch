import SwiftUI
import VRReview

/// The comment box: opens focused over the stage, so the person types (or
/// dictates) at once. Enter queues the comment, Shift+Enter adds a line,
/// Escape cancels. For a comment on a region it's narrower, to stand beside
/// the rectangle, and Escape takes the rectangle away with it. The box and
/// its text field are opaque, in the window's own colours: over the black
/// stage a material goes grey, and its text faint, in light appearance.
struct Composer: View {
    /// The time the comment is at.
    let time: Double
    /// Whether the comment is on a drawn region of the frame.
    var isOnRegion = false
    /// What the box holds. The model keeps it, so Cmd+Enter queues it.
    @Binding var text: String
    /// Queues the text; false when it's refused, and the box stays.
    let commit: (String) -> Bool
    let cancel: () -> Void

    @FocusState private var isFocused: Bool

    /// The box's width beside a region.
    static let regionWidth: CGFloat = 320

    private var isBlank: Bool {
        ReviewSession.isBlank(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    isOnRegion ? "Comment on the region at \(TimeText.short(time))" : "Comment at \(TimeText.short(time))",
                    systemImage: isOnRegion ? "rectangle.dashed" : "plus.bubble"
                )
                .font(.headline)
                .foregroundStyle(.primary)
                Spacer()
                if !isOnRegion {
                    Text("Enter queues · Shift+Enter adds a line · Esc cancels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TextEditor(text: $text)
                .font(.body)
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 72)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
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
                if isOnRegion {
                    Text("Enter queues · Esc cancels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: cancel)
                Button("Queue") { _ = commit(text) }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBlank)
            }
        }
        .padding(Theme.gap)
        .frame(maxWidth: isOnRegion ? Self.regionWidth : 480)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.cardCorner + 2))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner + 2).strokeBorder(Color(nsColor: .separatorColor)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .onAppear { isFocused = true }
    }
}
