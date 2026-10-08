import LabHost
import SwiftUI

/// Step wizard: Welcome → Tools → Connect → Try it, with a progress
/// indicator, Back / Continue, and Skip on every step.
public let variant = LabVariant(window: LabWindow(titleVisibility: .hidden, titlebarAppearsTransparent: true)) { WizardView() }

private enum Step: Int, CaseIterable {
    case welcome, tools, connect, tryIt

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .tools: "Tools"
        case .connect: "Connect"
        case .tryIt: "Try It"
        }
    }
}

struct WizardView: View {
    @State private var setup = Setup()
    @State private var step: Step = .welcome

    var body: some View {
        Group {
            if setup.demoOpen {
                DemoOpened(setup: setup) { restart() }
            } else if setup.skipped {
                SkippedHome(setup: setup)
            } else {
                wizard
            }
        }
        .frame(width: 760, height: 540)
        .ignoresSafeArea()
        .background(Pal.window)
        .foregroundStyle(Pal.textPrimary)
        .tint(Pal.accent)
    }

    private func restart() {
        setup.reset()
        step = .welcome
    }

    private var wizard: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, 40)
                .padding(.horizontal, 120)
            Group {
                switch step {
                case .welcome: welcome
                case .tools: tools
                case .connect: connect
                case .tryIt: tryIt
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .transition(.opacity)
            Divider()
            footer
        }
        .animation(.smooth(duration: 0.2), value: step)
    }

    // MARK: Progress

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { s in
                let reached = s.rawValue <= step.rawValue
                VStack(spacing: 5) {
                    Capsule()
                        .fill(reached ? Pal.accent : Pal.hover)
                        .frame(height: 4)
                    HStack(spacing: 4) {
                        if isDone(s) {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Pal.done)
                        }
                        Text(s.title)
                            .font(.caption.weight(s == step ? .semibold : .regular))
                            .foregroundStyle(s == step ? Pal.textPrimary : Pal.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { step = s }
                .labID("progress-\(s.rawValue + 1)")
            }
        }
    }

    private func isDone(_ s: Step) -> Bool {
        switch s {
        case .welcome: step.rawValue > 0
        case .tools: setup.cliDone && setup.skillDone
        case .connect: setup.connected
        case .tryIt: false
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Skip Setup") { setup.skipped = true }
                .buttonStyle(.borderless)
                .foregroundStyle(Pal.textSecondary)
                .labID("skip")
            Spacer()
            Text(footerHint).font(.callout).foregroundStyle(Pal.textTertiary)
            if step != .welcome {
                Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                    .controlSize(.large)
                    .labID("back")
            }
            if step == .tryIt {
                Button("Open the Demo") { setup.demoOpen = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .labID("open-demo")
            } else {
                Button(nextTitle) { step = Step(rawValue: step.rawValue + 1) ?? .tryIt }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .labID("next")
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
    }

    private var nextTitle: String {
        switch step {
        case .welcome: "Get Started"
        case .tools: setup.cliDone && setup.skillDone ? "Continue" : "Continue Anyway"
        case .connect: setup.connected ? "Continue" : "Later"
        case .tryIt: "Continue"
        }
    }

    private var footerHint: String {
        switch step {
        case .welcome: "Takes about a minute"
        case .tools: setup.cliDone && setup.skillDone ? "" : "\(2 - [setup.cliDone, setup.skillDone].filter { $0 }.count) left"
        case .connect: setup.connected ? "" : "You can connect any time"
        case .tryIt: ""
        }
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            CatMark(size: 64)
            VStack(spacing: 6) {
                Text("Welcome to Havooch").font(.largeTitle.weight(.semibold))
                Text("Watch a video, pause where something's off, and tell your own coding agent.\nIt does the work in your repo and answers right here.")
                    .font(.title3)
                    .foregroundStyle(Pal.textSecondary)
                    .multilineTextAlignment(.center)
            }
            loopPicture.padding(.top, 6)
            HStack(spacing: 6) {
                Text("Havooch isn't an agent. It works with the one you use:")
                    .font(.callout).foregroundStyle(Pal.textSecondary)
                ForEach([Harness.claude, .codex, .cursor, .pi, .opencode]) { h in
                    HarnessLogo(harness: h, size: 16).help(h.name)
                }
                Text("…").foregroundStyle(Pal.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var loopPicture: some View {
        HStack(spacing: 0) {
            loopNode(title: "Pause and write", detail: "on any frame") {
                DemoFrame(region: true).frame(width: 96, height: 54).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            arrow("⌘↩")
            loopNode(title: "Your agent works", detail: "in your repo") {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Pal.letterbox).frame(width: 96, height: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("$ havooch wait").font(.system(size: 7.5, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                        Text("✓ editing Hero.swift").font(.system(size: 7.5, design: .monospaced)).foregroundStyle(Color(hex: 0x9CCBA8))
                    }
                }
            }
            arrow("reply")
            loopNode(title: "It answers here", detail: "beside the frame") {
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(Pal.bubblePerson).frame(width: 58, height: 12)
                    Capsule().fill(Pal.bubbleAgent).frame(width: 80, height: 12).frame(maxWidth: .infinity, alignment: .trailing)
                    Capsule().fill(Pal.bubbleAgent).frame(width: 52, height: 12).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(8)
                .frame(width: 96, height: 54)
                .background(Pal.well, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        .card()
    }

    private func loopNode<V: View>(title: String, detail: String, @ViewBuilder picture: () -> V) -> some View {
        VStack(spacing: 8) {
            picture()
            VStack(spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Pal.textSecondary)
            }
        }
        .frame(width: 130)
    }

    private func arrow(_ label: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(Pal.textTertiary)
            Image(systemName: "arrow.right").foregroundStyle(Pal.textTertiary)
        }
        .frame(width: 44)
        .offset(y: -14)
    }

    // MARK: Tools

    private var tools: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Give your agent two tools", "Havooch talks to your agent through a command and a skill. Both stay on this Mac.")
            HStack(alignment: .top, spacing: 14) {
                CLICard(setup: setup)
                SkillCard(setup: setup)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 22)
    }

    // MARK: Connect

    private var connect: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Connect your agent", "Pick where you work, then paste one line into a session in your project.")
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your agent").font(.callout.weight(.semibold)).foregroundStyle(Pal.textSecondary)
                    HarnessPicker(setup: setup)
                }
                .frame(width: 300)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste this in \(setup.harness.name)").font(.callout.weight(.semibold)).foregroundStyle(Pal.textSecondary)
                    CommandBox(text: setup.prompt, copyID: "copy-prompt", copied: setup.copied) { setup.copyPrompt() }
                    Text(setup.harness.whereToPaste)
                        .font(.caption).foregroundStyle(Pal.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ListenStatus(setup: setup).padding(.top, 4)
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lightbulb").foregroundStyle(Pal.control)
                        Text("Shortcut: tell your agent **open demo.mp4 with Havooch**. It opens the video and starts listening.")
                            .font(.caption).foregroundStyle(Pal.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 22)
    }

    // MARK: Try it

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Send your first message", setup.connected
                   ? "\(setup.harness.name) is listening in \(Setup.project). Try it on the demo video."
                   : "Try it on the demo video. What you send waits until an agent listens.")
            HStack(alignment: .top, spacing: 20) {
                ZStack(alignment: .bottom) {
                    DemoFrame(region: true)
                    HStack(spacing: 6) {
                        Text("Make the title bigger").font(.caption)
                        Spacer()
                        Text("⌘↩").font(.caption.weight(.semibold)).foregroundStyle(Pal.textSecondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .padding(10)
                }
                .frame(width: 330)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 14) {
                    instruction(1, "Pause", "Press Space where something is off.", key: "Space")
                    instruction(2, "Point and write", "Drag a box on the frame, or press C. Write what to change.", key: "C")
                    instruction(3, "Send", "Your messages go to \(setup.connected ? setup.harness.name : "your agent") at once. Its answer shows in the sidebar.", key: "⌘↩")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 22)
    }

    private func instruction(_ n: Int, _ title: String, _ detail: String, key: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.callout.weight(.bold))
                .foregroundStyle(Pal.textOnAccent)
                .frame(width: 22, height: 22)
                .background(Pal.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.body.weight(.semibold))
                    Text(key)
                        .font(.caption.weight(.semibold).monospaced())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Pal.hover, in: RoundedRectangle(cornerRadius: 4))
                }
                Text(detail).font(.callout).foregroundStyle(Pal.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title.weight(.semibold))
            Text(detail).font(.body).foregroundStyle(Pal.textSecondary)
        }
    }
}
