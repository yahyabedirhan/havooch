import Darwin
import Foundation
@testable import ReviewApp
import ReviewWire
import Testing

/// App control's server: how it answers each request (with a fake app), and
/// the real socket, from the command's client to the server and back, in a
/// temporary folder.
@Suite("The control server")
@MainActor
struct ControlServerTests {
    /// A player with a 21.233 s video open (or none), which records each
    /// call and refuses all of them with `refusal` when it's set.
    final class FakeApp: AppControlling {
        var calls: [String] = []
        var refusal: AppRefusal?
        var hasVideo = true
        var time = 0.0
        var playing = false

        func state() -> StateReport {
            StateReport(
                app: .init(version: "0.1.0", variant: "proto-2", demo: true, support: "/demo"),
                video: hasVideo ? .init(path: "/videos/sample.mp4", title: "sample", duration: 21.233) : nil,
                player: .init(time: time, playing: playing)
            )
        }

        private func record(_ call: String) throws(AppRefusal) {
            calls.append(call)
            if let refusal { throw refusal }
        }

        func open(_ url: URL) async throws(AppRefusal) {
            try record("open \(url.path)")
            hasVideo = true
        }

        func play() throws(AppRefusal) {
            try record("play")
            playing = true
        }

        func pause() throws(AppRefusal) {
            try record("pause")
            playing = false
        }

        func seek(to seconds: Double) async throws(AppRefusal) {
            try record("seek \(seconds)")
            time = seconds
        }
    }

    final class FakeScreenshotter: Screenshotting {
        var calls: [String] = []

        func capture(to file: URL, appearance: ControlRequest.Appearance?, withBanner: Bool) async throws(AppRefusal) {
            calls.append("\(file.path) \(appearance?.rawValue ?? "as is")" + (withBanner ? " with banner" : ""))
        }
    }

    static let holder = Holder(key: "agent-1", name: "Claude Code", place: "/Users/me/shop")

    let app = FakeApp()
    let screenshotter = FakeScreenshotter()

    private func server(at socket: URL = URL(fileURLWithPath: "/nowhere/control.sock"), quit: @escaping @MainActor () -> Void = {}) -> ControlServer {
        ControlServer(socket: socket, app: app, screenshotter: screenshotter, quit: quit)
    }

