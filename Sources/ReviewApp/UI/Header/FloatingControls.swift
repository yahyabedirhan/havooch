import SwiftUI

/// proto-1's floating group at the top right of the window, from left to
/// right: the agent-control icon (only while an agent holds the lease),
/// Context, and the sidebar toggle. They are toolbar items, so the system
/// draws them as one floating group.
struct FloatingControls: ToolbarContent {
    let model: AppModel
    let lease: LeaseIndicator
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
                AgentControlButton(indicator: lease, stop: stopLease)
            }
            if model.video != nil {
                ContextButton(model: model)
                SidebarToggle(model: model)
            }
        }
    }
}

/// The sidebar toggle. The root view animates the column in and out with
/// proto-1's motion (`SidebarColumn.animation`), whatever opens it.
private struct SidebarToggle: View {
    let model: AppModel

    var body: some View {
        Button {
            model.isRailVisible.toggle()
        } label: {
            Label("Sidebar", systemImage: "sidebar.trailing")
        }
        .help(model.isRailVisible ? "Hide the sidebar" : "Show the sidebar")
    }
}
