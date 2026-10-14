import SwiftUI

struct FloatingControls: ToolbarContent {
    let model: WindowModel
    let lease: AgentControlIcon
    let stopLease: () -> Void
    let isControlled: Bool

    var body: some ToolbarContent {
        ToolbarSpacer(.flexible)
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
