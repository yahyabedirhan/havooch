import Foundation
import ReviewCore

/// An agent harness Havooch helps set up: where its user skills folders
/// are, where it is usually installed, the name `npx skills add -a` takes
/// for it, and how its prompt invokes a skill. Every path is relative to the
/// person's home folder, unless it starts with `/`.
public struct Harness: Hashable, Sendable {
    /// The harness, for its logo and its name in a listener session.
    public var agent: KnownAgent
    /// The name the person reads: "Claude Code".
    public var name: String
    /// The user skills folders the harness reads, the global install's
    /// first. Only these are looked in: a skill installed in a repository
    /// can't be seen (ADR 0005).
    public var skillsFolders: [String]
    /// Where the harness's app or command usually is. Any one of them
    /// existing is a best guess that the harness is installed.
    public var presenceHints: [String]
    /// The harness's name for `npx skills add -a`: "claude-code".
    public var installName: String
    /// How the harness's prompt invokes the skill.
    public var promptForm: PromptForm

    /// How a harness invokes a skill in a prompt.
    public enum PromptForm: Hashable, Sendable {
        /// A word before the request: `/havooch-mate`, `$havooch-mate`,
        /// `/skill:havooch-mate`.
        case invocation(String)
        /// A sentence that names the skill: OpenCode's "Use the
        /// havooch-mate skill to …".
        case sentence
    }

    /// The prompt the person pastes into the harness to make its agent
    /// listen to `target`. It assumes the skill is there (G10).
    public func prompt(for target: PromptTarget) -> String {
        let request = "listen for my feedback on \(target.words)"
        switch promptForm {
        case .invocation(let word): return "\(word) \(request)"
        case .sentence: return "Use the \(HarnessCatalog.skill) skill to \(request)"
        }
    }

    /// The first-run window's prompt (H2): the person's own agent opens
    /// the demo video bundled in the app and listens to it. It assumes the
    /// skill is there, as `prompt(for:)` does.
    public var demoPrompt: String {
        switch promptForm {
        case .invocation(let word): "\(word) use Havooch to open the demo video and listen for my feedback"
        case .sentence: "Use the \(HarnessCatalog.skill) skill to open the demo video in Havooch and listen for my feedback"
        }
    }
}

/// What a prompt names: the window's video by its file name, or a project
/// by its slug.
public enum PromptTarget: Hashable, Sendable {
    case video(fileName: String)
    case project(slug: String)

    /// The words the prompt ends with: `cut2.mp4`, `project launch-video`.
    var words: String {
        switch self {
        case .video(let fileName): fileName
        case .project(let slug): "project \(slug)"
        }
    }
}

/// The harnesses Havooch knows how to set up, in the order the person
/// sees them. The folders, names and prompt forms come from ADR 0005 and
/// the target design's catalog; Cursor's prompt form is unverified until its
/// live QA.
public enum HarnessCatalog {
    /// The skill an agent needs to listen.
    public static let skill = "havooch-mate"
    /// Where the skill comes from, for `npx skills add`.
    public static let source = "yahyabedirhan/havooch"

    /// Where a command line tool is usually installed, for presence hints.
    private static let commandFolders = [".local/bin", "/opt/homebrew/bin", "/usr/local/bin", ".bun/bin", ".npm-global/bin"]

    /// `command` in each usual command folder.
    private static func command(_ name: String) -> [String] {
        commandFolders.map { "\($0)/\(name)" }
    }

    /// `name.app` in the system's and the person's Applications folders.
    private static func app(_ name: String) -> [String] {
        ["/Applications/\(name).app", "Applications/\(name).app"]
    }

    public static let all: [Harness] = [
        Harness(
            agent: .claude, name: "Claude Code", skillsFolders: [".claude/skills"],
            presenceHints: app("Claude") + command("claude") + [".claude/local/claude"],
            installName: "claude-code", promptForm: .invocation("/\(skill)")
        ),
        Harness(
            agent: .codex, name: "Codex", skillsFolders: [".agents/skills", ".codex/skills"],
            presenceHints: app("Codex") + command("codex"),
            installName: "codex", promptForm: .invocation("$\(skill)")
        ),
        Harness(
            agent: .cursor, name: "Cursor", skillsFolders: [".agents/skills", ".cursor/skills"],
            presenceHints: app("Cursor") + command("cursor-agent"),
            installName: "cursor", promptForm: .invocation("/\(skill)")
        ),
        Harness(
            agent: .pi, name: "Pi", skillsFolders: [".pi/agent/skills", ".agents/skills"],
            presenceHints: command("pi"),
            installName: "pi", promptForm: .invocation("/skill:\(skill)")
        ),
        Harness(
            agent: .opencode, name: "OpenCode", skillsFolders: [".config/opencode/skills", ".claude/skills", ".agents/skills"],
            presenceHints: app("OpenCode") + command("opencode") + [".opencode/bin/opencode"],
            installName: "opencode", promptForm: .sentence
        ),
    ]

    /// The harness a name says: its install name ("claude-code"), or any
    /// name a listener session may carry ("Claude Code", "claude").
    public static func harness(named name: String) -> Harness? {
        let lowered = name.lowercased()
        if let harness = all.first(where: { $0.installName == lowered }) { return harness }
        guard let agent = KnownAgent(sender: name) else { return nil }
        return all.first { $0.agent == agent }
    }

    /// The harness of `agent`, when Havooch knows how to set it up.
    public static func harness(of agent: KnownAgent) -> Harness? {
        all.first { $0.agent == agent }
    }
}
