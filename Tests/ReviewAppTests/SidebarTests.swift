import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire
import Testing

/// The sidebar through the app's model, on the fixture video: the order of
/// the threads, the thread list's groups and a row's words, the thread view
/// with Back, Previous and Next, the field at a thread's foot, the
/// commands that show a view, and the kept width.
@Suite("The sidebar of threads", .serialized)
struct SidebarTests {
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("video-review-tests-\(UUID().uuidString)", isDirectory: true)

    private func model() async throws -> AppModel {
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        try await model.open(MessageTests.fixture)
        return model
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    private func thread(_ number: Int, _ model: AppModel) throws -> ReviewThread {
        try #require(model.threads.first { $0.number == number })
    }

    /// Waits until `condition` holds: a click moves the player in a task.
    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func id(_ text: String) throws -> ItemID {
        try #require(ItemID(text))
    }

    @Test("General comes first, even with nothing on it, then the threads in time order, not in the order written")
    func order() async throws {
        defer { cleanUp() }
        let model = try await model()
        #expect(model.threads.map(\.number) == [0])
        _ = try await model.addMessage(text: "Later", at: 15)
        _ = try await model.addMessage(text: "Earlier", at: 5)
        _ = try await model.addMessage(text: "Whole video", at: nil, thread: "0")

        #expect(model.threads.map(\.number) == [0, 2, 1])
        #expect(model.threads.first?.isGeneral == true)
    }

    @Test("the list groups the threads as Needs you, With agent, Queued, Done; each in the first group it matches, in time order with General first")
    func groups() async throws {
        defer { cleanUp() }
        let model = try await model()
        let done = try await model.addMessage(text: "Done one", at: 3)
        _ = try await model.addMessage(text: "Sent one", at: 6)
        let asked = try await model.addMessage(text: "Asked one", at: 9)
        _ = try await model.addMessage(text: "Followed up", at: 15)
        let failed = try await model.addMessage(text: "Failed one", at: 18)
        _ = try await model.sendQueue()
        let (doneID, failedID, askedID) = (try id(done.message.id), try id(failed.message.id), try id(asked.thread.id))
        _ = try model.desk.change { review throws(ReviewRefusal) in try review.setState(doneID, .done) }
        _ = try model.desk.change { review throws(ReviewRefusal) in try review.setState(failedID, .failed) }
        _ = try model.desk.change { review throws(ReviewRefusal) in try review.ask(on: askedID, question: "Which part?", now: Date()) }
        // Queued after the send: a new thread, a follow-up on a sent one, and General.
        _ = try await model.addMessage(text: "Queued one", at: 12)
        _ = try await model.addMessage(text: "And this", at: nil, thread: "4")
        _ = try await model.addMessage(text: "Whole video", at: nil, thread: "0")

        #expect(model.threads.map(\.number) == [0, 1, 2, 3, 6, 4, 5])
        let sections = model.threadGroups
        #expect(sections.map(\.group) == [.needsYou, .withAgent, .queued, .done])
        #expect(sections.map { $0.threads.map(\.number) } == [[3], [2, 4], [0, 6], [1, 5]])
        #expect(sections.map(\.group.title) == ["Needs you", "With agent", "Queued", "Done"])
        #expect(sections.map(\.group.hint) == [nil, nil, "⌘↩ sends them all", nil])
        #expect(ThreadListSummary.line(threads: model.threads, queued: model.queuedCount) == "7 threads · 1 needs you · 3 queued")

        // An answer moves the thread out of Needs you; an empty group goes.
        _ = try model.answer("3", text: "The intro")
        #expect(model.threadGroups.map(\.group) == [.withAgent, .queued, .done])
        #expect(model.threadGroups.first?.threads.map(\.number) == [2, 3, 4])
    }

    @Test("General with no message of the person's is Done; the summary line leaves out a count of none")
    func emptyReview() async throws {
        defer { cleanUp() }
        let model = try await model()
        #expect(model.threadGroups.map(\.group) == [.done])
        #expect(ThreadListSummary.line(threads: model.threads, queued: 0) == "1 thread")
        _ = try await model.addMessage(text: "One", at: 5)
        #expect(ThreadListSummary.line(threads: model.threads, queued: model.queuedCount) == "2 threads · 1 queued")
    }

    @Test("a row shows the number, the time, the state, how fresh it is and the last message by who wrote it; VoiceOver reads them all")
    func summary() async throws {
        defer { cleanUp() }
        let model = try await model()
        let added = try await model.addMessage(text: "Too fast\nhere", at: 12.5)
        var summary = ThreadSummary(try thread(1, model), agent: "Claude Code")
        #expect(summary.title == "#1")
        #expect(summary.time == "0:12")
        #expect(summary.state == .queued)
        #expect(summary.writer == "You")
        #expect(!summary.byAgent)
        #expect(summary.preview == "You: Too fast here")
        #expect(summary.lastAt != nil)
        #expect(!summary.waitsForAnswer)
        #expect(summary.text == "#1, 0:12, Queued, You: Too fast here")

        _ = try await model.sendQueue()
        let id = try id(added.thread.id)
        _ = try model.desk.change { review throws(ReviewRefusal) in try review.reply(on: id, text: "Slowed it", now: Date()) }
        #expect(ThreadSummary(try thread(1, model), agent: "Claude Code").preview == "Claude Code: Slowed it")
        _ = try model.desk.change { review throws(ReviewRefusal) in try review.ask(on: id, question: "Which part?", now: Date()) }
        summary = ThreadSummary(try thread(1, model), agent: "Claude Code")
        #expect(summary.state == .sent)
        #expect(summary.preview == "Asks: Which part?")
        #expect(summary.byAgent)
        #expect(summary.waitsForAnswer)
        #expect(summary.text == "#1, 0:12, waiting for your answer, Claude Code asks: Which part?")

        let general = ThreadSummary(try thread(0, model), agent: "Claude Code")
        #expect(general.title == "General")
        #expect(general.time == nil)
        #expect(general.state == nil)
        #expect(general.writer == nil)
        #expect(general.lastAt == nil)
        #expect(general.preview == "Talk with the agent about the whole video")
    }

    @Test("the relative time is now, then minutes, hours and days")
    func relativeTime() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(RelativeTime.short(now, now: now) == "now")
        #expect(RelativeTime.short(now.addingTimeInterval(-44), now: now) == "now")
        #expect(RelativeTime.short(now.addingTimeInterval(-50), now: now) == "1m")
        #expect(RelativeTime.short(now.addingTimeInterval(-180), now: now) == "3m")
        #expect(RelativeTime.short(now.addingTimeInterval(-7_300), now: now) == "2h")
        #expect(RelativeTime.short(now.addingTimeInterval(-4 * 86_400), now: now) == "4d")
        // A clock that went back is no time ago.
        #expect(RelativeTime.short(now.addingTimeInterval(60), now: now) == "now")
    }

