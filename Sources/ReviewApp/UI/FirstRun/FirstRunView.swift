import ReviewCore
import ReviewSetup
import SwiftUI

/// The first-run window's content (H1), from first-run V1 "Step wizard
/// (first launch)" (`docs/prototypes/2026-10-08-lab/agent-onboarding/
/// first-run-V1/`): a progress bar of four steps, Welcome, Tools, Connect
/// and Try it, then Skip Setup, Back and the next step in a footer. Tools
/// and Connect show the Connect view's own steps (`CommandLineStep`,
/// `SkillStep`, `HarnessPicker`, `HarnessReadiness`) on the first run's
/// model, whose prompt is the demo prompt (H2). Nothing waits on the
/// person: each step can be passed with nothing done.
struct FirstRunView: View {
    let app: AppModel

    /// The window's size, as first-run V1 draws it.
    static let size = CGSize(width: 760, height: 540)

    private var firstRun: FirstRun { app.firstRun }
    private var setup: SetupDesk { app.setup }

    var body: some View {
        let palette = Palette(theme: app.themes.theme)
        VStack(spacing: 0) {
            FirstRunProgress(firstRun: firstRun, isDone: isDone)
                .padding(.top, 40)
                .padding(.horizontal, 120)
            Group {
                switch firstRun.step {
                case .welcome: FirstRunWelcome()
                case .tools: FirstRunTools(firstRun: firstRun)
                case .connect: FirstRunConnect(firstRun: firstRun, agentConnected: app.agentConnectedOnce)
                case .tryIt: FirstRunTryIt(agentConnected: app.agentConnectedOnce)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .transition(.opacity)
            Hairline(axis: .horizontal)
            footer
        }
        .animation(.smooth(duration: 0.2), value: firstRun.step)
        .frame(width: Self.size.width, height: Self.size.height)
        .ignoresSafeArea()
        .background(palette[.window])
        .foregroundStyle(palette[.textPrimary])
        .tint(palette[.accent])
        .preferredColorScheme(RootView.scheme(of: app.themes))
        .environment(\.palette, palette)
    }

    /// Whether a step's work is done, for its check on the progress bar.
    private func isDone(_ step: FirstRunStep) -> Bool {
        switch step {
        case .welcome: firstRun.step.index > 0
        case .tools: setup.isDetected
        case .connect: app.agentConnectedOnce
        case .tryIt: false
        }
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        FirstRunFooter(app: app, nextTitle: nextTitle, hint: hint)
    }

    private var nextTitle: String {
        switch firstRun.step {
        case .welcome: "Get Started"
        case .tools: setup.isDetected ? "Continue" : "Continue Anyway"
        case .connect: app.agentConnectedOnce ? "Continue" : "Later"
        case .tryIt: "Open the Demo"
        }
    }

    private var hint: String {
        switch firstRun.step {
        case .welcome: "Takes about a minute"
        case .tools:
            switch [setup.isLinked, setup.isSkillDetected].filter({ !$0 }).count {
            case 0: ""
            case 1: "1 left"
            default: "2 left"
            }
        case .connect: app.agentConnectedOnce ? "" : "You can connect any time"
        case .tryIt: ""
        }
    }
}

/// The footer: Skip Setup, a hint, Back, and the step's main button. A
/// problem with Link, Install or the demo shows in place of the hint.
private struct FirstRunFooter: View {
    let app: AppModel
    let nextTitle: String
    let hint: String
    @Environment(\.palette) private var palette

    private var firstRun: FirstRun { app.firstRun }

    var body: some View {
        HStack(spacing: 10) {
            Button("Skip Setup") { firstRun.close() }
                .buttonStyle(.borderless)
                .foregroundStyle(palette[.textSecondary])
                .help("Close this window. Finish setup stays in the header.")
            Spacer()
            if let problem = firstRun.problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(palette[.stateFailed])
                    .lineLimit(2)
                    .help(problem)
            } else {
                Text(hint).font(.callout).foregroundStyle(palette[.textTertiary])
            }
            if firstRun.step != .welcome {
                Button("Back") { firstRun.back() }
                    .controlSize(.large)
            }
            Button(nextTitle) { primary() }
                .filledButton(palette)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
    }

    private func primary() {
        guard firstRun.step == .tryIt else {
            firstRun.next()
            return
        }
        Task {
            do throws(AppRefusal) {
                try await app.openDemoFromFirstRun()
            } catch {
                firstRun.problem = error.reason
            }
        }
    }
}

// MARK: - Progress

/// Four segments, the reached ones filled, each with its title and a
/// check once its work is done. A click on one shows that step.
private struct FirstRunProgress: View {
    let firstRun: FirstRun
    let isDone: (FirstRunStep) -> Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(FirstRunStep.allCases, id: \.self) { step in
                let reached = step.index <= firstRun.step.index
                let current = step == firstRun.step
                Button { firstRun.go(to: step) } label: {
                    VStack(spacing: 5) {
                        Capsule()
                            .fill(reached ? palette[.accent] : palette[.track])
                            .frame(height: 4)
                        HStack(spacing: 4) {
                            if isDone(step) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(palette[.stateDone])
                            }
                            Text(step.title)
                                .font(.caption.weight(current ? .semibold : .regular))
                                .foregroundStyle(current ? palette[.textPrimary] : palette[.textSecondary])
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Step \(step.index + 1): \(step.title)")
                .accessibilityAddTraits(current ? .isSelected : [])
            }
        }
    }
}

/// A step's heading: a title and a line under it.
private struct FirstRunHeader: View {
    let title: String
    let detail: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title.weight(.semibold))
            Text(detail)
                .font(.body)
                .foregroundStyle(palette[.textSecondary])
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Welcome

/// What Havooch is, as one loop: pause and write, the agent works, it
/// answers here; and that it works with the agent the person already uses.
private struct FirstRunWelcome: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            HavoochMark(size: 64)
            VStack(spacing: 6) {
                Text("Welcome to Havooch").font(.largeTitle.weight(.semibold))
                Text("Watch a video, pause where something's off, and tell your own coding agent.\nIt does the work in your repo and answers right here.")
                    .font(.title3)
                    .foregroundStyle(palette[.textSecondary])
                    .multilineTextAlignment(.center)
            }
            loop.padding(.top, 6)
            HStack(spacing: 6) {
                Text("Havooch isn't an agent. It works with the one you use:")
                    .font(.callout)
                    .foregroundStyle(palette[.textSecondary])
                ForEach(HarnessCatalog.all, id: \.installName) { harness in
                    AgentMark(agent: harness.agent, size: 16).help(harness.name)
                }
                Text("…").foregroundStyle(palette[.textSecondary])
            }
            Spacer(minLength: 0)
        }
    }

    private var loop: some View {
        HStack(spacing: 0) {
            node(title: "Pause and write", detail: "on any frame") {
                DemoFramePicture(region: true)
                    .frame(width: 96, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            arrow("⌘↩")
            node(title: "Your agent works", detail: "in your repo") {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette[.letterbox]).frame(width: 96, height: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("$ havooch wait").font(.system(size: 7.5, design: .monospaced)).foregroundStyle(palette[.sizeLabel].opacity(0.8))
                        Text("✓ editing Hero.swift").font(.system(size: 7.5, design: .monospaced)).foregroundStyle(palette[.stateDone])
                    }
                }
            }
            arrow("reply")
            node(title: "It answers here", detail: "beside the frame") {
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(palette[.bubblePerson]).frame(width: 58, height: 12)
                    Capsule().fill(palette[.bubbleAgent]).frame(width: 80, height: 12).frame(maxWidth: .infinity, alignment: .trailing)
                    Capsule().fill(palette[.bubbleAgent]).frame(width: 52, height: 12).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(8)
                .frame(width: 96, height: 54)
                .background(palette[.well], in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(16)
        .background(palette[.well], in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette[.separator], lineWidth: 1))
    }

    private func node<Picture: View>(title: String, detail: String, @ViewBuilder picture: () -> Picture) -> some View {
        VStack(spacing: 8) {
            picture()
            VStack(spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(palette[.textSecondary])
            }
        }
        .frame(width: 130)
    }

    private func arrow(_ label: String) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(palette[.textTertiary])
            Image(systemName: "arrow.right").foregroundStyle(palette[.textTertiary])
        }
        .frame(width: 44)
        .offset(y: -14)
        .accessibilityHidden(true)
    }
}

