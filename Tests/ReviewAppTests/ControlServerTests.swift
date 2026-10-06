import Darwin
import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire
import Testing

/// App control's server: how it answers each request (with a fake app), and
/// the real socket, from the command's client to the server and back, in a
/// temporary folder.
@Suite("The control server")
struct ControlServerTests {
    /// A player with a 21.233 s video open (or none), which records each
    /// call and refuses all of them with `refusal` when it's set.
    final class FakeApp: AppControlling {
        var calls: [String] = []
        var refusal: AppRefusal?
        var hasVideo = true
        var time = 0.0
        var playing = false

        /// The open video's content hash, and its review, kept in memory.
        static let hash = "abcdef0123"
        static let layout = SupportLayout(root: URL(fileURLWithPath: "/demo", isDirectory: true))
        var review = VideoReview(video: VideoInfo(contentHash: hash, title: "sample", duration: 21.233, path: "/videos/sample.mp4"))
        static let sentAt = Date(timeIntervalSince1970: 1_790_000_000)

        func state() -> StateReport {
            var report = StateReport(
                app: .init(version: "0.2.0", demo: true, support: "/demo"),
                video: hasVideo
                    ? .init(path: "/videos/sample.mp4", contentHash: Self.hash, title: "sample", duration: 21.233, contextNote: note) : nil,
                player: .init(time: time, playing: playing),
                threads: review.threads.map { StateReport.Thread($0, contentHash: Self.hash, layout: Self.layout) },
                queue: review.queue.map(\.id.text),
                sends: review.sends.map { StateReport.Send($0, in: review) }
            )
            report.sidebar = StateReport.Sidebar(thread: shown, width: 340)
            return report
        }

        private func change<Result>(_ call: String, _ change: (inout VideoReview) throws(ReviewRefusal) -> Result) throws(AppRefusal) -> Result {
            try record(call)
            do throws(ReviewRefusal) {
                return try change(&review)
            } catch {
                throw AppRefusal(error.line)
            }
        }

        private func id(_ text: String) throws(AppRefusal) -> ItemID {
            guard let id = ItemID(text) else { throw AppRefusal(ReviewRefusal.unknownID(text).line) }
            return id
        }

        func addMessage(
            text: String, at: Double?, region: Region?, thread: String?
        ) async throws(AppRefusal) -> (message: StateReport.Message, thread: StateReport.Thread) {
            let place = region.map { " on \($0.text)" } ?? ""
            let on = thread.map { " on thread \($0)" } ?? ""
            let written = try change("comment add \(text) at \(at.map { "\($0)" } ?? "the player's time")\(place)\(on)") {
                review throws(ReviewRefusal) in
                let target = try thread.flatMap(ThreadRef.init).map { ref throws(ReviewRefusal) in try review.threadID(ref) }
                return try review.write(text: text, at: target == nil ? (at ?? time) : at, region: region, to: target, now: Self.sentAt)
            }
            return (
                StateReport.Message(written.message, contentHash: Self.hash, layout: Self.layout),
                StateReport.Thread(written.thread, contentHash: Self.hash, layout: Self.layout)
            )
        }

        func openPopover(text: String, region: Region?) throws(AppRefusal) -> StateReport.Popover {
            try record("comment open \(text)\(region.map { " on \($0.text)" } ?? "")")
            return StateReport.Popover(thread: review.nextThreadNumber, time: time, text: text, region: region)
        }

        func editMessage(_ id: String, text: String) throws(AppRefusal) -> StateReport.Message {
            let messageID = try self.id(id)
            let message = try change("comment edit \(id) \(text)") { review throws(ReviewRefusal) in try review.edit(messageID, text: text) }
            return StateReport.Message(message, contentHash: Self.hash, layout: Self.layout)
        }

        func deleteMessage(_ id: String) throws(AppRefusal) -> StateReport.Message {
            let messageID = try self.id(id)
            let deleted = try change("comment delete \(id)") { review throws(ReviewRefusal) in try review.delete(messageID) }
            return StateReport.Message(deleted.message, contentHash: Self.hash, layout: Self.layout)
        }

        var note = ""

        func setContextNote(_ text: String) throws(AppRefusal) -> String {
            try record("context set \(text)")
            note = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return note
        }

        func sendQueue() async throws(AppRefusal) -> StateReport.Send {
            let send = try change("send") { review throws(ReviewRefusal) in try review.send(at: Self.sentAt) }
            return StateReport.Send(send, in: review)
        }

