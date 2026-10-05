import Foundation
@testable import ReviewApp
import ReviewLease
import ReviewWire
import Testing

/// The fake app's theme: Default Light, with Dimmed to pin.
extension ControlServerTests.FakeApp {
    func themeList() -> StateReport.ThemeList {
        StateReport.ThemeList(
            themes: [
                .init(name: "Default Light", kind: "light", source: "built-in", path: nil, active: true, pinned: false),
                .init(name: "Dimmed", kind: "dark", source: "built-in", path: nil, active: false, pinned: false),
            ],
            problems: []
        )
    }

    func setTheme(_ name: String) throws(AppRefusal) -> StateReport.Theme {
        guard name == "Dimmed" else { throw AppRefusal("no theme \(name); havooch theme list names them") }
        return StateReport.Theme(active: "Dimmed", kind: "dark", pinned: "Dimmed", appearance: "light", overrides: 0)
    }
}

@Suite("The control server's theme requests")
struct ThemeServerTests {
    static let agent = Holder(key: "agent-1", name: "Claude Code", place: "/work")
    static let other = Holder(key: "agent-2", name: "Codex", place: "/elsewhere")

    private func server(_ app: ControlServerTests.FakeApp) -> ControlServer {
        ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: app, listeners: ControlServerTests.noListeners(),
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
    }

    @Test("theme list prints a line per theme, and needs no lease even while another agent holds it")
    func listIsFree() async {
        let server = server(ControlServerTests.FakeApp())
        _ = await server.reply(to: ControlRequest.controlTake(waitSeconds: nil).sent(by: Self.other))
        let reply = await server.reply(to: ControlRequest.themeList.sent(by: Self.agent)).reply
        #expect(reply == .done("Default Light  light  built-in  active\nDimmed         dark   built-in\n"))
    }

    @Test("theme set prints the pinned theme, and needs the lease")
    func setNeedsTheLease() async {
        let server = server(ControlServerTests.FakeApp())
        #expect(await server.reply(to: ControlRequest.themeSet(name: "Dimmed").sent(by: Self.agent)).reply.output == "theme Dimmed pinned\n")
        let refused = await server.reply(to: ControlRequest.themeSet(name: "Dimmed").sent(by: Self.other)).reply
        #expect(!refused.ok)
    }
}
