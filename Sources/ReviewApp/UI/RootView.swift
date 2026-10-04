import ReviewWire
import SwiftUI

/// The window: the stage with the timeline lane under it, and the rail at
/// the side. With no video, a place to open one.
struct RootView: View {
    @Bindable var model: AppModel
    /// The lease as the banner draws it, and the banner's Stop.
    let lease: LeaseIndicator
    let stopLease: () -> Void

    var body: some View {
        Group {
            if model.video == nil {
                EmptyState(model: model)
            } else {
                VStack(spacing: 0) {
                    StageView(model: model)
                    TimelineLane(model: model)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .safeAreaInset(edge: .top, spacing: 0) {
            LeaseBannerView(indicator: lease, stop: stopLease)
        }
        .inspector(isPresented: railShown) {
            RailView(model: model)
                .inspectorColumnWidth(
                    min: Theme.railWidthRange.lowerBound, ideal: Theme.railWidth, max: Theme.railWidthRange.upperBound
                )
        }
        .navigationTitle(model.video?.title ?? AppIdentity.appName)
        .navigationSubtitle(model.video.map { Self.folder(of: $0.url) } ?? "")
        .toolbar {
            if model.isDemo {
                ToolbarItem(placement: .primaryAction) { DemoChip() }
                    .sharedBackgroundVisibility(.hidden)
            }
            if model.video != nil {
                ToolbarItem(placement: .primaryAction) { ContextButton(model: model) }
                ToolbarItem(placement: .primaryAction) { TranscriptChipView(model: model) }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.isRailVisible.toggle()
                    } label: {
                        Label("Comments", systemImage: "sidebar.trailing")
                    }
                    .help(model.isRailVisible ? "Hide the comments" : "Show the comments")
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.openForPerson(url)
            return true
        }
        .alert(model.problem?.title ?? "", isPresented: hasProblem) {
            Button("OK") {}
        } message: {
            Text(model.problem?.reason ?? "")
        }
    }

    /// The rail shows beside a video only.
    private var railShown: Binding<Bool> {
        Binding(
            get: { model.video != nil && model.isRailVisible },
            set: { model.isRailVisible = $0 }
        )
    }

    private var hasProblem: Binding<Bool> {
        Binding(
            get: { model.problem != nil },
            set: { if !$0 { model.problem = nil } }
        )
    }

    /// The folder `url` is in, with the home folder as `~`.
    private static func folder(of url: URL) -> String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }
}

/// Tells a demo run from the person's own data.
private struct DemoChip: View {
    var body: some View {
        Text("Demo data")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.orange.opacity(0.16), in: Capsule())
            .help("This run uses a demo folder, not your own reviews")
    }
}
