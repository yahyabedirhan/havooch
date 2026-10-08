import AppKit
import LabHost
import Observation
import SwiftUI

// The integrated connect flow: one "Connect an agent" view in the sidebar,
// opened from the presence pill, from Send with no listener, and from the
// header; plus an optional tour. Pieces copied from setup-view V1 (window
// shell, status view), listener-area V1 (step content, pill, listener),
// send-without-listener V2 (thread rows, outbox) and first-run V3 (coach).

// MARK: - Tokens (Havooch's Default Light / Default Dark themes)

func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
    Color(
        .sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255, opacity: alpha
    )
}

struct Tok {
    let dark: Bool
    var window: Color { Color(nsColor: .windowBackgroundColor) }
    var field: Color { Color(nsColor: .textBackgroundColor) }
    var separator: Color { Color(nsColor: .separatorColor) }
    var popoverBorder: Color { dark ? hex(0xFFFFFF, 0.16) : hex(0x000000, 0.08) }
    var letterbox: Color { dark ? hex(0x000000) : hex(0x151412) }
    var well: Color { dark ? hex(0xFFFFFF, 0.04) : hex(0x000000, 0.04) }
    var wellStrong: Color { dark ? hex(0xFFFFFF, 0.08) : hex(0x000000, 0.07) }
    var controlHover: Color { dark ? hex(0xFFFFFF, 0.08) : hex(0x000000, 0.06) }
    var track: Color { dark ? hex(0x45423D) : hex(0xD8D2C6) }
    var textPrimary: Color { dark ? hex(0xECE9E3) : hex(0x2B2925) }
    var textSecondary: Color { dark ? hex(0xADA79D) : hex(0x6B665D) }
    var textTertiary: Color { dark ? hex(0x7D776E) : hex(0x9A948A) }
    var textOnAccent: Color { dark ? hex(0x1A1918) : hex(0xFFFFFF) }
    var accent: Color { dark ? hex(0x9DB6DD) : hex(0x5B7DB1) }
    /// Filled buttons: white text reads at 5.5:1 or more in both modes.
    var accentFill: Color { hex(0x48689D) }
    var amber: Color { dark ? hex(0xE3BF84) : hex(0xB98A45) }
    var done: Color { dark ? hex(0x9CCBA8) : hex(0x5E9771) }
    var failed: Color { dark ? hex(0xDE9C84) : hex(0xB5654F) }
    var absent: Color { dark ? hex(0x7D776E) : hex(0x9A948A) }
    var stateQueued: Color { dark ? hex(0x958F85) : hex(0x8E897F) }
    var stateSent: Color { dark ? hex(0xA7ACB4) : hex(0x8A8F98) }
    var shadow: Color { hex(0x000000, dark ? 0.45 : 0.2) }
}

private struct TokKey: EnvironmentKey {
    static let defaultValue = Tok(dark: false)
}

extension EnvironmentValues {
    var tok: Tok {
        get { self[TokKey.self] }
        set { self[TokKey.self] = newValue }
    }
}

/// Fills `\.tok` from the appearance.
struct Themed<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .environment(\.tok, Tok(dark: scheme == .dark))
            .environment(\.locale, Locale(identifier: "en_US"))
    }
}

/// Code names shown in monospace inside running text: the command and the skill.
enum Code {
    static var cli: Text { Text("havooch").monospaced() }
    static var skill: Text { Text("/havooch\u{2011}mate").monospaced() }
}

/// A one-line label with a code name in a soft chip: "havooch command line".
struct CodeLabel: View {
    let code: String
    let rest: String
    @Environment(\.tok) private var t

    var body: some View {
        HStack(spacing: 4) {
            Text(code)
                .monospaced()
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(t.wellStrong, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(rest)
        }
        .fixedSize()
    }

    static var cli: CodeLabel { CodeLabel(code: "havooch", rest: "command line") }
    static var skill: CodeLabel { CodeLabel(code: "/havooch-mate", rest: "skill") }
}

struct Hairline: View {
    @Environment(\.tok) private var t
    var body: some View { Rectangle().fill(t.separator).frame(height: 1) }
}

// MARK: - Harnesses and logos

enum Harness: String, CaseIterable, Identifiable {
    case claude, codex, cursor, pi, opencode
    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .pi: "Pi"
        case .opencode: "OpenCode"
        }
    }

    var short: String { self == .claude ? "Claude" : name }
    var hasDarkLogo: Bool { self == .opencode }
}

@MainActor
enum Logos {
    static let folder = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Developer/yahyabedirhan/havooch/Packaging/AgentLogos", isDirectory: true)
    static var cache: [String: NSImage] = [:]

    static func image(_ harness: Harness, dark: Bool) -> NSImage? {
        let name = harness.hasDarkLogo && dark ? harness.rawValue + "-dark" : harness.rawValue
        if let hit = cache[name] { return hit }
        guard let image = NSImage(contentsOf: folder.appendingPathComponent(name + ".pdf")) else { return nil }
        cache[name] = image
        return image
    }
}

