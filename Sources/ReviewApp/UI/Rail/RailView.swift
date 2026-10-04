import SwiftUI

/// The rail beside the stage: the queue of comments, then the send bar.
struct RailView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            VStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)
                Text("No comments yet")
                    .font(.headline)
                Text("Comments on this video queue here, then go to your agent as one batch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            SendBar()
        }
    }
}