// MARK: - Tools

/// The command line and the skill: the Connect view's steps 1 and 2. A
/// step not done is open; a done one folds, and a click on its title opens it.
private struct FirstRunTools: View {
    let firstRun: FirstRun
    @State private var commandLinePinned: Bool?
    @State private var skillPinned: Bool?

    private var setup: SetupDesk { firstRun.setup }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FirstRunHeader(
                title: "Give your agent two tools",
                detail: "Havooch talks to your agent through a command and a skill. Both stay on this Mac."
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CommandLineStep(model: firstRun, open: commandLineOpen, toggle: { commandLinePinned = !commandLineOpen })
                    SkillStep(model: firstRun, open: skillOpen, isLast: true, toggle: { skillPinned = !skillOpen })
                }
                .frame(maxWidth: 480, alignment: .leading)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.automatic)
        }
        .padding(.top, 22)
        .onChange(of: setup.isLinked) { commandLinePinned = nil }
        .onChange(of: setup.isSkillDetected) { skillPinned = nil }
        .animation(.easeOut(duration: 0.2), value: commandLinePinned)
        .animation(.easeOut(duration: 0.2), value: skillPinned)
    }

    private var commandLineOpen: Bool { commandLinePinned ?? !setup.isLinked }
    private var skillOpen: Bool { skillPinned ?? (setup.isLinked && !setup.isSkillDetected) }
}

// MARK: - Connect