/// The harness logo, like Havooch's `AgentMark`; a monogram when the file is missing.
struct Mark: View {
    let harness: Harness
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.tok) private var t

    var body: some View {
        Group {
            if let image = Logos.image(harness, dark: scheme == .dark) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Text(String(harness.name.prefix(1)))
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(t.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

/// The Havooch cat mark, drawn: a head with two ears.
struct CatMark: View {
    var size: CGFloat = 22
    @Environment(\.tok) private var t

    var body: some View {
        ZStack {
            Path { p in
                let s = size
                p.move(to: CGPoint(x: s * 0.14, y: s * 0.46))
                p.addLine(to: CGPoint(x: s * 0.2, y: s * 0.08))
                p.addLine(to: CGPoint(x: s * 0.42, y: s * 0.3))
                p.addLine(to: CGPoint(x: s * 0.58, y: s * 0.3))
                p.addLine(to: CGPoint(x: s * 0.8, y: s * 0.08))
                p.addLine(to: CGPoint(x: s * 0.86, y: s * 0.46))
                p.addQuadCurve(to: CGPoint(x: s * 0.14, y: s * 0.46), control: CGPoint(x: s * 0.5, y: s * 1.12))
            }
            .fill(t.textPrimary)
            HStack(spacing: size * 0.18) {
                Capsule().fill(t.window).frame(width: size * 0.09, height: size * 0.16)
                Capsule().fill(t.window).frame(width: size * 0.09, height: size * 0.16)
            }
            .offset(y: size * 0.1)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Model

/// What Havooch knows about a harness. `installed` and `missing` read the
/// harness's user skills folder, so they are facts. `notDetected` is a best
/// guess: Havooch didn't find the harness, which may still be there.
enum SkillMark { case installed, missing, notFound }

/// The status under the agent picker, from what Havooch can know.
enum Readiness: Equatable { case checking, ready, notInstalled, notDetected }
enum CLIState: Equatable { case notLinked, linking, failed, linked }
enum InstallState: Equatable { case idle, running, cancelled, done }
enum Phase: Equatable { case none, connected, reconnecting }
enum SidePage: Equatable { case threads, connect }
enum ThreadState: Equatable { case queued, waiting, sent, working, done }

enum TourStep: Int, CaseIterable {
    case tools, connect, write, send, reply
    static let count = 5
}

enum Banner: Equatable {
    case waiting(Int)
    case delivered(Int, Harness)
}

struct ThreadItem: Identifiable, Equatable {
    let id: Int
    let time: String
    let words: String
    let hue: Double
    let answer: String
    var state: ThreadState = .queued
    var replied = false
}

struct Listener: Equatable {
    var harness: Harness
    var place: String
    var isFolder: Bool
    var since: String
}

@MainActor @Observable
final class Onboard {
    var cli: CLIState = .notLinked
    var cliAttempts = 0
    var marks: [Harness: SkillMark] = Onboard.startMarks
    var install: InstallState = .idle
    var logLine = ""
    var npxFound = true
    var repoOpen = false
    var skillExpanded = true
    var cliExpanded = true
    var chosen: Harness = .claude
    var checking = false
    var installingOne: Harness?
    var copied: String?
    var phase: Phase = .none
    var listener: Listener?
    var everConnected = false
    var reconnectStart = Date()
    var copiedPath = false
    var threads: [ThreadItem] = Onboard.startThreads
    var page: SidePage = .threads
    var banner: Banner?
    var draft = ""
    var tourOpen = false
    var tourStep: TourStep = .tools
    var tourFinished = false
    var menuOpen = false
    private var epoch = 0
    private var installTask: Task<Void, Never>?

    static let video = "onboarding-cut-v3.mp4"
    static let globalCommand = "npx skills add yahyabedirhan/havooch --skill havooch-mate -g"
    static let repoCommand = "npx skills add yahyabedirhan/havooch --skill havooch-mate"
    static let linkPath = "~/.local/bin/havooch"
    static let linkCommand = "ln -sf /Applications/Havooch.app/Contents/Helpers/havooch ~/.local/bin/havooch"
    static let repoNote = "Havooch checks each agent's user skills folder. A skill installed in a repo isn't detected, and still works there."
    static func agentCommand(_ harness: Harness) -> String { globalCommand + " -a " + harness.rawValue }
    static let startMarks: [Harness: SkillMark] = [
        .claude: .installed, .codex: .missing, .cursor: .missing, .pi: .notFound, .opencode: .installed,
    ]
    static let startThreads = [
        ThreadItem(id: 1, time: "0:04", words: "Logo comes in too late", hue: 0.62,
                   answer: "Moved the logo in 6 frames earlier in Intro.swift. Reload to check."),
        ThreadItem(id: 2, time: "0:14", words: "The cursor jumps here", hue: 0.08,
                   answer: "Smoothed the cursor path between 0:13 and 0:15."),
        ThreadItem(id: 3, time: "0:21", words: "End card should hold longer", hue: 0.78,
                   answer: "The end card now holds for 3 s."),
    ]

    /// The listen prompt, in the picked harness's own way of calling a skill.
    var prompt: String { Self.prompt(for: chosen) }
    static func prompt(for harness: Harness) -> String {
        let ask = "listen for my feedback on \(video)"
        return switch harness {
        case .claude, .cursor: "/havooch-mate " + ask
        case .codex: "$havooch-mate " + ask
        case .pi: "/skill:havooch-mate " + ask
        case .opencode: "Use the havooch-mate skill to " + ask
        }
    }

    var missing: [Harness] { Harness.allCases.filter { marks[$0] == .missing } }
    var found: [Harness] { Harness.allCases.filter { marks[$0] != .notFound } }
    var cliDone: Bool { cli == .linked }
    var skillDone: Bool { missing.isEmpty }
    var readiness: Readiness {
        if checking { return .checking }
        switch marks[chosen] ?? .notFound {
        case .installed: return .ready
        case .missing: return .notInstalled
        case .notFound: return .notDetected
        }
    }
    var remaining: Int { (cliDone ? 0 : 1) + (skillDone ? 0 : 1) + (everConnected ? 0 : 1) }
    var setupComplete: Bool { remaining == 0 }
    /// The tour button shows while setup is incomplete, or while its panel is open.
    var showsTourButton: Bool { !setupComplete || tourOpen }
    var queuedCount: Int { threads.filter { $0.state == .queued }.count }
    var waitingCount: Int { threads.filter { $0.state == .waiting }.count }
    var replied: Bool { threads.contains { $0.replied } }

    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        default: names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }

    private func later(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        let mine = epoch
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard mine == self.epoch else { return }
            action()
        }
    }

    // Pages

    func openConnect() {
        menuOpen = false
        page = .connect
    }

    func back() { page = .threads }

    func pillClicked() { page = page == .connect ? .threads : .connect }

    // Command line

    func link() {
        cli = .linking
        later(0.7) {
            self.cliAttempts += 1
            // The first try meets a file in the way, so the copy state shows; the next one links.
            self.cli = self.cliAttempts == 1 ? .failed : .linked
            if self.cli == .linked { self.cliExpanded = false }
            self.checkTools()
        }
    }

    // Skill

    func startInstall() {
        guard npxFound, !missing.isEmpty else { return }
        install = .running
        let targets = missing
        let mine = epoch
        installTask = Task { @MainActor in
            var lines = ["$ " + Self.globalCommand, "Resolving yahyabedirhan/havooch…", "Fetching skill havooch-mate (12 files)…"]
            lines += targets.map { "Installing for \($0.name) (global)…" }
            for line in lines {
                logLine = line
                try? await Task.sleep(for: .milliseconds(1100))
                if Task.isCancelled || mine != epoch { return }
            }
            for target in targets { marks[target] = .installed }
            logLine = "Installed for " + Self.list(targets.map(\.name))
            install = .done
            skillExpanded = false
            checkTools()
        }
    }

    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
        install = .cancelled
        logLine = "Cancelled. Nothing was installed."
    }

    /// Picking a harness checks its skill folder before the prompt shows.
    func choose(_ harness: Harness) {
        chosen = harness
        checking = true
        later(0.45) { self.checking = false }
    }

    func installOne(_ harness: Harness) {
        guard installingOne == nil else { return }
        installingOne = harness
        later(1.4) {
            self.marks[harness] = .installed
            self.installingOne = nil
            if self.skillDone { self.skillExpanded = false }
            self.checkTools()
        }
    }

    func copy(_ id: String) {
        copied = id
        later(1.6) { if self.copied == id { self.copied = nil } }
    }

    func copyPath() {
        copiedPath = true
        later(1.6) { self.copiedPath = false }
    }

    // Agent

    func agentConnects() {
        let harness = chosen
        listener = Listener(
            harness: harness,
            place: harness == .codex ? "Herdr pane w2:p5" : "~/Developer/my-app",
            isFolder: harness != .codex,
            since: "12:04"
        )
        phase = .connected
        everConnected = true
        // Lab: show the connect view, so the connected state is in sight.
        page = .connect
        let waiting = waitingCount
        if waiting > 0 {
            for i in threads.indices where threads[i].state == .waiting { threads[i].state = .sent }
            banner = .delivered(waiting, harness)
            work()
        }
        if tourOpen, tourStep == .connect { later(0.9) { self.go(.write) } }
    }

    func disconnect() {
        listener = nil
        phase = .none
    }

    func relaunch() {
        if listener == nil { listener = Listener(harness: .claude, place: "~/Developer/my-app", isFolder: true, since: "12:04") }
        everConnected = true
        phase = .reconnecting
        reconnectStart = .now
        page = .threads
        banner = nil
        menuOpen = false
    }

    /// The board holds the countdown still.
    var frozenSecondsLeft: Int?
    func secondsLeft(at date: Date) -> Int { frozenSecondsLeft ?? max(0, 30 - Int(date.timeIntervalSince(reconnectStart))) }

    // Threads

    func queueDraft() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let next = (threads.map(\.id).max() ?? 0) + 1
        threads.append(ThreadItem(id: next, time: "0:42", words: text, hue: 0.4, answer: "Done: the title is now 44 pt semibold. Reload to check."))
        draft = ""
        if tourOpen, tourStep == .write { go(.send) }
    }

    func send() {
        guard queuedCount > 0 else { return }
        menuOpen = false
        if phase == .connected {
            for i in threads.indices where threads[i].state == .queued { threads[i].state = .sent }
            work()
        } else {
            for i in threads.indices where threads[i].state == .queued { threads[i].state = .waiting }
            banner = .waiting(waitingCount)
            page = .connect
        }
        if tourOpen, tourStep == .send { tourStep = .reply }
    }

    private func work() {
        later(1.2) {
            for i in self.threads.indices where self.threads[i].state == .sent { self.threads[i].state = .working }
        }
        later(3.6) {
            for i in self.threads.indices where self.threads[i].state == .working {
                self.threads[i].state = .done
                self.threads[i].replied = true
            }
        }
    }

    // Tour

    func toggleTour() {
        menuOpen = false
        tourOpen.toggle()
        if tourOpen { go(tourStep) }
    }

    func go(_ step: TourStep) {
        tourStep = step
        switch step {
        case .tools, .connect: page = .connect
        case .write, .send: page = .threads
        case .reply: if waitingCount == 0 { page = .threads }
        }
    }

    func finishTour() {
        tourFinished = true
        tourOpen = false
    }

    private func checkTools() {
        if cliDone, skillDone, tourOpen, tourStep == .tools { later(0.8) { self.go(.connect) } }
    }

    func reset() {
        epoch += 1
        installTask?.cancel()
        cli = .notLinked
        cliAttempts = 0
        marks = Self.startMarks
        install = .idle
        logLine = ""
        repoOpen = false
        skillExpanded = true
        cliExpanded = true
        chosen = .claude
        checking = false
        installingOne = nil
        copied = nil
        phase = .none
        listener = nil
        everConnected = false
        copiedPath = false
        threads = Self.startThreads
        page = .threads
        banner = nil
        draft = ""
        tourOpen = false
        tourStep = .tools
        tourFinished = false
        menuOpen = false
    }
}

// MARK: - Small parts

struct SmallButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    @Environment(\.tok) private var t
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(prominent ? Color.white : (destructive ? t.failed : t.textPrimary))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prominent ? t.accentFill : (destructive ? t.failed.opacity(0.12) : t.wellStrong))
            )
            .opacity(configuration.isPressed ? 0.7 : (enabled ? 1 : 0.45))
            .contentShape(Rectangle())
    }
}

