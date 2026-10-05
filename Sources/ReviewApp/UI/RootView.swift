import ReviewWire
import SwiftUI

/// The window: the stage with the timeline lane under it, and the rail at
/// the side. With no video, a place to open one.
struct RootView: View {
    @Bindable var model: AppModel
    /// The lease as the toolbar's agent-control sign draws it, and its Stop.
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
        .inspector(isPresented: railShown) {
            RailView(model: model)
                .inspectorColumnWidth(
                    min: Theme.railWidthRange.lowerBound, ideal: Theme.railWidth, max: Theme.railWidthRange.upperBound
                )
        }
        // The soft slate blue in place of the system's bright one, for the
        // scrubber, a selection and a prominent button.
        .tint(Theme.accent)
        .navigationTitle(model.video?.title ?? AppIdentity.appName)
        .navigationSubtitle(subtitle)
        .toolbar {
            // One group of icon buttons at the trailing edge: the agent's
            // sign while it holds the lease, then Context, then the rail.
            if isControlled || model.video != nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    if isControlled {
                        AgentControlButton(indicator: lease, stop: stopLease)
                    }
                    if model.video != nil {
                        ContextButton(model: model)
                        Button {
                            model.isRailVisible.toggle()
                        } label: {
                            Label("Comments", systemImage: "sidebar.trailing")
                        }
                        .help(model.isRailVisible ? "Hide the comments" : "Show the comments")
                    }
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

    /// Whether an agent's sign is in the toolbar: while it holds the lease,
    /// unless a screenshot leaves the sign out.
    private var isControlled: Bool {
        lease.shown(at: Date()) != nil
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

    /// Under the title: that this is a demo run, and the video's folder.
    private var subtitle: String {
        ([model.isDemo ? "Demo" : nil] + [model.video.map { Self.folder(of: $0.url) }])
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    /// The folder `url` is in, with the home folder as `~`.
    private static func folder(of url: URL) -> String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }
}
