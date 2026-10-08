import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewStore
import ReviewWire
import Testing

/// The composer at the sidebar's foot (L41), through the app's model on the
/// fixture video: where its words go in the thread list and in a thread
/// view, the answer path, the drafts per thread, the region chip and the
/// General toggle, and `comment compose`.
@Suite("The composer at the sidebar's foot", .serialized)
struct ComposerTests {
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private func model() async throws -> WindowModel {
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path]).makeWindow()
        try await model.open(MessageTests.fixture)
        return model
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    private func thread(_ number: Int, _ model: WindowModel) throws -> ReviewThread {
        try #require(model.threads.first { $0.number == number })
    }

    private func resolved(_ model: WindowModel) throws -> ComposerTarget {
        try #require(model.composerTarget)
    }

    /// Thread 1 at 5 s, sent, with the agent's open question on it.
    private func asked(_ model: WindowModel) async throws -> ThreadID {
        let added = try await model.addMessage(text: "One", at: 5)
        _ = try await model.sendQueue()
        let id = try #require(ItemID(added.thread.id))
        _ = try model.desk.change(model.reviewKey!) { review throws(ReviewRefusal) in try review.ask(on: id, question: "Which part?", now: Date()) }
        return id
    }

    @Test("in the list the composer writes at the playhead: to a new thread on a frame with none, else to the frame's thread, or to General with the toggle on")
    func listTarget() async throws {
        defer { cleanUp() }
        let model = try await model()
        _ = try await model.addMessage(text: "One", at: 5)
        try await model.seek(to: 12)

        var target = try resolved(model)
        #expect(target.kind == .newThread)
        #expect(target.thread == nil)
        #expect(target.number == 2)
        #expect(target.time == model.engine.frameTime(of: 12))
        #expect(target.label == "New thread at 0:12")
        #expect(target.placeholder == "Comment on 0:12…")
        #expect(target.toolbarLabel == "New thread at 0:12")
        #expect(ComposerTarget.atMoment(try #require(target.time)) == "At 0:12")
        #expect(!target.answers)

        let frame = try #require(try thread(1, model).time)
        try await model.seek(to: frame)
        target = try resolved(model)
        #expect(target.kind == .reply)
        #expect(target.thread == (try thread(1, model)).id)
        #expect(target.label == "Reply on #1")
        #expect(target.toolbarLabel == "#1")
        #expect(target.placeholder == "Message #1…")

        model.toggleComposerGeneral()
        target = try resolved(model)
        #expect(target.kind == .reply)
        #expect(target.isGeneral)
        #expect(target.time == nil)
        #expect(target.label == "Reply on General")
        #expect(target.toolbarLabel == "General thread")
        #expect(model.state().sidebar?.composer?.general == true)
        model.toggleComposerGeneral()
        #expect(try resolved(model).thread == (try thread(1, model)).id)
    }

    @Test("a comment from the list at a new frame makes a new thread, which the list shows in Queued; the sidebar stays on the list")
    func newThreadFromList() async throws {
        defer { cleanUp() }
        let model = try await model()
        try await model.seek(to: 12)
        model.composerText = "  Too fast here  "
        #expect(model.canSend)

        #expect(try await model.writeComposer() == .newThread)
        let made = try thread(1, model)
        #expect(made.time == model.engine.frameTime(of: 12))
        #expect(made.messages.map(\.text) == ["Too fast here"])
        #expect(made.messages.first?.state == .queued)
        #expect(model.threadGroups.first { $0.group == .queued }?.threads.map(\.number) == [1])
        #expect(model.shown == nil)
        #expect(model.composerText.isEmpty)
        // The playhead is on the new thread's frame now: the composer replies on it.
        #expect(try resolved(model).label == "Reply on #1")

        // Empty words are none.
        model.composerText = "   "
        await #expect(throws: AppRefusal.self) { try await model.writeComposer() }
    }

    @Test("in a thread view the composer follows up on the thread, in the queue, and the player stays where it is")
    func threadViewTarget() async throws {
        defer { cleanUp() }
        let model = try await model()
        _ = try await model.addMessage(text: "One", at: 5)
        _ = try await model.sendQueue()
        let id = try thread(1, model).id
        _ = try await model.showThread(id.text)
        try await model.seek(to: 15)

        let target = try resolved(model)
        #expect(target.kind == .followUp)
        #expect(target.thread == id)
        #expect(target.label == "Follow up on #1")
        #expect(target.toolbarLabel == "#1")
        #expect(model.state().sidebar?.composer?.target == "Follow up on #1")
        #expect(model.state().sidebar?.composer?.kind == "follow-up")
        #expect(model.state().sidebar?.composer?.general == false)

        model.composerText = "And slower"
        #expect(try await model.writeComposer() == .followUp)
        let messages = try thread(1, model).messages
        #expect(messages.map(\.text) == ["One", "And slower"])
        #expect(messages.last?.state == .queued)
        #expect(model.engine.time == 15)
        #expect(model.shown == id)

        // General's view follows up on General.
        _ = try await model.showThread("0")
        #expect(try resolved(model).label == "Follow up on General")
        #expect(try resolved(model).placeholder == "Write to the agent…")
        model.composerText = "Overall: good"
        _ = try await model.writeComposer()
        #expect(try thread(0, model).messages.last?.text == "Overall: good")
    }

    @Test("with an open question the composer answers at once, in the question's words, and the thread leaves Needs you")
    func answer() async throws {
        defer { cleanUp() }
        let model = try await model()
        let id = try await asked(model)
        _ = try await model.showThread(id.text)

        let target = try resolved(model)
        #expect(target.kind == .answer)
        #expect(target.label == "Answer #1")
        #expect(target.note == "goes at once")
        #expect(model.state().sidebar?.composer?.target == "Answer #1 · goes at once")
        #expect(target.placeholder == "Type your answer…")
        #expect(target.toolbarLabel == "Answer #1, goes at once")
        #expect(model.threadGroups.first?.group == .needsYou)
        model.composerText = "The intro"
        // An answer is not counted for the queue.
        #expect(model.sendCount == 0)

        #expect(try await model.writeComposer() == .answer)
        let last = try #require(try thread(1, model).messages.last)
        #expect(last.kind == .answer)
        #expect(last.text == "The intro")
        #expect(try thread(1, model).openQuestion == nil)
        #expect(model.state().queue.isEmpty)
        #expect(!model.threadGroups.contains { $0.group == .needsYou })
        #expect(try resolved(model).kind == .followUp)
        #expect(model.composerText.isEmpty)
    }

    @Test("in the list on the frame of a thread with an open question the composer answers it too")
    func answerFromList() async throws {
        defer { cleanUp() }
        let model = try await model()
        let id = try await asked(model)
        #expect(model.shown == nil)
        let target = try resolved(model)
        #expect(target.kind == .answer)
        #expect(target.thread == id)
        model.composerText = "The intro"
        // Cmd+Return with nothing queued: the answer goes at once all the same.
        #expect(!model.canSend)
        model.send()
        #expect(try thread(1, model).messages.last?.kind == .answer)
        #expect(model.composerText.isEmpty)
        #expect(model.problem == nil)
    }

    @Test("the composer's Send counts what a send would deliver, the queue with the words, and names no count for one or none")
    func sendTitle() async throws {
        defer { cleanUp() }
        let model = try await model()
        #expect(Composer.sendTitle(model.sendCount) == "Send")
        _ = try await model.addMessage(text: "One", at: 5)
        #expect(Composer.sendTitle(model.sendCount) == "Send")
        try await model.seek(to: 12)
        model.composerText = "Two"
        #expect(model.sendCount == 2)
        #expect(Composer.sendTitle(model.sendCount) == "Send 2")
        model.composerText = "   "
        #expect(Composer.sendTitle(model.sendCount) == "Send")
    }

    @Test("the composer keeps one draft per target thread, and one for a new thread, until the words are written or another video opens")
    func drafts() async throws {
        defer { cleanUp() }
        let model = try await model()
        _ = try await model.addMessage(text: "One", at: 5)
        _ = try await model.addMessage(text: "Two", at: 15)
        let (one, two) = (try thread(1, model).id, try thread(2, model).id)

        model.showThread(one)
        model.composerText = "For one"
        model.showThread(two)
        #expect(model.composerText.isEmpty)
        model.composerText = "For two"
        model.showThread(one)
        #expect(model.composerText == "For one")

        // The list on thread one's frame writes on thread one: the same draft.
        _ = model.showThreadList()
        await eventually { model.engine.frameTime(of: model.engine.time) == (try? thread(1, model).time) }
        #expect(model.composerText == "For one")
        try await model.seek(to: 10)
        #expect(model.composerText.isEmpty)
        model.composerText = "For a new one"
        try await model.seek(to: 11)
        #expect(model.composerText == "For a new one")

        model.showThread(two)
        #expect(model.composerText == "For two")
        _ = try await model.writeComposer()
        #expect(model.composerText.isEmpty)
        model.showThread(one)
        #expect(model.composerText == "For one")

        try await model.open(MessageTests.fixture)
        #expect(model.composerDrafts.isEmpty)
    }

    @Test("a drawn region is the composer's chip on its frame; it goes with the composer's words, and the popover's words or its discard take it")
    func region() async throws {
        defer { cleanUp() }
        let model = try await model()
        try await model.seek(to: 12)
        let region = try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)

        // Drawn: the popover opens on it, and the composer shows it too.
        model.beginRegion()
        model.endRegion(region)
        #expect(model.draft?.region == region)
        #expect(model.composerRegion == region)
        // A click into the composer closes the empty popover; the chip stays.
        model.closePopover(.clickOutside)
        #expect(model.composerRegion == region)
        model.composerText = "This box"
        #expect(try resolved(model).takesRegion)
        _ = try await model.writeComposer()
        #expect(try thread(1, model).messages.first?.region == region)
        #expect(model.composerRegion == nil)

        // The × on the chip.
        model.startDraft(region: region)
        model.closePopover(.clickOutside)
        model.removeComposerRegion()
        #expect(model.composerRegion == nil)

        // Escape in the popover drops the region everywhere.
        model.startDraft(region: region)
        #expect(model.composerRegion == region)
        model.closePopover(.discard)
        #expect(model.composerRegion == nil)

        // Words in the popover take the region.
        model.startDraft(region: region)
        model.draft?.text = "Here"
        model.commitDraft()
        #expect(model.composerRegion == nil)
    }

    @Test("the chip goes with no General message, and stays on its frame only; a region turns an answer into a message on the frame")
    func regionRules() async throws {
        defer { cleanUp() }
        let model = try await model()
        let id = try await asked(model)
        let region = try Region(x: 0.1, y: 0.1, w: 0.2, h: 0.2)
        #expect(try resolved(model).kind == .answer)

        model.startDraft(region: region)
        model.closePopover(.clickOutside)
        var target = try resolved(model)
        #expect(target.kind == .reply)
        #expect(target.takesRegion)
        #expect(model.composerRegion == region)

        model.toggleComposerGeneral()
        #expect(model.composerRegion == nil)
        model.toggleComposerGeneral()
        #expect(model.composerRegion == region)

        // Off its frame the chip goes.
        try await model.seek(to: 20)
        #expect(model.composerRegion == nil)
        #expect(try resolved(model).kind == .newThread)

        // Back on it, a follow-up with the region in the thread view.
        _ = try await model.showThread(id.text)
        target = try resolved(model)
        #expect(target.kind == .followUp)
        model.composerText = "This part"
        _ = try await model.writeComposer()
        let last = try #require(try thread(1, model).messages.last)
        #expect(last.region == region)
        #expect(last.kind == .message)
        #expect(try thread(1, model).openQuestion != nil)
    }

    @Test("Cmd+Return sends the queue with the composer's words")
    func sendTakesWords() async throws {
        defer { cleanUp() }
        let model = try await model()
        try await model.seek(to: 12)
        model.composerText = "Too fast"
        #expect(model.sendCount == 1)
        let send = try await model.sendQueue()
        #expect(send.messageIds.count == 1)
        #expect(try thread(1, model).messages.first?.state == .sent)
        #expect(model.composerText.isEmpty)
    }

    @Test("comment compose puts the words, a region chip and the General toggle in the composer, and state reports them")
    func composeCommand() async throws {
        defer { cleanUp() }
        let model = try await model()
        try await model.seek(to: 12)
        let region = try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        let before = model.composerFocusRequests

        let composer = try model.compose(text: "This box", region: region, general: false)
        #expect(composer.target == "New thread at 0:12")
        #expect(composer.kind == "new")
        #expect(composer.number == 1)
        #expect(composer.text == "This box")
        #expect(composer.region == region)
        #expect(model.composerFocusRequests == before + 1)
        #expect(model.draft == nil)

        let general = try model.compose(text: "Overall", region: nil, general: true)
        #expect(general.target == "Reply on General")
        #expect(general.kind == "reply")
        #expect(general.time == nil)
        #expect(general.region == nil)
        #expect(general.text == "Overall")

        let state = try #require(JSONSerialization.jsonObject(with: Data(model.state().json.utf8)) as? [String: Any])
        let sidebar = try #require(state["sidebar"] as? [String: Any])
        let reported = try #require(sidebar["composer"] as? [String: Any])
        #expect(reported["general"] as? Bool == true)
        #expect(reported["text"] as? String == "Overall")
        #expect(reported["region"] is NSNull)
    }

    /// Waits until `condition` holds: a click moves the player in a task.
    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