/// A command or prompt with a copy action. The text runs full width on top;
/// a footer bar under a hairline holds the copy button. Copying changes no state.
struct CopyBox: View {
    let m: Onboard
    let id: String
    let text: String
    var mono = true
    /// The footer's button title; a prompt or a command by default.
    var action: String?
    @Environment(\.tok) private var t

    var body: some View {
        let isCopied = m.copied == id
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(mono ? .system(size: 11.5, weight: .medium, design: .monospaced) : .body)
                .lineSpacing(mono ? 2 : 1)
                .foregroundStyle(t.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.top, 10)
                .padding(.bottom, 10)
            Rectangle().fill(t.separator.opacity(0.6)).frame(height: 0.5)
            HStack(spacing: 6) {
                Image(systemName: mono ? "terminal" : "text.bubble")
                    .font(.system(size: 10, weight: .medium))
                Text(mono ? "Terminal" : "Prompt")
                    .font(.caption2.weight(.medium))
                Spacer(minLength: 6)
                Button {
                    m.copy(id)
                } label: {
                    Label(isCopied ? "Copied" : (action ?? (mono ? "Copy Command" : "Copy Prompt")),
                          systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(isCopied ? t.done : t.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(isCopied ? t.done.opacity(0.14) : t.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .fixedSize()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .labID(id)
                .help(mono ? "Copy the command" : "Copy the prompt")
            }
            .foregroundStyle(t.textTertiary)
            .padding(.leading, 11)
            .padding(.trailing, 6)
            .frame(height: 30)
            .background(t.well)
        }
        .background(t.field.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(t.separator.opacity(0.7), lineWidth: 0.5))
    }
}

/// A section's tile: an SF Symbol on a soft square, like a System Settings row.
struct Tile: View {
    let symbol: String
    var side: CGFloat = 22
    var tint: Color?
    @Environment(\.tok) private var t

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: side * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(tint ?? t.accent, in: RoundedRectangle(cornerRadius: side * 0.26, style: .continuous))
    }
}

/// A trailing status: a glyph and a word in its tone.
struct StatusTag: View {
    enum Tone { case done, attention, failed, neutral }
    let tone: Tone
    let text: String
    @Environment(\.tok) private var t

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).imageScale(.small)
            Text(text)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }

