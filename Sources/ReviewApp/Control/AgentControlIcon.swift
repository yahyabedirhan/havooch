import Foundation
import Observation
import ReviewLease

@Observable
final class AgentControlIcon {
    var lease = ControlLease()
    private(set) var capturesHiding = 0

    func hideForCapture() {
        capturesHiding += 1
    }

    func showAfterCapture() {
        capturesHiding = max(0, capturesHiding - 1)
    }

    func shown(at now: Date) -> ControlLease.Status? {
        capturesHiding > 0 ? nil : lease.status(at: now)
    }
}