    @Test("a click on a row shows the thread's view, picks out its pin and pauses the player on its frame; Back shows the list and leaves the player")
    func showAndBack() async throws {
        defer { cleanUp() }
        let model = try await model()
        _ = try await model.addMessage(text: "One", at: 5)
        _ = try await model.addMessage(text: "Two", at: 15)
        let (one, two) = (try thread(1, model).id, try thread(2, model).id)
        // A message written picks out its thread's pin; the sidebar stays on the list.
        #expect(model.selection == two)
        #expect(model.shown == nil)
        #expect(model.state().sidebar?.thread == nil)
        try await model.seek(to: 10)
        try model.play()

        model.showThread(one)
        #expect(model.shown == one)
        #expect(model.selection == one)
        #expect(model.state().sidebar?.thread == one.text)
        #expect(!model.engine.isPlaying)
        await eventually { model.engine.time == 5 }
        #expect(model.engine.time == 5)
        #expect(model.stageThread == one)

        #expect(model.showThreadList() == StateReport.Sidebar(thread: nil, width: Double(Metrics.sidebarWidth)))
        #expect(model.shown == nil)
        #expect(model.state().sidebar?.thread == nil)
        #expect(model.selection == one)
        #expect(model.engine.time == 5)

        // Escape goes back too, once nothing else takes it.
        model.showThread(two)
        await eventually { model.engine.time == 15 }
        #expect(model.escape())
        #expect(model.shown == nil)
        #expect(!model.escape())
    }

