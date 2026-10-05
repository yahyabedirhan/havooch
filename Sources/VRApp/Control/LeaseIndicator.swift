import Foundation
import Observation
import VRLease

/// What the person sees of the lease: the toolbar's button at the window's
/// top right, there while an agent holds it. The control server, which owns
/// the lease, writes each change here and settles it when it runs out, so
/// the button follows the lease's start and end with no request. Of the
/// person's clicks, only the popover's Stop reaches the lease (`ControlServer.stopLease`); the
/// views only read it here.
@MainActor
@Observable
final class LeaseIndicator {
    /// The lease as the control server last left it.
    var lease = ControlLease()

    /// Whether an agent holds the lease now. The server settles the lease at
    /// its end, so a view that reads this redraws when it goes.
    var isHeld: Bool { lease.status(at: .now) != nil }

    /// The words of the toolbar button and its popover, made from the
    /// lease's status at the moment drawn, so the countdown ticks with the
    /// time it's made at.
    struct Summary: Equatable {
        /// "Claude Code controls this app".
        var title: String
        /// Where the holder runs, short: a working folder's last component
        /// (`shop`), or `Herdr pane <id>` as it is.
        var place: String
        /// The time left: `48s` under a minute, `4m 05s` above.
        var timeLeft: String
        /// `2 waiting` while others queue for the lease; nil when nobody does.
        var waiting: String?

        init(_ lease: LeaseStatus) {
            // A process's name may start lowercase ("codex"); the line starts a sentence.
            title = lease.holder.prefix(1).uppercased() + lease.holder.dropFirst() + " controls this app"
            place = lease.place.hasPrefix("/") ? URL(fileURLWithPath: lease.place).lastPathComponent : lease.place
            let minutes = lease.secondsLeft / 60, seconds = lease.secondsLeft % 60
            timeLeft = minutes == 0 ? "\(seconds)s" : "\(minutes)m " + (seconds < 10 ? "0" : "") + "\(seconds)s"
            waiting = lease.waiting > 0 ? "\(lease.waiting) waiting" : nil
        }

        /// The place, the time left and how many wait, joined by ` · `.
        var detail: String {
            ([place, timeLeft] + (waiting.map { [$0] } ?? [])).joined(separator: " · ")
        }

        /// The summary as one line, for the tooltip and VoiceOver.
        var text: String { "\(title) · \(detail)" }
    }
}
