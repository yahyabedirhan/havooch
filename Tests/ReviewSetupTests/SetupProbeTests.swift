import Foundation
import ReviewCore
import ReviewSetup
import Testing

@Suite("Setup detection")
struct SetupProbeTests {
    static let home = "/Users/me"
    static let bundleCommand = "/Applications/Havooch.app/Contents/Helpers/havooch"
    static let link = "/Users/me/.local/bin/havooch"

    private func probe(_ items: [String: FileItem]) -> (SetupReport, FakeFileSystem) {
        let fileSystem = FakeFileSystem(items)
        return (SetupProbe(fileSystem: fileSystem, home: Self.home).probe(), fileSystem)
    }

    private func harness(_ report: SetupReport, _ agent: KnownAgent) -> HarnessSetup {
        report.harnesses.first { $0.harness.agent == agent }!
    }

    @Test("an empty home detects nothing, and nothing reads as missing")
    func emptyHome() {
        let (report, _) = probe([:])
        #expect(report.commandLine.detection == .notDetected)
        #expect(report.harnesses.map(\.harness.agent) == [.claude, .codex, .cursor, .pi, .opencode])
        #expect(report.harnesses.allSatisfy { $0.skill == .notDetected && $0.presence == .notDetected })
        #expect(Set(Detection.allCases.map(\.rawValue)) == ["detected", "notDetected", "cannotKnow"])
    }

    @Test("the command line is detected when the link points to the command in a Havooch bundle")
    func linkIntoBundle() {
        let (report, _) = probe([Self.link: .link(to: Self.bundleCommand), Self.bundleCommand: .file])
        #expect(report.commandLine.detection == .detected)
        #expect(report.commandLine.destination == Self.bundleCommand)
    }

    @Test("a link elsewhere, a dangling link, a plain file or a folder is not detected", arguments: [
        [link: FileItem.link(to: "/opt/homebrew/bin/havooch"), "/opt/homebrew/bin/havooch": .file],
        [link: .link(to: bundleCommand)],
        [link: .file],
        [link: .folder],
    ])
    func linkNotDetected(items: [String: FileItem]) {
        let (report, _) = probe(items)
        #expect(report.commandLine.detection == .notDetected)
    }

    @Test("a relative link is read from its folder")
    func relativeLink() {
        let command = "/Users/me/Apps/Havooch (proto-2).app/Contents/Helpers/havooch"
        let (report, _) = probe([Self.link: .link(to: "../../Apps/Havooch (proto-2).app/Contents/Helpers/havooch"), command: .file])
        #expect(report.commandLine.detection == .detected)
        #expect(report.commandLine.destination == command)
    }

    @Test("a link folder that can't be read is cannot know")
    func linkCannotKnow() {
        let (report, _) = probe([Self.link: .unreadable])
        #expect(report.commandLine.detection == .cannotKnow)
    }

    @Test("the skill is detected per harness in its user skills folders", arguments: [
        ("/Users/me/.claude/skills/havooch-mate/SKILL.md", [KnownAgent.claude, .opencode]),
        ("/Users/me/.agents/skills/havooch-mate/SKILL.md", [.codex, .cursor, .pi, .opencode]),
        ("/Users/me/.codex/skills/havooch-mate/SKILL.md", [.codex]),
        ("/Users/me/.cursor/skills/havooch-mate/SKILL.md", [.cursor]),
        ("/Users/me/.pi/agent/skills/havooch-mate/SKILL.md", [.pi]),
        ("/Users/me/.config/opencode/skills/havooch-mate/SKILL.md", [.opencode]),
    ])
    func skillPerHarness(file: String, detected: [KnownAgent]) {
        let (report, _) = probe([file: .file])
        for setup in report.harnesses {
            let expected: Detection = detected.contains(setup.harness.agent) ? .detected : .notDetected
            #expect(setup.skill == expected, "\(setup.harness.name)")
        }
        #expect(harness(report, detected[0]).skillFolder == URL(fileURLWithPath: file).deletingLastPathComponent().path)
    }

