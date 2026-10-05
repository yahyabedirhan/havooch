import SwiftUI
import VRReview

/// The head of one batch's group: its number, when it was sent, and where
/// it stands, from waiting for a listener to finished.
struct BatchHeader: View {
    let batch: Batch
    /// The batch's comments.
    let comments: [Comment]
    let standing: ListenerLedger.Standing

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Batch \(batch.id.number.map(String.init) ?? batch.id.rawValue)")
                    .font(.headline)
                Spacer()
                Text(batch.sentAt, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Label(Self.words(standing, comments: comments), systemImage: Self.symbol(standing))
                .font(.caption)
                .foregroundStyle(standing == .pending ? AnyShapeStyle(Theme.apricot) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    /// Where the batch stands, in words: `Waiting for a listener`,
    /// `Delivered to the listener`, `Acknowledged · 1 of 2 finished`,
    /// `Finished · 1 done, 1 failed`.
    static func words(_ standing: ListenerLedger.Standing, comments: [Comment]) -> String {
        let done = comments.count { $0.state == .done }
        let failed = comments.count { $0.state == .failed }
        switch standing {
        case .pending:
            return "Waiting for a listener"
        case .taken:
            guard !comments.contains(where: { $0.state == .sent }) else { return "Delivered to the listener" }
            return done + failed == 0 ? "Acknowledged" : "Acknowledged · \(done + failed) of \(comments.count) finished"
        case .finished:
            let parts = [done > 0 ? "\(done) done" : nil, failed > 0 ? "\(failed) failed" : nil].compactMap { $0 }
            return parts.isEmpty ? "Finished" : "Finished · " + parts.joined(separator: ", ")
        }
    }

    private static func symbol(_ standing: ListenerLedger.Standing) -> String {
        switch standing {
        case .pending: "hourglass"
        case .taken: "checkmark.circle"
        case .finished: "checkmark.circle.fill"
        }
    }
}

/// The agent's messages for a whole batch, at the head of the batch's
/// group, above the comments they are about: chat bubbles under a small
/// label, with no box around them.
struct BatchCard: View {
    let batch: Batch

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("For the whole batch", systemImage: "tray.full")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(batch.thread.enumerated()), id: \.offset) { _, message in
                MessageRow(message: message)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Messages for the whole batch")
    }
}