    private var symbol: String {
        switch tone {
        case .done: "checkmark.circle.fill"
        case .attention: "exclamationmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .neutral: "circle.dashed"
        }
    }

    private var color: Color {
        switch tone {
        case .done: t.done
        case .attention: t.amber
        case .failed: t.failed
        case .neutral: t.textTertiary
        }
    }
}

/// The tour's pulsing ring around the part of the window a step is about.
/// `radius` is the highlighted content's corner radius; the ring sits `pad`
/// points outside it, with its radius grown by the same amount, so it never
/// touches the content.
struct CoachRing: ViewModifier {
    let on: Bool
    let radius: CGFloat
    var pad: CGFloat = 9
    @State private var pulse = false
    @Environment(\.tok) private var t

    func body(content: Content) -> some View {
        content
            .overlay {
                if on {
                    RoundedRectangle(cornerRadius: radius + pad, style: .continuous)
                        .strokeBorder(t.accent, lineWidth: 2)
                        .padding(-pad)
                        .shadow(color: t.accent.opacity(pulse ? 0.7 : 0.2), radius: pulse ? 8 : 2)
                        .allowsHitTesting(false)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
                        }
                        .onDisappear { pulse = false }
                }
            }
    }
}

extension View {
    func coachRing(_ on: Bool, radius: CGFloat = 8, pad: CGFloat = 9) -> some View {
        modifier(CoachRing(on: on, radius: radius, pad: pad))
    }
}


