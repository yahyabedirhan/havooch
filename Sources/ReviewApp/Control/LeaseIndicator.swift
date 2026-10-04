import Foundation
import Observation
import ReviewLease

/// What the person sees of the lease: the banner across the top of the
/// window, drawn while an agent holds it. The control server, which owns
/// the lease, writes each change here and settles it when it runs out, so
/// the banner follows its start and end with no request. Of the person's
/// clicks only the banner's Stop reaches the lease, through the control
/// server; the view only reads.
@MainActor
@Observable
final class LeaseIndicator {
    /// The lease as the control server last left it.
    var lease = ControlLease()
    /// How many captures that leave the banner out are under way, each
    /// counted by `Screenshotter` from its start to its end. A count, not a
    /// flag, so the last one to end shows the banner again.
    private(set) var capturesHiding = 0

    /// A capture that leaves the banner out starts.
    func hideForCapture() {
        capturesHiding += 1
    }

    /// A capture that left the banner out ends.
    func showAfterCapture() {
        capturesHiding = max(0, capturesHiding - 1)
    }

    /// The lease to draw at `now`: nil while it's free, or while a capture
    /// hides the banner.
    func shown(at now: Date) -> ControlLease.Status? {
        capturesHiding > 0 ? nil : lease.status(at: now)
    }
}
