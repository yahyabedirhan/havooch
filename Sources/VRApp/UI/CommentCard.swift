import AppKit
import ImageIO
import SwiftUI
import VRReview

/// One comment in the sidebar: its time, its state, its picture, its text
/// and its thread. A click shows its moment. While it's queued it can be
/// edited in place or deleted. While the agent's question on it is open,
/// its edge is orange and it holds the answer box.
struct CommentCard: View {
    let comment: Comment
    /// The file of the crop of its region, else of its keyframe, or nil
    /// while it isn't on disk.
    let picture: URL?
    let isSelected: Bool
    /// Whether the agent's question on it waits for the person's answer.
    let hasOpenQuestion: Bool
    let show: () -> Void
    /// Replaces the text; false when it's refused.
    let edit: (String) -> Bool
    let delete: () -> Void
    /// Answers the open question; false when it's refused.
    let answer: (String) -> Bool

    @State private var editing: String?
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: Theme.glyph(for: comment.state))
                    .foregroundStyle(Theme.colour(for: comment.state))
                Text(TimeText.short(comment.time))
                    .font(Theme.timeFont)
                Text(Theme.label(for: comment.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if comment.region != nil {
                    Image(systemName: "rectangle.dashed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("On a region of the frame")
                }
                Spacer()
                if comment.state == .queued, editing == nil {
                    Button {
                        editing = comment.text
                        isEditorFocused = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help("Edit")
                    Button(role: .destructive, action: delete) {
                        Image(systemName: "trash")
                    }
                    .help("Delete")
                }
            }
            .buttonStyle(.borderless)

            HStack(alignment: .top, spacing: 8) {
                Thumbnail(file: picture)
                if let editing {
                    editor(editing)
                } else {
                    Text(comment.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            if !comment.thread.isEmpty {
                Divider()
                ThreadView(messages: comment.thread)
            }
            if hasOpenQuestion {
                AnswerBox(answer: answer)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(isSelected ? 0.9 : 0.4), in: RoundedRectangle(cornerRadius: Theme.cardCorner))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .strokeBorder(hasOpenQuestion ? Theme.question : isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCorner))
        .onTapGesture(perform: show)
    }

    private func editor(_ text: String) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextEditor(text: Binding(get: { editing ?? text }, set: { editing = $0 }))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(minHeight: 56)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .focused($isEditorFocused)
            HStack {
                Button("Cancel") { editing = nil }
                Button("Save") {
                    if edit(editing ?? text) { editing = nil }
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
    }
}

/// A comment's keyframe or crop, small. Read off the main actor and scaled down, so
/// a list of full-size frames stays light.
private struct Thumbnail: View {
    let file: URL?

    @State private var image: CGImage?

    nonisolated private static let width: CGFloat = 96
    nonisolated private static let height: CGFloat = 54

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(.black)
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(width: Self.width, height: Self.height)
        .task(id: file) {
            guard let file else {
                image = nil
                return
            }
            image = await Self.small(file)
        }
    }

    /// The image at `file` no larger than the thumbnail at 2x.
    nonisolated private static func small(_ file: URL) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: width * 2,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