// MARK: - Thread list (Havooch's real look, from send-without-listener)

struct Thumb: View {
    let hue: Double
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hue: hue, saturation: 0.55, brightness: 0.42),
                         Color(hue: hue + 0.06, saturation: 0.65, brightness: 0.22)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.85)).frame(width: 26, height: 8).offset(x: -14, y: -6)
            RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.4)).frame(width: 40, height: 4).offset(x: -7, y: 6)
        }
        .frame(width: 88, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct StateChip: View {
    let state: ThreadState
    @Environment(\.tok) private var t

    var body: some View {
        let (glyph, name, colour): (String, String, Color) = switch state {
        case .queued: ("circle.dashed", "Queued", t.stateQueued)
        case .waiting: ("clock", "Waiting", t.amber)
        case .sent: ("arrow.up.circle.fill", "Sent", t.stateSent)
        case .working: ("ellipsis.circle.fill", "Working", t.amber)
        case .done: ("checkmark.circle.fill", "Done", t.done)
        }
        HStack(spacing: 3) {
            Image(systemName: glyph).imageScale(.small)
            Text(name)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(colour)
        .lineLimit(1)
        .fixedSize()
    }
}

struct RowView: View {
    let thread: ThreadItem
    let agent: Harness?
    @Environment(\.tok) private var t
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Thumb(hue: thread.hue)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("#\(thread.id)").font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(t.textPrimary)
                    Text(thread.time).font(.callout.monospacedDigit()).foregroundStyle(t.textSecondary)
                    StateChip(state: thread.state)
                    Spacer(minLength: 4)
                    Text("now").font(.subheadline).foregroundStyle(t.textTertiary).fixedSize()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(t.textTertiary)
                }
                .frame(height: 18)
                Group {
                    if thread.replied, let agent {
                        Text(agent.name + ": ").foregroundStyle(t.accent) + Text(thread.answer)
                    } else {
                        Text("You: ").foregroundStyle(t.textTertiary) + Text(thread.words)
                    }
                }
                .font(.callout)
                .foregroundStyle(t.textSecondary)
                .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovered ? t.controlHover : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovered = $0 }
    }
}

struct GroupHeaderView: View {
    let glyph: String
    let title: String
    let count: Int
    let colour: Color
    var hint: String?
    @Environment(\.tok) private var t
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: glyph).imageScale(.small).foregroundStyle(colour)
            Text(title.uppercased()).fontWeight(.semibold).tracking(0.2)
            Text("\(count)").monospacedDigit()
            Spacer(minLength: 4)
            if let hint { Text(hint) }
        }
        .font(.subheadline)
        .foregroundStyle(t.textTertiary)
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ThreadListView: View {
    let m: Onboard
    @Environment(\.tok) private var t

    private struct TGroup: Identifiable {
        let id: String
        let glyph: String
        let colour: Color
        let hint: String?
        let items: [ThreadItem]
    }

    private var groups: [TGroup] {
        let by: (Set<ThreadState>) -> [ThreadItem] = { s in m.threads.filter { s.contains($0.state) } }
        return [
            TGroup(id: "Waiting for an agent", glyph: "clock", colour: t.amber, hint: nil, items: by([.waiting])),
            TGroup(id: "Queued", glyph: "circle.dashed", colour: t.stateQueued, hint: "⌘↩ sends them all", items: by([.queued])),
            TGroup(id: "With agent", glyph: "ellipsis.circle.fill", colour: t.amber, hint: nil, items: by([.sent, .working])),
            TGroup(id: "Done", glyph: "checkmark.circle.fill", colour: t.done, hint: nil, items: by([.done])),
        ].filter { !$0.items.isEmpty }
    }

    private var summary: String {
        var parts = ["\(m.threads.count) threads"]
        if m.waitingCount > 0 { parts.append("\(m.waitingCount) waiting for an agent") }
        if m.queuedCount > 0 { parts.append("\(m.queuedCount) queued") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let firstReplied = m.threads.first { $0.replied }?.id
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Threads").font(.title2.weight(.bold)).foregroundStyle(t.textPrimary)
                Text(summary).font(.subheadline.monospacedDigit()).foregroundStyle(t.textTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        GroupHeaderView(glyph: group.glyph, title: group.id, count: group.items.count, colour: group.colour, hint: group.hint)
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, thread in
                            RowView(thread: thread, agent: m.listener?.harness ?? m.chosen)
                                .overlay(alignment: .top) {
                                    if index > 0 { Hairline().padding(.leading, 10 + 88 + 11).padding(.trailing, 10) }
                                }
                                .coachRing(m.tourOpen && m.tourStep == .reply && thread.id == firstReplied, radius: 10, pad: 6)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .animation(.smooth(duration: 0.25), value: m.threads)
            }
        }
    }
}

