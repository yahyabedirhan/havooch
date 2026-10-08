import SwiftUI

/// "Finish setup" on its own while setup isn't finished (H4, P11), then
/// the floating group at the top right of the window, from left to
/// right: the agent-control icon (only while an agent holds the lease),
/// Connect an Agent, "Open a Video…", Context, and the sidebar toggle;
/// the last four in the player only, since home has its own "Open a
/// Video…" and the Connect view is in the sidebar. They are toolbar items,
/// so the system draws them as one floating group.
struct FloatingControls: ToolbarContent {
    let model: WindowModel
    let lease: AgentControlIcon
    let stopLease: () -> Void
    /// Whether the agent-control icon shows: an agent holds the lease, and
    /// no screenshot leaves it out.
    let isControlled: Bool

    var body: some ToolbarContent {
        // Pushes the group to the trailing edge: beside the header's title,
        // primary actions would otherwise sit at the leading end.
        ToolbarSpacer(.flexible)
        // Separate from the connect button, in a capsule of its own.
        if model.showsFinishSetup {
            ToolbarItem(placement: .primaryAction) {
                FinishSetupButton(model: model)
            }
            ToolbarSpacer(.fixed)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if isControlled {
                AgentControlButton(model: model, indicator: lease, stop: stopLease)
            }
            if model.video != nil {
                ConnectButton(model: model)
                OpenVideoButton(model: model)
                ContextButton(model: model)
                SidebarToggle(model: model)
            }
        }
    }
}

/// Connect an Agent: opens the Connect view in the sidebar, and goes back
/// to the threads when it shows (G1). A dot shows while setup isn't fully
/// detected and no agent has ever connected (P11).
private struct ConnectButton: View {
    let model: WindowModel
    @Environment(\.palette) private var palette

    var body: some View {
        let isOpen = model.connect != nil && model.isSidebarVisible
        let dot = model.showsConnectDot
        Button {
            model.toggleConnect(.header)
        } label: {
            Label {
                Text("Connect an Agent")
            } icon: {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(isOpen ? palette[.accent] : palette[.textPrimary])
                    .overlay(alignment: .topTrailing) {
                        if dot {
                            Circle()
                                .fill(palette[.stateWorking])
                                .frame(width: 7, height: 7)
                                .offset(x: 3, y: -2)
                                .accessibilityHidden(true)
                        }
                    }
            }
        }
        .pressedByKeys(in: model) { model.toggleConnect(.header) }
        .help(isOpen ? "Back to the threads" : dot ? "Connect an agent: setup isn't finished" : "Connect an agent")
        .accessibilityValue(dot ? "Setup isn't finished" : "")
    }
}

/// "Finish setup" with the count of setup items left: opens the setup
/// tour over the stage, and closes it while it shows (H4). From
/// connect-flow V6's tour button.
private struct FinishSetupButton: View {
    let model: WindowModel
    @Environment(\.palette) private var palette

    var body: some View {
        let left = model.setupItemsLeft
        let isOpen = model.tour.isOpen
        Button {
            model.toggleTour()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                Text("Finish setup")
                    .font(.callout.weight(.medium))
                    .fixedSize()
                if left > 0 {
                    Text("\(left)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(palette[.textOnAccent])
                        .frame(minWidth: 16, minHeight: 16)
                        .background(palette[.stateWorking], in: Circle())
                }
            }
            .foregroundStyle(isOpen ? palette[.accent] : palette[.textPrimary])
            .padding(.horizontal, 4)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pressedByKeys(in: model) { model.toggleTour() }
        .help(isOpen ? "Close the setup tour" : "Take the setup tour")
        .accessibilityLabel("Finish setup")
        .accessibilityValue(left == 1 ? "1 item left" : "\(left) items left")
    }
}

/// The sidebar toggle. The root view animates the column in and out with
/// one spring (`SidebarColumn.animation`), whatever opens it.
private struct SidebarToggle: View {
    let model: WindowModel

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
    let model: WindowModel

    var body: some View {
        Button {
            model.openFromPanel()
        } label: {
            Label("Open a Video…", systemImage: "film")
        }
        .pressedByKeys(in: model) { model.openFromPanel() }
        .help("Open a Video…")
    }
}
