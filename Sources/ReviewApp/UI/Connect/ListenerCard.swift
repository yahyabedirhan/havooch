import ReviewCore
import SwiftUI

/// The listener card: the agent's logo and harness, where it runs
/// and since when, Copy Path, Disconnect, and the prompt that makes it
/// listen again later. After a relaunch, while the agent the last run had
/// hasn't come back yet: "Reconnecting to <harness>…" for about 30 s, with
/// Forget.
struct ListenerCard: View {
    let model: WindowModel
    let phase: ListenerQueue.Phase
    /// The time the card is drawn at, for the countdown.
    let time: Date

    @State private var copiedPath = false
    @Environment(\.palette) private var palette

    init(model: WindowModel, phase: ListenerQueue.Phase, at time: Date) {
        self.model = model
        self.phase = phase
        self.time = time
    }

    var body: some View {
        switch phase {
        case .none:
            EmptyView()
        case .connected(let session):
            card(session, until: nil)
        case .reconnecting(let session, let until):
            card(session, until: until)
        }
    }

    private func card(_ session: ListenerSession, until: Date?) -> some View {
        let reconnecting = until != nil
        let harness = WindowModel.harness(of: session)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Group {
                    if let agent = session.agent {
                        AgentMark(agent: agent, size: 24)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 16))
                            .foregroundStyle(palette[.textSecondary])
                            .frame(width: 24, height: 24)
                    }
                }
                .saturation(reconnecting ? 0 : 1)
                .opacity(reconnecting ? 0.6 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.name).font(.callout.weight(.semibold)).foregroundStyle(palette[.textPrimary])
                    HStack(spacing: 5) {
                        Circle().fill(reconnecting ? palette[.stateWorking] : palette[.stateDone]).frame(width: 6, height: 6)
                        Text(reconnecting ? "Havooch relaunched" : "Listening to \(model.video?.url.lastPathComponent ?? "this video")")
                            .font(.caption)
                            .foregroundStyle(palette[.textSecondary])
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if reconnecting {
                    Button("Forget") { _ = try? model.forgetAgent() }
                        .controlSize(.small)
                        .pressedByKeys(in: model) { _ = try? model.forgetAgent() }
                        .help("Stop waiting for \(session.name), to connect another agent")
                } else {
                    Button("Disconnect") { _ = try? model.disconnectAgent() }
                        .controlSize(.small)
                        .foregroundStyle(palette[.stateFailed])
                        .pressedByKeys(in: model) { _ = try? model.disconnectAgent() }
                        .help("Let \(session.name) go: it stops listening to this video")
                }
            }
            if let until {
                let left = max(0, Int(until.timeIntervalSince(time).rounded(.up)))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Reconnecting to \(session.name)… \(left) s")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette[.textPrimary])
                    ProgressView(value: Double(left), total: ListenerQueue.reconnectSeconds)
                        .tint(palette[.stateWorking])
                        .controlSize(.mini)
                    StepNote(text: "It picks up again on its next havooch wait. Forget it to connect another agent.")
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Where").font(.caption).foregroundStyle(palette[.textTertiary])
                    HStack(spacing: 6) {
                        Text(session.place)
                            .font(.caption.monospaced())
                            .foregroundStyle(palette[.textPrimary])
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(session.place)
                        Spacer(minLength: 4)
                        Button(copiedPath ? "Copied" : "Copy Path") { copyPath(session.place) }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(copiedPath ? palette[.stateDone] : palette[.accent])
                    }
                }
                if let since = session.since {
                    GridRow {
                        Text("Since").font(.caption).foregroundStyle(palette[.textTertiary])
                        Text(since.formatted(date: .omitted, time: .shortened))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette[.textPrimary])
                    }
                }
            }
            StepNote(text: "A new agent that listens replaces \(session.name).")
            if let harness, let prompt = model.prompt(for: harness) {
                StepDetail(text: "To listen again later, paste this in \(harness.name):")
                CopyBox(text: prompt, kind: .prompt)
            }
        }
    }

    private func copyPath(_ path: String) {
        CopyBox.copy(path)
        copiedPath = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            copiedPath = false
        }
    }
}