/// The composer at the sidebar's foot: the target line and the field.
struct ComposerView: View {
    @Bindable var m: Onboard
    @Environment(\.tok) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "plus.bubble").imageScale(.small)
                Text("New thread at 0:42").fontWeight(.medium).foregroundStyle(t.textPrimary)
                Spacer(minLength: 4)
                Label("General", systemImage: "globe")
                    .font(.subheadline)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(t.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.separator))
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(t.textSecondary)
            .frame(height: 22)
            HStack(spacing: 8) {
                TextField("Write on this frame…", text: $m.draft)
                    .textFieldStyle(.plain)
                    .onSubmit { m.queueDraft() }
                    .labID("composer")
                Text("↩ queues")
                    .font(.caption)
                    .foregroundStyle(t.textTertiary)
                    .fixedSize()
            }
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background(t.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(t.separator))
            .coachRing(m.tourOpen && m.tourStep == .write, radius: 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Hairline() }
    }
}

// MARK: - Footer and presence pill (Havooch's real footer)

struct Pill: View {
    let m: Onboard
    let pressed: Bool
    @State private var hover = false
    @Environment(\.tok) private var t

    private var colour: Color {
        switch m.phase {
        case .none: t.absent
        case .connected: t.done
        case .reconnecting: t.amber
        }
    }

