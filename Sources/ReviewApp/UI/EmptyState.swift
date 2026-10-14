import SwiftUI

struct EmptyState: View {
    let model: WindowModel
    @Environment(\.palette) private var palette

    var body: some View {
        ContentUnavailableView {
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

private struct VideoDropTarget: ViewModifier {
    let model: WindowModel
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
    func videoDropTarget(_ model: WindowModel) -> some View {
        modifier(VideoDropTarget(model: model))
    }
}
