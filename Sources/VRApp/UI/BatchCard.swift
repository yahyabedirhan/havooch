import SwiftUI
import VRReview

/// One batch in the sidebar, as a header above the first of its comments:
/// its id, how many comments it took, where it is, and the thread of the
/// agent's messages for the full batch.
struct BatchCard: View {
    let batch: Batch
    let progress: Progress

    /// Where a batch is on its way: waiting for a listener, with one, or
    /// with every comment done or failed.
    enum Progress: String, Equatable {
        case pending, taken, finished

        var label: String {
            switch self {
            case .pending: "Waiting for a listener"
            case .taken: "With the agent"
            case .finished: "Finished"
            }
        }

        var glyph: String {
            switch self {
            case .pending: "tray"
            case .taken: "tray.and.arrow.up"
            case .finished: "checkmark.seal"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: progress.glyph)
                    .foregroundStyle(.secondary)
                Text("Batch \(batch.id)")
                    .font(.callout.weight(.semibold))
                Text("\(batch.commentIDs.count) comment\(batch.commentIDs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(progress.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !batch.thread.isEmpty {
                ThreadView(messages: batch.thread)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
