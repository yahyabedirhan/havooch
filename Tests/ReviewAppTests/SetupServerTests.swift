import Foundation
@testable import ReviewApp
import ReviewLease
import ReviewSetup
import ReviewWire
import Testing

/// The fake app's setup: the command line linked, Claude Code with its
/// skill, Codex without, and an install that starts and stops at once.
extension ControlServerTests.FakeApp {
    static let fakeSetup = StateReport.Setup(
        commandLine: .init(
            detection: "detected", path: "/Users/me/.local/bin/havooch",
            destination: "/Applications/Havooch.app/Contents/Helpers/havooch",
            command: "/Applications/Havooch.app/Contents/Helpers/havooch"
        ),
        harnesses: [
            .init(name: "Claude Code", installName: "claude-code", presence: "detected", skill: "detected",
                  skillFolder: "/Users/me/.claude/skills/havooch-mate", prompt: "/havooch-mate listen for my feedback on sample.mp4"),
            .init(name: "Codex", installName: "codex", presence: "detected", skill: "notDetected",
                  prompt: "$havooch-mate listen for my feedback on sample.mp4"),
        ]
    )

    func setupStatus() -> StateReport.Setup {
        Self.fakeSetup
    }

    func linkCommand(dryRun: Bool) throws(AppRefusal) -> (line: String, setup: StateReport.Setup) {
        ("linked /Users/me/.local/bin/havooch to /Applications/Havooch.app/Contents/Helpers/havooch", Self.fakeSetup)
    }

    func installSkill(harnesses: [String], dryRun: Bool) throws(AppRefusal) -> StateReport.Setup.Install {
        StateReport.Setup.Install(SkillInstall(for: [HarnessCatalog.harness(named: "codex")!]), state: dryRun ? "planned" : "running")
    }

    func cancelInstall() async throws(AppRefusal) -> StateReport.Setup.Install {
        StateReport.Setup.Install(SkillInstall(for: [HarnessCatalog.harness(named: "codex")!]), state: "cancelled", log: ["stopped"])
    }
}

@Suite("The control server's setup requests")
struct SetupServerTests {
    static let agent = Holder(key: "agent-1", name: "Claude Code", place: "/work")
    static let other = Holder(key: "agent-2", name: "Codex", place: "/elsewhere")

    private func server() -> ControlServer {
        ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: ControlServerTests.FakeApp(),
            listeners: ControlServerTests.noListeners(), screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
    }

    @Test("setup status prints the link and a row per harness, and needs no lease even while another agent holds it")
    func statusIsFree() async {
        let server = server()
        _ = await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent(by: Self.other))
        let reply = await server.reply(to: ControlRequest.setupStatus.sent(by: Self.agent)).reply
        #expect(reply == .done("""
            command line: detected, /Users/me/.local/bin/havooch links to /Applications/Havooch.app/Contents/Helpers/havooch
            harnesses:
              Claude Code  harness detected, skill detected in /Users/me/.claude/skills/havooch-mate
              Codex        harness detected, skill not detected

            """))
    }

    @Test("setup status --json names each detection, never missing")
    func statusJSON() async throws {
        let reply = await server().reply(to: ControlRequest.setupStatus.sent(by: Self.agent, json: true)).reply
        let output = try #require(reply.output)
        #expect(output.contains("\"skill\" : \"notDetected\""))
        #expect(!output.lowercased().contains("missing"))
    }

    @Test("setup link, install and cancel need the lease")
    func needTheLease() async {
        let server = server()
        _ = await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent(by: Self.other))
        for request in [ControlRequest.setupLink(), .setupInstall(), .setupCancel] {
            #expect(await server.reply(to: request.sent(by: Self.agent)).reply.ok == false)
        }
    }

    @Test("setup install prints what it runs and how to follow it; a dry run only the command")
    func install() async {
        let server = server()
        #expect(await server.reply(to: ControlRequest.setupInstall().sent(by: Self.agent)).reply.output == """
            install: running for Codex: npx skills add yahyabedirhan/havooch-mate --skill havooch-mate -g -y -a codex
            havooch setup status follows its log; havooch setup cancel stops it

            """)
        #expect(await server.reply(to: ControlRequest.setupInstall(dryRun: true).sent(by: Self.agent)).reply.output
            == "would run: npx skills add yahyabedirhan/havooch-mate --skill havooch-mate -g -y -a codex\n")
        #expect(await server.reply(to: ControlRequest.setupCancel.sent(by: Self.agent)).reply.output
            == "install: cancelled for Codex: npx skills add yahyabedirhan/havooch-mate --skill havooch-mate -g -y -a codex\n")
    }
}
