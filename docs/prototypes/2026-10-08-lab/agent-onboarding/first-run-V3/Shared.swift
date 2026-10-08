import AppKit
import LabHost
import SwiftUI

// MARK: - Palette (Havooch's Default Light / Default Dark tokens)

extension Color {
    /// A colour that follows the window's appearance.
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        func ns(_ hex: UInt32, _ alpha: Double) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha
            )
        }
        let l = ns(light, lightAlpha), d = ns(dark, darkAlpha)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l
        })
    }

    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

enum Pal {
    static let window = Color(nsColor: .windowBackgroundColor)
    static let textPrimary = Color(light: 0x2b2925, dark: 0xece9e3)
    static let textSecondary = Color(light: 0x6b665d, dark: 0xada79d)
    static let textTertiary = Color(light: 0x9a948a, dark: 0x7d776e)
    static let accent = Color(light: 0x5b7db1, dark: 0x9db6dd)
    static let textOnAccent = Color(light: 0xffffff, dark: 0x1a1918)
    static let control = Color(light: 0xb98a45, dark: 0xe3bf84)
    static let done = Color(light: 0x5e9771, dark: 0x9ccba8)
    static let failed = Color(light: 0xb5654f, dark: 0xde9c84)
    static let absent = Color(light: 0x9a948a, dark: 0x7d776e)
    static let well = Color(light: 0x000000, dark: 0xffffff, lightAlpha: 0.04, darkAlpha: 0.05)
    static let hover = Color(light: 0x000000, dark: 0xffffff, lightAlpha: 0.06, darkAlpha: 0.08)
    static let separator = Color(nsColor: .separatorColor)
    static let card = Color(light: 0xffffff, dark: 0xffffff, lightAlpha: 0.7, darkAlpha: 0.04)
    static let bubblePerson = Color(light: 0xece8e0, dark: 0x34322e)
    static let bubbleAgent = Color(light: 0xe3e9f2, dark: 0x2f3846)
    static let letterbox = Color(light: 0x151412, dark: 0x000000)
    static let field = Color(nsColor: .textBackgroundColor)
    static let cat = Color(hex: 0xE57F35)
}

// MARK: - The cat mark (a stand-in for the bundled PDF)

struct CatMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let orange = Color(hex: 0xE57F35), pink = Color(hex: 0xF2A99A), white = Color.white, ink = Color(hex: 0x2A1F1A)
            // Ears.
            for flip in [false, true] {
                var ear = Path()
                let x0 = flip ? w * 0.84 : w * 0.16
                let tip = flip ? w * 0.88 : w * 0.12
                let inner = flip ? w * 0.58 : w * 0.42
                ear.move(to: CGPoint(x: x0, y: h * 0.52))
                ear.addLine(to: CGPoint(x: tip, y: h * 0.06))
                ear.addLine(to: CGPoint(x: inner, y: h * 0.30))
                ear.closeSubpath()
                ctx.fill(ear, with: .color(orange))
                var innerEar = Path()
                innerEar.move(to: CGPoint(x: flip ? w * 0.80 : w * 0.20, y: h * 0.40))
                innerEar.addLine(to: CGPoint(x: flip ? w * 0.85 : w * 0.15, y: h * 0.14))
                innerEar.addLine(to: CGPoint(x: flip ? w * 0.66 : w * 0.34, y: h * 0.30))
                innerEar.closeSubpath()
                ctx.fill(innerEar, with: .color(pink))
            }
            // Head.
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.06, y: h * 0.22, width: w * 0.88, height: h * 0.72)), with: .color(orange))
            // Muzzle.
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.22, y: h * 0.56, width: w * 0.56, height: h * 0.38)), with: .color(white))
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.47, y: h * 0.36, width: w * 0.06, height: h * 0.26), cornerRadius: w * 0.03), with: .color(white))
            // Stripes.
            for dx in [-0.08, 0.0, 0.08] {
                ctx.fill(Path(roundedRect: CGRect(x: w * (0.485 + dx), y: h * 0.25, width: w * 0.03, height: h * 0.08), cornerRadius: w * 0.015), with: .color(Color(hex: 0xC4612A)))
            }
            // Eyes.
            for ex in [0.33, 0.67] {
                let r = w * 0.11
                ctx.fill(Path(ellipseIn: CGRect(x: w * ex - r, y: h * 0.56 - r, width: r * 2, height: r * 2)), with: .color(ink))
                let s = w * 0.04
                ctx.fill(Path(ellipseIn: CGRect(x: w * ex + r * 0.15, y: h * 0.56 - r * 0.6, width: s, height: s)), with: .color(white))
            }
            // Nose.
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.47, y: h * 0.69, width: w * 0.06, height: h * 0.04)), with: .color(pink))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Harnesses and their logos (drawn stand-ins)

