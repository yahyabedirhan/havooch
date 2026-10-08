import AppKit
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
    /// call and refuses all of them with `refusal` when it's set. It is the
    /// app and its one window, `w1`.
    final class FakeApp: AppControlling, WindowControlling {
        let id = "w1"
        var nsWindow: NSWindow? { nil }
        var calls: [String] = []
        var refusal: AppRefusal?
        var hasVideo = true
        var time = 0.0
        var playing = false

        /// The open video's content hash, and its review, kept in memory.
        static let hash = "abcdef0123"
        static let layout = SupportLayout(root: URL(fileURLWithPath: "/demo", isDirectory: true))
        var review = Review(video: VideoInfo(contentHash: hash, title: "sample", duration: 21.233, path: "/videos/sample.mp4"))
        static let sentAt = Date(timeIntervalSince1970: 1_790_000_000)

        func state() -> StateReport {
            var report = StateReport(
                app: .init(version: "0.4.1", demo: true, support: "/demo", active: active),
                video: hasVideo
                    ? .init(path: "/videos/sample.mp4", contentHash: Self.hash, title: "sample", duration: 21.233, contextNote: note) : nil,
                player: .init(time: time, playing: playing),
                threads: review.threads.map { StateReport.Thread($0, review: .video(contentHash: Self.hash), layout: Self.layout) },
                queue: review.queue.map(\.id.text),
                sends: review.sends.map { StateReport.Send($0, in: review) }
            )
            report.sidebar = StateReport.Sidebar(thread: shown, width: 340)
            report.screen = hasVideo ? .player : .home
            report.window = id
            report.windows = windowList()
            return report
        }

        func state(window: String?) throws(AppRefusal) -> StateReport {
            _ = try controlledWindow(window, making: false)
            return state()
        }

        func controlledWindow(_ id: String?, making: Bool) throws(AppRefusal) -> any WindowControlling {
            if let id, id != self.id { throw AppRefusal("no window `\(id)`; the windows are w1") }
            return self
        }

        func windowList() -> [StateReport.Window] {
            [StateReport.Window(
                id: id, key: true, onScreen: true, screen: hasVideo ? .player : .home,
                video: hasVideo ? .init(path: "/videos/sample.mp4", title: "sample", contentHash: Self.hash) : nil
            )]
        }

        func openWindow() -> StateReport.Window {
            calls.append("new window")
            return StateReport.Window(id: "w2", key: false, onScreen: false, screen: .home, video: nil)
        }

        func closeWindow(_ id: String?) throws(AppRefusal) -> StateReport.Window {
            _ = try controlledWindow(id, making: false)
            try record("close window")
            return windowList()[0]
        }

        private func change<Result>(_ call: String, _ change: (inout Review) throws(ReviewRefusal) -> Result) throws(AppRefusal) -> Result {
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
                StateReport.Message(written.message, review: .video(contentHash: Self.hash), layout: Self.layout),
                StateReport.Thread(written.thread, review: .video(contentHash: Self.hash), layout: Self.layout)
            )
        }

        func openPopover(text: String, region: Region?) throws(AppRefusal) -> StateReport.Popover {
            try record("comment open \(text)\(region.map { " on \($0.text)" } ?? "")")
            return StateReport.Popover(thread: review.nextThreadNumber, time: time, text: text, region: region)
        }

        func editMessage(_ id: String, text: String) throws(AppRefusal) -> StateReport.Message {
            let messageID = try self.id(id)
            let message = try change("comment edit \(id) \(text)") { review throws(ReviewRefusal) in try review.edit(messageID, text: text) }
            return StateReport.Message(message, review: .video(contentHash: Self.hash), layout: Self.layout)
        }

        func deleteMessage(_ id: String) throws(AppRefusal) -> StateReport.Message {
            let messageID = try self.id(id)
            let deleted = try change("comment delete \(id)") { review throws(ReviewRefusal) in try review.delete(messageID) }
            return StateReport.Message(deleted.message, review: .video(contentHash: Self.hash), layout: Self.layout)
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
            return (StateReport.Message(message, review: .video(contentHash: Self.hash), layout: Self.layout), threadID.number)
        }

        func choose(_ thread: String, choice number: Int) throws(AppRefusal) -> (message: StateReport.Message, number: Int) {
            let threadID = try id(thread)
            let message = try change("thread choose \(thread) \(number)") { review throws(ReviewRefusal) in
                try review.answer(threadID, text: try review.choice(number, on: threadID), now: Self.sentAt)
            }
            return (StateReport.Message(message, review: .video(contentHash: Self.hash), layout: Self.layout), threadID.number)
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
            var sidebar = StateReport.Sidebar(thread: shown, width: 340)
            sidebar.mode = "thread"
            return (sidebar, threadID.number)
        }

        func showThreadList() -> StateReport.Sidebar {
            calls.append("thread list")
            shown = nil
            return StateReport.Sidebar(thread: nil, width: 340)
        }

        /// A plain video: the thread list has no versions.
        static let plainVideo = AppRefusal("the thread list shows versions only in a project; this window holds a plain video")

        func openVersionMenu(search: String?) throws(AppRefusal) -> StateReport.Sidebar {
            try record("thread versions\(search.map { " --search \($0)" } ?? "")")
            throw Self.plainVideo
        }

        func closeVersionMenu() -> StateReport.Sidebar {
            calls.append("thread versions --close")
            return StateReport.Sidebar(thread: nil, width: 340)
        }

        func pickVersion(_ number: Int) throws(AppRefusal) -> StateReport.Sidebar {
            try record("thread version \(number)")
            throw Self.plainVideo
        }

        func removePickedVersion(_ number: Int) throws(AppRefusal) -> StateReport.Sidebar {
            try record("thread version \(number) --remove")
            throw Self.plainVideo
        }

        func compose(text: String, region: Region?, general: Bool) throws(AppRefusal) -> StateReport.Sidebar.Composer {
            try record("comment compose \(text)\(region.map { " on \($0.text)" } ?? "")\(general ? " general" : "")")
            return StateReport.Sidebar.Composer(
                target: general ? "Reply on General" : "New thread at 0:12", kind: general ? "reply" : "new", thread: nil, number: general ? 0 : 2, time: general ? nil : 12.5,
                general: general, text: text, region: region
            )
        }

        func showConnect() throws(AppRefusal) -> StateReport.Sidebar {
            try record("connect show")
            var sidebar = StateReport.Sidebar(thread: nil, width: 340)
            sidebar.mode = "connect"
            sidebar.connect = StateReport.Sidebar.Connect(
                reason: "header", phase: "none", harness: "claude-code", readiness: "ready",
                prompt: "/havooch-mate listen for my feedback on sample.mp4"
            )
            return sidebar
        }

        func pickHarness(named name: String) throws(AppRefusal) -> StateReport.Sidebar {
            try record("connect pick \(name)")
            var sidebar = try showConnect()
            sidebar.connect?.harness = name
            sidebar.connect?.readiness = "skillNotDetected"
            sidebar.connect?.prompt = "$havooch-mate listen for my feedback on sample.mp4"
            return sidebar
        }

        func disconnectAgent() throws(AppRefusal) -> String {
            try record("connect disconnect")
            return "Claude Code"
        }

        func forgetAgent() throws(AppRefusal) -> String {
            try record("connect forget")
            return "Codex"
        }

        /// The fake's tour: open on its step, or closed.
        var tour = StateReport.Tour(
            open: false, step: "tools", stepNumber: 1, steps: 5, title: "Give your agent two tools", rings: [],
            replied: false, finishSetup: true, setupItemsLeft: 3
        )

        func showTour() throws(AppRefusal) -> StateReport.Tour {
            try record("tour show")
            tour.open = true
            tour.rings = ["setupSteps"]
            return tour
        }

        func nextTourStep() throws(AppRefusal) -> StateReport.Tour {
            try record("tour next")
            if tour.step == "reply" {
                tour.open = false
                tour.step = "tools"
                tour.stepNumber = 1
            } else {
                tour.step = "connect"
                tour.stepNumber = 2
                tour.title = "Connect your agent"
            }
            return tour
        }

        func skipTour() throws(AppRefusal) -> StateReport.Tour {
            try record("tour skip")
            tour.open = false
            tour.step = "tools"
            tour.stepNumber = 1
            return tour
        }

        func closeTour() throws(AppRefusal) -> StateReport.Tour {
            try record("tour close")
            tour.open = false
            return tour
        }

        func switchVersion(to number: Int) async throws(AppRefusal) {
            try record("version show \(number)")
        }

        func openVersionPicker(query: String) throws(AppRefusal) -> VersionSwitch {
            try record("version pick \(query)")
            return VersionSwitch(versions: [], current: nil)
        }

        func closeVersionPicker() -> Bool {
            calls.append("version close")
            return false
        }

        func openCompare() throws(AppRefusal) {
            try record("compare open")
        }

        func pickCompareSide(_ side: CompareSide, query: String) throws(AppRefusal) {
            try record("compare pick \(side.rawValue) \(query)")
        }

        func setCompare(_ change: CompareChange) async throws(AppRefusal) {
            try record("compare set")
        }

        func swapCompare() throws(AppRefusal) {
            try record("compare swap")
        }

        func startCompare() async throws(AppRefusal) {
            try record("compare start")
        }

        func exitCompare() -> Bool {
            calls.append("compare exit")
            return false
        }

        private func record(_ call: String) throws(AppRefusal) {
            calls.append(call)
            if let refusal { throw refusal }
        }

        func open(_ url: URL) async throws(AppRefusal) {
            try record("open \(url.path)")
            hasVideo = true
        }

        /// Whether the app is in front, as `openInFront` leaves it.
        var active = false

        func open(_ url: URL, project: String?) async throws(AppRefusal) {
            try await open(url)
        }

        func openInFront(_ url: URL, project: String?) async throws(AppRefusal) -> any WindowControlling {
            try record("open in front \(url.path)")
            hasVideo = true
            playing = true
            active = true
            return self
        }

        /// A `wait` listens to the open video's review, or to the one its path names.
        func listenedReview(video: String?, project: String?) async throws(AppRefusal) -> ReviewKey {
            project.map { .project(slug: $0) } ?? .video(contentHash: video ?? Self.hash)
        }

        func projectNew(_ slug: String, from url: URL, title: String?) async throws(AppRefusal) -> StateReport.Project {
            try record("project new \(slug) \(url.path)")
            return StateReport.Project(
                ProjectOutline(slug: slug, title: title ?? slug, versions: [.init(path: url.path)]), onScreen: url.path
            )
        }

        func projectAdd(_ slug: String, video url: URL, label: String?) async throws(AppRefusal) -> any WindowControlling {
            try record("project add \(slug) \(url.path)")
            return self
        }

        func goHome() async {
            calls.append("home")
            hasVideo = false
        }

        func openDemo() async throws(AppRefusal) {
            try record("demo")
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
            to file: URL, appearance: ControlRequest.Appearance?, hideAgentIndicator: Bool, window: ControlRequest.Window,
            player: NSWindow?
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

    /// Listeners nobody sends to, the same ones at each request: the fake
    /// app has no reviews on disk.
    static func noListeners() -> @MainActor () -> ListenerHub {
        let hub = ListenerHub(
            desk: ReviewDesk(library: Library(layout: SupportLayout(root: URL(fileURLWithPath: "/demo", isDirectory: true)))),
            layout: SupportLayout(root: URL(fileURLWithPath: "/demo", isDirectory: true))
        )
        return { hub }
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
        #expect(await answer(.playerOpen(path: "/videos/sample.mp4")).reply == .done("opened sample (0:21.233) in w1\n"))
        #expect(await answer(.playerSeek(seconds: 10)).reply == .done("0:10\n"))
        #expect(await answer(.playerPlay).reply == .done("playing from 0:10\n"))
        #expect(await answer(.playerPause).reply == .done("paused at 0:10\n"))
        #expect(app.calls == ["open /videos/sample.mp4", "seek 10.0", "play", "pause"])
    }

    @Test("open answers once the video plays in front, and --json reports the app, the video and the player")
    func openInFront() async throws {
        app.hasVideo = false
        // The reply names the app's process, for the command to bring to the front.
        #expect(await answer(.open(path: "/videos/sample.mp4")).reply
            == ControlReply(ok: true, output: "opened sample (0:21.233) in w1, playing\n", pid: ProcessInfo.processInfo.processIdentifier))
        #expect(app.calls == ["open in front /videos/sample.mp4"])
        let open = try object(await answer(.open(path: "/videos/sample.mp4"), json: true).reply.output)
        #expect((open["app"] as? [String: Any])?["active"] as? Bool == true)
        #expect(open["screen"] as? String == "player")
        #expect((open["video"] as? [String: Any])?["path"] as? String == "/videos/sample.mp4")
        #expect(open["player"] as? [String: AnyHashable] == ["time": 0, "playing": true])
    }

    @Test("open needs no lease: it goes through while another agent holds it, which keeps it, and shows no agent-control icon")
    func openWithoutLease() async throws {
        let server = server()
        let other = Holder(key: "agent-2", name: "Codex", place: "/Users/me/other")
        let take = await server.reply(to: ControlMessage(.controlTake(waitSeconds: nil), holder: other).encoded())
        #expect(take.reply.ok)
        let open = await server.reply(to: ControlMessage(.open(path: "/videos/sample.mp4"), holder: Self.holder).encoded())
        #expect(open.reply.ok)
        #expect(open.granted == nil)
        #expect(server.lease.status(at: Date())?.holder == other)
        #expect(app.calls == ["open in front /videos/sample.mp4"])

        // With no lease held, an open takes none: the icon stays hidden.
        let free = self.server()
        _ = await free.reply(to: ControlMessage(.open(path: "/videos/sample.mp4"), holder: Self.holder).encoded())
        #expect(free.lease.status(at: Date()) == nil)
        #expect(free.indicator.shown(at: Date()) == nil)
    }

    @Test("a file the app can't play is refused, and the reply says why")
    func openRefused() async {
        app.hasVideo = false
        app.refusal = AppRefusal("can't play /videos/notes.txt: it has no video this Mac can play")
        #expect(await answer(.open(path: "/videos/notes.txt")).reply
            == .refused("can't play /videos/notes.txt: it has no video this Mac can play"))
        #expect(!app.hasVideo)
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
        #expect(state["app"] as? [String: AnyHashable] == ["version": "0.4.1", "demo": true, "support": "/demo", "active": false])
        #expect(state["player"] as? [String: AnyHashable] == ["time": 10, "playing": false])
        #expect(state["video"] as? [String: AnyHashable]
            == ["path": "/videos/sample.mp4", "contentHash": "abcdef0123", "title": "sample", "duration": 21.233, "contextNote": ""])
        #expect(state["lease"] is NSNull)
        #expect(state["popover"] is NSNull)
        #expect(state["threads"] as? [[String: AnyHashable]] == [[
            "id": "t-abcdef01-0", "number": 0, "time": NSNull(), "version": NSNull(), "state": NSNull(), "keyframePath": NSNull(),
            "popoverFrame": NSNull(), "unread": false, "messages": [] as [String],
        ]])
        #expect(state["queue"] as? [String] == [])
        #expect(state["sends"] as? [AnyHashable] == [])
        #expect(state["recents"] as? [AnyHashable] == [])
        #expect(state["project"] is NSNull)
        #expect(state["projects"] as? [AnyHashable] == [])
        #expect(state["screen"] as? String == "player")
        #expect(state["listener"] as? [String: AnyHashable] == [
            "presence": "absent", "waitOpen": false, "session": NSNull(), "pendingSends": 0, "takenSends": 0, "activity": [AnyHashable](), "tookOverFrom": NSNull(),
        ])

        app.hasVideo = false
        state = try object(await answer(.state, json: true).reply.output)
        #expect(state["video"] is NSNull)
        #expect(state["screen"] as? String == "home")
    }

    @Test("state and app status answer lines without --json")
    func lines() async {
        #expect(await answer(.state).reply.output == """
            \(AppIdentity.appName) 0.4.1, demo data in /demo
            window: w1
            screen: player
            video: sample (0:21.233) /videos/sample.mp4
            player: paused at 0:00
            transcript: none
            lease: free
            listener: absent, 0 sends waiting, 0 taken
            threads: 1 (0 queued)
              #0 General t-abcdef01-0 -
            recents: 0
            projects: 0
            windows: 1
              w1 key player sample /videos/sample.mp4

            """)
        #expect(await answer(.appStatus).reply.output == """
            running: \(AppIdentity.appName) 0.4.1
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
        #expect(shown["sidebar"] as? [String: AnyHashable] == [
            "mode": "thread", "thread": "t-abcdef01-0", "width": 340, "composer": NSNull(), "connect": NSNull(),
            "versions": NSNull(),
        ])
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

    @Test("`connect show` and `connect pick` show the Connect view and answer with the picked harness's readiness and prompt; disconnect and forget name the agent")
    func connectCommands() async throws {
        #expect(await answer(.connectShow).reply == .done("the sidebar shows the Connect view\n"))
        let shown = try object(await answer(.connectShow, json: true).reply.output)
        let sidebar = try #require(shown["sidebar"] as? [String: Any])
        #expect(sidebar["mode"] as? String == "connect")
        #expect((sidebar["connect"] as? [String: Any])?["reason"] as? String == "header")

        #expect(await answer(.connectPick(harness: "codex")).reply == .done(
            "picked codex: the skill isn't detected; paste the prompt if it's installed another way\n"
                + "prompt: $havooch-mate listen for my feedback on sample.mp4\n"
        ))
        #expect(await answer(.connectDisconnect).reply == .done("Claude Code disconnected\n"))
        #expect(await answer(.connectForget).reply == .done("Codex forgotten: no agent is waited for\n"))
        #expect(app.calls == [
            "connect show", "connect show", "connect pick codex", "connect show", "connect disconnect", "connect forget",
        ])

        app.refusal = AppRefusal("no agent is connected to this window")
        let refused = await answer(.connectDisconnect)
        #expect(refused.reply == .refused("no agent is connected to this window"))
    }

    @Test("`tour show`, `next`, `close` and `skip` move the tour and answer with its step; `--json` has the tour")
    func tourCommands() async throws {
        #expect(await answer(.tourShow).reply == .done("the tour shows step 1 of 5: Give your agent two tools\n"))
        #expect(await answer(.tourNext).reply == .done("the tour shows step 2 of 5: Connect your agent\n"))
        #expect(await answer(.tourClose).reply == .done(
            "the tour is closed at step 2 of 5; havooch tour show opens it there\n"
        ))
        let shown = try object(await answer(.tourShow, json: true).reply.output)
        let tour = try #require(shown["tour"] as? [String: Any])
        #expect(tour["open"] as? Bool == true)
        #expect(tour["step"] as? String == "connect")
        #expect(tour["finishSetup"] as? Bool == true)
        #expect(tour["setupItemsLeft"] as? Int == 3)
        #expect(await answer(.tourSkip).reply == .done(
            "the tour is skipped; Finish setup or havooch tour show starts it again\n"
        ))
        #expect(app.calls == ["tour show", "tour next", "tour close", "tour show", "tour skip"])

        app.refusal = AppRefusal("the tour isn't showing; havooch tour show opens it")
        #expect(await answer(.tourNext).reply == .refused("the tour isn't showing; havooch tour show opens it"))
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
            recents: 0
            projects: 0
            windows: 1
              w1 key player sample /videos/sample.mp4

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
        app.refusal = AppRefusal("no video is open in the window; open one with `havooch player open <path>`")
        #expect(await answer(.contextSet(text: "note")).reply
            == .refused("no video is open in the window; open one with `havooch player open <path>`"))
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
