import LabHost
import SwiftUI

/// connect-view V2: connect-flow V6's "Connect an agent" sidebar view, in
/// every state side by side, drawn by the same code with fixed fixtures.
public let variant = LabVariant { Themed { Board() } }

private struct Fixture: Identifiable {
    let id: String
    let caption: String
    let m: Onboard
}

@MainActor private func make(_ setUp: (Onboard) -> Void) -> Onboard {
    let m = Onboard()
    m.page = .connect
    setUp(m)
    return m
}

@MainActor private func linked(_ m: Onboard) { m.cli = .linked; m.cliAttempts = 2 }

@MainActor private let fixtures: [Fixture] = [
    Fixture(id: "a", caption: "a. Nothing set up", m: make { _ in }),
    Fixture(id: "b", caption: "b. After Send with no agent", m: make { m in
        m.banner = .waiting(3)
        for i in m.threads.indices { m.threads[i].state = .waiting }
    }),
    Fixture(id: "c", caption: "c. Command line link failed", m: make { m in
        m.cli = .failed; m.cliAttempts = 1
    }),
    Fixture(id: "d", caption: "d. Skill installing", m: make { m in
        linked(m)
        m.install = .running
        m.logLine = "Installing for Codex (global)…"
    }),
    Fixture(id: "e", caption: "e. Codex picked: skill not detected", m: make { m in
        linked(m)
        m.marks[.cursor] = .installed
        m.chosen = .codex
    }),
    Fixture(id: "f", caption: "f. Pi picked: not detected", m: make { m in
        linked(m)
        m.marks[.codex] = .installed; m.marks[.cursor] = .installed
        m.chosen = .pi
    }),
    Fixture(id: "g", caption: "g. Claude Code picked: Ready", m: make { m in
        linked(m)
        m.marks[.codex] = .installed; m.marks[.cursor] = .installed
    }),
    Fixture(id: "h", caption: "h. Connected", m: make { m in
        linked(m)
        m.marks[.codex] = .installed; m.marks[.cursor] = .installed
        m.listener = Listener(harness: .claude, place: "~/Developer/my-app", isFolder: true, since: "12:04")
        m.phase = .connected
        m.everConnected = true
    }),
    Fixture(id: "i", caption: "i. Reconnecting after relaunch (Codex)", m: make { m in
        linked(m)
        m.marks[.codex] = .installed; m.marks[.cursor] = .installed
        m.listener = Listener(harness: .codex, place: "Herdr pane w2:p5", isFolder: false, since: "12:04")
        m.phase = .reconnecting
        m.everConnected = true
        m.frozenSecondsLeft = 22
    }),
]

private struct Board: View {
    @Environment(\.tok) private var t
    /// Columns read top to bottom, left to right, so the board fits one screen.
    private let columns: [[String]] = [["a", "b"], ["c"], ["d"], ["e"], ["f", "g"], ["h", "i"]]

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(columns, id: \.self) { ids in
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(fixtures.filter { ids.contains($0.id) }) { f in tile(f) }
                }
            }
        }
        .padding(20)
        .fixedSize()
        .background(t.well)
    }

    private func tile(_ f: Fixture) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(f.caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(t.textSecondary)
            ConnectView(m: f.m, scrolls: false)
                .frame(width: 360)
                .fixedSize(horizontal: false, vertical: true)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
    }
}
