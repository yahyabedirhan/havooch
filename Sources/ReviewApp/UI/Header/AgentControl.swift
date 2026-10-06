import ReviewLease
import ReviewWire
import SwiftUI

/// The words shown while an agent holds the lease: "Claude Code controls
/// Havooch", with "havooch · 48s left · 2 waiting". Made from the
/// lease's status at the moment drawn, so the countdown ticks with the time
/// it's made at. The toolbar's agent-control sign and its popover say them.
struct AgentControlWords: Equatable {
    /// "Claude Code controls Havooch".
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

    /// The words as one line, for VoiceOver.
    var text: String { "\(title) · \(detail)" }

    /// The popover's button, which takes the app back from the holder.
    static let stop = "Stop"

    /// What Stop does, on the button and under the popover's words.
    static let stopHelp = "Take the app back. This agent can't control it again for 5 minutes."
}

/// The toolbar's sign that an agent controls the app: one glyph in the
/// control colour, at the head of the window's buttons. It is in the toolbar
/// only while `AgentControlIcon.shown(at:)` has a lease, so nothing shows while
/// the lease is free or while a screenshot leaves it out. A click opens who
/// controls the app, where, the time left, and Stop.
struct AgentControlButton: View {
    let model: AppModel
    let indicator: AgentControlIcon
    /// Takes the app back from the holder (`ControlServer.stopLease`).
    let stop: () -> Void

    @State private var isOpen = false
    /// The time the words are made at, moved on each second while the sign
    /// is in the toolbar, so VoiceOver reads the time left as it is.
    @State private var now = Date()
    /// Set once the sign is in the toolbar, for its one bounce.
    @State private var hasArrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    var body: some View {
        let words = indicator.shown(at: now).map { AgentControlWords($0) }
        Button {
            isOpen.toggle()
        } label: {
            Label {
                Text(words?.title ?? "Agent control")
            } icon: {
                Image(systemName: "cursorarrow.rays")
                    .foregroundStyle(palette[.control])
                    .symbolEffect(.bounce, value: hasArrived)
            }
        }
        .pressedByKeys(in: model) { isOpen.toggle() }
        .help(words.map { "\($0.title). Click for the time left and Stop" } ?? "")
        .accessibilityLabel(words?.text ?? "")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            AgentControlPopover(model: model, indicator: indicator) {
                isOpen = false
                stop()
            }
            .popoverSurface(palette)
        }
        .onAppear {
            if !reduceMotion { hasArrived = true }
        }
        .task {
            // Ends when the sign leaves the toolbar, so nothing ticks
            // while no agent holds the lease.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
            }
        }
    }
}

/// What the agent-control sign opens: who controls the app, where it runs,
/// the time left ticking each second, how many wait, and Stop, which ends
/// the lease and bars that agent for five minutes.
private struct AgentControlPopover: View {
    let model: AppModel
    let indicator: AgentControlIcon
    let stop: () -> Void

    static let width: CGFloat = 300
    @Environment(\.palette) private var palette

    var body: some View {
        // Each second, so the countdown ticks.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if let lease = indicator.shown(at: Date()) {
                content(AgentControlWords(lease))
            }
        }
    }

    private func content(_ words: AgentControlWords) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.rays")
                    .font(.title3)
                    .foregroundStyle(palette[.control])
                    .frame(width: 32, height: 32)
                    .background(palette[.control].opacity(0.16), in: Circle())
                    .accessibilityHidden(true)
                Text(words.title)
                    .font(.headline)
                    .foregroundStyle(palette[.textPrimary])
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label(words.place, systemImage: "terminal")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Label(words.timeLeft, systemImage: "timer")
                    .monospacedDigit()
                if let waiting = words.waiting {
                    Label(waiting, systemImage: "person.2")
                }
            }
            .font(.callout)
            .foregroundStyle(palette[.textSecondary])
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette[.well], in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(AgentControlWords.stopHelp)
                    .font(.caption)
                    .foregroundStyle(palette[.textTertiary])
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(AgentControlWords.stop, role: .destructive, action: stop)
                    .controlSize(.small)
                    .pressedByKeys(in: model, action: stop)
                    .help(AgentControlWords.stopHelp)
            }
        }
        .padding(16)
        .frame(width: Self.width)
        .foregroundStyle(palette[.textPrimary])
        .accessibilityElement(children: .contain)
        .accessibilityLabel(words.text)
    }
}
