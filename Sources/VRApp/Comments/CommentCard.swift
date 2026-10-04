import ImageIO
import SwiftUI
import VRReview

/// One comment in the sidebar: its keyframe, its state, its time and its
/// text. A click goes to its moment. A queued comment is edited in place
/// (a double click or the pencil; Return keeps the new text, Escape the
/// old) and deleted with the bin.
struct CommentCard: View {
    let model: AppModel
    let comment: Comment
    let keyframe: URL

    @State private var editing = false
    @State private var edited = ""
    @State private var hovering = false
    @FocusState private var focused: Bool

    private var selected: Bool { model.selection == comment.id }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Keyframe(file: keyframe)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    StatusMark(state: comment.state, size: 10)
                    Text(TimeText.short(comment.time))
                        .font(.callout.weight(.semibold).monospacedDigit())
                    Spacer(minLength: 0)
                    if comment.state == .queued, !editing {
                        Group {
                            Button(action: edit) { Image(systemName: "pencil") }
                                .help("Edit")
                                .accessibilityLabel("Edit")
                            Button {
                                model.attempt { () throws(ActionError) in try model.deleteComment(comment.id) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .help("Delete")
                            .accessibilityLabel("Delete")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        // Always there for the layout and for accessibility; seen on the card in use.
                        .opacity(hovering || selected ? 1 : 0)
                    }
                }
                if editing {
                    TextField("Comment", text: $edited, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...8)
                        .focused($focused)
                        .onSubmit(keep)
                        .onExitCommand { editing = false }
                } else {
                    Text(comment.text)
                        .font(.callout)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(8)
        .background(
            selected ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(hovering ? 1 : 0.5)),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            if selected { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.6)) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.select(comment.id) }
        .simultaneousGesture(TapGesture(count: 2).onEnded(edit))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comment at \(TimeText.short(comment.time))")
    }

    private func edit() {
        guard comment.state == .queued, !editing else { return }
        edited = comment.text
        editing = true
        focused = true
    }

    /// Return in the edit field: keeps the new text when the review takes it.
    private func keep() {
        if model.attempt({ () throws(ActionError) in try model.editComment(comment.id, text: edited) }) != nil {
            editing = false
        }
    }
}

/// A comment's keyframe, small, read from its PNG file.
private struct Keyframe: View {
    let file: URL
    @State private var image: CGImage?

    private static let size = CGSize(width: 72, height: 40.5)

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: file) { image = await Self.small(file) }
    }

    /// The PNG at `file`, no larger than the card shows it on a Retina display.
    nonisolated private static func small(_ file: URL) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 216,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
