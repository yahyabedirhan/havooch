import Foundation
import ReviewCore
import ReviewSetup

/// The Connect view in a window's sidebar: what opened it, and the
/// sends it waits to see delivered.
struct ConnectEntry: Equatable {
    /// What opened the view: the "No agent" pill, the header's connect
    /// button (and `connect show`), or Send with no agent there.
    enum Reason: String, Equatable {
        case pill, header, send
    }

    var reason: Reason
    /// The sends made with no agent there while the view showed, the
    /// first one opening it: the outbox banner counts their messages.
    var waiting: [SendRef] = []
}

/// The banner at the top of the Connect view after Send with no agent.
nonisolated enum OutboxBanner: Equatable {
    /// The sends wait in the outbox: `messages` messages in all.
    case waiting(messages: Int)
    /// An agent connected and took them.
    case delivered(messages: Int, to: String)

    /// "3 messages wait for an agent. They'll be delivered when one
    /// connects." or "Delivered 3 messages to Claude Code".
    var text: String {
        switch self {
        case .waiting(let count):
            count == 1
                ? "1 message waits for an agent. It'll be delivered when one connects."
                : "\(count) messages wait for an agent. They'll be delivered when one connects."
        case .delivered(let count, let agent):
            "Delivered \(count) \(count == 1 ? "message" : "messages") to \(agent)"
        }
    }
}

/// What the Connect view can say of the picked harness, from what Havooch
/// detects. Nothing here is an error: the prompt stays primary.
enum Readiness: String, Equatable {
    /// The skill is in the harness's user skills folder.
    case ready
    /// The harness looks installed, and its skill isn't detected.
    case skillNotDetected
    /// Havooch didn't find the harness on this Mac.
    case harnessNotDetected
}

extension WindowModel {
    // MARK: - Opening and closing the Connect view

    /// The "No agent" pill and the header's connect button: the Connect
    /// view opens, or goes back to the threads when it shows. The sidebar
    /// shows first when it's hidden.
    func toggleConnect(_ reason: ConnectEntry.Reason) {
        if connect != nil, isSidebarVisible {
            connect = nil
        } else {
            openConnect(reason)
        }
    }

    /// `connect show`: the Connect view, as the header's connect button
    /// opens it. Refused with no video: the sidebar is a video's.
    func showConnect() throws(AppRefusal) -> StateReport.Sidebar {
        try needVideo()
        openConnect(.header)
        return sidebarReport
    }

    /// Back in the Connect view: the threads again.
    func closeConnect() {
        connect = nil
    }

    private func openConnect(_ reason: ConnectEntry.Reason) {
        isSidebarVisible = true
        if connect == nil || reason == .send { connect = ConnectEntry(reason: reason, waiting: connect?.waiting ?? []) }
    }

    /// A send was made with no agent there: it waits in the outbox, and
    /// the Connect view opens to say so.
    func sentWithNoAgent(_ ref: SendRef) {
        var entry = connect ?? ConnectEntry(reason: .send)
        entry.reason = .send
        if !entry.waiting.contains(ref) { entry.waiting.append(ref) }
        isSidebarVisible = true
        connect = entry
    }

    // MARK: - What the view shows

    /// The banner over the steps: the sends that waited, while they still
    /// wait, then that the agent took them. Nil when the view didn't open
    /// with sends waiting.
    var outboxBanner: OutboxBanner? {
        guard let entry = connect, !entry.waiting.isEmpty, let listener else { return nil }
        let outbox = listener.outbox
        let left = entry.waiting.filter(outbox.pending.contains)
        if left.isEmpty {
            guard let agent = outbox.session?.name else { return nil }
            return .delivered(messages: messageCount(entry.waiting), to: agent)
        }
        return .waiting(messages: messageCount(left))
    }

    private func messageCount(_ refs: [SendRef]) -> Int {
        refs.reduce(0) { count, ref in count + (desk.review(of: ref.review)?.send(ref.sendID)?.messageIDs.count ?? 0) }
    }

    /// The window's listener as the pill and the Connect view show it at
    /// `time`; nobody with no video.
    func listenerPhase(at time: Date) -> ListenerQueue.Phase {
        listener?.phase(at: time) ?? .none
    }

    /// The harness the agent step shows: the one the person picked, else
    /// the one setup suggests (`SetupDesk.suggestedHarness`).
    var connectHarness: Harness {
        pickedHarness ?? app.setup.suggestedHarness
    }

    /// A click on a harness in the picker, and `connect pick <harness>`:
    /// its readiness and its prompt show. The Connect view opens when it's
    /// closed.
    func pickHarness(named name: String) throws(AppRefusal) -> StateReport.Sidebar {
        try needVideo()
        guard let harness = HarnessCatalog.harness(named: name) else {
            let known = HarnessCatalog.all.map(\.installName)
            throw AppRefusal("no harness \(name); Havooch sets up \(known.dropLast().joined(separator: ", ")) and \(known.last ?? "")")
        }
        pick(harness)
        return sidebarReport
    }

