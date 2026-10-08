import LabHost
import SwiftUI

/// Learn by doing: the demo opens at once in the real player layout, and a
/// coach panel under the stage walks through it in place: tools → connect →
/// pause and write → send → see the agent's reply. A ring marks the part
/// of the player each step is about. Skip hides the tour at any step.
public let variant = LabVariant(window: LabWindow(titleVisibility: .hidden, titlebarAppearsTransparent: true)) { LearnByDoingView() }

private enum Coach: Int, CaseIterable {
    case tools, connect, write, send, reply, finished

    static let count = 5
}

private enum MessageState {
    case none, queued, sent, working, done

    var label: String {
        switch self {
        case .none: ""
        case .queued: "Queued"
        case .sent: "Sent"
        case .working: "Working"
        case .done: "Done"
        }
    }

    var glyph: String {
        switch self {
        case .none, .queued: "circle.dashed"
        case .sent: "arrow.up.circle.fill"
        case .working: "ellipsis.circle.fill"
        case .done: "checkmark.circle.fill"
        }
    }
}

struct LearnByDoingView: View {
    @State private var setup = Setup()
    @State private var coach: Coach = .tools
    @State private var tourHidden = false
    @State private var draft = ""
    @State private var message = ""
    @State private var state: MessageState = .none
    @State private var activity = ""
    @State private var replied = false
    @FocusState private var composerFocused: Bool

