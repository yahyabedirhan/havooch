import SwiftUI

/// No video is open: the native empty state, with "Open a Video" and "Try
/// the Demo" (D 5.11, L42). The whole stage takes a dropped video; a
/// dashed outline over it shows while a file is dragged over it. The demo
/// is the launch video bundled in the app, on demo data (`DemoRun`); a
/// build with no bundled demo leaves the button out.
struct EmptyState: View {
    let model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        ContentUnavailableView {
            // The cat mark in place of a symbol: the first screen is the
            // app's own.
            VStack(spacing: 14) {
                HavoochMark(size: 76)
                Text("Drop a Video Here")
            }
        } description: {
            Text("An mp4, mov or m4v file. Pause anywhere, or draw on the frame, and write to your agent.")
        } actions: {
            HStack(spacing: 10) {
                Button("Open a Video…") { model.openFromPanel() }
                    .filledButton(palette)
                    .keyboardShortcut(.defaultAction)
                if DemoRun.video() != nil {
                    Button("Try the Demo") { model.tryDemo() }
                        .help("Open the launch video on demo data, apart from your own reviews")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .videoDropTarget(model)
    }
}

/// The stage with no video takes a dropped video: the empty state and the
/// home screen alike. A dashed outline over it shows while a file is
/// dragged over it.
private struct VideoDropTarget: ViewModifier {
    let model: AppModel
    @State private var isTargeted = false
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .overlay { dropOutline }
            .animation(.smooth(duration: 0.15), value: isTargeted)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.openForPerson(url)
                return true
            } isTargeted: { isTargeted = $0 }
    }

    /// The drop target, over the stage while a file is over it.
    @ViewBuilder private var dropOutline: some View {
        if isTargeted {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette[.accent], style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .background(palette[.accent].opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(24)
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Takes a video dropped anywhere on this view, with the drop outline.
    func videoDropTarget(_ model: AppModel) -> some View {
        modifier(VideoDropTarget(model: model))
    }
}
