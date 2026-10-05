import SwiftUI

/// The toolbar's sign that an agent holds the lease: one glyph at the
/// window's top right, there only while the lease is held. A click opens a
/// popover with who controls the app, where it runs, the time left, how
/// many wait, and Stop, which takes the app back and bars that agent for
/// five minutes.
struct LeaseButton: View {
    let indicator: LeaseIndicator
    /// Takes the app back from the holder (`ControlServer.stopLease`).
    let stop: () -> Void

    @State private var isShown = false

    var body: some View {
        // Read here, so a change of the lease redraws the button at once.
        let lease = indicator.lease
        // Redrawn each second so the tooltip and the popover's countdown
        // tick, and the glyph goes at the lease's end even before the
        // server's timer settles it.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let status = lease.status(at: context.date) {
                let summary = LeaseIndicator.Summary(status)
                Button {
                    isShown.toggle()
                } label: {
                    Label(summary.title, systemImage: "terminal")
                        .foregroundStyle(Theme.agent)
                }
                .help(summary.text)
                .accessibilityLabel(summary.text)
                .popover(isPresented: $isShown, arrowEdge: .bottom) {
                    LeasePopover(summary: summary) {
                        isShown = false
                        stop()
                    }
                }
            }
        }
    }
}

/// The lease as the popover shows it: who, where, the time left, how many
/// wait, and Stop.
private struct LeasePopover: View {
    let summary: LeaseIndicator.Summary
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.headline)
                Text("An agent drives the player through the video-review command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leading, horizontalSpacing: Theme.gap, verticalSpacing: 4) {
                GridRow {
                    Text("Runs in").foregroundStyle(.secondary)
                    Text(summary.place)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Time left").foregroundStyle(.secondary)
                    Text(summary.timeLeft).font(Theme.timeFont)
                }
                if let waiting = summary.waiting {
                    GridRow {
                        Text("In line").foregroundStyle(.secondary)
                        Text(waiting)
                    }
                }
            }
            .font(.callout)
            HStack {
                Spacer()
                Button("Stop", role: .destructive, action: stop)
                    .help("Take the app back. This agent is refused for 5 minutes.")
            }
        }
        .padding(Theme.edge)
        .frame(width: 300)
    }
}