    private static let stageWidth: CGFloat = 470

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                stageColumn.frame(width: Self.stageWidth)
                Divider()
                sidebar
            }
        }
        .frame(width: 760, height: 540)
        .ignoresSafeArea()
        .background(Pal.window)
        .foregroundStyle(Pal.textPrimary)
        .tint(Pal.accent)
        .animation(.smooth(duration: 0.25), value: coach)
        .animation(.smooth(duration: 0.25), value: state)
        .animation(.smooth(duration: 0.25), value: replied)
        .onChange(of: setup.cliDone) { advanceIfToolsDone() }
        .onChange(of: setup.skillDone) { advanceIfToolsDone() }
        .onChange(of: setup.connected) { _, on in
            if on, coach == .connect { later(0.9) { coach = .write } }
        }
    }

    private var ringed: Coach? { tourHidden ? nil : coach }

    private func later(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            action()
        }
    }

    private func advanceIfToolsDone() {
        if setup.cliDone, setup.skillDone, coach == .tools { later(0.8) { coach = .connect } }
    }

    private func restart() {
        setup.reset()
        coach = .tools
        tourHidden = false
        draft = ""
        message = ""
        state = .none
        activity = ""
        replied = false
    }

    // MARK: Header (the real app's title view)

    private var header: some View {
        HStack(spacing: 8) {
            CatMark(size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Label("halcyon-demo.mp4", systemImage: "film").font(.callout.weight(.semibold)).labelStyle(TightLabel())
                Label("Demo", systemImage: "folder").font(.caption).foregroundStyle(Pal.textSecondary).labelStyle(TightLabel())
            }
            Spacer()
        }
        .padding(.leading, 84)
        .frame(height: 40)
    }

    // MARK: Stage

    private var stageColumn: some View {
        VStack(spacing: 0) {
            ZStack {
                Pal.letterbox
                DemoFrame(region: coach.rawValue >= Coach.write.rawValue)
                if coach == .tools || coach == .connect {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 52, height: 52)
                        .background(.black.opacity(0.35), in: Circle())
                }
            }
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .coachRing(ringed == .write)
            .padding(.horizontal, 12)
            PlayerBar(time: coach.rawValue >= Coach.write.rawValue ? "0:12 / 0:42" : "0:00 / 0:42",
                      progress: coach.rawValue >= Coach.write.rawValue ? 0.29 : 0, paused: true)
            if tourHidden {
                hiddenBar
            } else {
                coachPanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
            Spacer(minLength: 0)
        }
    }

    private var hiddenBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "graduationcap").foregroundStyle(Pal.textSecondary)
            Text(setup.cliDone && setup.skillDone ? "Tour hidden." : "Tour hidden. Your agent can't hear Havooch until setup is done.")
                .font(.callout).foregroundStyle(Pal.textSecondary)
                .lineLimit(2)
            Spacer()
            Button("Show Tour") { tourHidden = false }
                .controlSize(.small)
                .labID("resume")
        }
        .padding(10)
        .card()
        .padding(12)
    }

    // MARK: Coach panel

    private var coachPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if coach != .finished {
                    ForEach(0..<Coach.count, id: \.self) { i in
                        Capsule()
                            .fill(i < coach.rawValue ? Pal.done : i == coach.rawValue ? Pal.accent : Pal.hover)
                            .frame(width: i == coach.rawValue ? 18 : 7, height: 7)
                    }
                    Text("Step \(coach.rawValue + 1) of \(Coach.count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Pal.textSecondary)
                        .padding(.leading, 4)
                }
                Spacer()
                if coach != .finished {
                    Button("Skip Tour") { tourHidden = true }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(Pal.textSecondary)
                        .labID("skip")
                }
            }
            Text(coachTitle).font(.headline)
            coachContent
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Pal.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Pal.accent.opacity(0.35), lineWidth: 1))
    }

    private var coachTitle: String {
        switch coach {
        case .tools: "Give your agent two tools"
        case .connect: "Connect your agent"
        case .write: "Write your first message"
        case .send: "Send it to \(setup.connected ? setup.harness.name : "your agent")"
        case .reply: replied ? "\(setup.harness.name) answered in the player" : "\(setup.harness.name) is on it"
        case .finished: "That's the loop"
        }
    }

    @ViewBuilder private var coachContent: some View {
        switch coach {
        case .tools: toolsStep
        case .connect: connectStep
        case .write: writeStep
        case .send: sendStep
        case .reply: replyStep
        case .finished: finishedStep
        }
    }

    private func nextButton(_ title: String = "Next", to step: Coach) -> some View {
        Button(title) { coach = step }
            .controlSize(.small)
            .labID("coach-next")
    }

    private var toolsStep: some View {
        VStack(alignment: .leading, spacing: 6) {
            toolRow(icon: "terminal", title: "Command line", detail: setup.cliDone ? "havooch is on your PATH" : "Lets your agent run havooch") {
                switch setup.cli {
                case .notLinked: Button("Link") { setup.linkCLI() }.buttonStyle(.borderedProminent).controlSize(.small).labID("link-cli")
                case .linking: ProgressView().controlSize(.small)
                case .linked: StatusDot(kind: .done)
                }
            }
            toolRow(icon: "sparkles", title: "havooch-mate skill", detail: setup.log.last ?? "Teaches your agent to listen") {
                HStack(spacing: 4) {
                    ForEach(setup.found) { h in
                        HarnessLogo(harness: h, size: 16)
                            .opacity(setup.skills[h] == .installed ? 1 : 0.35)
                            .overlay(alignment: .bottomTrailing) {
                                if setup.skills[h] == .installed {
                                    Circle().fill(Pal.done).frame(width: 6, height: 6).offset(x: 2, y: 2)
                                }
                            }
                    }
                    Group {
                        if setup.skillDone {
                            StatusDot(kind: .done)
                        } else if setup.isInstalling {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Install for All") { setup.installSkill() }.buttonStyle(.borderedProminent).controlSize(.small).labID("install-skill")
                        }
                    }
                    .padding(.leading, 4)
                }
            }
            HStack {
                Text("The ring marks the listener pill: it turns green once an agent listens.")
                    .font(.caption).foregroundStyle(Pal.textTertiary)
                Spacer()
                nextButton(setup.cliDone && setup.skillDone ? "Next" : "Later", to: .connect)
            }
        }
    }

    private func toolRow<Trailing: View>(icon: String, title: String, detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(Pal.accent).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption.monospaced()).foregroundStyle(Pal.textSecondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Pal.window.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                ForEach(Harness.allCases) { h in
                    let picked = setup.harness == h
                    Button { setup.harness = h } label: {
                        HStack(spacing: 4) {
                            HarnessLogo(harness: h, size: 16)
                            if picked { Text(h.name).font(.caption.weight(.semibold)).lineLimit(1).fixedSize() }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(picked ? Pal.accent.opacity(0.14) : Pal.window.opacity(0.6), in: Capsule())
                        .overlay(Capsule().strokeBorder(picked ? Pal.accent : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(h.name)
                    .labID("harness-\(h.rawValue)")
                }
            }
            CommandBox(text: setup.prompt, copyID: "copy-prompt", copied: setup.copied) { setup.copyPrompt() }
            HStack(spacing: 6) {
                switch setup.listen {
                case .idle:
                    Text("Paste it in \(setup.harness.name), in your project. Or tell it: open this video with Havooch.")
                        .font(.caption).foregroundStyle(Pal.textSecondary)
                case .waiting:
                    ProgressView().controlSize(.mini)
                    Text("Waiting for your agent…").font(.caption.weight(.medium))
                case .connected:
                    StatusDot(kind: .done, size: 12)
                    Text("\(setup.harness.name) is listening · \(Setup.project)").font(.caption.weight(.medium))
                }
                Spacer()
                nextButton(setup.connected ? "Next" : "Later", to: .write)
            }
        }
    }

    private var writeStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The video is paused at 0:12 with a box on the title. Say what you'd change in the box on the right, then press Return to queue it.")
                .font(.callout).foregroundStyle(Pal.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Pause anywhere with Space · drag on the frame to point")
                    .font(.caption).foregroundStyle(Pal.textTertiary)
                Spacer()
                Button("Write an Example") {
                    draft = "Make the title bigger and bolder"
                    composerFocused = true
                }
                .controlSize(.small)
                .labID("coach-example")
            }
        }
    }

    private var sendStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(setup.connected
                 ? "Your message is queued. Press ⌘↩ or click Send: every queued message goes to \(setup.harness.name) at once, with the frame, the box and the transcript."
                 : "Your message is queued. No agent listens yet, so a send waits for the next one. You can still send it now.")
                .font(.callout).foregroundStyle(Pal.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Queue more first if you like: each frame gets its own thread.")
                    .font(.caption).foregroundStyle(Pal.textTertiary)
                Spacer()
            }
        }
    }

    private var replyStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(replied
                 ? "It worked in \(Setup.project) with its own skills, and replied on the thread beside the frame. Reply there to keep going."
                 : "It acknowledged the send and works in its repo. Its live activity shows in the sidebar footer.")
                .font(.callout).foregroundStyle(Pal.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                if replied {
                    Button("Finish") { coach = .finished }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .labID("coach-finish")
                }
            }
        }
    }

    private var finishedStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pause, write, ⌘↩, read the answer. Open your own video, or ask your agent to open one with Havooch.")
                .font(.callout).foregroundStyle(Pal.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Start Over") { restart() }.controlSize(.small).labID("restart")
                Spacer()
                Button("Open a Video…") {}.buttonStyle(.borderedProminent).controlSize(.small).labID("open-video")
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Threads").font(.title3.weight(.bold))
                Text(state == .none ? "No threads" : "1 thread").font(.caption).foregroundStyle(Pal.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 10)
            if state == .none {
                VStack(spacing: 6) {
                    Image(systemName: "text.bubble").font(.system(size: 22)).foregroundStyle(Pal.textTertiary)
                    Text("No Threads Yet").font(.callout.weight(.semibold)).foregroundStyle(Pal.textSecondary)
                    Text("Pause, or drag on the frame, and write. Your messages queue, then go to your agent at once.")
                        .font(.caption).foregroundStyle(Pal.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.top, 30)
                .frame(maxWidth: .infinity)
            } else {
                thread
                    .coachRing(ringed == .reply && replied)
                    .padding(.horizontal, 14)
            }
            Spacer(minLength: 0)
            composer
            footer
        }
    }

    private var thread: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack { Pal.letterbox; DemoFrame(region: true) }
                    .frame(width: 56, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 1) {
                    Text("0:12").font(.callout.weight(.semibold).monospacedDigit())
                    Label(state.label, systemImage: state.glyph)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(stateColor)
                        .labelStyle(TightLabel())
                }
                Spacer()
            }
            // The person's message.
            Text(message)
                .font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Pal.bubblePerson, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
            if replied {
                HStack(alignment: .top, spacing: 6) {
                    HarnessLogo(harness: setup.harness, size: 18)
                    Text("Done. The hero title is now 44 pt semibold in `Hero.swift` (a1c3f9e). Reload to check.")
                        .font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Pal.bubbleAgent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if state == .working {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(activity).font(.caption).foregroundStyle(Pal.textSecondary)
                }
            }
        }
        .padding(10)
        .background(Pal.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var stateColor: Color {
        switch state {
        case .none, .queued: Pal.textTertiary
        case .sent: Pal.textSecondary
        case .working: Pal.control
        case .done: Pal.done
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(coach.rawValue >= Coach.write.rawValue ? "New thread at 0:12" : "New thread at 0:00", systemImage: "text.bubble")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Pal.textSecondary)
            TextField(coach.rawValue >= Coach.write.rawValue ? "Comment on 0:12…" : "Comment on 0:00…", text: $draft)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($composerFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Pal.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Pal.separator))
                .onSubmit(queue)
                .coachRing(ringed == .write, radius: 10)
                .labID("composer")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func queue() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, state == .none else { return }
        message = text
        draft = ""
        state = .queued
        if coach == .write || coach.rawValue < Coach.write.rawValue { coach = .send }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            PresenceChip(listening: setup.connected, harness: setup.harness)
                .coachRing(ringed == .tools || ringed == .connect, radius: 14)
            if state == .working, !activity.isEmpty {
                Text(activity).font(.caption).foregroundStyle(Pal.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(state == .queued ? 1 : 0) queued")
                .font(.callout.monospacedDigit())
                .foregroundStyle(Pal.textSecondary)
                .fixedSize()
            Button("Send", action: send)
                .buttonStyle(.borderedProminent)
                .disabled(state != .queued)
                .keyboardShortcut(.return, modifiers: .command)
                .coachRing(ringed == .send, radius: 8)
                .labID("send")
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .overlay(alignment: .top) { Divider() }
    }

    private func send() {
        guard state == .queued else { return }
        state = .sent
        coach = .reply
        guard setup.connected else {
            // Waits for a listener: connect now, so the tour can finish.
            setup.copyPrompt()
            later(4.5) { work() }
            return
        }
        later(0.8) { work() }
    }

    private func work() {
        state = .working
        activity = "Reading Hero.swift"
        later(2.2) { activity = "Changing the title size" }
        later(4.5) {
            state = .done
            activity = ""
            replied = true
        }
    }
}

// MARK: - Helpers

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

private struct CoachRing: ViewModifier {
    let on: Bool
    let radius: CGFloat
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Pal.accent, lineWidth: 2)
                        .padding(-4)
                        .shadow(color: Pal.accent.opacity(pulse ? 0.7 : 0.2), radius: pulse ? 8 : 2)
                        .allowsHitTesting(false)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
                        }
                        .onDisappear { pulse = false }
                }
            }
    }
}

extension View {
    fileprivate func coachRing(_ on: Bool, radius: CGFloat = 12) -> some View {
        modifier(CoachRing(on: on, radius: radius))
    }
}
