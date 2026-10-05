import SwiftUI
import VRLease
import VRWire

/// What the person sees of the lease. The control server, which owns the
/// lease, writes each change here and settles it when it runs out, so the
/// toolbar's lease button follows its start and end with no request. Of the person's
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

/// The toolbar's sign that an agent holds the lease: an icon at the
/// toolbar's far end whose popover says who, where and how long, with
/// Stop, which takes the app back. The window shows it only while the
/// lease is held.
struct LeaseButton: View {
    let indicator: LeaseIndicator
    @State private var shown = false

    var body: some View {
        let title = indicator.banner(at: Date())?.title ?? "An agent controls \(Identity.appName)"
        Button {
            shown.toggle()
        } label: {
            Label {
                Text("Agent in control")
            } icon: {
                Image(systemName: "cursorarrow.rays")
                    .foregroundStyle(Theme.apricot)
            }
        }
        .help(title)
        .accessibilityLabel(title)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            details
        }
    }

    private var details: some View {
        // The countdown ticks only while there's a lease to count down.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let text = indicator.banner(at: context.date) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "cursorarrow.rays")
                            .foregroundStyle(Theme.apricot)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(text.title)
                                .font(.headline)
                            Text(text.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(text.title), \(text.detail)")
                    HStack {
                        Spacer()
                        Button("Stop") {
                            shown = false
                            indicator.stop()
                        }
                        .help("Take the app back. The agent is refused for 5 minutes.")
                    }
                }
                .padding(14)
                .frame(width: 300)
            } else {
                Text("No agent controls \(Identity.appName)")
                    .foregroundStyle(.secondary)
                    .padding(14)
            }
        }
    }
}