        func answer(_ thread: String, text: String) throws(AppRefusal) -> (message: StateReport.Message, number: Int) {
            let threadID = try id(thread)
            let message = try change("thread answer \(thread) \(text)") { review throws(ReviewRefusal) in
                try review.answer(threadID, text: text, now: Self.sentAt)
            }
            return (StateReport.Message(message, contentHash: Self.hash, layout: Self.layout), threadID.number)
        }

        func openThread(_ thread: String, frame: PopoverFrame?) async throws(AppRefusal) -> StateReport.Popover {
            let place = frame.map { " at \($0.x),\($0.y),\($0.w),\($0.h)" } ?? ""
            try record("thread open \(thread)\(place)")
            let id = try self.id(thread)
            guard let time = review.thread(id)?.time else { throw AppRefusal(ReviewRefusal.unknownID(thread).line) }
            return StateReport.Popover(thread: id.number, time: time, text: "", region: nil)
        }

        /// The thread the sidebar shows; nil for the thread list.
        var shown: String?

        func showThread(_ thread: String) async throws(AppRefusal) -> (sidebar: StateReport.Sidebar, number: Int) {
            try record("thread show \(thread)")
            let threadID = try id(thread)
            guard review.thread(threadID) != nil else { throw AppRefusal(ReviewRefusal.unknownID(thread).line) }
            shown = threadID.text
            return (StateReport.Sidebar(thread: shown, width: 340), threadID.number)
        }

        func showThreadList() -> StateReport.Sidebar {
            calls.append("thread list")
            shown = nil
            return StateReport.Sidebar(thread: nil, width: 340)
        }

