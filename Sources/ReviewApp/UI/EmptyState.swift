import SwiftUI

/// No video is open: a drop target, "Open a video" and "Try the demo"
/// (D 5.11). The demo is the sample video bundled in the app, on demo data
/// (`DemoRun`); a build with no bundled demo leaves the button out.
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
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Drop a video here")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(palette[.textPrimary])
                Text("An mp4, mov or m4v file. Pause anywhere, or draw on the frame, and write to your agent.")
                    .foregroundStyle(palette[.textSecondary])
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button("Open a video") { model.openFromPanel() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                if DemoRun.video() != nil {
                    Button("Try the demo") { model.tryDemo() }
                        .buttonStyle(.bordered)
                        .help("Open the sample video on demo data, apart from your own reviews")
                }
            }
            .controlSize(.large)
        }
        .padding(32)
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
