import SwiftUI

struct ConnectView: View {
    let model: WindowModel

    @State private var commandLinePinned: Bool?
    @State private var skillPinned: Bool?
    @State private var setupOpen = false
    @Environment(\.palette) private var palette

    private var setup: SetupDesk { model.app.setup }
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
                        VStack(alignment: .leading, spacing: 0) {
                            CommandLineStep(model: model, open: commandLineOpen, toggle: { commandLinePinned = !commandLineOpen })
                            SkillStep(
                                model: model, open: skillOpen, isLast: listening, toggle: { skillPinned = !skillOpen }
                            )
                        }
                        .coachRing(model.tourRings(.setupSteps), radius: 6)
                    }
                    if !listening {
                        Rectangle()
                            .fill(setup.isSkillDetected ? palette[.stateDone].opacity(0.5) : palette[.track])
                            .frame(width: 1.5, height: 30)
                            .frame(width: 20)
                        AgentStep(model: model, isActive: activeStep == 3)
                            .coachRing(model.tourRings(.agentStep), radius: 6)
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

enum StepLook {
    case todo, active, done, failed
}

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

struct Step<Content: View>: View {
    let number: Int
    let title: CodeLabel
    let look: StepLook
    let status: String
    let statusColor: Color
    var isLast = false
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

struct CodeLabel: View {
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

    var text: String { [code, rest].compactMap(\.self).joined(separator: " ") }

    static let commandLine = CodeLabel(code: "havooch", rest: "command line")
    static let skill = CodeLabel(code: "/havooch-mate", rest: "skill")
    static let agent = CodeLabel(rest: "Your agent")
}

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