enum Harness: String, CaseIterable, Identifiable {
    case claude, codex, cursor, pi, opencode, other
    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .pi: "Pi"
        case .opencode: "OpenCode"
        case .other: "Other"
        }
    }

    /// Where the person pastes the prompt.
    var whereToPaste: String {
        switch self {
        case .claude: "Open Claude Code in your project, in the terminal or the desktop app, and paste it."
        case .codex: "Start Codex in your project and paste it as your first message."
        case .cursor: "Open your project in Cursor, start an Agent chat and paste it."
        case .pi: "Start Pi in your project and paste it."
        case .opencode: "Run opencode in your project and paste it."
        case .other: "Paste it into any agent that can run shell commands and has the havooch-mate skill."
        }
    }
}

struct HarnessLogo: View {
    let harness: Harness
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(fill)
            glyph
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        switch harness {
        case .claude: AnyShapeStyle(Color(hex: 0xD97757))
        case .codex: AnyShapeStyle(Color(hex: 0x0D0D0D))
        case .cursor: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x2A2A2A), Color(hex: 0x0A0A0A)], startPoint: .top, endPoint: .bottom))
        case .pi: AnyShapeStyle(Color(hex: 0x3B3F8F))
        case .opencode: AnyShapeStyle(Color(hex: 0x1B1B1F))
        case .other: AnyShapeStyle(Pal.hover)
        }
    }

    @ViewBuilder private var glyph: some View {
        switch harness {
        case .claude:
            Image(systemName: "asterisk").font(.system(size: size * 0.52, weight: .heavy)).foregroundStyle(.white)
        case .codex:
            Image(systemName: "hexagon").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white)
                .overlay(Image(systemName: "chevron.right").font(.system(size: size * 0.2, weight: .heavy)).foregroundStyle(.white))
        case .cursor:
            Canvas { ctx, s in
                var p = Path()
                p.move(to: CGPoint(x: s.width * 0.5, y: s.height * 0.18))
                p.addLine(to: CGPoint(x: s.width * 0.82, y: s.height * 0.72))
                p.addLine(to: CGPoint(x: s.width * 0.18, y: s.height * 0.72))
                p.closeSubpath()
                ctx.fill(p, with: .linearGradient(Gradient(colors: [.white, .white.opacity(0.45)]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: s.width, y: s.height)))
            }
            .padding(size * 0.08)
        case .pi:
            Text("π").font(.system(size: size * 0.62, weight: .semibold, design: .serif)).foregroundStyle(.white).offset(y: -size * 0.03)
        case .opencode:
            Text("{ }").font(.system(size: size * 0.36, weight: .bold, design: .monospaced)).foregroundStyle(.white)
        case .other:
            Image(systemName: "terminal").font(.system(size: size * 0.44, weight: .medium)).foregroundStyle(Pal.textSecondary)
        }
    }
}

// MARK: - The setup model (fixtures, with timed steps)

@MainActor @Observable
final class Setup {
    enum CLIState { case notLinked, linking, linked }
    enum SkillState { case missing, installing, installed }
    enum Listen { case idle, waiting, connected }

    var cli: CLIState = .notLinked
    var found: [Harness] = [.claude, .codex, .cursor]
    var skills: [Harness: SkillState] = [.claude: .installed, .codex: .missing, .cursor: .missing]
    var log: [String] = []
    var isInstalling = false
    var harness: Harness = .claude
    var copied = false
    var listen: Listen = .idle
    var skipped = false
    var demoOpen = false

    static let skillCommand = "npx skills add yahyabedirhan/havooch --skill havooch-mate"
    static let project = "~/Developer/my-app"

    var prompt: String { "Listen for my Havooch feedback" }

