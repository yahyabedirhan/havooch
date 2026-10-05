import Foundation

/// A coding agent harness the app recognises in a listener session's name,
/// so the agent's messages, the presence pill and the notices show its logo.
/// Ported from Shipyard (`yahyabedirhan/shipyard` at `74b9695`).
///
/// The app bundles each agent's real logo, its maker's own file where there
/// is one, only to say which agent answers (`Packaging/AgentLogos/NOTICE.md`).
public enum KnownAgent: String, CaseIterable, Hashable, Sendable {
    case claude, codex, opencode, cursor, pi, gemini, copilot, amp, droid

    /// The one table: each agent's names as a session may be named
    /// (lowercase, without spaces or dashes), and its logo.
    private var entry: (aliases: Set<String>, logo: AgentLogo) {
        switch self {
        case .claude: (["claude", "claudecode"], AgentLogo("claude"))
        case .codex: (["codex", "codexcli", "openaicodex"], AgentLogo("codex"))
        case .opencode: (["opencode"], AgentLogo("opencode", look: .lightAndDark))
        case .cursor: (["cursor", "cursoragent", "cursorcli"], AgentLogo("cursor"))
        case .pi: (["pi", "piagent", "picodingagent"], AgentLogo("pi"))
        case .gemini: (["gemini", "geminicli"], AgentLogo("gemini"))
        case .copilot: (["copilot", "copilotcli", "githubcopilot"], AgentLogo("copilot", look: .template))
        case .amp: (["amp", "ampcode"], AgentLogo("amp"))
        case .droid: (["droid", "factorydroid"], AgentLogo("droid"))
        }
    }

    /// The agent's logo.
    public var logo: AgentLogo { entry.logo }

    /// The agent a name says, or `nil`. Case, spaces, dashes and other
    /// punctuation don't count, and words after the agent's name are
    /// allowed: "Claude Code", "claude-code" and "claude: fix totals" are
    /// all Claude. The name has to come first and whole: "pipeline" and
    /// "my claude" name no agent.
    public init?(sender: String) {
        let words = sender.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        // The longest run of leading words that names an agent.
        for count in stride(from: words.count, through: 1, by: -1) {
            let name = words.prefix(count).joined()
            if let agent = Self.allCases.first(where: { $0.entry.aliases.contains(name) }) {
                self = agent
                return
            }
        }
        return nil
    }
}

/// A known agent's logo: which of the app's bundled files it is, and how it
/// reads in light and dark mode.
public struct AgentLogo: Hashable, Sendable {
    /// How a logo reads in light and dark mode.
    public enum Look: Hashable, Sendable {
        /// In its own colours, which read in both.
        case colour
        /// In its own colours, with its maker's second file for dark mode,
        /// named `<resource>-dark`.
        case lightAndDark
        /// A single dark glyph, tinted like text so it reads in both.
        case template
    }

    /// The logo's file in the app's `AgentLogos` resources, without its
    /// extension: "claude".
    public var resource: String
    public var look: Look

    public init(_ resource: String, look: Look = .colour) {
        self.resource = resource
        self.look = look
    }
}

extension ListenerSession {
    /// The agent harness the session's name says, or `nil` for a name no
    /// known agent has: the app then shows its neutral symbol.
    public var agent: KnownAgent? { KnownAgent(sender: name) }
}
