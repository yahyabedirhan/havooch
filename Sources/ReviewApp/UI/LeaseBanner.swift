import ReviewLease
import ReviewWire
import SwiftUI

/// The words of the banner while an agent holds the lease: "Claude Code
/// controls Video Review" beside "video-review · 48s left · 2 waiting".
/// Made from the lease's status at the moment drawn, so the countdown ticks
/// with the time it's made at.
struct LeaseBanner: Equatable {
    /// "Claude Code controls Video Review".
    var title: String
    /// Where the agent runs, short: a working folder's last component, or
    /// `Herdr pane <id>` as it is.
    var place: String
    /// The time left: `48s left` under a minute, `4m 05s left` above.
    var timeLeft: String
    /// `2 waiting` while others queue for the lease; nil when nobody does.
    var waiting: String?

    init(_ lease: ControlLease.Status) {
        let name = lease.holder.name
        // A process's name may start lowercase ("codex"); the line starts a sentence.
        title = name.prefix(1).uppercased() + name.dropFirst() + " controls \(AppIdentity.appName)"
        let spot = lease.holder.place
        place = spot.hasPrefix("/") ? URL(fileURLWithPath: spot).lastPathComponent : spot
        let minutes = lease.secondsLeft / 60, seconds = lease.secondsLeft % 60
        timeLeft = (minutes == 0 ? "\(seconds)s" : "\(minutes)m " + (seconds < 10 ? "0" : "") + "\(seconds)s") + " left"
        waiting = lease.waiting > 0 ? "\(lease.waiting) waiting" : nil
    }

    /// The place, the time left and how many wait, joined by ` · `.
    var detail: String {
        ([place, timeLeft] + [waiting].compactMap(\.self)).joined(separator: " · ")
    }

    /// The banner as one line, for VoiceOver.
    var text: String { "\(title) · \(detail)" }

    /// The banner's button, which takes the app back from the holder.
    static let stop = "Stop"
}

/// The strip across the top of the window while an agent holds the lease:
/// who controls the app, where, the time left, and Stop, which ends the
/// lease and bars that agent for five minutes. Nothing is drawn while the
/// lease is free, or while a screenshot leaves the banner out.
struct LeaseBannerView: View {
    let indicator: LeaseIndicator
    /// Takes the app back from the holder (`ControlServer.stopLease`).
    let stop: () -> Void

    var body: some View {
        // Nothing at all while there's no lease to draw, so the window's
        // layout is as it was. A change to the lease redraws at once.
        if indicator.shown(at: Date()) != nil {
            // Each second, so the countdown ticks.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if let lease = indicator.shown(at: Date()) {
                    strip(LeaseBanner(lease))
                }
            }
        }
    }

    private func strip(_ banner: LeaseBanner) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "cursorarrow.rays")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(banner.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Text(banner.detail)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button(LeaseBanner.stop, role: .destructive, action: stop)
                .controlSize(.small)
                .help("Take the app back. This agent can't control it again for 5 minutes.")
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.orange.opacity(0.16))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(banner.text)
    }
}
