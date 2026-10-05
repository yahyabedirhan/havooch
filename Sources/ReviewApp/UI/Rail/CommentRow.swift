import ReviewCore
import ReviewStore
import ReviewWire
import SwiftUI

/// One of the person's messages in the rail, as a full-width row: its
/// state, a picture (the region's crop, else the thread's keyframe) and the
/// text. A click selects its thread and moves the player to its frame. A
/// queued row can be edited and deleted; no other row shows those controls.
///
/// A row has no border: the selected thread's rows are told by their fill.
struct CommentRow: View {
    let model: AppModel
    let message: Message
    let thread: ReviewThread

    @State private var thumbnail: CGImage?
    /// The text being edited; nil while the row only shows its message.
    @State private var edited: String?
    @State private var isHovered = false
    @Environment(\.palette) private var palette

    private static let thumbnailSize = CGSize(width: 96, height: 54)

    private var isSelected: Bool { model.selection == thread.id }
    private var state: MessageState { message.state ?? .queued }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .top, spacing: 10) {
                if !thread.isGeneral { keyframe }
                if let edited {
                    CommentField(text: binding(edited), placeholder: "Message", commit: save, cancel: { self.edited = nil })
                        .frame(height: 66)
                } else {
                    Text(message.text)
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
        .padding(.horizontal, Metrics.railPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill)
        .animation(.smooth(duration: 0.15), value: isSelected)
        .animation(.smooth(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture { model.select(thread.id) }
        .onHover { isHovered = $0 }
        .task(id: message.id) { await loadThumbnail() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your message on thread \(thread.number)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The selected thread's fill; a fainter one under the pointer.
    private var fill: Color {
        if isSelected { return palette[.sidebarRowSelected] }
        return isHovered ? palette[.sidebarRowHover] : .clear
    }

    private var header: some View {
        HStack(spacing: 8) {
            StateChip(state: state)
            if message.region != nil {
                Image(systemName: "rectangle.dashed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette[.textSecondary])
                    .help("On a region of the frame")
                    .accessibilityLabel("On a region of the frame")
            }
            Spacer(minLength: 4)
            if state.isEditable, edited == nil {
                RowButton("Edit", symbol: "pencil") { edited = message.text }
                RowButton("Delete", symbol: "trash") { model.delete(message.id) }
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
        model.edit(message.id, text: edited)
        self.edited = nil
    }

    private func loadThumbnail() async {
        // What the message points at: its region's crop, else the whole frame.
        guard let file = model.crop(of: message) ?? model.keyframe(of: thread) else { return }
        // Twice the thumbnail's size, for a sharp picture on a Retina display.
        thumbnail = await Self.thumbnail(of: file, side: Int(Self.thumbnailSize.width) * 2)
    }

    /// The picture at `file`, made small off the main actor.
    @concurrent
    nonisolated private static func thumbnail(of file: URL, side: Int) async -> CGImage? {
        ImageFiles.thumbnail(of: file, side: side)
    }
}

/// A message's state: its glyph and its name, in its colour. No capsule
/// behind it: the pin beside it already carries the colour, and the name
/// only has to be read.
struct StateChip: View {
    let state: MessageState
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
