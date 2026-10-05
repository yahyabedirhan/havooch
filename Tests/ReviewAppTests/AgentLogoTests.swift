import AppKit
import Foundation
@testable import ReviewApp
import ReviewCore
import Testing

/// Every known agent's logo is a file the app bundles: an agent added to
/// `KnownAgent`, or a logo renamed, without its PDF in `AgentLogos` would
/// show an empty mark.
@Suite("Agent logos")
struct AgentLogoTests {
    @Test("every known agent's logo loads, in light and dark mode, and a template logo is a template image", arguments: KnownAgent.allCases)
    func bundled(agent: KnownAgent) throws {
        for dark in [false, true] {
            let image = try #require(AgentLogoImage.image(for: agent, dark: dark), "\(agent) has no logo (dark: \(dark))")
            #expect(image.size.width > 0 && image.size.height > 0)
            #expect(image.isTemplate == (agent.logo.look == .template))
        }
    }

    @Test("every bundled logo has its maker's SVG beside it, and the notice names every agent")
    func sources() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let pdfs = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Packaging/AgentLogos").path)
            .filter { $0.hasSuffix(".pdf") }
        #expect(pdfs.count == 10)
        for pdf in pdfs {
            let svg = root.appendingPathComponent("assets/images/agent-logos/\(pdf.dropLast(4)).svg")
            #expect(FileManager.default.fileExists(atPath: svg.path), "\(pdf) has no SVG")
        }
        let notice = try String(contentsOf: root.appendingPathComponent("Packaging/AgentLogos/NOTICE.md"), encoding: .utf8)
        for name in ["Claude", "Codex", "OpenCode", "Cursor", "Pi", "Gemini", "GitHub Copilot", "Amp", "Droid"] {
            #expect(notice.contains("| \(name) |"), "the notice doesn't name \(name)")
        }
        #expect(notice.components(separatedBy: "MIT License").count - 1 == 3)
        #expect(notice.contains("implies no endorsement"))
    }

    @Test("a notice shows the logo of the agent its name says, and the symbol for an unknown one")
    func notice() {
        let thread = ThreadID(.thread, hash8: "f92cbb2a", number: 1)
        #expect(Notice(thread: thread, kind: .message, agent: "Claude Code", text: "Done", at: .now).knownAgent == .claude)
        #expect(Notice(thread: thread, kind: .message, agent: "The agent", text: "Done", at: .now).knownAgent == nil)
    }
}