/// The harness picker and what Havooch detects of the picked one, from the
/// Connect view's step 3, with the demo prompt to paste (H2), and whether
/// an agent listens. There is no "waiting for you" state (G6).
private struct FirstRunConnect: View {
    let firstRun: FirstRun
    let agentConnected: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FirstRunHeader(
                title: "Connect your agent",
                detail: "Pick where you work, then paste one line into a session in your project. Your agent opens the demo video and listens."
            )
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your agent").font(.callout.weight(.semibold)).foregroundStyle(palette[.textSecondary])
                    HarnessPicker(model: firstRun)
                    listening.padding(.top, 6)
                }
                .frame(width: 280)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        HarnessReadiness(model: firstRun, harness: firstRun.steppedHarness)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(.top, 22)
    }

    private var listening: some View {
        HStack(spacing: 10) {
            Image(systemName: agentConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(agentConnected ? palette[.stateDone] : palette[.textTertiary])
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(agentConnected ? "Your agent is listening" : "No agent is listening yet")
                    .font(.callout.weight(.medium))
                Text(agentConnected ? "Setup works. Try it on the demo video." : "It shows here once one does.")
                    .font(.caption)
                    .foregroundStyle(palette[.textSecondary])
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(agentConnected ? palette[.stateDone].opacity(0.12) : palette[.well], in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Try it

/// How the loop goes, on a picture of the demo video: pause, point and
/// write, send. Open the Demo in the footer opens it.
private struct FirstRunTryIt: View {
    let agentConnected: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FirstRunHeader(
                title: "Send your first message",
                detail: agentConnected
                    ? "Your agent is listening. Try it on the demo video, and it guides you through your first send."
                    : "Try it on the demo video. What you send waits until an agent listens."
            )
            HStack(alignment: .top, spacing: 20) {
                ZStack(alignment: .bottom) {
                    DemoFramePicture(region: true)
                    HStack(spacing: 6) {
                        Text("Make the title bigger").font(.caption)
                        Spacer()
                        Text("⌘↩").font(.caption.weight(.semibold)).foregroundStyle(palette[.textSecondary])
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(palette[.popover], in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(10)
                }
                .frame(width: 330)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 14) {
                    instruction(1, "Pause", "Press Space where something is off.", key: "Space")
                    instruction(2, "Point and write", "Drag a box on the frame, or press C. Write what to change.", key: "C")
                    instruction(
                        3, "Send", "Your messages go to \(agentConnected ? "your agent" : "the agent that listens") at once. Its answer shows in the sidebar.",
                        key: "⌘↩"
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 22)
    }

    private func instruction(_ number: Int, _ title: String, _ detail: String, key: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.bold))
                .foregroundStyle(palette[.textOnAccent])
                .frame(width: 22, height: 22)
                .background(palette[.accentFill], in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.body.weight(.semibold))
                    Text(key)
                        .font(.caption.weight(.semibold).monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(palette[.well], in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(palette[.textSecondary])
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A picture of the demo video

/// A drawn frame of the demo video, a landing page on the letterbox, with
/// the dimmed region a message points at when `region` asks. Decoration.
private struct DemoFramePicture: View {
    var region = false
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            // What the video shows, light on its dark ground, as a label on the frame is.
            let mark = palette[.sizeLabel]
            ZStack(alignment: .topLeading) {
                palette[.letterbox]
                VStack(alignment: .leading, spacing: height * 0.03) {
                    RoundedRectangle(cornerRadius: 3).fill(mark.opacity(0.85)).frame(width: width * 0.42, height: height * 0.07)
                    RoundedRectangle(cornerRadius: 3).fill(mark.opacity(0.35)).frame(width: width * 0.55, height: height * 0.035)
                    RoundedRectangle(cornerRadius: 3).fill(mark.opacity(0.35)).frame(width: width * 0.36, height: height * 0.035)
                    Capsule().fill(palette[.accent]).frame(width: width * 0.16, height: height * 0.07).padding(.top, height * 0.03)
                }
                .padding(.leading, width * 0.08)
                .padding(.top, height * 0.24)
                RoundedRectangle(cornerRadius: 6).fill(mark.opacity(0.10))
                    .frame(width: width * 0.28, height: height * 0.42)
                    .offset(x: width * 0.64, y: height * 0.24)
                if region {
                    let dim = palette[.regionDim], outline = palette[.regionOutline]
                    Canvas { context, size in
                        let hole = CGRect(x: size.width * 0.06, y: size.height * 0.21, width: size.width * 0.48, height: size.height * 0.14)
                        var shade = Path(CGRect(origin: .zero, size: size))
                        shade.addRoundedRect(in: hole, cornerSize: CGSize(width: 3, height: 3))
                        context.fill(shade, with: .color(dim), style: FillStyle(eoFill: true))
                        context.stroke(Path(roundedRect: hole, cornerRadius: 3), with: .color(outline), lineWidth: 2)
                    }
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