    private func answer(_ request: ControlRequest, json: Bool = false) async -> ControlServer.Answer {
        await server().reply(to: ControlMessage(request, holder: Self.holder, json: json).encoded())
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test("a request of another version is refused, naming both versions, and nothing is done")
    func otherVersion() async throws {
        let other = Version.controlProtocol + 1
        let request = try JSONSerialization.data(withJSONObject: [
            "version": other, "command": "player.play",
            "holder": ["key": "agent-1", "name": "Claude Code", "place": "/Users/me/shop"],
        ])
        let answer = await server().reply(to: request)
        #expect(!answer.reply.ok)
        #expect(answer.reply.error.contains("version \(other)"))
        #expect(answer.reply.error.contains("version \(Version.controlProtocol)"))
        #expect(app.calls.isEmpty)
    }

    @Test("a request that doesn't read is refused in words")
    func unreadable() async {
        let answer = await server().reply(to: Data("hello".utf8))
        #expect(answer.reply == .refused("the request isn't a control request"))
    }

    @Test("player commands reach the app and answer one line")
    func player() async {
        #expect(await answer(.playerOpen(path: "/videos/sample.mp4")).reply == .done("opened sample (0:21.233)\n"))
        #expect(await answer(.playerSeek(seconds: 10)).reply == .done("0:10\n"))
        #expect(await answer(.playerPlay).reply == .done("playing from 0:10\n"))
        #expect(await answer(.playerPause).reply == .done("paused at 0:10\n"))
        #expect(app.calls == ["open /videos/sample.mp4", "seek 10.0", "play", "pause"])
    }

    @Test("with --json an action answers the parts it changed")
    func playerJSON() async throws {
        let seek = try object(await answer(.playerSeek(seconds: 10), json: true).reply.output)
        #expect(seek["player"] as? [String: AnyHashable] == ["time": 10, "playing": false])
        #expect(seek.count == 1)
        let open = try object(await answer(.playerOpen(path: "/videos/sample.mp4"), json: true).reply.output)
        #expect((open["video"] as? [String: Any])?["duration"] as? Double == 21.233)
        #expect(open["player"] != nil)
    }

    @Test("the app's refusal is the reply's error")
    func refusal() async {
        app.refusal = AppRefusal("0:40 is outside the video (0:00 to 0:21.233)")
        #expect(await answer(.playerSeek(seconds: 40)).reply == .refused("0:40 is outside the video (0:00 to 0:21.233)"))
        #expect(app.time == 0)
    }

    @Test("state --json reports the app, the video and the player, with null for what there isn't")
    func stateJSON() async throws {
        app.time = 10
        var state = try object(await answer(.state, json: true).reply.output)
        #expect(state["app"] as? [String: AnyHashable] == ["version": "0.1.0", "variant": "proto-2", "demo": true, "support": "/demo"])
        #expect(state["player"] as? [String: AnyHashable] == ["time": 10, "playing": false])
        #expect(state["video"] as? [String: AnyHashable] == ["path": "/videos/sample.mp4", "title": "sample", "duration": 21.233])
        #expect(state["lease"] is NSNull)

        app.hasVideo = false
        state = try object(await answer(.state, json: true).reply.output)
        #expect(state["video"] is NSNull)
    }

    @Test("state and app status answer lines without --json")
    func lines() async {
        #expect(await answer(.state).reply.output == """
            \(AppIdentity.appName) 0.1.0, demo data in /demo
            video: sample (0:21.233) /videos/sample.mp4
            player: paused at 0:00
            lease: free

            """)
        #expect(await answer(.appStatus).reply.output == """
            running: \(AppIdentity.appName) 0.1.0
            data: demo, /demo
            video: /videos/sample.mp4
            lease: free

            """)
    }

    @Test("app status --json says the app runs and on which data")
    func statusJSON() async throws {
        let status = try object(await answer(.appStatus, json: true).reply.output)
        #expect(status["running"] as? Bool == true)
        #expect(status["demo"] as? Bool == true)
        #expect(status["support"] as? String == "/demo")
        #expect(status["video"] as? String == "/videos/sample.mp4")
        #expect(status["lease"] is NSNull)
    }

    @Test("a screenshot is asked of the screenshotter, in the appearance named")
    func screenshot() async {
        #expect(await answer(.screenshot(path: "/tmp/shot.png", appearance: .dark)).reply == .done("/tmp/shot.png\n"))
        #expect(await answer(.screenshot(path: "/tmp/shot.png", appearance: nil)).reply == .done("/tmp/shot.png\n"))
        #expect(screenshotter.calls == ["/tmp/shot.png dark", "/tmp/shot.png as is"])
    }

    @Test("app quit answers first, and says the app quits")
    func quit() async {
        let answer = await answer(.appQuit)
        #expect(answer.reply.ok)
        #expect(answer.reply.output == "\(AppIdentity.appName) quit\n")
        #expect(answer.quits)
    }

    @Test("the command's client reaches the server over the real socket, which only its user can open")
    func realSocket() async throws {
        // A folder as deep as a worktree's: its socket's path is longer than
        // a socket's address holds. The same folder on every run, so the
        // short link to it is reused, not left behind once per run.
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-review-tests-\(AppIdentity.variant)-socket", isDirectory: true)
            .appendingPathComponent(String(repeating: "deep-", count: 12), isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let socket = ControlSocket.url(in: folder)
        #expect(socket.path.utf8.count > 104)
        let server = server(at: socket)
        try server.start()

        var status = stat()
        #expect(stat(socket.path, &status) == 0)
        #expect(status.st_mode & 0o777 == 0o600)

        let client = ControlClient(socket: socket, holder: Self.holder, transport: UnixSocketTransport())
        let reply = await Task.detached { client.send(.playerSeek(seconds: 10)) }.value
        #expect(reply == .success(.done("0:10\n")))
        #expect(app.calls == ["seek 10.0"])

        server.stop()
        let gone = await Task.detached { client.send(.state) }.value
        #expect(gone == .failure(.notRunning))
    }
}
