import ReviewCore
import ReviewStore
import ReviewWire
import SwiftUI

/// One comment in the rail, as a full-width row: its pin, time and state, a
/// picture (the region's crop, else the keyframe) and the text, then its
/// thread. A click selects it and moves the player to its time. A queued
/// row can be edited and deleted; no other row shows those controls. The
/// thread is open on the selected row and on any row with an open
/// question; another row shows its last message on one line.
///
/// A row has no border: the selected row is told by its fill, and the rail
/// draws a hairline between rows.
struct CommentRow: View {
    let model: AppModel
    let comment: Comment
    /// The comment's number in time order, as on its marker.
    let number: Int

    @State private var thumbnail: CGImage?
    /// The text being edited; nil while the row only shows its comment.
    @State private var edited: String?
    @State private var isHovered = false
    @Environment(\.palette) private var palette

    private static let thumbnailSize = CGSize(width: 96, height: 54)
    /// The space between the pin and the time, which the text lines up with.
    static let pinSpacing: CGFloat = 8
    /// How far a row's words start from its leading edge, where the
    /// hairline between rows starts.
    static let textInset: CGFloat = Metrics.railPadding + MarkerPin.size + pinSpacing

    private var isSelected: Bool { model.selection == comment.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .top, spacing: 10) {
                keyframe
                if let edited {
                    CommentField(text: binding(edited), placeholder: "Comment", commit: save, cancel: { self.edited = nil })
                        .frame(height: 66)
                } else {
                    Text(comment.text)
                        .font(.callout)
                        .lineLimit(isSelected ? nil : 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            if let edited {
                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { self.edited = nil }
                    Button("Save", action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(!AppModel.hasWords(edited))
                }
                .controlSize(.small)
            }
            if !comment.thread.isEmpty {
                if isSelected || comment.openQuestion != nil {
                    ThreadView(messages: comment.thread, agent: model.agentName) { model.answerQuestion(comment.id, text: $0) }
                        .padding(.top, 4)
                } else {
                    threadSummary
                }
            }
        }
        .padding(.horizontal, Metrics.railPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill)
        .animation(.smooth(duration: 0.15), value: isSelected)
        .animation(.smooth(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture { model.select(comment.id) }
        .onHover { isHovered = $0 }
        .task(id: comment.id) { await loadThumbnail() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comment \(number) at \(TimeCode.text(comment.time))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The selected row's fill; a fainter one under the pointer.
    private var fill: Color {
        if isSelected { return palette[.sidebarRowSelected] }
        return isHovered ? palette[.sidebarRowHover] : .clear
    }

    private var header: some View {
        HStack(spacing: Self.pinSpacing) {
            MarkerPin(
                number: number, state: comment.state, isSelected: isSelected,
                badge: MarkerPin.Badge(comment, unread: model.unread)
            )
            Text(TimeCode.text(comment.time))
                .font(.callout.monospacedDigit().weight(.semibold))
            if comment.region != nil {
                Image(systemName: "rectangle.dashed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette[.textSecondary])
                    .help("On a region of the frame")
                    .accessibilityLabel("On a region of the frame")
            }
            StateChip(state: comment.state)
            Spacer(minLength: 4)
            if comment.state.isEditable, edited == nil {
                RowButton("Edit", symbol: "pencil") { edited = comment.text }
                RowButton("Delete", symbol: "trash") { model.delete(comment.id) }
            }
        }
    }

    /// A closed thread on one line: its last message, and how many there
    /// are. An unread one is picked out.
    @ViewBuilder
    private var threadSummary: some View {
        if let last = comment.thread.last {
            let isUnread = model.unread.contains(comment.id)
            HStack(spacing: 6) {
                Image(systemName: isUnread ? "bubble.left.fill" : "bubble.left")
                    .font(.caption)
                    .foregroundStyle(isUnread ? palette[.agent] : palette[.textTertiary])
                    .accessibilityHidden(true)
                Text("\(last.author == .agent ? model.agentName : "You"): \(last.text)")
                    .font(.caption.weight(isUnread ? .semibold : .regular))
                    .foregroundStyle(isUnread ? palette[.textPrimary] : palette[.textSecondary])
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if comment.thread.count > 1 {
                    Text("\(comment.thread.count)")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(palette[.textTertiary])
                        .accessibilityLabel("\(comment.thread.count) messages")
                }
            }
        }
    }

    private var keyframe: some View {
        ZStack {
            palette[.letterbox]
            if let thumbnail {
                Image(decorative: thumbnail, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        // A hairline only, so the black of the letterbox keeps an edge on a
        // dark rail.
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(palette[.separator], lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private func binding(_ edited: String) -> Binding<String> {
        Binding(get: { self.edited ?? edited }, set: { self.edited = $0 })
    }

    private func save() {
        guard let edited, AppModel.hasWords(edited) else { return }
        model.edit(comment.id, text: edited)
        self.edited = nil
    }

    private func loadThumbnail() async {
        // What the comment points at: its region's crop, else the whole frame.
        guard let file = model.crop(of: comment) ?? model.keyframe(of: comment) else { return }
        // Twice the thumbnail's size, for a sharp picture on a Retina display.
        thumbnail = await Self.thumbnail(of: file, side: Int(Self.thumbnailSize.width) * 2)
    }

    /// The picture at `file`, made small off the main actor.
    @concurrent
    nonisolated private static func thumbnail(of file: URL, side: Int) async -> CGImage? {
        ImageFiles.thumbnail(of: file, side: side)
    }
}

/// A comment's state: its glyph and its name, in its colour. No capsule
/// behind it: the pin beside it already carries the colour, and the name
/// only has to be read.
struct StateChip: View {
    let state: CommentState
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: StateLook.glyph(state))
                .imageScale(.small)
            Text(StateLook.name(state))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(palette.state(state))
        .accessibilityElement(children: .combine)
    }
}

/// A quiet symbol button on a row.
private struct RowButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    init(_ title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}
