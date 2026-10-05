import SwiftUI
import VRReview

/// An agent message that just arrived, as the window announces it: on a
/// comment, or for a whole batch.
struct Notice: Equatable, Identifiable, Sendable {
    var id = UUID()
    var batch: BatchID
    /// The comment it is on; nil for a message about the whole batch.
    var comment: CommentID?
    /// That comment's time in the video.
    var time: Double?
    var kind: ThreadMessage.Kind
    var text: String

    /// How long a notice stays up.
    static let duration: Duration = .seconds(5)

    /// Who speaks and about what: `Agent asks · 0:10`, `Agent · Batch 1`.
    var title: String {
        let who = kind == .question ? "Agent asks" : "Agent"
        if let time { return "\(who) · \(TimeText.short(time))" }
        return "\(who) · Batch \(batch.number.map(String.init) ?? batch.rawValue)"
    }
}

/// The brief notice for an agent message: at the bottom right of the
/// frame, away from its centre, gone by itself after a few seconds. A
/// click goes to the comment it is about.
struct NoticeToast: View {
    let model: AppModel
    let notice: Notice

    private var asks: Bool { notice.kind == .question }

    var body: some View {
        Button {
            model.openNotice()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: asks ? "questionmark.bubble.fill" : "sparkles")
                    .font(.callout)
                    .foregroundStyle(asks ? Theme.honey : Color.secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(notice.title)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(notice.text)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 300, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.bubbleCorner))
            .overlay(RoundedRectangle(cornerRadius: Theme.bubbleCorner).strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: Theme.bubbleCorner))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: true)
        // Dark in both appearances: it lies over the frame and its black
        // surround, where a light material turns grey and hides its title.
        .environment(\.colorScheme, .dark)
        .help(notice.comment == nil ? "A message for the whole batch" : "Go to this comment")
        .accessibilityLabel("\(notice.title): \(notice.text)")
    }
}
