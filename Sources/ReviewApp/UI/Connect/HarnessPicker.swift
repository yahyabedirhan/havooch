import ReviewSetup
import SwiftUI

struct AgentStep: View {
    let model: WindowModel
    let isActive: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        Step(
            number: 3, title: .agent, look: isActive ? .active : .todo, status: "Not listening",
            statusColor: palette[.textTertiary], isLast: true, open: true
        ) {
            HarnessPicker(model: model)
            HarnessReadiness(model: model, harness: model.steppedHarness)
            HStack(spacing: 5) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash").symbolRenderingMode(.hierarchical)
                Text("No agent is listening. It shows here once it does.")
            }
            .font(.caption)
            .foregroundStyle(palette[.textTertiary])
        }
    }
}

struct HarnessPicker: View {
    let model: any SetupSteering
    @Environment(\.palette) private var palette

    var body: some View {
        let picked = model.steppedHarness
        HStack(spacing: 2) {
            ForEach(model.setup.report.harnesses, id: \.harness.installName) { entry in
                let harness = entry.harness
                let selected = harness == picked
                let found = entry.presence == .detected
                Button { model.pick(harness) } label: {
                    VStack(spacing: 3) {
                        AgentMark(agent: harness.agent, size: 18).opacity(found ? 1 : 0.5)
                        Text(Self.short(harness))
                            .font(.system(size: 10, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? palette[.textPrimary] : palette[.textSecondary])
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(selected ? palette[.accent].opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pressedByKeys(in: model.keysWindow) { model.pick(harness) }
                .help(found ? harness.name : "\(harness.name): not detected on this Mac")
                .accessibilityLabel(harness.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    static func short(_ harness: Harness) -> String {
        harness.agent == .claude ? "Claude" : harness.name
    }
}

struct HarnessReadiness: View {
    let model: any SetupSteering
    let harness: Harness
    @Environment(\.palette) private var palette

    var body: some View {
        let prompt = model.pastePrompt(for: harness) ?? ""
        switch model.setup.readiness(of: harness) {
        case .ready:
            line("checkmark.circle.fill", palette[.stateDone], "Ready. The skill is installed for \(harness.name).")
            StepDetail(text: "Paste this in \(harness.name), in your project, to start a session that listens:")
            CopyBox(text: prompt, kind: .prompt)
        case .skillNotDetected:
            line("questionmark.circle", palette[.textSecondary], "Havooch couldn't detect the skill for \(harness.name).")
            StepDetail(text: "If it's installed another way, paste the prompt and your agent will take it from there. If not, install it first:")
            let install = model.setup.install
            let running = install?.state == .running
            let mine = running && install?.install.harnesses.contains(harness) == true
            RunBox(
                text: SkillInstall(for: [harness]).commandLine, running: mine, log: install?.log.last ?? "",
                canRun: !running, keysWindow: model.keysWindow, run: { model.installSkill(for: [harness]) }
            )
            pastePrompt(prompt)
        case .harnessNotDetected:
            line("questionmark.circle", palette[.textSecondary], "Havooch couldn't detect \(harness.name) on this Mac.")
            StepDetail(text: "If it's installed another way, paste the prompt and your agent will take it from there. If not, install the skill for \(harness.name) first:")
            CopyBox(text: SkillInstall(for: [harness]).commandLine)
            pastePrompt(prompt)
        }
    }

    private func line(_ symbol: String, _ colour: Color, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(colour)
            Text(text)
                .font(.callout.weight(.medium))
                .foregroundStyle(palette[.textPrimary])
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func pastePrompt(_ prompt: String) -> some View {
        StepDetail(text: "Paste this in \(harness.name), in your project:")
        CopyBox(text: prompt, kind: .prompt)
    }
}
