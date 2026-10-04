import SwiftUI

/// The one-line strip under the title bar while an agent holds the lease:
/// who controls the app, where it runs, the time left, how many wait, and
/// Stop, which takes the app back and bars that agent for five minutes.
/// Nothing is drawn while the lease is free.
struct LeaseBanner: View {
    let indicator: LeaseIndicator
    /// Takes the app back from the holder (`ControlServer.stopLease`).
    let stop: () -> Void

    var body: some View {
        // Read here, so a change of the lease redraws the strip at once.
        let lease = indicator.lease
        // Redrawn each second so the countdown ticks, and the strip goes at
        // the lease's end even before the server's timer settles it.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let status = lease.status(at: context.date) {
                strip(LeaseIndicator.Banner(status))
            }
        }
    }

    private func strip(_ banner: LeaseIndicator.Banner) -> some View {
        HStack(spacing: Theme.gap) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(banner.title)
                .fontWeight(.medium)
                .lineLimit(1)
            // The place gives way first, cut in the middle, so the countdown stays whole.
            Text(banner.place)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(banner.timeLeft)
                .font(Theme.timeFont)
                .foregroundStyle(.secondary)
                .fixedSize()
            if let waiting = banner.waiting {
                Text(waiting)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Spacer(minLength: 0)
            Button("Stop", role: .destructive, action: stop)
                .controlSize(.small)
                .fixedSize()
                .help("Take the app back. This agent is refused for 5 minutes.")
        }
        .font(.callout)
        .padding(.horizontal, Theme.edge)
        .frame(height: Theme.bannerHeight)
        .background(Color.orange.opacity(0.16))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(banner.text)
    }
}