    private var title: String {
        switch m.phase {
        case .none: "No agent"
        case .connected: "Listening"
        case .reconnecting: "Reconnecting"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if let listener = m.listener, m.phase != .none {
                Mark(harness: listener.harness, size: 14)
                    .saturation(m.phase == .reconnecting ? 0 : 1)
                    .opacity(m.phase == .reconnecting ? 0.6 : 1)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right.slash").symbolRenderingMode(.hierarchical)
            }
            Text(title)
            Image(systemName: "chevron.up")
                .font(.system(size: 8, weight: .bold))
                .rotationEffect(.degrees(pressed ? 180 : 0))
                .opacity(hover || pressed ? 0.9 : 0.55)
        }
        .font(.callout.weight(.medium))
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(colour)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(colour.opacity(hover || pressed ? 0.24 : 0.14), in: Capsule())
        .contentShape(Capsule())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

struct FooterView: View {
    let m: Onboard
    @Environment(\.tok) private var t

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { m.pillClicked() } label: { Pill(m: m, pressed: m.page == .connect) }
                    .buttonStyle(.plain)
                    .labID("pill")
                    .help(m.listener == nil ? "Connect an agent" : "Show the listener")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(activity(context.date))
                        .font(.callout)
                        .foregroundStyle(m.phase == .none ? t.textTertiary : t.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(m.waitingCount > 0 ? "\(m.waitingCount) waiting" : "\(m.queuedCount) queued")
                .font(.callout.monospacedDigit())
                .foregroundStyle(m.waitingCount > 0 ? t.amber : t.textSecondary)
                .lineLimit(1)
                .fixedSize()
            Button("Send") { m.send() }
                .buttonStyle(.borderedProminent)
                .tint(t.accentFill)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(m.queuedCount == 0)
                .fixedSize()
                .labID("send")
                .help("Send every queued message (⌘↩)")
                .coachRing(m.tourOpen && m.tourStep == .send, radius: 6)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(t.window)
        .overlay(alignment: .top) { Hairline() }
    }

    private func activity(_ date: Date) -> String {
        switch m.phase {
        case .none: ""
        case .connected: m.listener?.harness.name ?? ""
        case .reconnecting: "\(m.secondsLeft(at: date)) s"
        }
    }
}

// MARK: - The tour (first-run V3's coach panel)

struct TourPanel: View {
    let m: Onboard
    @Environment(\.tok) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<TourStep.count, id: \.self) { i in
                    Capsule()
                        .fill(i < m.tourStep.rawValue ? t.done : i == m.tourStep.rawValue ? t.accent : t.wellStrong)
                        .frame(width: i == m.tourStep.rawValue ? 18 : 7, height: 7)
                }
                Text("Step \(m.tourStep.rawValue + 1) of \(TourStep.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(t.textSecondary)
                    .padding(.leading, 4)
                Spacer()
                Button { m.tourOpen = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(t.textTertiary)
                        .frame(width: 18, height: 18)
                        .background(t.controlHover, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .labID("tourClose")
                .help("Close the tour. It keeps your place.")
            }
            Text(title).font(.headline).foregroundStyle(t.textPrimary)
            content
        }
        .padding(14)
        .frame(width: 380, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThickMaterial)
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.window.opacity(0.85))
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.accent.opacity(0.06))
        }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.accent.opacity(0.35), lineWidth: 1))
        .shadow(color: t.shadow, radius: 16, y: 6)
        .animation(.smooth(duration: 0.25), value: m.tourStep)
    }

    private var agentName: String { m.listener?.harness.name ?? "your agent" }

    private var title: String {
        switch m.tourStep {
        case .tools: "Give your agent two tools"
        case .connect: "Connect your agent"
        case .write: "Write on a frame"
        case .send: "Send them to \(agentName)"
        case .reply:
            if m.replied { "\(agentName) answered in the player" }
            else if m.waitingCount > 0 { "Your messages wait for an agent" }
            else { "\(agentName) is on it" }
        }
    }

    private func para(_ text: String) -> some View { para(Text(text)) }

    private func para(_ text: Text) -> some View {
        text
            .font(.callout)
            .foregroundStyle(t.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func check(_ done: Bool, _ text: String) -> some View { check(done, Text(text)) }

    private func check(_ done: Bool, _ text: some View) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? t.done : t.textTertiary)
            text.font(.callout.weight(.medium)).foregroundStyle(done ? t.textPrimary : t.textSecondary)
        }
    }

    private func next(_ title: String, to step: TourStep) -> some View {
        Button(title) { m.go(step) }
            .controlSize(.small)
            .labID("tourNext")
    }

    private var skip: some View {
        Button("Skip Tour") { m.finishTour() }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(t.textSecondary)
            .labID("tourSkip")
    }

    @ViewBuilder private var content: some View {
        switch m.tourStep {
        case .tools:
            para(Text("Link the \(Code.cli) command line and install the \(Code.skill) skill. Both are in the sidebar, in the ring."))
            HStack(spacing: 14) {
                check(m.cliDone, CodeLabel.cli)
                check(m.skillDone, CodeLabel.skill)
            }
            HStack { skip; Spacer(); next(m.cliDone && m.skillDone ? "Next" : "Later", to: .connect) }
        case .connect:
            para("Pick your agent and copy the prompt. Paste it in your agent's session; Havooch shows it here once it listens.")
            check(m.phase == .connected, m.phase == .connected ? "\(agentName) is listening" : "No agent is listening yet")
            HStack { skip; Spacer(); next(m.phase == .connected ? "Next" : "Later", to: .write) }
        case .write:
            para("Pause the video, or drag a box on the frame, then write in the field under the threads. Return queues it.")
            HStack {
                skip
                Spacer()
                Button("Write an Example") { m.draft = "Make the title bigger and bolder" }
                    .controlSize(.small)
                    .labID("tourExample")
                next("Next", to: .send)
            }
        case .send:
            para(m.phase == .connected
                 ? "Press ⌘↩ or click Send: every queued message goes to \(agentName) at once, with the frame, the box and the transcript."
                 : "No agent listens yet. Send anyway: the messages wait in the outbox and go out when one connects.")
            HStack { skip; Spacer() }
        case .reply:
            if m.replied {
                para("It worked in its repo with its own skills and answered on each thread. Open a thread to reply.")
                HStack {
                    Spacer()
                    Button("Finish") { m.finishTour() }
                        .buttonStyle(.borderedProminent).tint(t.accentFill)
                        .controlSize(.small)
                        .labID("tourFinish")
                }
            } else if m.waitingCount > 0 {
                para("Nothing is lost. Connect an agent in the sidebar and they go out at once.")
                HStack { skip; Spacer() }
            } else {
                para("It got the batch and works in its repo. Each thread turns Done when it answers.")
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Working…").font(.callout).foregroundStyle(t.textSecondary)
                    Spacer()
                    skip
                }
            }
        }
    }
}

// MARK: - The window

struct HeaderAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// A glyph button in the header's floating group.
struct GroupButton<Badge: View>: View {
    let symbol: String
    var isOn = false
    let id: String
    let help: String
    @ViewBuilder var badge: Badge
    let action: () -> Void
    @State private var hover = false
    @Environment(\.tok) private var t

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isOn ? t.accent : t.textPrimary)
                .frame(width: 32, height: 28)
                .background(isOn || hover ? t.controlHover : .clear, in: Capsule())
                .overlay(alignment: .topTrailing) { badge }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .labID(id)
        .help(help)
    }
}

