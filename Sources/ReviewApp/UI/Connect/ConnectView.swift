import SwiftUI

/// The Connect view (G1, G2): the sidebar's view for connecting an agent,
/// in place of the threads, with Back. From connect-flow V6 and
/// connect-view V2 (`docs/prototypes/2026-10-08-lab/agent-onboarding/`):
/// numbered steps, 1 the `havooch` command line, 2 the `/havooch-mate`
/// skill, 3 your agent, joined by a thin line. The first step not done is
/// open; a done step folds to one line, and a click on its title opens it.
/// While an agent listens, or reconnects, the listener card leads and the
/// setup steps fold to one "Set up" line.
struct ConnectView: View {
    let model: WindowModel

    /// nil follows the timeline (the step not done is open); a click on a
    /// step's title pins it open or shut.
    @State private var commandLinePinned: Bool?
    @State private var skillPinned: Bool?
    /// While an agent listens, whether the setup steps show under "Set up".
    @State private var setupOpen = false
    @Environment(\.palette) private var palette

    private var setup: SetupDesk { model.app.setup }
    /// The first step not done: 1, 2 or 3.
    private var activeStep: Int { !setup.isLinked ? 1 : !setup.isSkillDetected ? 2 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                model.closeConnect()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("Threads")
                }
                .font(.callout)
                .foregroundStyle(palette[.accent])
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pressedByKeys(in: model) { model.closeConnect() }
            .help("Back to the threads (Escape)")
            .padding(.horizontal, Metrics.sidebarPadding)
            .padding(.top, 10)
            .padding(.bottom, 4)
            // Each second: a listener that goes, or a reconnect that runs
            // out, changes the view with no event.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(phase: model.listenerPhase(at: context.date), at: context.date)
            }
        }
        .background(palette[.window])
        .onChange(of: setup.isLinked) { commandLinePinned = nil }
        .onChange(of: setup.isSkillDetected) { skillPinned = nil }
    }

    private func content(phase: ListenerQueue.Phase, at time: Date) -> some View {
        let listening = phase != .none
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let banner = model.outboxBanner { OutboxBannerLine(banner: banner) }
                head(listening: listening)
                if listening {
                    ListenerCard(model: model, phase: phase, at: time)
                    Hairline(axis: .horizontal)
                    SetupLine(setup: setup, open: $setupOpen)
                }
                VStack(alignment: .leading, spacing: 0) {
                    if !listening || setupOpen {
                        CommandLineStep(model: model, open: commandLineOpen, toggle: { commandLinePinned = !commandLineOpen })
                        SkillStep(
                            model: model, open: skillOpen, isLast: listening, toggle: { skillPinned = !skillOpen }
                        )
                    }
                    if !listening {
                        // The line runs on between the setup steps and the
                        // agent step.
                        Rectangle()
                            .fill(setup.isSkillDetected ? palette[.stateDone].opacity(0.5) : palette[.track])
                            .frame(width: 1.5, height: 30)
                            .frame(width: 20)
                        AgentStep(model: model, isActive: activeStep == 3)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .animation(.easeOut(duration: 0.2), value: setupOpen)
            .animation(.easeOut(duration: 0.2), value: commandLinePinned)
            .animation(.easeOut(duration: 0.2), value: skillPinned)
        }
    }

    private var commandLineOpen: Bool { commandLinePinned ?? (activeStep == 1) }
    private var skillOpen: Bool { skillPinned ?? (activeStep == 2) }

    private func head(listening: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(listening ? "Your agent" : "Connect an agent")
                .font(.headline)
                .foregroundStyle(palette[.textPrimary])
            Text(listening
                ? "One agent listens to \(model.video?.url.lastPathComponent ?? "this video") at a time."
                : "Three steps. Your agent then answers in the player.")
                .font(.caption)
                .foregroundStyle(palette[.textSecondary])
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The banner over the steps after Send with no agent (G8): the messages
/// wait, then they were delivered.
struct OutboxBannerLine: View {
    let banner: OutboxBanner
    @Environment(\.palette) private var palette

    var body: some View {
        let (symbol, tint): (String, Color) = switch banner {
        case .waiting: ("tray.and.arrow.up.fill", palette[.stateWorking])
        case .delivered: ("checkmark.circle.fill", palette[.stateDone])
        }
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(tint).frame(width: 18)
            Text(banner.text)
                .font(.callout.weight(.medium))
                .foregroundStyle(palette[.textPrimary])
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The step timeline

/// How a step looks on the timeline.
enum StepLook {
    case todo, active, done, failed
}

/// A step's circle: its number, or a check once it's done.
struct StepDot: View {
    let number: Int
    let look: StepLook
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            switch look {
            case .done:
                Circle().fill(palette[.stateDone])
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(palette[.textOnAccent])
            case .active:
                Circle().fill(palette[.accent])
                numeral.foregroundStyle(palette[.textOnAccent])
            case .failed:
                Circle().fill(palette[.stateFailed])
                numeral.foregroundStyle(palette[.textOnAccent])
            case .todo:
                Circle().strokeBorder(palette[.track], lineWidth: 1.5)
                numeral.foregroundStyle(palette[.textTertiary])
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }

    private var numeral: some View {
        Text("\(number)").font(.system(size: 11, weight: .semibold).monospacedDigit())
    }
}

/// One step: the dot and the line down to the next step, a title line
/// with a status word, and the body while it's open. A step with `toggle`
/// opens and folds on a click on its title line.
struct Step<Content: View>: View {
    let number: Int
    let title: CodeLabel
    let look: StepLook
    let status: String
    let statusColor: Color
    var isLast = false
    /// The space under the step, where the line runs on to the next one.
    var gap: CGFloat = 18
    let open: Bool
    var toggle: (() -> Void)?
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                StepDot(number: number, look: look)
                if !isLast {
                    Rectangle()
                        .fill(look == .done ? palette[.stateDone].opacity(0.5) : palette[.track])
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 8) {
                titleLine
                if open { content }
            }
            .padding(.bottom, isLast ? 0 : gap)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var titleLine: some View {
        let line = HStack(spacing: 6) {
            title
                .font(.callout.weight(.semibold))
                .foregroundStyle(look == .todo ? palette[.textSecondary] : palette[.textPrimary])
            Spacer(minLength: 6)
            Text(status)
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .fixedSize()
            if toggle != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette[.textTertiary])
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
        }
        .frame(height: 20)
        .contentShape(Rectangle())
        if let toggle {
            Button(action: toggle) { line }
                .buttonStyle(.plain)
                .accessibilityLabel("Step \(number): \(title.text), \(status)")
                .accessibilityHint(open ? "Folds the step" : "Opens the step")
        } else {
            line
                .accessibilityElement(children: .combine)
        }
    }
}

/// A one-line label with a code name on a soft chip: "`havooch` command
/// line" (G2).
struct CodeLabel: View {
    /// The code name, in monospace: `havooch`, `/havooch-mate`.
    var code: String?
    let rest: String
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            if let code {
                Text(code)
                    .monospaced()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(palette[.well], in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Text(rest)
        }
        .fixedSize()
    }

    /// The label as words, for VoiceOver.
    var text: String { [code, rest].compactMap(\.self).joined(separator: " ") }

    static let commandLine = CodeLabel(code: "havooch", rest: "command line")
    static let skill = CodeLabel(code: "/havooch-mate", rest: "skill")
    static let agent = CodeLabel(rest: "Your agent")
}

/// Secondary words under a step's title.
struct StepDetail: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(palette[.textSecondary])
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A quiet note under a step.
struct StepNote: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(palette[.textTertiary])
            .fixedSize(horizontal: false, vertical: true)
    }
}
