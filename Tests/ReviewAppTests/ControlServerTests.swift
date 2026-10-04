import Darwin
import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewStore
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
                video: hasVideo
                    ? .init(path: "/videos/sample.mp4", contentHash: "abc", title: "sample", duration: 21.233, contextNote: note) : nil,
                player: .init(time: time, playing: playing),
                comments: comments
            )
        }

        var comments: [StateReport.Comment] = []

        private func comment(_ id: String, _ call: String) throws(AppRefusal) -> Int {
            try record(call)
            guard let index = comments.firstIndex(where: { $0.id == id }) else { throw AppRefusal("no comment `\(id)`") }
            return index
        }

        func addComment(text: String, at: Double?, region: Region?) async throws(AppRefusal) -> StateReport.Comment {
            let place = region.map { " on \($0.text)" } ?? ""
            try record("comment add \(text) at \(at.map { "\($0)" } ?? "the player's time")\(place)")
            let id = "c-0000000\(comments.count + 1)"
            let comment = StateReport.Comment(
                id: id, time: at ?? time, text: text, state: "queued", keyframePath: "/demo/videos/abc/frames/\(id).png",
                region: region, cropPath: region.map { _ in "/demo/videos/abc/crops/\(id).png" }
            )
            comments.append(comment)
            comments.sort { $0.time < $1.time }
            return comment
        }

        func editComment(_ id: String, text: String) throws(AppRefusal) -> StateReport.Comment {
            let index = try comment(id, "comment edit \(id) \(text)")
            comments[index].text = text
            return comments[index]
        }

        func deleteComment(_ id: String) throws(AppRefusal) -> StateReport.Comment {
            comments.remove(at: try comment(id, "comment delete \(id)"))
        }

        var note = ""

        func setContextNote(_ text: String) throws(AppRefusal) -> String {
            try record("context set \(text)")
            note = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return note
        }

        func sendBatch() async throws(AppRefusal) -> StateReport.Batch {
            try record("batch send")
            let queued = comments.indices.filter { comments[$0].state == "queued" }
            guard !queued.isEmpty else { throw AppRefusal("no comment is queued") }
            for index in queued {
                comments[index].state = "sent"
                comments[index].batchId = "b-00000001"
            }
            return StateReport.Batch(
                id: "b-00000001", sentAt: Date(timeIntervalSince1970: 1_790_000_000), commentIds: queued.map { comments[$0].id }
            )
        }

        func answer(_ commentID: String, text: String) throws(AppRefusal) -> StateReport.Comment {
            let index = try comment(commentID, "thread answer \(commentID) \(text)")
            return comments[index]
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
        ControlServer(socket: socket, app: app, listeners: Self.noListeners(), screenshotter: screenshotter, quit: quit)
    }

    /// A listener queue nobody sends a batch to: the fake app has no reviews.
    static func noListeners() -> ListenerQueue {
        ListenerQueue(
            desk: ReviewDesk(library: Library(support: URL(fileURLWithPath: "/demo", isDirectory: true))),
            images: ImageFiles(support: URL(fileURLWithPath: "/demo", isDirectory: true))
        )
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
        #expect(state["video"] as? [String: AnyHashable]
            == ["path": "/videos/sample.mp4", "contentHash": "abc", "title": "sample", "duration": 21.233, "contextNote": ""])
        #expect(state["lease"] is NSNull)
        #expect(state["draft"] is NSNull)
        #expect(state["comments"] as? [AnyHashable] == [])
        #expect(state["queue"] as? [String] == [])
        #expect(state["batches"] as? [AnyHashable] == [])
        #expect(state["listener"] as? [String: AnyHashable] == [
            "presence": "absent", "waitOpen": false, "session": NSNull(), "pendingBatches": 0, "takenBatches": 0,
        ])

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
            transcript: none
            lease: free
            listener: absent, 0 batches waiting, 0 taken
            comments: none

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

    @Test("comment commands reach the app and answer one line")
    func comments() async {
        #expect(await answer(.commentAdd(text: "Too fast", at: 10)).reply == .done("c-00000001 queued at 0:10\n"))
        #expect(await answer(.commentAdd(text: "Good", at: nil)).reply == .done("c-00000002 queued at 0:00\n"))
        #expect(await answer(.commentEdit(id: "c-00000001", text: "Slower")).reply == .done("c-00000001 edited\n"))
        #expect(await answer(.commentDelete(id: "c-00000002")).reply == .done("c-00000002 deleted\n"))
        #expect(await answer(.commentDelete(id: "c-00000002")).reply == .refused("no comment `c-00000002`"))
        #expect(app.calls == [
            "comment add Too fast at 10.0", "comment add Good at the player's time", "comment edit c-00000001 Slower",
            "comment delete c-00000002", "comment delete c-00000002",
        ])
    }

    @Test("a comment on a region reaches the app with its region, and answers with the region and the crop's path")
    func regionComment() async throws {
        let region = ControlRequest.Rectangle(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        #expect(await answer(.commentAdd(text: "This box", at: 12.5, region: region)).reply
            == .done("c-00000001 queued at 0:12.5 on the region 0.25,0.2,0.3,0.25\n"))
        #expect(app.calls == ["comment add This box at 12.5 on 0.25,0.2,0.3,0.25"])

        let added = try object(await answer(.commentAdd(text: "That box", at: 3, region: region), json: true).reply.output)
        let comment = try #require(added["comment"] as? [String: Any])
        #expect(comment["region"] as? [String: Double] == ["x": 0.25, "y": 0.2, "w": 0.3, "h": 0.25])
        #expect(comment["cropPath"] as? String == "/demo/videos/abc/crops/c-00000002.png")
        #expect(await answer(.state).reply.output.contains("  c-00000001 0:12.5 region 0.25,0.2,0.3,0.25 queued: This box\n"))
    }

    @Test("numbers that aren't a region of the frame are refused before the app is asked", arguments: [
        ControlRequest.Rectangle(x: 0.9, y: 0.2, w: 0.3, h: 0.25), .init(x: 0.25, y: 0.2, w: 0, h: 0.25),
        .init(x: -0.1, y: 0.2, w: 0.3, h: 0.25), .init(x: 0.25, y: 0.2, w: 0.3, h: 1.5),
    ])
    func badRegion(rectangle: ControlRequest.Rectangle) async {
        let reply = await answer(.commentAdd(text: "This box", at: 12.5, region: rectangle)).reply
        #expect(!reply.ok)
        #expect(reply.error.hasPrefix("the region \(rectangle.x),\(rectangle.y),\(rectangle.w),\(rectangle.h) isn't a rectangle inside the frame"))
        #expect(app.calls.isEmpty)
    }

    @Test("state --json lists the comments in time order, and the queue by id")
    func commentsJSON() async throws {
        let added = try object(await answer(.commentAdd(text: "Later", at: 12.5), json: true).reply.output)
        #expect(added["comment"] as? [String: AnyHashable] == [
            "id": "c-00000001", "time": 12.5, "text": "Later", "state": "queued",
            "keyframePath": "/demo/videos/abc/frames/c-00000001.png", "region": NSNull(), "cropPath": NSNull(),
            "batchId": NSNull(), "thread": [] as [String],
        ])
        #expect(added.count == 1)
        _ = await answer(.commentAdd(text: "Earlier", at: 3))

        let state = try object(await answer(.state, json: true).reply.output)
        let comments = try #require(state["comments"] as? [[String: Any]])
        #expect(comments.map { $0["id"] as? String } == ["c-00000002", "c-00000001"])
        #expect(comments.map { $0["time"] as? Double } == [3, 12.5])
        #expect(state["queue"] as? [String] == ["c-00000002", "c-00000001"])
        #expect(await answer(.state).reply.output.hasSuffix("""
            comments: 2 (2 queued)
              c-00000002 0:03 queued: Earlier
              c-00000001 0:12.5 queued: Later

            """))

        let deleted = try object(await answer(.commentDelete(id: "c-00000001"), json: true).reply.output)
        #expect(deleted as? [String: String] == ["deleted": "c-00000001"])
    }

    @Test("context set reaches the app and answers what it kept; with --json, the video with its note")
    func contextSet() async throws {
        #expect(await answer(.contextSet(text: " Compare with the old cut \n")).reply == .done("context note set (24 characters)\n"))
        #expect(app.calls == ["context set  Compare with the old cut \n"])
        let set = try object(await answer(.contextSet(text: "Mind the intro"), json: true).reply.output)
        #expect((set["video"] as? [String: Any])?["contextNote"] as? String == "Mind the intro")
        #expect(set.count == 1)
        let state = try object(await answer(.state, json: true).reply.output)
        #expect((state["video"] as? [String: Any])?["contextNote"] as? String == "Mind the intro")
        #expect(await answer(.contextSet(text: "")).reply == .done("context note cleared\n"))
        app.refusal = AppRefusal("no video is open; open one with `video-review player open <path>`")
        #expect(await answer(.contextSet(text: "note")).reply
            == .refused("no video is open; open one with `video-review player open <path>`"))
    }

    @Test("batch send reaches the app and answers the batch's id and how many comments it carries")
    func batchSend() async throws {
        #expect(await answer(.batchSend).reply == .refused("no comment is queued"))
        _ = await answer(.commentAdd(text: "Too fast", at: 10))
        _ = await answer(.commentAdd(text: "Good", at: 3))

        #expect(await answer(.batchSend).reply == .done("b-00000001 sent with 2 comments, waiting for a listener\n"))
        #expect(app.calls.suffix(1) == ["batch send"])
        #expect(await answer(.state).reply.output.contains("  c-00000001 0:10 sent: Too fast\n"))

        _ = await answer(.commentAdd(text: "One more", at: 5))
        let sent = try object(await answer(.batchSend, json: true).reply.output)
        #expect(sent["batch"] as? [String: AnyHashable]
            == ["id": "b-00000001", "sentAt": "2026-09-21T14:13:20Z", "commentIds": ["c-00000003"], "messages": [] as [String]])
        #expect(sent.count == 1)
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