extension GroupButton where Badge == EmptyView {
    init(symbol: String, isOn: Bool = false, id: String, help: String, action: @escaping () -> Void) {
        self.init(symbol: symbol, isOn: isOn, id: id, help: help, badge: { EmptyView() }, action: action)
    }
}

struct AmberDot: View {
    @Environment(\.tok) private var t
    var body: some View {
        Circle()
            .fill(t.amber)
            .frame(width: 8, height: 8)
            .overlay(Circle().strokeBorder(t.window, lineWidth: 1.5))
            .offset(x: -4, y: 3)
    }
}

/// The player window: header with title and floating controls, the stage
/// with the tour panel over it, the sidebar, and the lab-only strip.
struct WindowShell<Leading: View, Grouped: View, Over: View>: View {
    @Bindable var m: Onboard
    @ViewBuilder var leading: Leading
    @ViewBuilder var grouped: Grouped
    @ViewBuilder var overlay: (CGRect) -> Over
    @Environment(\.tok) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                stage
                Divider()
                sidebar.frame(width: 360)
            }
            LabStrip(m: m)
        }
        .frame(width: 1180, height: 720)
        .ignoresSafeArea()
        .background(t.window)
        .overlayPreferenceValue(HeaderAnchorKey.self) { anchor in
            GeometryReader { proxy in
                overlay(anchor.map { proxy[$0] } ?? .zero)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            CatMark(size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Label(Onboard.video, systemImage: "film")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(t.textPrimary)
                Label("~/Movies/Reviews/Havooch", systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(t.textSecondary)
            }
            .labelStyle(SmallIconLabel())
            Spacer()
            leading
            HStack(spacing: 2) {
                grouped
                GroupButton(symbol: "folder", id: "openVideo", help: "Open a Video…") {}
                GroupButton(symbol: "doc.text", id: "context", help: "Context") {}
                GroupButton(symbol: "sidebar.trailing", id: "sidebarToggle", help: "Hide the sidebar") {}
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(t.popoverBorder, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
        }
        .padding(.leading, 84)
        .padding(.trailing, 14)
        .frame(height: 50)
    }

    private var stage: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.letterbox)
                LinearGradient(colors: [hex(0x3B4A63), hex(0x7A6A55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.85))
                            Text("Stage").font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .coachRing(m.tourOpen && m.tourStep == .write, radius: 10)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .overlay(alignment: .bottomLeading) {
                if m.tourOpen {
                    TourPanel(m: m)
                        .padding(.leading, 24)
                        .padding(.bottom, 12)
                        .transition(.scale(scale: 0.96, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: m.tourOpen)
            HStack(spacing: 12) {
                Image(systemName: "play.fill").foregroundStyle(t.textPrimary)
                Text("0:42").font(.callout.monospacedDigit()).foregroundStyle(t.textSecondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(t.track).frame(height: 4)
                        Capsule().fill(t.accent).frame(width: geo.size.width * 0.3, height: 4)
                        Circle().fill(.white).frame(width: 12, height: 12).shadow(radius: 1).offset(x: geo.size.width * 0.3 - 6)
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 14)
                Text("2:18").font(.callout.monospacedDigit()).foregroundStyle(t.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ZStack {
                if m.page == .connect {
                    ConnectView(m: m)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                        .zIndex(1)
                } else {
                    VStack(spacing: 0) {
                        ThreadListView(m: m)
                        ComposerView(m: m)
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .animation(.spring(duration: 0.35, bounce: 0.1), value: m.page)
            FooterView(m: m)
        }
    }
}

private struct SmallIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.imageScale(.small).frame(width: 14).opacity(0.75)
            configuration.title
        }
    }
}

/// A lab-only strip at the window's foot: drive the fixture.
struct LabStrip: View {
    @Bindable var m: Onboard
    @Environment(\.tok) private var t

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flask").foregroundStyle(t.textTertiary)
            Text("Lab fixture · not part of the app").font(.caption.weight(.semibold)).foregroundStyle(t.textTertiary)
            Spacer()
            Button("Reset") { m.reset() }.labID("labReset")
            Button("Simulate: Agent Connects") { m.agentConnects() }
                .labID("labConnect")
                .disabled(m.phase == .connected)
            Button("Simulate: Relaunch") { m.relaunch() }.labID("labRelaunch")
            Toggle("npx found", isOn: $m.npxFound)
                .toggleStyle(.checkbox)
                .font(.caption)
                .labID("labNpx")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(
            Canvas { ctx, size in
                // Diagonal stripes mark the strip as lab-only.
                var x: CGFloat = -size.height
                while x < size.width {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    ctx.stroke(p, with: .color(t.textTertiary.opacity(0.10)), lineWidth: 6)
                    x += 16
                }
            }
            .background(t.well)
        )
        .overlay(alignment: .top) { Hairline() }
    }
}