    /// The person picked `harness`.
    func pick(_ harness: Harness) {
        pickedHarness = harness
        if connect == nil { openConnect(.header) }
    }

    /// What Havooch detects of `harness`'s setup.
    func readiness(of harness: Harness) -> Readiness {
        app.setup.readiness(of: harness)
    }

    /// What the copied prompt names: the window's project as
    /// `project <slug>`, else its video's file name; nil with no video.
    var promptTarget: PromptTarget? {
        guard let video else { return nil }
        return project.map { .project(slug: $0) } ?? .video(fileName: video.url.lastPathComponent)
    }

    /// The prompt that makes `harness`'s agent listen to this window's
    /// video or project; nil with no video.
    func prompt(for harness: Harness) -> String? {
        promptTarget.map { harness.prompt(for: $0) }
    }

    /// The harness of the listener session `session`, for its prompt to
    /// listen again; nil for an agent Havooch doesn't set up.
    static func harness(of session: ListenerSession) -> Harness? {
        session.agent.flatMap(HarnessCatalog.harness(of:))
    }

    // MARK: - The listener card

    /// Disconnect on the listener card, and `connect disconnect`: the
    /// agent is let go, its open `wait` refused so it stops. Refused when
    /// no agent is connected. Returns the agent's name.
    func disconnectAgent() throws(AppRefusal) -> String {
        guard case .connected(let session) = listenerPhase(at: Date()) else {
            throw AppRefusal("no agent is connected to this window")
        }
        listener?.disconnect()
        return session.name
    }

    /// Forget on the listener card while it reconnects, and `connect
    /// forget`: the agent the last run had is no longer waited for. Refused
    /// when no agent reconnects.
    func forgetAgent() throws(AppRefusal) -> String {
        guard case .reconnecting(let session, _) = listenerPhase(at: Date()) else {
            throw AppRefusal("no agent is reconnecting to this window")
        }
        listener?.disconnect()
        return session.name
    }

    // MARK: - The setup steps, as the view's buttons take them

    /// Link: the command linked in `~/.local/bin`. A failure shows in the
    /// step, with the line to copy; one that has no line shows as a problem.
    func linkCommandLine() {
        do throws(AppRefusal) {
            try app.setup.link()
        } catch {
            if app.setup.linkFailure == nil { problem = Problem(title: "The command wasn't linked", reason: error.reason) }
        }
    }

    /// Run Command: installs for the harnesses `harnesses`, or for every harness found
    /// without the skill when it's empty.
    func installSkill(for harnesses: [Harness]) {
        do throws(AppRefusal) {
            try app.setup.startInstall(for: harnesses.map(\.installName))
        } catch {
            problem = Problem(title: "The skill wasn't installed", reason: error.reason)
        }
    }

    /// Cancel under the running install.
    func cancelSkillInstall() {
        Task { _ = try? await app.setup.cancelInstall() }
    }

    /// Whether the connect button shows its dot: setup isn't fully
    /// detected, and no agent has ever connected.
    var showsConnectDot: Bool {
        app.showsConnectDot
    }

    // MARK: - state

    /// The Connect view as `state` reports it; nil while it doesn't show.
    var connectReport: StateReport.Sidebar.Connect? {
        guard let connect else { return nil }
        let time = Date()
        let harness = connectHarness
        var report = StateReport.Sidebar.Connect(
            reason: connect.reason.rawValue, phase: "none", harness: harness.installName,
            readiness: readiness(of: harness).rawValue, prompt: prompt(for: harness)
        )
        report.banner = outboxBanner.map(StateReport.Sidebar.Connect.Banner.init)
        switch listenerPhase(at: time) {
        case .none:
            break
        case .connected(let session):
            report.phase = "connected"
            report.listener = .init(session, prompt: Self.harness(of: session).flatMap(prompt(for:)))
        case .reconnecting(let session, let until):
            report.phase = "reconnecting"
            report.listener = .init(session, prompt: Self.harness(of: session).flatMap(prompt(for:)))
            report.listener?.reconnectingUntil = until
        }
        return report
    }
}

/// The Connect view's setup steps act on the window: its own problem
/// line, its harness and the prompt for its video.
extension WindowModel: SetupSteering {
    var setup: SetupDesk { app.setup }
    var steppedHarness: Harness { connectHarness }
    func pastePrompt(for harness: Harness) -> String? { prompt(for: harness) }
    var keysWindow: WindowModel? { self }
}

extension AppModel {
    /// Whether the connect button shows its dot: setup isn't fully
    /// detected, and no agent has ever connected.
    var showsConnectDot: Bool {
        !setup.isDetected && !agentConnectedOnce
    }
}
