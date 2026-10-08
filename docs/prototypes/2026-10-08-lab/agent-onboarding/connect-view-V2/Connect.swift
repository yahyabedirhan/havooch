import SwiftUI

// V4 "Step timeline": numbered vertical steps - 1 Command line, 2 Skill,
// 3 Your agent - joined by a thin line. A step's circle turns into a check
// when it is done; the active step is open, done steps fold to one line.

private enum StepLook { case todo, active, done, failed }

/// The step's circle: a number, or a check once done.
private struct StepDot: View {
    let number: Int
    let look: StepLook
    @Environment(\.tok) private var t

    var body: some View {
        ZStack {
            switch look {
            case .done:
                Circle().fill(t.done)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(t.textOnAccent)
            case .active:
                Circle().fill(t.accent)
                Text("\(number)").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(t.textOnAccent)
            case .failed:
                Circle().fill(t.failed)
                Text("\(number)").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(t.textOnAccent)
            case .todo:
                Circle().strokeBorder(t.track, lineWidth: 1.5)
                Text("\(number)").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(t.textTertiary)
            }
        }
        .frame(width: 20, height: 20)
    }
}

/// One step: the dot and the line down to the next step, a title line with
/// a status word, and the body while open.
private struct Step<Body: View>: View {
    let number: Int
    let title: AnyView
    let look: StepLook
    let status: String
    let statusColor: Color
    var isLast = false
    /// Space under the step, where the line runs on to the next one.
    var gap: CGFloat = 18
    var open: Bool
    var toggleID: String?
    var toggle: (() -> Void)?
    @ViewBuilder var content: Body
    @Environment(\.tok) private var t

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                StepDot(number: number, look: look)
                if !isLast {
                    Rectangle().fill(look == .done ? t.done.opacity(0.5) : t.track).frame(width: 1.5)
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
                .foregroundStyle(look == .todo ? t.textSecondary : t.textPrimary)
            Spacer(minLength: 6)
            Text(status)
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .fixedSize()
            if toggle != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(t.textTertiary)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
        }
        .frame(height: 20)
        .contentShape(Rectangle())
        if let toggle, let toggleID {
            Button(action: toggle) { line }.buttonStyle(.plain).labID(toggleID)
        } else {
            line
        }
    }
}

/// A scroll view, or plain content at its natural height for the board.
private struct Scroller<Content: View>: View {
    let on: Bool
    @ViewBuilder var content: Content
    var body: some View {
        if on { ScrollView { content } } else { content.fixedSize(horizontal: false, vertical: true) }
    }
}

struct ConnectView: View {
    @Bindable var m: Onboard
    /// The board draws each state at its natural height.
    var scrolls = true
    @Environment(\.tok) private var t
    /// nil follows the timeline (only the active or failed step is open);
    /// a click on the title pins it open or shut.
    @State private var cliPinned: Bool?
    @State private var skillPinned: Bool?
    /// While an agent listens, the setup steps fold to one line; a click opens them.
    @State private var setupOpen = false

    private var cliOpen: Bool { cliPinned ?? (activeStep == 1) }
    private var skillOpen: Bool { skillPinned ?? (activeStep == 2) }

