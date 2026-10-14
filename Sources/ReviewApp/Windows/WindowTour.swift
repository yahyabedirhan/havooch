import Foundation
import ReviewCore

nonisolated enum TourStep: String, CaseIterable, Equatable, Sendable {
    case tools, connect, write, send, reply

    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    var next: TourStep? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
}

nonisolated struct TourState: Equatable, Sendable {
    var isOpen = false
    var step: TourStep = .tools
    var send: SendRef?
}

nonisolated enum TourRing: String, Equatable, Sendable {
    case setupSteps
    case agentStep
    case stage
    case composer
    case send
    case thread
}

extension WindowModel {
    var setupItemsLeft: Int {
        let setup = app.setup
        return (setup.isLinked ? 0 : 1) + (setup.isSkillDetected ? 0 : 1) + (app.agentConnectedOnce ? 0 : 1)
    }

    var showsFinishSetup: Bool {
        video != nil && (app.showsConnectDot || tour.isOpen)
    }

    func toggleTour() {
        if tour.isOpen {
            tour.isOpen = false
        } else {
            openTour()
        }
    }

    func showTour() throws(AppRefusal) -> StateReport.Tour {
        try needVideo()
        openTour()
        return tourReport
    }

    func nextTourStep() throws(AppRefusal) -> StateReport.Tour {
        try needTour()
        if let next = tour.step.next {
            go(next)
        } else {
            endTour()
        }
        return tourReport
    }

    func skipTour() throws(AppRefusal) -> StateReport.Tour {
        try needTour()
        endTour()
        return tourReport
    }

    func closeTour() throws(AppRefusal) -> StateReport.Tour {
        try needTour()
        tour.isOpen = false
        return tourReport
    }

    func writeTourExample() {
        _ = try? compose(text: Self.tourExample, region: nil, general: false)
    }

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
        guard tour.isOpen else { throw AppRefusal("the tour isn't showing; havooch tour open opens it") }
    }

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

    func tourNoticedSetup() {
        guard tour.isOpen, tour.step == .tools, app.setup.isDetected else { return }
        go(.connect)
    }

    func tourNoticedAgent() {
        guard tour.isOpen, tour.step == .connect else { return }
        go(.write)
    }

    func tourNoticedQueued() {
        guard tour.isOpen, tour.step == .write else { return }
        go(.send)
    }

    func tourNoticedSend(_ ref: SendRef) {
        guard tour.isOpen, tour.step == .write || tour.step == .send else { return }
        tour.step = .reply
        tour.send = ref
    }

    var isTourSendWaiting: Bool {
        guard let ref = tour.send, let listener else { return false }
        return listener.outbox.pending.contains { $0.sendID == ref.sendID }
    }

    var tourReplied: Bool {
        guard let ref = tour.send, let review = desk.review(of: desk.key(of: ref.sendID) ?? ref.review) else { return false }
        return !review.messages(of: ref.sendID).isEmpty && review.isFinished(ref.sendID)
    }

    var tourReplyThread: ThreadID? {
        guard tourReplied, let ref = tour.send else { return nil }
        return desk.review(of: desk.key(of: ref.sendID) ?? ref.review)?.messages(of: ref.sendID).first?.thread
    }

    var tourAgentName: String {
        if case .connected(let session) = listenerPhase(at: Date()) { return session.name }
        return "your agent"
    }

    var isAgentConnected: Bool {
        if case .connected = listenerPhase(at: Date()) { return true }
        return false
    }

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

    func tourRings(_ part: TourRing) -> Bool {
        tourRings.contains(part)
    }

    var tourReport: StateReport.Tour {
        StateReport.Tour(
            open: tour.isOpen, step: tour.step.rawValue, stepNumber: tour.step.number, steps: TourStep.allCases.count,
            title: tourTitle, rings: tourRings.map(\.rawValue), replied: tourReplied,
            finishSetup: showsFinishSetup, setupItemsLeft: setupItemsLeft
        )
    }
}