    @Test("a skill folder without SKILL.md is not detected, and one linked in by the installer is")
    func skillFile() {
        let canonical = "/Users/me/.agents/skills/havooch-mate/SKILL.md"
        let (empty, _) = probe(["/Users/me/.claude/skills/havooch-mate": .folder])
        #expect(harness(empty, .claude).skill == .notDetected)
        let (linked, _) = probe(["/Users/me/.claude/skills/havooch-mate/SKILL.md": .link(to: canonical), canonical: .file])
        #expect(harness(linked, .claude).skill == .detected)
    }

    @Test("a skills folder that can't be read is cannot know, unless another folder has the skill")
    func skillCannotKnow() {
        let (report, _) = probe(["/Users/me/.agents/skills/havooch-mate/SKILL.md": .unreadable])
        #expect(harness(report, .codex).skill == .cannotKnow)
        #expect(harness(report, .claude).skill == .notDetected)
        let (found, _) = probe([
            "/Users/me/.agents/skills/havooch-mate/SKILL.md": .unreadable,
            "/Users/me/.codex/skills/havooch-mate/SKILL.md": .file,
        ])
        #expect(harness(found, .codex).skill == .detected)
    }

    @Test("a harness is detected from its app or its command", arguments: [
        ("/Applications/Claude.app", KnownAgent.claude),
        ("/Users/me/.local/bin/claude", .claude),
        ("/Users/me/Applications/Codex.app", .codex),
        ("/opt/homebrew/bin/codex", .codex),
        ("/Applications/Cursor.app", .cursor),
        ("/usr/local/bin/pi", .pi),
        ("/Users/me/.opencode/bin/opencode", .opencode),
    ])
    func presence(path: String, agent: KnownAgent) {
        let (report, _) = probe([path: .folder])
        for setup in report.harnesses {
            #expect(setup.presence == (setup.harness.agent == agent ? .detected : .notDetected), "\(setup.harness.name)")
        }
    }

    @Test("repository installs are never looked for: the probe reads only the home folder's user places and app and command folders")
    func onlyUserPlaces() {
        let (_, fileSystem) = probe(["/Users/me/Developer/shop/.claude/skills/havooch-mate/SKILL.md": .file])
        let allowed = ["/Users/me/.", "/Users/me/Applications/", "/Applications/", "/opt/homebrew/bin/", "/usr/local/bin/"]
        #expect(!fileSystem.reads.isEmpty)
        for read in fileSystem.reads {
            #expect(allowed.contains { read.hasPrefix($0) }, "\(read)")
        }
        #expect(!fileSystem.reads.contains { $0.contains("Developer") })
    }

    @Test("an install with no harness named is for the harnesses found without the skill")
    func lackingSkill() {
        let (report, _) = probe([
            "/Applications/Claude.app": .folder, "/Users/me/.claude/skills/havooch-mate/SKILL.md": .file,
            "/opt/homebrew/bin/codex": .file,
            "/usr/local/bin/pi": .file,
        ])
        #expect(report.harnessesLackingSkill.map(\.installName) == ["codex", "pi"])
    }
}

@Suite("Linking the command")
struct CommandLinkTests {
    static let home = "/Users/me"
    static let command = "/Applications/Havooch.app/Contents/Helpers/havooch"

    @Test("Link makes ~/.local/bin and the link in it, and the probe then detects it")
    func makes() throws {
        let fileSystem = FakeFileSystem([Self.command: .file])
        let link = CommandLink(fileSystem: fileSystem, home: Self.home)
        try link.make(to: Self.command)
        #expect(fileSystem.items["/Users/me/.local/bin"] == .folder)
        #expect(fileSystem.items["/Users/me/.local/bin/havooch"] == .link(to: Self.command))
        #expect(link.state().detection == .detected)
    }

