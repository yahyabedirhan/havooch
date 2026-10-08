import ReviewSetup
import SwiftUI

/// Step 1, the `havooch` command line (G3): Link puts it in
/// `~/.local/bin`, and done reads "Linked". A failed link shows the line
/// to run in a terminal. Only a detected link counts (ADR 0005).
struct CommandLineStep: View {
    let model: any SetupSteering
    let open: Bool
    let toggle: () -> Void
    @Environment(\.palette) private var palette

    private var setup: SetupDesk { model.setup }

    var body: some View {
        let linked = setup.isLinked
        let failure = linked ? nil : setup.linkFailure
        let (look, status, colour): (StepLook, String, Color) =
            if linked { (.done, "Linked", palette[.stateDone]) }
            else if failure != nil { (.failed, "Couldn't link", palette[.stateFailed]) }
            else { (.active, "Not linked", palette[.textTertiary]) }
        Step(number: 1, title: .commandLine, look: look, status: status, statusColor: colour, open: open, toggle: toggle) {
            if linked {
                Text("havooch → \(Self.home(setup.report.commandLine.path))")
                    .font(.caption.monospaced())
                    .foregroundStyle(palette[.textSecondary])
                StepNote(text: "If your agent can't find havooch, add ~/.local/bin to its PATH.")
            } else if let failure {
                StepDetail(text: "Havooch couldn't link it: \(failure.reason). Run this in a terminal:")
                CopyBox(text: failure.fallback)
                Button("Try Again") { model.linkCommandLine() }
                    .controlSize(.small)
                    .pressedByKeys(in: model.keysWindow) { model.linkCommandLine() }
            } else {
                StepDetail(text: "Agents control Havooch through the havooch command. Link puts it in ~/.local/bin.")
                Button("Link") { model.linkCommandLine() }
                    .filledButton(palette)
                    .controlSize(.small)
                    .pressedByKeys(in: model.keysWindow) { model.linkCommandLine() }
            }
        }
    }

