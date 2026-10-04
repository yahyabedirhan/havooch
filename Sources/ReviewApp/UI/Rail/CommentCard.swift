import ReviewCore
import ReviewStore
import ReviewWire
import SwiftUI

/// One comment in the rail: its pin, time and state, the keyframe and the
/// text. A click selects it and moves the player to its time. A queued card
/// can be edited and deleted; no other card shows those controls.
struct CommentCard: View {
    let model: AppModel
    let comment: Comment
    /// The comment's number in time order, as on its marker.
    let number: Int

    @State private var thumbnail: CGImage?
    /// The text being edited; nil while the card only shows its comment.
    @State private var edited: String?

    private static let thumbnailSize = CGSize(width: 96, height: 54)
    private static let corner: CGFloat = 10

    private var isSelected: Bool { model.selection == comment.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
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
        }
        .padding(10)
        .background(
            isSelected ? AnyShapeStyle(.tint.opacity(0.13)) : AnyShapeStyle(.quaternary.opacity(0.45)),
            in: RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .strokeBorder(isSelected ? AnyShapeStyle(.tint.opacity(0.75)) : AnyShapeStyle(.quaternary), lineWidth: isSelected ? 1.5 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .onTapGesture { model.select(comment.id) }
        .task(id: comment.id) { await loadThumbnail() }        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comment \(number) at \(TimeCode.text(comment.time))")
    }

    private var header: some View {
        HStack(spacing: 8) {
            MarkerPin(number: number, state: comment.state, isSelected: isSelected)
            Text(TimeCode.text(comment.time))
                .font(.callout.monospacedDigit().weight(.semibold))
            StateChip(state: comment.state)
            Spacer(minLength: 4)
            if comment.state.isEditable, edited == nil {
                CardButton("Edit", symbol: "pencil") { edited = comment.text }
                CardButton("Delete", symbol: "trash") { model.delete(comment.id) }
            }
        }
    }

    private var keyframe: some View {
        ZStack {
            Theme.letterbox
            if let thumbnail {
                Image(decorative: thumbnail, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.quaternary, lineWidth: 1) }
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
        guard let file = model.keyframe(of: comment) else { return }
        // Twice the card's size, for a sharp picture on a Retina display.
        thumbnail = await Self.thumbnail(of: file, side: Int(Self.thumbnailSize.width) * 2)
    }

    /// The picture at `file`, made small off the main actor.
    nonisolated private static func thumbnail(of file: URL, side: Int) async -> CGImage? {
        ImageFiles.thumbnail(of: file, side: side)
    }
}

/// A comment's state as a chip: its glyph and its name, in its colour.
struct StateChip: View {
    let state: CommentState

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: Theme.glyph(state))
                .imageScale(.small)
            Text(Theme.name(state))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.tint(state))
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Theme.tint(state).opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A quiet symbol button on a card.
private struct CardButton: View {
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
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(title)
        .accessibilityLabel(title)
    }
}