    private var ring: TourStep? { m.tourOpen ? m.tourStep : nil }
    private var connected: Bool { m.listener != nil && m.phase != .none }
    /// The first step not done is the active one.
    private var activeStep: Int { !m.cliDone ? 1 : !m.skillDone ? 2 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { m.back() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("Threads")
                }
                .font(.callout)
                .foregroundStyle(t.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .labID("back")
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
            Scroller(on: scrolls) {
                VStack(alignment: .leading, spacing: 18) {
                    if let banner = m.banner { bannerLine(banner) }
                    head
                    if connected {
                        listenerBlock
                        Hairline()
                        setupLine
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        if !connected || setupOpen {
                            VStack(alignment: .leading, spacing: 0) {
                                cliStep
                                skillStep
                            }
                            .coachRing(ring == .tools, radius: 6)
                        }
                        if !connected {
                            // The line runs on between the setup steps and the
                            // agent step, leaving room for the tour's ring.
                            Rectangle().fill(m.skillDone ? t.done.opacity(0.5) : t.track)
                                .frame(width: 1.5, height: 30)
                                .frame(width: 20)
                            agentStep
                                .coachRing(ring == .connect || (ring == .reply && m.waitingCount > 0), radius: 6)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .animation(.easeOut(duration: 0.2), value: m.install)
                .animation(.easeOut(duration: 0.2), value: m.cli)
                .animation(.easeOut(duration: 0.2), value: m.phase)
                .animation(.easeOut(duration: 0.2), value: m.repoOpen)
                .animation(.easeOut(duration: 0.2), value: m.cliExpanded)
                .animation(.easeOut(duration: 0.2), value: m.skillExpanded)
                .animation(.easeOut(duration: 0.2), value: m.readiness)
                .animation(.easeOut(duration: 0.2), value: cliPinned)
                .animation(.easeOut(duration: 0.2), value: skillPinned)
                .animation(.easeOut(duration: 0.2), value: setupOpen)
            }
        }
        .background(t.window)
        .onChange(of: m.cli) { if m.cli == .linked || m.cli == .notLinked { cliPinned = nil } }
        .onChange(of: m.skillDone) { skillPinned = nil }
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(connected ? "Your agent" : "Connect an agent")
                .font(.headline)
                .foregroundStyle(t.textPrimary)
            Text(connected
                 ? "One agent listens to \(Onboard.video) at a time."
                 : "Three steps. Your agent then answers in the player.")
                .font(.caption)
                .foregroundStyle(t.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func bannerLine(_ banner: Banner) -> some View {
        let (symbol, tint, text): (String, Color, String) = switch banner {
        case .waiting(let n): ("tray.and.arrow.up.fill", t.amber, "\(n) messages wait for an agent. They'll be delivered when one connects.")
        case .delivered(let n, let h): ("checkmark.circle.fill", t.done, "Delivered \(n) messages to \(h.name). Its answers show on each thread.")
        }
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(tint).frame(width: 18)
            Text(text)
                .font(.callout.weight(.medium))
                .foregroundStyle(t.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .labID("outboxBanner")
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(t.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(t.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // 1 Command line

    private var cliStep: some View {
        let (look, status, color): (StepLook, String, Color) = switch m.cli {
        case .linked: (.done, "Linked", t.done)
        case .linking: (.active, "Linking…", t.textSecondary)
        case .notLinked: (activeStep == 1 ? .active : .todo, "Not linked", t.textTertiary)
        case .failed: (.failed, "Couldn't link", t.failed)
        }
        return Step(number: 1, title: AnyView(CodeLabel.cli), look: look, status: status, statusColor: color,
                    open: cliOpen, toggleID: "cliExpand", toggle: { cliPinned = !cliOpen }) {
            switch m.cli {
            case .linked:
                Text("havooch → \(Onboard.linkPath)")
                    .font(.caption.monospaced())
                    .foregroundStyle(t.textSecondary)
                note("If your agent can't find havooch, add ~/.local/bin to its PATH.")
            case .notLinked, .linking:
                detail("Agents control Havooch through the havooch command. Link puts it in ~/.local/bin.")
                Button("Link") { m.link() }
                    .buttonStyle(.borderedProminent)
                    .tint(t.accentFill)
                    .controlSize(.small)
                    .disabled(m.cli == .linking)
                    .labID("cliLink")
            case .failed:
                detail("\(Onboard.linkPath) is a file Havooch didn't make. Run this in a terminal to replace it:")
                CopyBox(m: m, id: "cliCopy", text: Onboard.linkCommand)
                Button("Try Again") { m.link() }
                    .controlSize(.small)
                    .labID("cliRetry")
            }
        }
    }

    // 2 Skill

    private var skillStep: some View {
        let look: StepLook = m.skillDone ? .done : (activeStep == 2 ? .active : .todo)
        let status = m.skillDone ? "Installed" : m.install == .running ? "Installing…" : "\(m.missing.count) not detected"
        let color = m.skillDone ? t.done : t.textSecondary
        return Step(number: 2, title: AnyView(CodeLabel.skill), look: look, status: status, statusColor: color,
                    isLast: connected, gap: 6, open: skillOpen, toggleID: "skillExpand", toggle: { skillPinned = !skillOpen }) {
            detail("Teaches your agent to listen and answer in the player.")
            harnessGrid
            if !m.skillDone { skillAction }
            note(Onboard.repoNote)
        }
    }

    private var harnessGrid: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Harness.allCases) { harness in
                let mark = m.marks[harness] ?? .notFound
                HStack(spacing: 7) {
                    Mark(harness: harness, size: 14).opacity(mark == .notFound ? 0.45 : 1)
                    Text(harness.name).font(.caption).foregroundStyle(mark == .notFound ? t.textSecondary : t.textPrimary)
                    Spacer(minLength: 4)
                    glyphWord(mark)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func glyphWord(_ mark: SkillMark) -> some View {
        let (symbol, word, color): (String, String, Color) = switch mark {
        case .installed: ("checkmark", "Installed", t.done)
        case .missing: ("circle.dashed", "Not detected", t.textTertiary)
        case .notFound: ("circle.dashed", "Not detected", t.textTertiary)
        }
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(word)
        }
        .font(.caption)
        .foregroundStyle(color)
    }

    @ViewBuilder private var skillAction: some View {
        if !m.npxFound {
            Text("npx isn't on your PATH").font(.caption.weight(.semibold)).foregroundStyle(t.failed)
            detail("Install Node from nodejs.org, or run this where npx works:")
            CopyBox(m: m, id: "skillCopy", text: Onboard.globalCommand)
            Button("Check Again") { m.npxFound = true }.controlSize(.small).labID("skillCheck")
        } else {
            switch m.install {
            case .idle, .cancelled, .done:
                if m.install == .cancelled { note(m.logLine) }
                HStack(spacing: 10) {
                    Button("Install for \(Onboard.list(m.missing.map(\.name)))") { m.startInstall() }
                        .buttonStyle(.borderedProminent)
                        .tint(t.accentFill)
                        .controlSize(.small)
                        .labID("skillInstall")
                    Button(m.repoOpen ? "Hide repo command" : "In one repo…") { m.repoOpen.toggle() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(t.accent)
                        .labID("repoDisclosure")
                }
                if m.repoOpen {
                    detail("Run this in your repo's folder. Only agents working there get the skill.")
                    CopyBox(m: m, id: "repoCopy", text: Onboard.repoCommand)
                }
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(m.logLine)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(t.textSecondary)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(m.logLine)
                    Button("Cancel") { m.cancelInstall() }.controlSize(.small).labID("skillCancel")
                }
            }
        }
    }

    // 3 Your agent

    private var agentStep: some View {
        let look: StepLook = activeStep == 3 ? .active : .todo
        return Step(number: 3, title: AnyView(Text("Your agent")), look: look, status: "Not listening", statusColor: t.textTertiary,
                    isLast: true, open: true) {
            picker
            readiness
            HStack(spacing: 5) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash").symbolRenderingMode(.hierarchical)
                Text("No agent is listening. It shows here once it does.")
            }
            .font(.caption)
            .foregroundStyle(t.textTertiary)
        }
    }

    private var picker: some View {
        HStack(spacing: 2) {
            ForEach(Harness.allCases) { harness in
                let selected = m.chosen == harness
                let notFound = m.marks[harness] == .notFound
                Button { m.choose(harness) } label: {
                    VStack(spacing: 3) {
                        Mark(harness: harness, size: 18).opacity(notFound ? 0.5 : 1)
                        Text(harness.short)
                            .font(.system(size: 10, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? t.textPrimary : t.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(selected ? t.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .labID("harness-\(harness.rawValue)")
                .help(notFound ? "\(harness.name): not detected on this Mac" : harness.name)
            }
        }
    }

    private func line(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            Text(text).font(.callout.weight(.medium)).foregroundStyle(t.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .labID("readiness")
    }

    @ViewBuilder private var readiness: some View {
        let h = m.chosen
        switch m.readiness {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Checking \(h.name)…").font(.callout).foregroundStyle(t.textSecondary)
            }
            .labID("readiness")
        case .ready:
            line("checkmark.circle.fill", t.done, "Ready. The skill is installed for \(h.name).")
            detail("Paste this in \(h.name), in your project, to start a session that listens:")
            CopyBox(m: m, id: "copyPrompt", text: m.prompt, mono: false)
        case .notInstalled:
            line("questionmark.circle", t.textSecondary, "Havooch couldn't detect the skill for \(h.name).")
            detail("If it's installed another way, paste the prompt and your agent will take it from there. If not, install it first:")
            Button(m.installingOne == h ? "Installing…" : "Install for \(h.name)") { m.installOne(h) }
                .buttonStyle(.borderedProminent)
                .tint(t.accentFill)
                .controlSize(.small)
                .disabled(m.installingOne != nil)
                .labID("harnessInstall")
            pastePrompt
        case .notDetected:
            line("questionmark.circle", t.textSecondary, "Havooch couldn't detect \(h.name) on this Mac.")
            detail("If it's installed another way, paste the prompt and your agent will take it from there. If not, install the skill for \(h.name) first:")
            CopyBox(m: m, id: "agentCommandCopy", text: Onboard.agentCommand(h))
            pastePrompt
        }
    }

    /// The prompt, full size, after an install offer.
    @ViewBuilder private var pastePrompt: some View {
        detail("Paste this in \(m.chosen.name), in your project:")
        CopyBox(m: m, id: "copyPrompt", text: m.prompt, mono: false)
    }

    // Set up, folded while an agent listens

    /// One line: "Set up" with a check (or an open circle) for each setup step.
    private var setupLine: some View {
        let allDone = m.cliDone && m.skillDone
        return Button { setupOpen.toggle() } label: {
            HStack(spacing: 10) {
                ZStack {
                    if allDone {
                        Circle().fill(t.done)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(t.textOnAccent)
                    } else {
                        Circle().strokeBorder(t.track, lineWidth: 1.5)
                    }
                }
                .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Set up").font(.callout.weight(.semibold)).foregroundStyle(t.textPrimary)
                        Spacer(minLength: 6)
                        Text(allDone ? "Done" : !m.cliDone ? "Not linked" : "\(m.missing.count) not detected")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(allDone ? t.done : t.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(t.textTertiary)
                            .rotationEffect(.degrees(setupOpen ? 90 : 0))
                    }
                    HStack(spacing: 12) {
                        setupCheck(m.cliDone, CodeLabel.cli)
                        setupCheck(m.skillDone, CodeLabel.skill)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .labID("setupExpand")
        .help(setupOpen ? "Fold the setup steps" : "Show the setup steps")
    }

    private func setupCheck(_ done: Bool, _ text: some View) -> some View {
        HStack(spacing: 4) {
            Image(systemName: done ? "checkmark" : "circle.dashed")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(done ? t.done : t.textTertiary)
            text.font(.caption).foregroundStyle(t.textSecondary)
        }
        .fixedSize()
    }

    // Listener

    @ViewBuilder private var listenerBlock: some View {
        if let listener = m.listener {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Mark(harness: listener.harness, size: 24)
                        .saturation(m.phase == .reconnecting ? 0 : 1)
                        .opacity(m.phase == .reconnecting ? 0.6 : 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(listener.harness.name).font(.callout.weight(.semibold)).foregroundStyle(t.textPrimary)
                        HStack(spacing: 5) {
                            Circle().fill(m.phase == .reconnecting ? t.amber : t.done).frame(width: 6, height: 6)
                            Text(m.phase == .reconnecting ? "Havooch relaunched" : "Listening to \(Onboard.video)")
                                .font(.caption).foregroundStyle(t.textSecondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if m.phase == .reconnecting {
                        Button("Forget") { m.disconnect() }.controlSize(.small).labID("forget")
                    } else {
                        Button("Disconnect") { m.disconnect() }
                            .controlSize(.small)
                            .foregroundStyle(t.failed)
                            .labID("disconnect")
                    }
                }
                if m.phase == .reconnecting {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = m.secondsLeft(at: context.date)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(left > 0 ? "Reconnecting to \(listener.harness.name)… \(left) s" : "\(listener.harness.name) didn't come back")
                                .font(.caption.weight(.medium)).foregroundStyle(t.textPrimary)
                            ProgressView(value: Double(left), total: 30).tint(t.amber).controlSize(.mini)
                            note("It picks up again on its next havooch wait. Forget it to connect another agent.")
                        }
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        Text("Where").font(.caption).foregroundStyle(t.textTertiary)
                        HStack(spacing: 6) {
                            Text(listener.place).font(.caption.monospaced()).foregroundStyle(t.textPrimary)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Button(m.copiedPath ? "Copied" : "Copy Path") { m.copyPath() }
                                .buttonStyle(.borderless).font(.caption)
                                .foregroundStyle(m.copiedPath ? t.done : t.accent)
                                .labID("copyPath")
                        }
                    }
                    GridRow {
                        Text("Since").font(.caption).foregroundStyle(t.textTertiary)
                        Text(listener.since).font(.caption.monospacedDigit()).foregroundStyle(t.textPrimary)
                    }
                }
                note("A new agent that listens replaces \(listener.harness.name).")
                detail("To listen again later, paste this in \(listener.harness.name):")
                CopyBox(m: m, id: "copyPrompt", text: Onboard.prompt(for: listener.harness), mono: false)
            }
        }
    }
}
