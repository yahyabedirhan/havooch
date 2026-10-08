import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewWire
import SwiftUI
import Testing

/// The thread popover through the app's model, on the fixture video
/// (D 2.6 to D 2.11): a pin or a badge opens it on its thread's frame, its
/// field continues the thread or answers its open question, and the thread
/// keeps where the person left it. No window.
@Suite("A thread continues in its popover on the video", .serialized)
struct ThreadPopoverTests {
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private func model() async throws -> WindowModel {
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path, MutedRun.variable: "1"]).makeWindow()
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
        #expect(model.draft == WindowModel.Draft(time: 3, text: ""))
        #expect(model.draftThread?.messages.map(\.text) == ["Too fast"])
        #expect(model.selection?.text == moment.thread.id)
        await eventually { model.engine.time == 3 }
        #expect(model.engine.time == 3)
        #expect(!model.engine.isPlaying)

        model.openThread(try id(boxed.thread.id))
        #expect(model.draft == WindowModel.Draft(time: 12.5, text: ""))
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
        #expect(model.draft == WindowModel.Draft(time: 12.5, text: ""))
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
        #expect(model.draft == WindowModel.Draft(time: 12.5, text: ""))
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
        _ = try await model.app.listeners.ask(on: added.thread.id, question: "Cmd+Return or Cmd+Enter?", waitSeconds: 0)

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
        _ = try model.app.listeners.reply(on: added.thread.id, text: "Cmd+Return it is.")
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

        let again = AppModel(environment: [SupportFolder.overrideVariable: support.path, MutedRun.variable: "1"]).makeWindow()
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
        _ = try model.app.listeners.reply(on: added.thread.id, text: "On it.")
        #expect(model.draft == nil)
        try model.pause()
    }

    @Test("a kept frame is fitted to the stage: no smaller than the popover can be used at, and inside the margins")
    func geometry() {
        let stage = CGSize(width: 1000, height: 600)
        let rect = ThreadPopover.rect(of: PopoverFrame(x: 0.55, y: 0.1, w: 0.4, h: 0.6), in: stage)
        #expect(rect == CGRect(x: 550, y: 60, width: 400, height: 360))
        #expect(ThreadPopover.frame(of: rect, in: stage) == PopoverFrame(x: 0.55, y: 0.1, w: 0.4, h: 0.6))

        // Dragged past the corner: back inside the margin.
        let outside = ThreadPopover.fit(CGRect(x: 900, y: -40, width: 400, height: 360), in: stage)
        #expect(outside == CGRect(x: 592, y: 8, width: 400, height: 360))
        // Resized too small, or larger than the stage.
        #expect(ThreadPopover.fit(CGRect(x: 100, y: 100, width: 50, height: 20), in: stage).size == ThreadPopover.minimumSize)
        #expect(ThreadPopover.fit(CGRect(x: 0, y: 0, width: 4000, height: 4000), in: stage) == CGRect(x: 8, y: 8, width: 984, height: 584))
    }

    @Test("a resize moves only the sides of its edge or corner, and stops at the minimum size, the maximum size and the room")
    func resized() {
        let rules = ThreadPopover.rules
        let room = CGRect(x: 8, y: 8, width: 984, height: 584)
        let start = CGRect(x: 300, y: 120, width: 400, height: 360)
        // An edge moves its side alone, whatever the drag does across it.
        #expect(rules.resized(start, from: .trailing, by: CGSize(width: 30, height: 50), in: room) == CGRect(x: 300, y: 120, width: 430, height: 360))
        #expect(rules.resized(start, from: .top, by: CGSize(width: 30, height: -50), in: room) == CGRect(x: 300, y: 70, width: 400, height: 410))
        // A corner moves its two sides; the ones across stay.
        #expect(rules.resized(start, from: .bottomLeading, by: CGSize(width: -40, height: 20), in: room) == CGRect(x: 260, y: 120, width: 440, height: 380))
        // Past the minimum size, 340 by 320, the moved sides stop; the sides across don't move.
        #expect(rules.resized(start, from: .topLeading, by: CGSize(width: 500, height: 500), in: room) == CGRect(x: 360, y: 160, width: 340, height: 320))
        // Past the maximum width, 640, and past the room's foot.
        #expect(rules.resized(start, from: .bottomTrailing, by: CGSize(width: 900, height: 900), in: room) == CGRect(x: 300, y: 120, width: 640, height: 472))
        #expect(rules.resized(start, from: .leading, by: CGSize(width: -900, height: 0), in: room) == CGRect(x: 60, y: 120, width: 640, height: 360))
        // Past the room's top, the moved side stops at it.
        #expect(rules.resized(start, from: .top, by: CGSize(width: 0, height: -900), in: room) == CGRect(x: 300, y: 8, width: 400, height: 472))
        // No drag, no change.
        #expect(rules.resized(start, from: .bottom, by: .zero, in: room) == start)
    }

    @Test("a new message's popover resizes between 340 by 170 and 560 by 320, and its sides never pass the notch")
    func newMessage() {
        let rules = CommentPopover.rules
        let room = CGRect(x: 10, y: 10, width: 620, height: 355)
        let start = CGRect(x: 100, y: 195, width: 340, height: 170)
        #expect(rules.resized(start, from: .top, by: CGSize(width: 0, height: -50), in: room) == CGRect(x: 100, y: 145, width: 340, height: 220))
        // At the minimum height, the top edge can't come down.
        #expect(rules.resized(start, from: .top, by: CGSize(width: 0, height: 50), in: room) == start)
        // The top stops at the maximum height, the trailing side at the room.
        #expect(rules.resized(start, from: .topTrailing, by: CGSize(width: 600, height: -400), in: room) == CGRect(x: 100, y: 45, width: 530, height: 320))
        #expect(rules.resized(CGRect(x: 10, y: 195, width: 340, height: 170), from: .trailing, by: CGSize(width: 600, height: 0), in: room).width == 560)
        // The leading side stops at the notch, before the minimum width does.
        let wide = CGRect(x: 50, y: 195, width: 450, height: 170)
        #expect(rules.resized(wide, from: .leading, by: CGSize(width: 100, height: 0), in: room, covers: 80...124).minX == 80)
        // The trailing side stops at the minimum width.
        #expect(rules.resized(wide, from: .trailing, by: CGSize(width: -300, height: 0), in: room, covers: 80...124).maxX == 390)
        // The bottom edge stays above the notch's room.
        #expect(rules.resized(start, from: .bottom, by: CGSize(width: 0, height: 50), in: room).maxY == 365)
    }

    @Test("every step of a drag is measured from where it started; the header moves the popover inside the stage at its size")
    func drag() {
        let stage = CGSize(width: 1000, height: 600)
        var drag = ThreadPopover.Drag(handle: .bottomTrailing, start: CGRect(x: 10, y: 260, width: 360, height: 330))
        drag.translation = CGSize(width: 3, height: 3)
        #expect(drag.rect(in: stage) == CGRect(x: 10, y: 260, width: 363, height: 332))
        // The same step again gives the same box: the drag doesn't build on itself.
        #expect(drag.rect(in: stage) == CGRect(x: 10, y: 260, width: 363, height: 332))
        drag.translation = CGSize(width: -3, height: -3)
        #expect(drag.rect(in: stage) == CGRect(x: 10, y: 260, width: 357, height: 327))

        var move = ThreadPopover.Drag(handle: nil, start: CGRect(x: 300, y: 180, width: 400, height: 360))
        move.translation = CGSize(width: 40, height: 20)
        #expect(move.rect(in: stage) == CGRect(x: 340, y: 200, width: 400, height: 360))
        move.translation = CGSize(width: 900, height: -900)
        #expect(move.rect(in: stage) == CGRect(x: 592, y: 8, width: 400, height: 360))
    }

    @Test("the resize pointer shows only the outward arrows at the minimum size and only the inward ones at the maximum")
    func directions() {
        let rules = ThreadPopover.rules
        #expect(rules.directions(.trailing, size: CGSize(width: 400, height: 400)) == .all)
        #expect(rules.directions(.leading, size: CGSize(width: 340, height: 400)) == .outward)
        #expect(rules.directions(.top, size: CGSize(width: 340, height: 400)) == .all)
        #expect(rules.directions(.bottom, size: CGSize(width: 400, height: 560)) == .inward)
        // A corner at the minimum one way and free the other goes both ways.
        #expect(rules.directions(.topLeading, size: CGSize(width: 340, height: 400)) == .all)
        #expect(rules.directions(.bottomTrailing, size: CGSize(width: 340, height: 320)) == .outward)
        #expect(CommentPopover.rules.directions(.topTrailing, size: CGSize(width: 560, height: 320)) == .inward)
    }
}