    @Test("Previous and Next go through the threads in time order, General first, and stop at either end")
    func previousAndNext() async throws {
        defer { cleanUp() }
        let model = try await model()
        _ = try await model.addMessage(text: "Later", at: 15)
        _ = try await model.addMessage(text: "Earlier", at: 5)
        let (general, later, earlier) = (try thread(0, model).id, try thread(1, model).id, try thread(2, model).id)
        #expect(model.neighbour(forward: true) == nil)

        model.showThread(earlier)
        #expect(model.neighbour(forward: false)?.id == general)
        model.showNeighbour(forward: true)
        #expect(model.shown == later)
        await eventually { model.engine.time == 15 }
        #expect(model.engine.time == 15)
        #expect(model.neighbour(forward: true) == nil)
        model.showNeighbour(forward: true)
        #expect(model.shown == later)

        model.showNeighbour(forward: false)
        model.showNeighbour(forward: false)
        #expect(model.shown == general)
        #expect(model.neighbour(forward: false) == nil)
        model.showNeighbour(forward: false)
        #expect(model.shown == general)
    }

    @Test("a pin, a frame badge, a notice and Up or Down show the thread's view; Back counts the other threads that need the person")
    func pinAndNotice() async throws {
        defer { cleanUp() }
        let model = try await model()
        let one = try await model.addMessage(text: "One", at: 5)
        _ = try await model.addMessage(text: "Two", at: 15)
        let three = try await model.addMessage(text: "Three", at: 18)
        _ = try await model.sendQueue()
        let (first, second, third) = (try id(one.thread.id), try thread(2, model).id, try id(three.thread.id))

        // A pin or a badge opens the thread's popover and shows its view.
        model.openThread(first)
        #expect(model.shown == first)
        #expect(model.state().popover?.thread == 1)
        model.closePopover(.discard)

        // A notice of the agent's shows its thread's view.
        model.raise(Notice(thread: second, kind: .message, agent: "Claude Code", text: "Done", at: Date()))
        model.openNotice(try #require(model.notices.last).id)
        #expect(model.shown == second)
        model.closePopover(.discard)

        _ = model.showThreadList()
        await eventually { model.engine.time == 15 }
        model.jumpToMarker(forward: true)
        #expect(model.shown == third)

        // Questions on #1 and #3: Back in #3 counts #1 only.
        for thread in [first, third] {
            _ = try model.desk.change { review throws(ReviewRefusal) in try review.ask(on: thread, question: "Which?", now: Date()) }
        }
        #expect(model.othersNeedingYou == 1)
        _ = model.showThreadList()
        #expect(model.othersNeedingYou == 2)
    }

    @Test("a thread view of a thread that goes, with its last message, goes back to the list; another video opens on the list")
    func goneThread() async throws {
        defer { cleanUp() }
        let model = try await model()
        let added = try await model.addMessage(text: "One", at: 5)
        let id = try id(added.thread.id)
        model.showThread(id)
        _ = try model.deleteMessage(added.message.id)
        #expect(model.shown == nil)

        model.showThread(try thread(0, model).id)
        try await model.open(MessageTests.fixture)
        #expect(model.shown == nil)
    }

    @Test("the field at a thread's foot queues a follow-up on that thread and leaves the player where it is")
    func followUp() async throws {
        defer { cleanUp() }
        let model = try await model()
        _ = try await model.addMessage(text: "One", at: 5)
        _ = try await model.sendQueue()
        try await model.seek(to: 15)

        #expect(await model.writeOnThread(try thread(1, model).id, text: "  And slower  "))
        let messages = try thread(1, model).messages
        #expect(messages.map(\.text) == ["One", "And slower"])
        #expect(messages.last?.state == .queued)
        #expect(messages.last?.kind == .message)
        #expect(model.engine.time == 15)
        #expect(model.state().queue == [messages[1].id.text])

        // General takes one too; empty words are none.
        #expect(await model.writeOnThread(try thread(0, model).id, text: "Overall: good"))
        #expect(try thread(0, model).messages.last?.text == "Overall: good")
        #expect(await model.writeOnThread(try thread(0, model).id, text: "   ") == false)
    }

    @Test("with an open question the field answers at once, not in the queue")
    func answer() async throws {
        defer { cleanUp() }
        let model = try await model()
        let added = try await model.addMessage(text: "One", at: 5)
        _ = try await model.sendQueue()
        let id = try id(added.thread.id)
        _ = try model.desk.change { review throws(ReviewRefusal) in try review.ask(on: id, question: "Which part?", now: Date()) }
        #expect(ThreadFieldLook(try thread(1, model)).answers)
        #expect(ThreadFieldLook(try thread(1, model)).button == "Answer")

        #expect(await model.writeOnThread(id, text: "The intro"))
        let last = try #require(try thread(1, model).messages.last)
        #expect(last.kind == .answer)
        #expect(last.text == "The intro")
        #expect(try thread(1, model).openQuestion == nil)
        #expect(model.state().queue.isEmpty)
        #expect(ThreadFieldLook(try thread(1, model)).button == "Queue")
        #expect(ThreadFieldLook(try thread(0, model)).placeholder == "Write to the agent…")
    }

    @Test("the sidebar's width stays within its limits, and the width a drag ends at is kept in settings.json for the next run")
    func width() async throws {
        defer { cleanUp() }
        #expect(AppModel.sidebarWidth(kept: nil) == Metrics.sidebarWidth)
        #expect(AppModel.sidebarWidth(kept: 380) == 380)
        #expect(AppModel.sidebarWidth(kept: 10) == Metrics.sidebarWidthRange.lowerBound)
        #expect(AppModel.sidebarWidth(kept: 9000) == Metrics.sidebarWidthRange.upperBound)
        #expect(AppModel.sidebarWidth(kept: .infinity) == Metrics.sidebarWidth)

        let model = try await model()
        #expect(model.state().sidebar?.width == Double(Metrics.sidebarWidth))
        model.keepSidebarWidth(390.4)
        #expect(model.sidebarWidth == 390)
        #expect(model.state().sidebar?.width == 390)
        let layout = SupportLayout(root: support)
        #expect(try Settings.load(layout).sidebarWidth == 390)

        // The next run opens at that width.
        let again = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        #expect(again.sidebarWidth == 390)

        // A drag past a limit is kept at the limit.
        model.keepSidebarWidth(9000)
        #expect(try Settings.load(layout).sidebarWidth == Double(Metrics.sidebarWidthRange.upperBound))
    }

    @Test("thread show shows a thread of the open video by its number or its id once the player is on its frame; thread list shows the list")
    func showCommands() async throws {
        defer { cleanUp() }
        let model = try await model()
        let added = try await model.addMessage(text: "One", at: 5)
        _ = try await model.addMessage(text: "Two", at: 15)
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: model, listeners: model.listeners,
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        let holder = Holder(key: "operator", name: "Claude Code", place: "/work")
        func send(_ request: ControlRequest, json: Bool = false) async -> ControlReply {
            await server.reply(to: request.sent(by: holder, json: json)).reply
        }
        func sidebar() throws -> [String: Any] {
            let state = try #require(JSONSerialization.jsonObject(with: Data(model.state().json.utf8)) as? [String: Any])
            return try #require(state["sidebar"] as? [String: Any])
        }

        #expect(try sidebar()["thread"] is NSNull)
        #expect(await send(.threadShow(thread: "1")) == .done("the sidebar shows #1\n"))
        #expect(model.shown?.text == added.thread.id)
        #expect(model.engine.time == 5)
        #expect(!model.engine.isPlaying)
        #expect(try sidebar()["thread"] as? String == added.thread.id)
        #expect(await send(.threadShow(thread: added.thread.id)) == .done("the sidebar shows #1\n"))

        let printed = try #require(JSONSerialization.jsonObject(with: Data(await send(.threadShow(thread: "0"), json: true).output.utf8)) as? [String: Any])
        let shown = try #require(printed["sidebar"] as? [String: Any])
        #expect(shown["thread"] as? String == (try thread(0, model)).id.text)
        // General has no frame: the player stays.
        #expect(model.engine.time == 5)

        #expect(await send(.threadList) == .done("the sidebar shows the thread list\n"))
        #expect(model.shown == nil)
        #expect(try sidebar()["thread"] is NSNull)
        #expect(await send(.threadShow(thread: "9")).ok == false)
        #expect(await send(.threadShow(thread: "t-00000000-1")).ok == false)
        #expect(model.shown == nil)
    }
}
