import Foundation
import ReviewCore
import ReviewSetup

struct ConnectEntry: Equatable {
    enum Reason: String, Equatable {
        case pill, header, send
    }

    var reason: Reason
    var waiting: [SendRef] = []
}

nonisolated enum OutboxBanner: Equatable {
    case waiting(messages: Int)
    case delivered(messages: Int, to: String)

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

enum Readiness: String, Equatable {
    case ready
    case skillNotDetected
    case harnessNotDetected
}

extension WindowModel {
    func toggleConnect(_ reason: ConnectEntry.Reason) {
        if connect != nil, isSidebarVisible {
            connect = nil
        } else {
            openConnect(reason)
        }
    }

    func showConnect() throws(AppRefusal) -> StateReport.Sidebar {
        try needVideo()
        openConnect(.header)
        return sidebarReport
    }

    func closeConnect() {
        connect = nil
    }

    private func openConnect(_ reason: ConnectEntry.Reason) {
        isSidebarVisible = true
        if connect == nil || reason == .send { connect = ConnectEntry(reason: reason, waiting: connect?.waiting ?? []) }
    }

    func sentWithNoAgent(_ ref: SendRef) {
        var entry = connect ?? ConnectEntry(reason: .send)
        entry.reason = .send
        if !entry.waiting.contains(ref) { entry.waiting.append(ref) }
        isSidebarVisible = true
        connect = entry
    }

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

    func listenerPhase(at time: Date) -> ListenerQueue.Phase {
        listener?.phase(at: time) ?? .none
    }

    var connectHarness: Harness {
        pickedHarness ?? app.setup.suggestedHarness
    }

    func pickHarness(named name: String) throws(AppRefusal) -> StateReport.Sidebar {
        try needVideo()
        guard let harness = HarnessCatalog.harness(named: name) else {
            let known = HarnessCatalog.all.map(\.installName)
            throw AppRefusal("no harness \(name); Havooch sets up \(known.dropLast().joined(separator: ", ")) and \(known.last ?? "")")
        }
        pick(harness)
        return sidebarReport
    }

    func pick(_ harness: Harness) {
        pickedHarness = harness
        if connect == nil { openConnect(.header) }
    }

    func readiness(of harness: Harness) -> Readiness {
        app.setup.readiness(of: harness)
    }

    var promptTarget: PromptTarget? {
        guard let video else { return nil }
        return project.map { .project(slug: $0) } ?? .video(fileName: video.url.lastPathComponent)
    }

    func prompt(for harness: Harness) -> String? {
        promptTarget.map { harness.prompt(for: $0) }
    }

    static func harness(of session: ListenerSession) -> Harness? {
        session.agent.flatMap(HarnessCatalog.harness(of:))
    }

    func disconnectAgent() throws(AppRefusal) -> String {
        guard case .connected(let session) = listenerPhase(at: Date()) else {
            throw AppRefusal("no agent is connected to this window")
        }
        listener?.disconnect()
        return session.name
    }

    func forgetAgent() throws(AppRefusal) -> String {
        guard case .reconnecting(let session, _) = listenerPhase(at: Date()) else {
            throw AppRefusal("no agent is reconnecting to this window")
        }
        listener?.disconnect()
        return session.name
    }

    func linkCommandLine() {
        do throws(AppRefusal) {
            try app.setup.link()
        } catch {
            if app.setup.linkFailure == nil { problem = Problem(title: "The command wasn't linked", reason: error.reason) }
        }
    }

    func installSkill(for harnesses: [Harness]) {
        do throws(AppRefusal) {
            try app.setup.startInstall(for: harnesses.map(\.installName))
        } catch {
            problem = Problem(title: "The skill wasn't installed", reason: error.reason)
        }
    }

    func cancelSkillInstall() {
        Task { _ = try? await app.setup.cancelInstall() }
    }

    var showsConnectDot: Bool {
        app.showsConnectDot
    }

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

extension WindowModel: SetupSteering {
    var setup: SetupDesk { app.setup }
    var steppedHarness: Harness { connectHarness }
    func pastePrompt(for harness: Harness) -> String? { prompt(for: harness) }
    var keysWindow: WindowModel? { self }
}

extension AppModel {
    var showsConnectDot: Bool {
        !setup.isDetected && !agentConnectedOnce
    }
}