    /// `path` with the home folder written `~`.
    static func home(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// Step 2, the `/havooch-mate` skill (G4): a row per harness with what is
/// detected, the install command for every harness found without it in a
/// `RunBox` with Run Command, its live log and Cancel, and the command for
/// one repository. A ✓ only for what is detected; anything else is a
/// neutral "Not detected" (G9).
struct SkillStep: View {
    let model: any SetupSteering
    let open: Bool
    var isLast = false
    let toggle: () -> Void
    /// Whether the command for one repository shows.
    @State private var repoOpen = false
    @Environment(\.palette) private var palette

    private var setup: SetupDesk { model.setup }
    private var lacking: [Harness] { setup.report.harnessesLackingSkill }
    private var isRunning: Bool { setup.install?.state == .running }

    var body: some View {
        let done = setup.isSkillDetected
        let status = done ? "Installed" : isRunning ? "Installing…" : lacking.isEmpty ? "Not detected" : "\(lacking.count) not detected"
        Step(
            number: 2, title: .skill, look: done ? .done : setup.isLinked ? .active : .todo, status: status,
            statusColor: done ? palette[.stateDone] : palette[.textSecondary], isLast: isLast, gap: 6, open: open, toggle: toggle
        ) {
            StepDetail(text: "Teaches your agent to listen and answer in the player.")
            harnessRows
            if !done { action }
            StepNote(text: "Havooch checks each agent's user skills folder. A skill installed in a repo isn't detected, and still works there.")
        }
    }

    private var harnessRows: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(setup.report.harnesses, id: \.harness.installName) { entry in
                let found = entry.presence == .detected
                HStack(spacing: 7) {
                    AgentMark(agent: entry.harness.agent, size: 14).opacity(found ? 1 : 0.45)
                    Text(entry.harness.name)
                        .font(.caption)
                        .foregroundStyle(found ? palette[.textPrimary] : palette[.textSecondary])
                    Spacer(minLength: 4)
                    DetectionWord(detected: entry.skill == .detected, word: "Installed")
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var action: some View {
        let install = setup.install
        if install?.state == .noNode {
            Text("npx isn't on your PATH").font(.caption.weight(.semibold)).foregroundStyle(palette[.textPrimary])
            StepDetail(text: "Installing the skill needs Node. Install Node from nodejs.org, or run this where npx works:")
            CopyBox(text: SkillInstall(for: install?.install.harnesses ?? lacking).commandLine)
            Button("Check Again") { model.installSkill(for: install?.install.harnesses ?? lacking) }
                .controlSize(.small)
                .pressedByKeys(in: model.keysWindow) { model.installSkill(for: install?.install.harnesses ?? lacking) }
        } else {
            if let install, install.state == .cancelled { StepNote(text: "Cancelled.") }
            if let install, install.state == .failed {
                StepNote(text: "The install stopped with exit status \(install.exitStatus.map(String.init) ?? "unknown")"
                    + (install.log.last.map { ": \($0)" } ?? "."))
            }
            // While it runs, the box shows the install that runs; else the one Run Command starts.
            let harnesses = isRunning ? install?.install.harnesses ?? lacking : lacking
            if !harnesses.isEmpty {
                StepDetail(text: "Run Command installs it for \(Self.list(harnesses.map(\.name))) in your login shell:")
                RunBox(
                    text: SkillInstall(for: harnesses).commandLine, running: isRunning, log: install?.log.last ?? "",
                    keysWindow: model.keysWindow, run: { model.installSkill(for: lacking) },
                    cancel: { model.cancelSkillInstall() }
                )
            }
            if !isRunning {
                Button(repoOpen ? "Hide repo command" : "In one repo…") { repoOpen.toggle() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(palette[.accent])
                if repoOpen {
                    StepDetail(text: "Run this in your repo's folder. Only agents working there get the skill.")
                    CopyBox(text: SkillInstall(for: lacking).repositoryCommandLine)
                }
            }
        }
    }

    /// "Codex", "Codex and Pi", "Claude Code, Codex and Pi".
    static func list(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
    }
}

/// A check and a word for what is detected, else a neutral "Not detected"
/// with an open circle: never a cross (G9).
struct DetectionWord: View {
    let detected: Bool
    let word: String
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: detected ? "checkmark" : "circle.dashed").font(.system(size: 9, weight: .bold))
            Text(detected ? word : "Not detected")
        }
        .font(.caption)
        .foregroundStyle(detected ? palette[.stateDone] : palette[.textTertiary])
    }
}

/// While an agent listens, the setup steps folded to one line (G7): "Set
/// up" with a check, or an open circle, for each step. A click shows them.
struct SetupLine: View {
    let setup: SetupDesk
    @Binding var open: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        let done = setup.isDetected
        Button { open.toggle() } label: {
            HStack(spacing: 10) {
                ZStack {
                    if done {
                        Circle().fill(palette[.stateDone])
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(palette[.textOnAccent])
                    } else {
                        Circle().strokeBorder(palette[.track], lineWidth: 1.5)
                    }
                }
                .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Set up").font(.callout.weight(.semibold)).foregroundStyle(palette[.textPrimary])
                        Spacer(minLength: 6)
                        Text(done ? "Done" : !setup.isLinked ? "Not linked" : "Skill not detected")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(done ? palette[.stateDone] : palette[.textSecondary])
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette[.textTertiary])
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                    HStack(spacing: 12) {
                        check(setup.isLinked, .commandLine)
                        check(setup.isSkillDetected, .skill)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(open ? "Fold the setup steps" : "Show the setup steps")
    }

    private func check(_ done: Bool, _ label: CodeLabel) -> some View {
        HStack(spacing: 4) {
            Image(systemName: done ? "checkmark" : "circle.dashed")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(done ? palette[.stateDone] : palette[.textTertiary])
            label.font(.caption).foregroundStyle(palette[.textSecondary])
        }
        .fixedSize()
    }
}
