import SwiftUI

/// No video is open: a drop target and the Open button.
struct EmptyState: View {
    let model: AppModel
    @State private var isTargeted = false
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(palette[.accent])
                .frame(width: 92, height: 92)
                .background(palette[.accent].opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(spacing: 6) {
                Text("Open a video to review")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(palette[.textPrimary])
                Text("Drop an mp4, mov or m4v file here, or choose one.")
                    .foregroundStyle(palette[.textSecondary])
            }
            Button("Open a Video…") { model.openFromPanel() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isTargeted ? palette[.accent] : palette[.separator],
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [7, 6])
                )
                .background(
                    isTargeted ? palette[.accent].opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
        .animation(.smooth(duration: 0.15), value: isTargeted)
        .padding(24)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.openForPerson(url)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}
