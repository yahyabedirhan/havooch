import Foundation
import VRReview

/// A brief word that the agent wrote something: shown over the stage for a
/// few seconds, one per agent message. It names the comment the message is
/// on, or the batch for a message about the full batch.
struct Notice: Identifiable, Equatable {
    let id: UUID
    /// The comment the message is on; nil for a message for a full batch.
    var commentID: String?
    /// The comment's time in its video, when the message is on a comment.
    var time: Double?
    var batchID: String
    var message: ThreadMessage

    /// How long a notice stays, in seconds.
    static let lifetime: Duration = .seconds(5)
    /// How many notices show at once: the newest ones.
    static let shown = 3

    /// The line above the text: `Agent asks · 0:10`, `Agent · 0:10`, or
    /// `Agent · batch b1`.
    var title: String {
        let who = message.kind == .question ? "Agent asks" : "Agent"
        guard let time else { return "\(who) · batch \(batchID)" }
        return "\(who) · \(TimeText.short(time))"
    }
}
