import SwiftUI

/// The floating group at the top right of the window, from left to
/// right: the agent-control icon (only while an agent holds the lease),
/// "Open a Video…", Context, and the sidebar toggle; the last three in
/// the player only, since home has its own "Open a Video…". They are toolbar items, so the system
/// draws them as one floating group.
struct FloatingControls: ToolbarContent {
    let model: AppModel
    let lease: AgentControlIcon
    let stopLease: () -> Void
    /// Whether the agent-control icon shows: an agent holds the lease, and
    /// no screenshot leaves it out.
    let isControlled: Bool

    var body: some ToolbarContent {
        // Pushes the group to the trailing edge: beside the header's title,
        // primary actions would otherwise sit at the leading end.
        ToolbarSpacer(.flexible)
        ToolbarItemGroup(placement: .primaryAction) {
            if isControlled {
                AgentControlButton(model: model, indicator: lease, stop: stopLease)
            }
            if model.video != nil {
                OpenVideoButton(model: model)
                ContextButton(model: model)
                SidebarToggle(model: model)
            }
        }
    }
}

/// The sidebar toggle. The root view animates the column in and out with
/// one spring (`SidebarColumn.animation`), whatever opens it.
private struct SidebarToggle: View {
    let model: AppModel

    var body: some View {
        Button {
            model.isSidebarVisible.toggle()
        } label: {
            Label("Sidebar", systemImage: "sidebar.trailing")
        }
        .pressedByKeys(in: model) { model.isSidebarVisible.toggle() }
        .help(model.isSidebarVisible ? "Hide the sidebar" : "Show the sidebar")
    }
}

/// "Open a Video…" in the header: the Open panel, without going home
/// first. On an in-app demo the video opens on the person's data.
private struct OpenVideoButton: View {
    let model: AppModel

    var body: some View {
        Button {
            model.openFromPanel()
        } label: {
            Label("Open a Video…", systemImage: "folder")
        }
        .pressedByKeys(in: model) { model.openFromPanel() }
        .help("Open a Video…")
    }
}
