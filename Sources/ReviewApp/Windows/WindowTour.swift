import Foundation
import ReviewCore

/// One step of the setup tour (H4): first-run V3's coach panel, as
/// connect-flow V6 draws it in the player window. It walks the tools, the
/// connect step, writing on a frame, the send and the agent's reply.
nonisolated enum TourStep: String, CaseIterable, Equatable, Sendable {
    case tools, connect, write, send, reply

    /// The step's place, from 1.
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    /// The step after this one; nil after the last.
    var next: TourStep? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
}

/// A window's tour: whether its panel shows, the step it is on, and the
/// send it made, which the reply step watches. Closing the panel keeps the
/// step; Skip and Finish start the next tour from the first step.
nonisolated struct TourState: Equatable, Sendable {
    var isOpen = false
    var step: TourStep = .tools
    /// The send made while the tour showed the write or send step.
    var send: SendRef?
}

/// A part of the window the tour rings (H4): the ring stands
/// `CoachRing.padding` points outside it.
nonisolated enum TourRing: String, Equatable, Sendable {
    /// The command line and skill steps of the Connect view.
    case setupSteps
    /// The Connect view's agent step.
    case agentStep
    /// The video on the stage.
    case stage
    /// The composer at the sidebar's foot.
    case composer
    /// Send in the sidebar's footer.
    case send
    /// The first thread of the tour's send, once the agent answered it.
    case thread
}

extension WindowModel {
    // MARK: - Finish setup

    /// How many setup items are left, the count on "Finish setup": the
    /// command line, the skill and a first connection, each until it is
    /// detected (P11).
    var setupItemsLeft: Int {
        let setup = app.setup
        return (setup.isLinked ? 0 : 1) + (setup.isSkillDetected ? 0 : 1) + (app.agentConnectedOnce ? 0 : 1)
    }

    /// Whether "Finish setup" shows in the header: beside a video, while
    /// setup isn't fully detected and no agent has ever connected (P11), and
    /// while the tour shows, so the button that closes it stays.
    var showsFinishSetup: Bool {
        video != nil && (app.showsConnectDot || tour.isOpen)
    }

    // MARK: - Opening, moving and closing the tour

    /// "Finish setup": the tour shows at the step it was left on, or closes
    /// when it shows.
    func toggleTour() {
        if tour.isOpen {
            tour.isOpen = false
        } else {
            openTour()
        }
    }

    /// `tour show`: the tour shows, as "Finish setup" opens it. Refused with
    /// no video: the tour is about a video's window.
    func showTour() throws(AppRefusal) -> StateReport.Tour {
        try needVideo()
        openTour()
        return tourReport
    }

    /// Next, Later and Finish on the panel, and `tour next`: the next step,
    /// or after the last one the tour ends. Refused while the tour doesn't
    /// show.
    func nextTourStep() throws(AppRefusal) -> StateReport.Tour {
        try needTour()
        if let next = tour.step.next {
            go(next)
        } else {
            endTour()
        }
        return tourReport
    }

    /// Skip Tour on the panel, and `tour skip`: the tour ends. "Finish
    /// setup" starts it again from the first step. Refused while the tour
    /// doesn't show.
    func skipTour() throws(AppRefusal) -> StateReport.Tour {
        try needTour()
        endTour()
        return tourReport
    }

    /// The panel's close button, and `tour close`: the panel goes, and the
    /// tour keeps its step for "Finish setup". Refused while it doesn't show.
    func closeTour() throws(AppRefusal) -> StateReport.Tour {
        try needTour()
        tour.isOpen = false
        return tourReport
    }

    /// Write an Example on the write step: the example in the composer, as
    /// `comment compose` puts it there.
    func writeTourExample() {
        _ = try? compose(text: Self.tourExample, region: nil, general: false)
    }

    /// The words Write an Example puts in the composer.
    static let tourExample = "Make the title bigger and bolder"

    private func openTour() {
        tour.isOpen = true
        go(tour.step)
    }

    private func endTour() {
        tour = TourState()
    }

    private func needTour() throws(AppRefusal) {
        try needVideo()
        guard tour.isOpen else { throw AppRefusal("the tour isn't showing; havooch tour show opens it") }
    }