        func compose(text: String, region: Region?, general: Bool) throws(AppRefusal) -> StateReport.Sidebar.Composer {
            try record("comment compose \(text)\(region.map { " on \($0.text)" } ?? "")\(general ? " general" : "")")
            return StateReport.Sidebar.Composer(
                target: general ? "Reply on General" : "New thread at 0:12", kind: general ? "reply" : "new", thread: nil, number: general ? 0 : 2, time: general ? nil : 12.5,
                general: general, text: text, region: region
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

        func capture(
            to file: URL, appearance: ControlRequest.Appearance?, hideAgentIndicator: Bool, window: ControlRequest.Window
        ) async throws(AppRefusal) {
            calls.append(
                "\(file.path) \(appearance?.rawValue ?? "as is")" + (hideAgentIndicator ? " without the indicator" : "")
                    + (window == .main ? "" : " of \(window.rawValue)")
            )
        }
    }

    static let holder = Holder(key: "agent-1", name: "Claude Code", place: "/Users/me/shop")

    let app = FakeApp()
    let screenshotter = FakeScreenshotter()

    private func server(at socket: URL = URL(fileURLWithPath: "/nowhere/control.sock"), quit: @escaping @MainActor () -> Void = {}) -> ControlServer {
        ControlServer(socket: socket, app: app, listeners: Self.noListeners(), screenshotter: screenshotter, quit: quit)
    }

    /// A listener queue nobody sends to: the fake app has no reviews on disk.
    static func noListeners() -> ListenerQueue {
        ListenerQueue(
            desk: ReviewDesk(library: Library(layout: SupportLayout(root: URL(fileURLWithPath: "/demo", isDirectory: true)))),
            layout: SupportLayout(root: URL(fileURLWithPath: "/demo", isDirectory: true))
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
        #expect(state["app"] as? [String: AnyHashable] == ["version": "0.2.0", "demo": true, "support": "/demo"])
        #expect(state["player"] as? [String: AnyHashable] == ["time": 10, "playing": false])
        #expect(state["video"] as? [String: AnyHashable]
            == ["path": "/videos/sample.mp4", "contentHash": "abcdef0123", "title": "sample", "duration": 21.233, "contextNote": ""])
        #expect(state["lease"] is NSNull)
        #expect(state["popover"] is NSNull)
        #expect(state["threads"] as? [[String: AnyHashable]] == [[
            "id": "t-abcdef01-0", "number": 0, "time": NSNull(), "state": NSNull(), "keyframePath": NSNull(),
            "popoverFrame": NSNull(), "unread": false, "messages": [] as [String],
        ]])
        #expect(state["queue"] as? [String] == [])
        #expect(state["sends"] as? [AnyHashable] == [])
        #expect(state["listener"] as? [String: AnyHashable] == [
            "presence": "absent", "waitOpen": false, "session": NSNull(), "pendingSends": 0, "takenSends": 0,
        ])

        app.hasVideo = false
        state = try object(await answer(.state, json: true).reply.output)
        #expect(state["video"] is NSNull)
    }

    @Test("state and app status answer lines without --json")
    func lines() async {
        #expect(await answer(.state).reply.output == """
            \(AppIdentity.appName) 0.2.0, demo data in /demo
            video: sample (0:21.233) /videos/sample.mp4
            player: paused at 0:00
            transcript: none
            lease: free
            listener: absent, 0 sends waiting, 0 taken
            threads: 1 (0 queued)
              #0 General t-abcdef01-0 -

            """)
        #expect(await answer(.appStatus).reply.output == """
            running: \(AppIdentity.appName) 0.2.0
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

    @Test("comment commands reach the app and answer one line, with the message's id and its thread's number")
    func comments() async {
        #expect(await answer(.commentAdd(text: "Too fast", at: 10)).reply == .done("m-abcdef01-1 queued on #1 at 0:10\n"))
        #expect(await answer(.commentAdd(text: "Same frame", at: 10)).reply == .done("m-abcdef01-2 queued on #1 at 0:10\n"))
        #expect(await answer(.commentAdd(text: "Good", at: nil)).reply == .done("m-abcdef01-3 queued on #2 at 0:00\n"))
        #expect(await answer(.commentAdd(text: "In general", at: nil, thread: "0")).reply == .done("m-abcdef01-4 queued on #0\n"))
        #expect(await answer(.commentAdd(text: "Follow-up", at: nil, thread: "t-abcdef01-1")).reply
            == .done("m-abcdef01-5 queued on #1 at 0:10\n"))
        #expect(await answer(.commentEdit(id: "m-abcdef01-1", text: "Slower")).reply == .done("m-abcdef01-1 edited\n"))
        #expect(await answer(.commentDelete(id: "m-abcdef01-2")).reply == .done("m-abcdef01-2 deleted\n"))
        #expect(await answer(.commentDelete(id: "m-abcdef01-2")).reply == .refused(ReviewRefusal.unknownID("m-abcdef01-2").line))
        #expect(app.calls == [
            "comment add Too fast at 10.0", "comment add Same frame at 10.0", "comment add Good at the player's time",
            "comment add In general at the player's time on thread 0", "comment add Follow-up at the player's time on thread t-abcdef01-1",
            "comment edit m-abcdef01-1 Slower", "comment delete m-abcdef01-2", "comment delete m-abcdef01-2",
        ])
    }

    @Test("comment open reaches the app with its words and region, and answers with the thread number and the time")
    func commentOpen() async throws {
        app.time = 12.5
        #expect(await answer(.commentOpen(text: "")).reply == .done("popover open on #1 at 0:12.5\n"))
        let region = ControlRequest.Rectangle(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        #expect(await answer(.commentOpen(text: "This box", region: region)).reply
            == .done("popover open on #1 at 0:12.5 on the region 0.25,0.2,0.3,0.25\n"))
        let opened = try object(await answer(.commentOpen(text: "Again"), json: true).reply.output)
        let popover = try #require(opened["popover"] as? [String: Any])
        #expect(popover["thread"] as? Int == 1)
        #expect(popover["text"] as? String == "Again")
        #expect(popover["region"] is NSNull)
        // Numbers that aren't a region are refused before the app is asked.
        let outside = ControlRequest.Rectangle(x: 0.9, y: 0, w: 0.5, h: 0.5)
        #expect(await answer(.commentOpen(text: "", region: outside)).reply.ok == false)
        #expect(app.calls == ["comment open ", "comment open This box on 0.25,0.2,0.3,0.25", "comment open Again"])
    }

    @Test("comment compose reaches the app with its words, region and General toggle, and answers with what the composer says it writes to")
    func commentCompose() async throws {
        #expect(await answer(.commentCompose(text: "Too fast")).reply == .done("the composer says \"New thread at 0:12\"\n"))
        let region = ControlRequest.Rectangle(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        #expect(await answer(.commentCompose(text: "", region: region)).reply
            == .done("the composer says \"New thread at 0:12\" with the region 0.25,0.2,0.3,0.25\n"))
        let printed = try object(await answer(.commentCompose(text: "Overall", general: true), json: true).reply.output)
        let composer = try #require(printed["composer"] as? [String: Any])
        #expect(composer["target"] as? String == "Reply on General")
        #expect(composer["kind"] as? String == "reply")
        #expect(composer["general"] as? Bool == true)
        #expect(composer["text"] as? String == "Overall")
        #expect(composer["time"] is NSNull)
        // Numbers that aren't a region are refused before the app is asked.
        #expect(await answer(.commentCompose(text: "", region: .init(x: 0.9, y: 0, w: 0.5, h: 0.5))).reply.ok == false)
        #expect(app.calls == ["comment compose Too fast", "comment compose  on 0.25,0.2,0.3,0.25", "comment compose Overall general"])
    }

    @Test("`thread open` opens a thread's popover, kept at a frame when it names one; a frame outside the video area is refused first")
    func threadOpen() async throws {
        _ = try await app.addMessage(text: "Here", at: 12.5, region: nil, thread: nil)
        #expect(await answer(.threadOpen(thread: "t-abcdef01-1")).reply == .done("popover open on #1 at 0:12.5\n"))
        let frame = ControlRequest.Rectangle(x: 0.55, y: 0.1, w: 0.4, h: 0.5)
        let opened = try object(await answer(.threadOpen(thread: "t-abcdef01-1", frame: frame), json: true).reply.output)
        let popover = try #require(opened["popover"] as? [String: Any])
        #expect(popover["thread"] as? Int == 1)
        #expect(popover["time"] as? Double == 12.5)
        let outside = ControlRequest.Rectangle(x: 0.8, y: 0, w: 0.4, h: 0.5)
        #expect(await answer(.threadOpen(thread: "t-abcdef01-1", frame: outside)).reply.ok == false)
        #expect(await answer(.threadOpen(thread: "t-abcdef01-9")).reply.ok == false)
        #expect(app.calls.dropFirst() == [
            "thread open t-abcdef01-1", "thread open t-abcdef01-1 at 0.55,0.1,0.4,0.5", "thread open t-abcdef01-9",
        ])
    }

    @Test("`thread show` shows a thread's view and `thread list` the list; the state report names the thread the sidebar shows, or null")
    func threadShowAndList() async throws {
        _ = try await app.addMessage(text: "Here", at: 12.5, region: nil, thread: nil)
        var sidebar = try #require(try object(await answer(.state, json: true).reply.output)["sidebar"] as? [String: Any])
        #expect(sidebar["thread"] is NSNull)

        #expect(await answer(.threadShow(thread: "t-abcdef01-1")).reply == .done("the sidebar shows #1\n"))
        sidebar = try #require(try object(await answer(.state, json: true).reply.output)["sidebar"] as? [String: Any])
        #expect(sidebar["thread"] as? String == "t-abcdef01-1")
        let shown = try object(await answer(.threadShow(thread: "t-abcdef01-0"), json: true).reply.output)
        #expect(shown["sidebar"] as? [String: AnyHashable] == ["thread": "t-abcdef01-0", "width": 340, "composer": NSNull()])
        #expect(shown.count == 1)
        #expect(await answer(.threadShow(thread: "t-abcdef01-9")).reply.ok == false)

        #expect(await answer(.threadList).reply == .done("the sidebar shows the thread list\n"))
        let listed = try object(await answer(.threadList, json: true).reply.output)
        #expect((listed["sidebar"] as? [String: Any])?["thread"] is NSNull)
        sidebar = try #require(try object(await answer(.state, json: true).reply.output)["sidebar"] as? [String: Any])
        #expect(sidebar["thread"] is NSNull)
        #expect(app.calls.dropFirst() == [
            "thread show t-abcdef01-1", "thread show t-abcdef01-0", "thread show t-abcdef01-9", "thread list", "thread list",
        ])
    }

    @Test("a message on a region reaches the app with its region, and answers with the region, the crop's path and the thread")
    func regionComment() async throws {
        let region = ControlRequest.Rectangle(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        #expect(await answer(.commentAdd(text: "This box", at: 12.5, region: region)).reply
            == .done("m-abcdef01-1 queued on #1 at 0:12.5 on the region 0.25,0.2,0.3,0.25\n"))
        #expect(app.calls == ["comment add This box at 12.5 on 0.25,0.2,0.3,0.25"])

        let added = try object(await answer(.commentAdd(text: "That box", at: 12.5, region: region), json: true).reply.output)
        #expect(Set(added.keys) == ["message", "thread"])
        let message = try #require(added["message"] as? [String: Any])
        #expect(message["region"] as? [String: Double] == ["x": 0.25, "y": 0.2, "w": 0.3, "h": 0.25])
        #expect(message["cropPath"] as? String == "/demo/videos/abcdef0123/crops/m-abcdef01-2.png")
        #expect(added["thread"] as? [String: AnyHashable] == ["id": "t-abcdef01-1", "number": 1])
        #expect(await answer(.state).reply.output.contains("    m-abcdef01-1 person message queued region 0.25,0.2,0.3,0.25: This box\n"))
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

    @Test("state --json lists the threads, General first then in time order, their messages and states, and the queue by id")
    func commentsJSON() async throws {
        let added = try object(await answer(.commentAdd(text: "Later", at: 12.5), json: true).reply.output)
        #expect(added["message"] as? [String: AnyHashable] == [
            "id": "m-abcdef01-1", "author": "person", "kind": "message", "text": "Later", "at": "2026-09-21T14:13:20Z",
            "state": "queued", "region": NSNull(), "cropPath": NSNull(), "sendId": NSNull(),
        ])
        _ = await answer(.commentAdd(text: "Earlier", at: 3))

        let state = try object(await answer(.state, json: true).reply.output)
        let threads = try #require(state["threads"] as? [[String: Any]])
        #expect(threads.map { $0["id"] as? String } == ["t-abcdef01-0", "t-abcdef01-2", "t-abcdef01-1"])
        #expect(threads.map { $0["time"] as? Double } == [nil, 3, 12.5])
        #expect(threads.map { $0["state"] as? String } == [nil, "queued", "queued"])
        #expect(threads[1]["keyframePath"] as? String == "/demo/videos/abcdef0123/frames/t-abcdef01-2.png")
        #expect(state["queue"] as? [String] == ["m-abcdef01-2", "m-abcdef01-1"])
        #expect(await answer(.state).reply.output.hasSuffix("""
            threads: 3 (2 queued)
              #0 General t-abcdef01-0 -
              #2 at 0:03 t-abcdef01-2 queued
                m-abcdef01-2 person message queued: Earlier
              #1 at 0:12.5 t-abcdef01-1 queued
                m-abcdef01-1 person message queued: Later

            """))

        let deleted = try object(await answer(.commentDelete(id: "m-abcdef01-1"), json: true).reply.output)
        #expect(deleted as? [String: String] == ["deleted": "m-abcdef01-1"])
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
        app.refusal = AppRefusal("no video is open; open one with `havooch player open <path>`")
        #expect(await answer(.contextSet(text: "note")).reply
            == .refused("no video is open; open one with `havooch player open <path>`"))
    }

    @Test("send reaches the app and answers the send's id, how many messages it carries and on how many threads")
    func send() async throws {
        #expect(await answer(.send).reply == .refused(ReviewRefusal.nothingQueued.line))
        _ = await answer(.commentAdd(text: "Too fast", at: 10))
        _ = await answer(.commentAdd(text: "Here too", at: 10))
        _ = await answer(.commentAdd(text: "Good", at: 3))

        #expect(await answer(.send).reply == .done("s-abcdef01-1 sent: 3 messages on 2 threads, waiting for a listener\n"))
        #expect(app.calls.suffix(1) == ["send"])
        #expect(await answer(.state).reply.output.contains("    m-abcdef01-1 person message sent: Too fast\n"))

        _ = await answer(.commentAdd(text: "One more", at: 5))
        let sent = try object(await answer(.send, json: true).reply.output)
        #expect(sent["send"] as? [String: AnyHashable]
            == ["id": "s-abcdef01-2", "sentAt": "2026-09-21T14:13:20Z", "messageIds": ["m-abcdef01-4"], "threadIds": ["t-abcdef01-3"]])
        #expect(sent.count == 1)
    }

    @Test("a screenshot is asked of the screenshotter, in the appearance named")
    func screenshot() async {
        #expect(await answer(.screenshot(path: "/tmp/shot.png", appearance: .dark)).reply == .done("/tmp/shot.png\n"))
        #expect(await answer(.screenshot(path: "/tmp/shot.png", appearance: nil)).reply == .done("/tmp/shot.png\n"))
        #expect(await answer(.screenshot(path: "/tmp/set.png", appearance: .light, window: .settings)).reply == .done("/tmp/set.png\n"))
        #expect(screenshotter.calls == ["/tmp/shot.png dark", "/tmp/shot.png as is", "/tmp/set.png light of settings"])
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
            .appendingPathComponent("havooch-tests-socket", isDirectory: true)
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
        let reply = await LeaseServerTests.sending { client.send(.playerSeek(seconds: 10)) }
        #expect(reply == .success(.done("0:10\n")))
        #expect(app.calls == ["seek 10.0"])

        server.stop()
        let gone = await LeaseServerTests.sending { client.send(.state) }
        #expect(gone == .failure(.notRunning))
    }
}
