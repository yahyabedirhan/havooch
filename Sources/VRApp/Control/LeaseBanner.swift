import SwiftUI
import VRLease
import VRWire

/// What the person sees of the lease. The control server, which owns the
/// lease, writes each change here and settles it when it runs out, so the
/// banner follows its start and end with no request. Of the person's
/// clicks only Stop reaches the lease; the view only reads it.
@MainActor @Observable
final class LeaseIndicator {
    /// The lease as the control server last left it.
    var lease = ControlLease()
    /// The banner's Stop: the control server's `stopLease`.
    @ObservationIgnored var stop: @MainActor () -> Void = {}

    /// The banner's words at `now`: nil while the lease is free.
    func banner(at now: Date) -> LeaseBannerText? {
        lease.status(at: now).map(LeaseBannerText.init)
    }
}

/// The words of the banner, made from the lease as `state` reports it at
/// the moment drawn: "Claude Code controls Video Review" and
/// "/work/repo · 48 s left · 2 waiting".
struct LeaseBannerText: Equatable {
    var title: String
    var detail: String

    init(_ lease: ControlLease.Status) {
        // A process's name may start lowercase ("codex", "an unknown agent"); the line starts a sentence.
        title = lease.holder.prefix(1).uppercased() + lease.holder.dropFirst() + " controls \(Identity.appName)"
        detail = ([lease.place, "\(lease.secondsLeft) s left"] + (lease.waiting > 0 ? ["\(lease.waiting) waiting"] : [])).joined(separator: " · ")
    }
}

/// The banner under the title bar while an agent holds the lease: who, where,
/// how long, and Stop, which takes the app back. It draws nothing while
/// the lease is free.
struct LeaseBanner: View {
    let indicator: LeaseIndicator

    var body: some View {
        // The countdown ticks only while there's a lease to count down.
        if indicator.lease.nextEnd(after: Date()) != nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let text = indicator.banner(at: context.date) {
                    row(text)
                }
            }
        }
    }

    private func row(_ text: LeaseBannerText) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.rays")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(text.title)
                    .fontWeight(.medium)
                Text(text.detail)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                Button("Stop") { indicator.stop() }
                    .controlSize(.small)
                    .help("Take the app back. The agent is refused for 5 minutes.")
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Color.orange.opacity(0.16))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(text.title), \(text.detail)")
            Divider()
        }
    }
}