    var cliDone: Bool { cli == .linked }
    var skillDone: Bool { found.allSatisfy { skills[$0] == .installed } }
    var connected: Bool { listen == .connected }
    var doneCount: Int { [cliDone, skillDone, connected].filter { $0 }.count }
    var missingCount: Int { found.filter { skills[$0] != .installed }.count }

    func linkCLI() {
        guard cli == .notLinked else { return }
        cli = .linking
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            cli = .linked
        }
    }

    func installSkill() {
        guard !isInstalling, !skillDone else { return }
        isInstalling = true
        let missing = found.filter { skills[$0] != .installed }
        for h in missing { skills[h] = .installing }
        log = ["$ " + Self.skillCommand]
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            log.append("Found 3 agents: Claude Code, Codex, Cursor")
            for h in missing {
                try? await Task.sleep(for: .milliseconds(1400))
                log.append("Installing havooch-mate for \(h.name)…")
                try? await Task.sleep(for: .milliseconds(900))
                skills[h] = .installed
                log.append("✓ \(h.name)")
            }
            log.append("Done. havooch-mate is ready in 3 agents.")
            isInstalling = false
        }
    }

    func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        copied = true
        if listen == .idle {
            listen = .waiting
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                if listen == .waiting { listen = .connected }
            }
        }
    }

    func reset() {
        cli = .notLinked
        skills = [.claude: .installed, .codex: .missing, .cursor: .missing]
        log = []
        isInstalling = false
        copied = false
        listen = .idle
        skipped = false
        demoOpen = false
    }
}

// MARK: - Building blocks

/// A Shipyard-style card: a quiet filled rounded rectangle with a hairline.
struct CardBackground: ViewModifier {
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .background(Pal.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(highlighted ? Pal.accent : Pal.separator, lineWidth: highlighted ? 1.5 : 1)
            )
    }
}

extension View {
    func card(highlighted: Bool = false) -> some View { modifier(CardBackground(highlighted: highlighted)) }
}

/// A command or a prompt in code font on a well, with an optional copy button.
struct CommandBox: View {
    let text: String
    var copyID: String? = nil
    var copied = false
    var onCopy: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Pal.textPrimary)
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onCopy, let copyID {
                Button(action: onCopy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .labID(copyID)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Pal.well, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Pal.separator.opacity(0.6), lineWidth: 0.5))
    }
}

/// A status glyph: a green check, a spinner, or an empty ring.
struct StatusDot: View {
    enum Kind { case done, running, todo, missing }
    let kind: Kind
    var size: CGFloat = 15

    var body: some View {
        Group {
            switch kind {
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Pal.done)
            case .running: ProgressView().controlSize(.mini)
            case .todo: Image(systemName: "circle").foregroundStyle(Pal.textTertiary)
            case .missing: Image(systemName: "xmark.circle").foregroundStyle(Pal.textTertiary)
            }
        }
        .font(.system(size: size))
        .frame(width: size + 2, height: size + 2)
    }
}

/// The footer's presence chip, as Havooch draws it.
struct PresenceChip: View {
    let listening: Bool
    var harness: Harness? = nil

