import SwiftUI
import VRWire

/// The window: once a video is open, the stage with the transport bar under
/// it and the review sidebar beside them; the empty state before. A video
/// file dropped anywhere opens.
struct MainWindow: View {
    let model: ReviewModel
    let controller: PlayerController

    var body: some View {
        Group {
            if model.video != nil {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Stage(controller: controller, model: model)
                        Divider()
                        TransportBar(model: model)
                    }
                    Divider()
                    Sidebar(model: model)
                }
            } else {
                EmptyState(demoFolder: model.demoFolder) { model.openByPerson($0) }
            }
        }
        .frame(minWidth: 820, minHeight: 420)
        .navigationTitle(model.video?.info.title ?? AppIdentity.name)
        .navigationSubtitle(model.demoFolder == nil ? "" : "Demo")
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.openByPerson(url)
            return true
        }
        .alert(
            "The video didn't open",
            isPresented: Binding(get: { model.openFailure != nil }, set: { if !$0 { model.openFailure = nil } })
        ) {
            Button("OK") { model.openFailure = nil }
        } message: {
            Text(model.openFailure ?? "")
        }
    }
}