    @Test("Link replaces a link already there, as ln -sf does")
    func replacesLink() throws {
        let fileSystem = FakeFileSystem(["/Users/me/.local/bin/havooch": .link(to: "/old/Havooch.app/Contents/Helpers/havooch")])
        try CommandLink(fileSystem: fileSystem, home: Self.home).make(to: Self.command)
        #expect(fileSystem.items["/Users/me/.local/bin/havooch"] == .link(to: Self.command))
    }

    @Test("Link leaves a plain file alone, and its failure gives the ln -sf line")
    func plainFile() {
        let fileSystem = FakeFileSystem(["/Users/me/.local/bin/havooch": .file])
        #expect(throws: CommandLink.Failure(
            reason: "/Users/me/.local/bin/havooch is already there and isn't a link, so Havooch leaves it alone",
            fallback: "mkdir -p ~/.local/bin && ln -sf /Applications/Havooch.app/Contents/Helpers/havooch ~/.local/bin/havooch"
        )) {
            try CommandLink(fileSystem: fileSystem, home: Self.home).make(to: Self.command)
        }
        #expect(fileSystem.items["/Users/me/.local/bin/havooch"] == .file)
    }

    @Test("a folder that can't be made fails with the ln -sf line, the path quoted when it needs it")
    func folderFails() {
        let command = "/Users/me/Apps/Havooch (proto-2).app/Contents/Helpers/havooch"
        let fileSystem = FakeFileSystem(failing: ["/Users/me/.local/bin"])
        do {
            try CommandLink(fileSystem: fileSystem, home: Self.home).make(to: command)
            Issue.record("the link was made")
        } catch {
            #expect(error.reason == "Havooch couldn't make /Users/me/.local/bin: Operation not permitted")
            #expect(error.fallback == "mkdir -p ~/.local/bin && ln -sf '/Users/me/Apps/Havooch (proto-2).app/Contents/Helpers/havooch' ~/.local/bin/havooch")
        }
    }
}

@Suite("The harness catalog")
struct HarnessCatalogTests {
    @Test("each harness gets its own prompt form", arguments: [
        (KnownAgent.claude, "/havooch-mate listen for my feedback on cut2.mp4"),
        (.codex, "$havooch-mate listen for my feedback on cut2.mp4"),
        (.cursor, "/havooch-mate listen for my feedback on cut2.mp4"),
        (.pi, "/skill:havooch-mate listen for my feedback on cut2.mp4"),
        (.opencode, "Use the havooch-mate skill to listen for my feedback on cut2.mp4"),
    ])
    func prompts(agent: KnownAgent, prompt: String) {
        #expect(HarnessCatalog.harness(of: agent)?.prompt(for: .video(fileName: "cut2.mp4")) == prompt)
    }

    @Test("the demo prompt asks to open the demo video and listen, in each harness's form", arguments: [
        (KnownAgent.claude, "/havooch-mate use Havooch to open the demo video and listen for my feedback"),
        (.codex, "$havooch-mate use Havooch to open the demo video and listen for my feedback"),
        (.cursor, "/havooch-mate use Havooch to open the demo video and listen for my feedback"),
        (.pi, "/skill:havooch-mate use Havooch to open the demo video and listen for my feedback"),
        (.opencode, "Use the havooch-mate skill to open the demo video in Havooch and listen for my feedback"),
    ])
    func demoPrompts(agent: KnownAgent, prompt: String) {
        #expect(HarnessCatalog.harness(of: agent)?.demoPrompt == prompt)
    }

    @Test("a project's prompt names it as project <slug>")
    func projectPrompt() {
        #expect(HarnessCatalog.harness(of: .codex)?.prompt(for: .project(slug: "launch-video"))
            == "$havooch-mate listen for my feedback on project launch-video")
    }

    @Test("a harness is found by its install name or a name a session carries", arguments: [
        ("claude-code", KnownAgent?.some(.claude)), ("Claude Code", .claude), ("codex", .codex), ("OpenCode", .opencode),
        ("pi", .pi), ("gemini", nil), ("nobody", nil),
    ])
    func names(name: String, agent: KnownAgent?) {
        #expect(HarnessCatalog.harness(named: name)?.agent == agent)
    }
}