    var body: some View {
        let colour = listening ? Pal.done : Pal.absent
        Label {
            Text(listening ? "Listening" : "No listener")
        } icon: {
            if listening, let harness {
                HarnessLogo(harness: harness, size: 14)
            } else {
                Image(systemName: listening ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .font(.callout.weight(.medium))
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(colour)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(colour.opacity(0.14), in: Capsule())
    }
}

// MARK: - The command line card

struct CLICard: View {
    let setup: Setup
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "terminal").foregroundStyle(Pal.accent).frame(width: 18)
                Text("Command line").font(.body.weight(.semibold))
                Spacer()
                switch setup.cli {
                case .notLinked:
                    Button("Link") { setup.linkCLI() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .labID("link-cli")
                case .linking:
                    ProgressView().controlSize(.small)
                case .linked:
                    Label("Linked", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Pal.done)
                }
            }
            .frame(minHeight: 24)
            Text(setup.cliDone
                 ? "Your agent can run `havooch` from any folder."
                 : "Your agent talks to Havooch through the `havooch` command. Link it from the app into `~/.local/bin`.")
                .font(.callout)
                .foregroundStyle(Pal.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !compact {
                CommandBox(text: setup.cliDone ? "~/.local/bin/havooch → Havooch.app" : "~/.local/bin/havooch  ·  not linked")
                    .opacity(setup.cliDone ? 1 : 0.85)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - The skill card

struct SkillCard: View {
    let setup: Setup
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Pal.accent).frame(width: 18)
                Text("Agent skill").font(.body.weight(.semibold))
                Spacer()
                if setup.skillDone {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Pal.done)
                } else if setup.isInstalling {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Install for All") { setup.installSkill() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .labID("install-skill")
                }
            }
            .frame(minHeight: 24)
            Text("The havooch-mate skill teaches your agent to listen, do what you ask, and answer in the player.")
                .font(.callout)
                .foregroundStyle(Pal.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(setup.found) { h in
                    HStack(spacing: 8) {
                        HarnessLogo(harness: h, size: 18)
                        Text(h.name).font(.callout)
                        Spacer()
                        switch setup.skills[h] ?? .missing {
                        case .installed:
                            Text("Installed").font(.callout).foregroundStyle(Pal.textSecondary)
                            StatusDot(kind: .done, size: 13)
                        case .installing:
                            Text("Installing…").font(.callout).foregroundStyle(Pal.textSecondary)
                            StatusDot(kind: .running, size: 13)
                        case .missing:
                            Text("Not installed").font(.callout).foregroundStyle(Pal.textTertiary)
                            StatusDot(kind: .missing, size: 13)
                        }
                    }
                    .padding(.vertical, 5)
                    if h != setup.found.last { Divider() }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(Pal.well, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            if !setup.log.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(setup.log.enumerated()), id: \.offset) { i, line in
                                Text(line)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(line.hasPrefix("✓") ? Pal.done : Pal.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: compact ? 48 : 78)
                    .background(Pal.well, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .onChange(of: setup.log.count) { proxy.scrollTo(setup.log.count - 1, anchor: .bottom) }
                }
            } else if !compact {
                Text("Runs `\(Setup.skillCommand)`")
                    .font(.caption)
                    .foregroundStyle(Pal.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - The harness picker

struct HarnessPicker: View {
    let setup: Setup
    var columns = 3
    var tile: CGFloat = 30

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(Harness.allCases) { h in
                let picked = setup.harness == h
                Button { setup.harness = h } label: {
                    VStack(spacing: 6) {
                        HarnessLogo(harness: h, size: tile)
                        Text(h.name).font(.callout.weight(picked ? .semibold : .regular)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(picked ? Pal.accent.opacity(0.12) : Pal.well, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(picked ? Pal.accent : Pal.separator.opacity(0.6), lineWidth: picked ? 1.5 : 0.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .labID("harness-\(h.rawValue)")
            }
        }
    }
}

// MARK: - Listening status

struct ListenStatus: View {
    let setup: Setup
    var showsChip = true

    var body: some View {
        HStack(spacing: 10) {
            switch setup.listen {
            case .idle:
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(Pal.textTertiary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("No agent is listening yet").font(.callout.weight(.medium))
                    Text("Copy the prompt and paste it in \(setup.harness.name).").font(.caption).foregroundStyle(Pal.textSecondary)
                }
            case .waiting:
                ProgressView().controlSize(.small).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Waiting for your agent…").font(.callout.weight(.medium))
                    Text("This turns green when \(setup.harness.name) starts listening.").font(.caption).foregroundStyle(Pal.textSecondary)
                }
            case .connected:
                HarnessLogo(harness: setup.harness, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(setup.harness.name) is listening").font(.callout.weight(.semibold))
                    Text(Setup.project).font(.caption.monospaced()).foregroundStyle(Pal.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if showsChip, setup.listen == .connected { PresenceChip(listening: true, harness: setup.harness) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(setup.listen == .connected ? Pal.done.opacity(0.10) : Pal.well, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(setup.listen == .connected ? Pal.done.opacity(0.5) : Pal.separator.opacity(0.6), lineWidth: 1)
        )
        .animation(.smooth(duration: 0.25), value: setup.listen)
    }
}

// MARK: - A demo frame (the sample video, drawn)

struct DemoFrame: View {
    var region = false
    var paused = true

    var body: some View {
        GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [Color(hex: 0x1C2340), Color(hex: 0x0E1020)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    // A landing page mock in the frame.
                    VStack(alignment: .leading, spacing: h * 0.03) {
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.85)).frame(width: w * 0.42, height: h * 0.07)
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.35)).frame(width: w * 0.55, height: h * 0.035)
                        RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.35)).frame(width: w * 0.36, height: h * 0.035)
                        Capsule().fill(Color(hex: 0x7D9CCC)).frame(width: w * 0.16, height: h * 0.07).padding(.top, h * 0.03)
                    }
                    .padding(.leading, w * 0.08)
                    .padding(.top, h * 0.24)
                    RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.10))
                        .frame(width: w * 0.28, height: h * 0.42)
                        .offset(x: w * 0.64, y: h * 0.24)
                    if region {
                        Canvas { ctx, s in
                            let hole = CGRect(x: s.width * 0.06, y: s.height * 0.21, width: s.width * 0.48, height: s.height * 0.14)
                            var dim = Path(CGRect(origin: .zero, size: s))
                            dim.addRoundedRect(in: hole, cornerSize: CGSize(width: 3, height: 3))
                            ctx.fill(dim, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
                            ctx.stroke(Path(roundedRect: hole, cornerRadius: 3), with: .color(Color(hex: 0x7D9CCC)), lineWidth: 2)
                        }
                    }
                }
            }
        .aspectRatio(16 / 9, contentMode: .fit)
    }
}

/// The player's bar under the stage: play, time, a timeline.
struct PlayerBar: View {
    var time = "0:12 / 0:42"
    var progress: CGFloat = 0.29
    var paused = true

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: paused ? "play.fill" : "pause.fill").font(.system(size: 13))
            Text(time).font(.callout.monospacedDigit()).foregroundStyle(Pal.textPrimary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(light: 0xd8d2c6, dark: 0x45423d)).frame(height: 4)
                    Capsule().fill(Pal.accent).frame(width: geo.size.width * progress, height: 4)
                    Circle().fill(.white).frame(width: 12, height: 12).shadow(radius: 1).offset(x: geo.size.width * progress - 6)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }
}

// MARK: - Where the flow ends

/// After Skip: Havooch's empty state, with a notice to finish setup later.
struct SkippedHome: View {
    let setup: Setup

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Pal.control)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Setup isn't finished").font(.callout.weight(.semibold))
                    Text("Your agent can't hear Havooch until it has the command and the skill.")
                        .font(.caption).foregroundStyle(Pal.textSecondary)
                }
                Spacer()
                Button("Finish Setup") { setup.skipped = false }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .labID("resume")
            }
            .padding(10)
            .card()
            .padding(.horizontal, 20)
            .padding(.top, 40)
            Spacer()
            VStack(spacing: 12) {
                CatMark(size: 76)
                Text("Drop a Video Here").font(.title.weight(.medium))
                Text("An mp4, mov or m4v file. Pause anywhere, or draw on the frame,\nand write to your agent.")
                    .font(.body).multilineTextAlignment(.center).foregroundStyle(Pal.textPrimary)
                HStack(spacing: 10) {
                    Button("Open a Video…") {}
                    Button("Try the Demo") { setup.demoOpen = true }
                }
                .controlSize(.large)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The demo, open in the player: the stage, a slim sidebar and a hint.
struct DemoOpened: View {
    let setup: Setup
    var onRestart: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack { Pal.letterbox; DemoFrame() }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.top, 40)
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 10) {
                            Image(systemName: "lightbulb.fill").foregroundStyle(Pal.control)
                            Text("Pause with Space, drag a box on the frame, write what to change. ⌘↩ sends it to \(setup.connected ? setup.harness.name : "your agent").")
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(24)
                    }
                PlayerBar(time: "0:00 / 0:42", progress: 0.0, paused: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text("Threads").font(.title3.weight(.bold)).padding(.top, 40)
                Text("0 threads").font(.caption).foregroundStyle(Pal.textSecondary)
                Spacer()
                Text("Comment on 0:00…")
                    .font(.callout).foregroundStyle(Pal.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Pal.field, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Pal.separator))
                    .padding(.bottom, 8)
                HStack {
                    PresenceChip(listening: setup.connected, harness: setup.harness)
                    Spacer()
                    Button("Start Over", action: onRestart).controlSize(.small).labID("restart")
                }
                .frame(height: 44)
            }
            .padding(.horizontal, 14)
            .frame(width: 230)
        }
    }
}
