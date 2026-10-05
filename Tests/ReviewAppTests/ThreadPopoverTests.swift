import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewWire
import Testing

/// The thread popover through the app's model, on the fixture video
/// (D 2.6 to D 2.11): a pin or a badge opens it on its thread's frame, its
/// field continues the thread or answers its open question, and the thread
/// keeps where the person left it. No window.
@Suite("A thread continues in its popover on the video", .serialized)
struct ThreadPopoverTests {
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private func model() async throws -> AppModel {
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        try await model.open(MessageTests.fixture)
        return model
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func id(_ text: String) throws -> ThreadID {
        try #require(ItemID(text))
    }

    @Test("a click on a moment thread's pin and on a region thread's badge opens the same popover on that thread's frame")
    func opens() async throws {
        defer { cleanUp() }
        let model = try await model()
        let moment = try await model.addMessage(text: "Too fast", at: 3)
        let boxed = try await model.addMessage(text: "This box", at: 12.5, region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25))
        try await model.seek(to: 18)

        model.openThread(try id(moment.thread.id))
        #expect(model.draft == AppModel.Draft(time: 3, text: ""))
        #expect(model.draftThread?.messages.map(\.text) == ["Too fast"])
        #expect(model.selection?.text == moment.thread.id)
        await eventually { model.engine.time == 3 }
        #expect(model.engine.time == 3)
        #expect(!model.engine.isPlaying)

        model.openThread(try id(boxed.thread.id))
        #expect(model.draft == AppModel.Draft(time: 12.5, text: ""))
        #expect(model.draftThread?.messages.map(\.text) == ["This box"])
        #expect(model.state().popover == StateReport.Popover(thread: 2, time: 12.5, text: ""))
        await eventually { model.engine.time == 12.5 }
    }

    @Test("opening another thread is a change of the moment for the open popover; the same thread keeps its words")
    func closeRules() async throws {
        defer { cleanUp() }
        let model = try await model()
        let one = try await model.addMessage(text: "One", at: 3)
        let two = try await model.addMessage(text: "Two", at: 12.5)
        model.openThread(try id(one.thread.id))
        model.draft?.text = "More on one"
        model.openThread(try id(one.thread.id))
        #expect(model.draft?.text == "More on one")

        model.openThread(try id(two.thread.id))
        #expect(model.draft == AppModel.Draft(time: 12.5, text: ""))
        await eventually { model.state().queue.count == 3 }
        #expect(model.threads.first { $0.id.text == one.thread.id }?.messages.map(\.text) == ["One", "More on one"])

        // A click outside closes it; × or Escape drops its words.
        model.draft?.text = "never mind"
        #expect(model.escape())
        #expect(model.draft == nil)
        #expect(model.state().queue.count == 3)
    }

    @Test("the field queues a follow-up on the thread, and the popover stays open on it")
    func followUp() async throws {
        defer { cleanUp() }
        let model = try await model()
        let boxed = try await model.addMessage(text: "This box", at: 12.5, region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25))
        model.openThread(try id(boxed.thread.id))
        model.draft?.text = "And make it larger"
        model.commitDraft()
        #expect(model.draft == AppModel.Draft(time: 12.5, text: ""))
        await eventually { model.state().queue.count == 2 }
        let thread = try #require(model.draftThread)
        #expect(thread.messages.map(\.text) == ["This box", "And make it larger"])
        #expect(thread.messages.last?.region == nil)
        #expect(thread.messages.last?.state == .queued)
    }

    @Test("the field answers the thread's open question at once, never into the queue, and the sidebar's thread shows it")
    func answers() async throws {
        defer { cleanUp() }
        let model = try await model()
        let added = try await model.addMessage(text: "Keys", at: 12.5)
        _ = try await model.sendQueue()
        _ = try await model.listeners.ask(on: added.thread.id, question: "Cmd+Return or Cmd+Enter?", waitSeconds: 0)

        model.openThread(try id(added.thread.id))
        #expect(model.draftThread?.openQuestion?.text == "Cmd+Return or Cmd+Enter?")
        model.draft?.text = "Cmd+Return"
        model.commitDraft()
        let thread = try #require(model.draftThread)
        #expect(thread.openQuestion == nil)
        #expect(thread.messages.last.map { ($0.kind, $0.text) } ?? (.message, "") == (.answer, "Cmd+Return"))
        #expect(model.state().queue.isEmpty)
        // The sidebar reads the same thread.
        #expect(model.threads.first { $0.id == thread.id } == thread)

        // A message the agent writes meanwhile shows in the open popover.
        _ = try model.listeners.reply(on: added.thread.id, text: "Cmd+Return it is.")
        #expect(model.draftThread?.messages.last?.text == "Cmd+Return it is.")
    }

    @Test("`thread open --frame` keeps the popover's frame; it is kept across a restart; General and unknown threads are refused")
    func keptFrame() async throws {
        defer { cleanUp() }
        let model = try await model()
        let added = try await model.addMessage(text: "Here", at: 12.5)
        try await model.seek(to: 2)
        let frame = PopoverFrame(x: 0.55, y: 0.1, w: 0.4, h: 0.5)
        let popover = try await model.openThread("1", frame: frame)
        #expect(popover == StateReport.Popover(thread: 1, time: 12.5, text: ""))
        #expect(model.engine.time == 12.5)
        #expect(model.state().threads[1].popoverFrame == frame)

        let again = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        try await again.open(MessageTests.fixture)
        #expect(again.threads.first { $0.id.text == added.thread.id }?.popoverFrame == frame)

        await #expect(throws: AppRefusal.self) { try await model.openThread("0", frame: nil) }
        await #expect(throws: AppRefusal.self) { try await model.openThread("9", frame: nil) }
    }

    @Test("nothing opens by itself during playback: a reply on the thread on screen opens no popover")
    func nothingOpensByItself() async throws {
        defer { cleanUp() }
        let model = try await model()
        let added = try await model.addMessage(text: "Here", at: 2)
        _ = try await model.sendQueue()
        try await model.seek(to: 2)
        try model.play()
        _ = try model.listeners.reply(on: added.thread.id, text: "On it.")
        #expect(model.draft == nil)
        try model.pause()
    }

    @Test("a kept frame is fitted to the stage: no smaller than the popover can be used at, and inside the margins")
    func geometry() {
        let stage = CGSize(width: 1000, height: 600)
        let rect = ThreadPopover.rect(of: PopoverFrame(x: 0.55, y: 0.1, w: 0.4, h: 0.5), in: stage)
        #expect(rect == CGRect(x: 550, y: 60, width: 400, height: 300))
        #expect(ThreadPopover.frame(of: rect, in: stage) == PopoverFrame(x: 0.55, y: 0.1, w: 0.4, h: 0.5))

        // Dragged past the corner: back inside the margin.
        let outside = ThreadPopover.fit(CGRect(x: 900, y: -40, width: 400, height: 300), in: stage)
        #expect(outside == CGRect(x: 592, y: 8, width: 400, height: 300))
        // Resized too small, or larger than the stage.
        #expect(ThreadPopover.fit(CGRect(x: 100, y: 100, width: 50, height: 20), in: stage).size == ThreadPopover.minimumSize)
        #expect(ThreadPopover.fit(CGRect(x: 0, y: 0, width: 4000, height: 4000), in: stage) == CGRect(x: 8, y: 8, width: 984, height: 584))
    }
}
