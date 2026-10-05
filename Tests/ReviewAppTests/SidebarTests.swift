import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire
import Testing

/// The sidebar of threads through the app's model, on the fixture video:
/// the order of the threads, a collapsed row's words, the one expanded
/// thread, the field at a thread's foot, and the kept width.
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

    @Test("a collapsed row shows the number, the time, the state and the start of the last message, by who wrote it")
    func summary() async throws {
        defer { cleanUp() }
        let model = try await model()
        let added = try await model.addMessage(text: "Too fast\nhere", at: 12.5)
        var summary = ThreadSummary(try thread(1, model), agent: "Claude Code")
        #expect(summary.title == "#1")
        #expect(summary.time == "0:12")
        #expect(summary.state == .queued)
        #expect(summary.preview == "You: Too fast here")
        #expect(!summary.waitsForAnswer)

        _ = try await model.sendQueue()
        let id = try #require(ItemID(added.thread.id))
        _ = try model.desk.change { review throws(ReviewRefusal) in try review.ask(on: id, question: "Which part?", now: Date()) }
        summary = ThreadSummary(try thread(1, model), agent: "Claude Code")
        #expect(summary.state == .sent)
        #expect(summary.preview == "Claude Code: Which part?")
        #expect(summary.waitsForAnswer)
        #expect(summary.text == "#1, 0:12, waiting for your answer, Claude Code: Which part?")

        let general = ThreadSummary(try thread(0, model), agent: "Claude Code")
        #expect(general.title == "General")
        #expect(general.time == nil)
        #expect(general.state == nil)
        #expect(general.preview == "Talk with the agent about the whole video")
    }

    @Test("a click on a row expands it and collapses the one before; a click on the expanded one collapses it; the player stays")
    func expand() async throws {
        defer { cleanUp() }
        let model = try await model()
        _ = try await model.addMessage(text: "One", at: 5)
        _ = try await model.addMessage(text: "Two", at: 15)
        let (general, one, two) = (try thread(0, model).id, try thread(1, model).id, try thread(2, model).id)
        // A message written selects its thread's pin; every thread stays collapsed.
        #expect(model.selection == two)
        #expect(model.expanded == nil)
        #expect(model.state().sidebar?.expanded == nil)
        let time = model.engine.time

        model.expandThread(one)
        #expect(model.expanded == one)
        #expect(model.selection == one)
        #expect(model.state().sidebar?.expanded == one.text)
        model.expandThread(general)
        #expect(model.expanded == general)
        model.expandThread(general)
        #expect(model.expanded == nil)
        #expect(model.state().sidebar?.expanded == nil)
        #expect(model.engine.time == time)

        // A move to the thread's frame expands it too.
        model.select(two)
        #expect(model.expanded == two)
        // The thread popover opening (a pin, a badge, the keyframe, a notice) shows
        // the same conversation in the sidebar.
        model.openThread(one)
        #expect(model.expanded == one)
        #expect(model.state().popover?.thread == 1)
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
        let id = try #require(ItemID(added.thread.id))
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

    @Test("thread expand expands a thread of the open video by its number or its id, prints it, and stays expanded when asked again")
    func expandCommand() async throws {
        defer { cleanUp() }
        let model = try await model()
        let added = try await model.addMessage(text: "One", at: 5)
        _ = try await model.addMessage(text: "Two", at: 15)
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: model, listeners: model.listeners,
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        let holder = Holder(key: "operator", name: "Claude Code", place: "/work")
        func expand(_ thread: String, json: Bool = false) async -> ControlReply {
            await server.reply(to: ControlRequest.threadExpand(thread: thread).sent(by: holder, json: json)).reply
        }

        #expect(await expand("1") == .done("#1 expanded\n"))
        #expect(model.expanded?.text == added.thread.id)
        #expect(await expand(added.thread.id) == .done("#1 expanded\n"))
        #expect(model.expanded?.text == added.thread.id)
        let printed = try #require(JSONSerialization.jsonObject(with: Data(await expand("0", json: true).output.utf8)) as? [String: Any])
        let sidebar = try #require(printed["sidebar"] as? [String: Any])
        #expect(sidebar["expanded"] as? String == (try thread(0, model)).id.text)
        #expect(await expand("9").ok == false)
        #expect(await expand("t-00000000-1").ok == false)
    }
}
