import SwiftUI

/// The foot of the rail: whether an agent listens, and the Send button.
/// With nothing queued there is nothing to send.
struct SendBar: View {
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.tertiary)
                        .frame(width: 7, height: 7)
                    Text("No agent listening")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.6), in: Capsule())
                Spacer()
                Button {} label: {
                    HStack(spacing: 6) {
                        Text("Send")
                        Text("⌘↩")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(true)
                .help("Nothing is queued")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
}