    /// Shows `step`, and in the sidebar the part it is about: the Connect
    /// view for the tools and the agent, the threads and the composer for
    /// writing and sending. The reply step leaves the Connect view while
    /// the send waits in the outbox there.
    private func go(_ step: TourStep) {
        tour.step = step
        switch step {
        case .tools, .connect:
            if connect == nil { toggleConnect(.header) }
            isSidebarVisible = true
        case .write, .send:
            connect = nil
            isSidebarVisible = true
        case .reply:
            if !isTourSendWaiting { connect = nil }
        }
    }

    // MARK: - What moves the tour on by itself

    /// Setup changed: the tools step moves on once both tools are detected.
    /// The panel calls it a moment after the change, so the checks show.
    func tourNoticedSetup() {
        guard tour.isOpen, tour.step == .tools, app.setup.isDetected else { return }
        go(.connect)
    }

    /// An agent's `wait` opened on this window's video: the connect step
    /// moves on.
    func tourNoticedAgent() {
        guard tour.isOpen, tour.step == .connect else { return }
        go(.write)
    }

    /// A message was queued: the write step moves on to the send.
    func tourNoticedQueued() {
        guard tour.isOpen, tour.step == .write else { return }
        go(.send)
    }

    /// The queue was sent: the tour watches the send for the reply. The
    /// sidebar stays where the send left it, on the outbox banner when no
    /// agent is there.
    func tourNoticedSend(_ ref: SendRef) {
        guard tour.isOpen, tour.step == .write || tour.step == .send else { return }
        tour.step = .reply
        tour.send = ref
    }

    // MARK: - What the panel shows

    /// Whether the tour's send still waits in the outbox for an agent.
    var isTourSendWaiting: Bool {
        guard let ref = tour.send, let listener else { return false }
        // By id: a send moved into a project names the project now.
        return listener.outbox.pending.contains { $0.sendID == ref.sendID }
    }

    /// Whether the agent answered the tour's send: every message in it is
    /// done or failed.
    var tourReplied: Bool {
        guard let ref = tour.send, let review = desk.review(of: desk.key(of: ref.sendID) ?? ref.review) else { return false }
        return !review.messages(of: ref.sendID).isEmpty && review.isFinished(ref.sendID)
    }

    /// The thread the reply step rings: the first of the tour's send, once
    /// it is answered.
    var tourReplyThread: ThreadID? {
        guard tourReplied, let ref = tour.send else { return nil }
        return desk.review(of: desk.key(of: ref.sendID) ?? ref.review)?.messages(of: ref.sendID).first?.thread
    }

    /// The name the panel gives the agent: the one connected, else "your
    /// agent".
    var tourAgentName: String {
        if case .connected(let session) = listenerPhase(at: Date()) { return session.name }
        return "your agent"
    }

    /// Whether an agent listens to this window now.
    var isAgentConnected: Bool {
        if case .connected = listenerPhase(at: Date()) { return true }
        return false
    }

    /// The step's title on the panel.
    var tourTitle: String {
        switch tour.step {
        case .tools: "Give your agent two tools"
        case .connect: "Connect your agent"
        case .write: "Write on a frame"
        case .send: "Send them to \(tourAgentName)"
        case .reply:
            if tourReplied {
                "\(capitalized(tourAgentName)) answered in the player"
            } else if isTourSendWaiting {
                "Your messages wait for an agent"
            } else {
                "\(capitalized(tourAgentName)) is on it"
            }
        }
    }

    private func capitalized(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    /// The parts the tour rings now; none while it doesn't show.
    var tourRings: [TourRing] {
        guard tour.isOpen else { return [] }
        switch tour.step {
        case .tools: return [.setupSteps]
        case .connect: return [.agentStep]
        case .write: return [.stage, .composer]
        case .send: return [.send]
        case .reply:
            if isTourSendWaiting { return [.agentStep] }
            return tourReplied ? [.thread] : []
        }
    }

    /// Whether the tour rings `part` now.
    func tourRings(_ part: TourRing) -> Bool {
        tourRings.contains(part)
    }

    /// The tour as `state` reports it.
    var tourReport: StateReport.Tour {
        StateReport.Tour(
            open: tour.isOpen, step: tour.step.rawValue, stepNumber: tour.step.number, steps: TourStep.allCases.count,
            title: tourTitle, rings: tourRings.map(\.rawValue), replied: tourReplied,
            finishSetup: showsFinishSetup, setupItemsLeft: setupItemsLeft
        )
    }
}
