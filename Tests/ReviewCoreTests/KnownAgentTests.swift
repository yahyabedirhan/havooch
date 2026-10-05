import ReviewCore
import Testing

@Suite("Known agents")
struct KnownAgentTests {
    @Test(
        "a session's name says a known agent, ignoring case, spaces and dashes, and words after the agent's name",
        arguments: [
            ("claude", KnownAgent.claude), ("Claude Code", .claude), ("claude-code", .claude), ("CLAUDE", .claude),
            ("claude: fix totals", .claude), ("codex", .codex), ("Codex CLI", .codex), ("opencode", .opencode),
            ("OpenCode", .opencode), ("cursor", .cursor), ("cursor-agent", .cursor), ("pi", .pi), ("gemini", .gemini),
            ("gemini-cli", .gemini), ("copilot", .copilot), ("GitHub Copilot", .copilot), ("amp", .amp), ("droid", .droid),
            ("Factory Droid", .droid),
        ] as [(String, KnownAgent)]
    )
    func known(name: String, agent: KnownAgent) {
        #expect(KnownAgent(sender: name) == agent)
    }

    @Test(
        "a name that only starts like an agent's, or names no agent, is none",
        arguments: ["pipeline", "claudette", "deploy bot", "my claude", "", "an unknown agent"]
    )
    func unknown(name: String) {
        #expect(KnownAgent(sender: name) == nil)
    }

    @Test("a listener session's agent is the one its name says")
    func session() {
        #expect(ListenerSession(key: "k", name: "Claude Code", place: "/work").agent == .claude)
        #expect(ListenerSession(key: "k", name: "zsh", place: "/work").agent == nil)
    }

    @Test("each agent's logo look: OpenCode has a dark file, Copilot is a template, the rest are in colour")
    func looks() {
        for agent in KnownAgent.allCases {
            let look: AgentLogo.Look = switch agent {
            case .opencode: .lightAndDark
            case .copilot: .template
            default: .colour
            }
            #expect(agent.logo.look == look, "\(agent)")
            #expect(agent.logo.resource == agent.rawValue)
        }
    }
}
