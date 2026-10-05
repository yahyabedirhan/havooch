import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewWire
import Testing

/// The comment popover's close rules through the app's model, on the
/// fixture video (D 1.4, D 2.2, D 2.3): a click outside queues, the × and
/// Escape discard, an empty popover only closes, and a change of the moment
/// queues the words at the popover's own frame and region.
@Suite("The comment popover closes by its rules", .serialized)
struct PopoverCloseTests {
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

    /// Waits until `condition` holds: queueing from the popover finishes in a task.
    private func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Opens the popover at `time`, on `region` when there is one, with `text`.
    private func open(_ model: AppModel, at time: Double, region: Region? = nil, text: String) async throws {
        try await model.seek(to: time)
        _ = try model.openPopover(text: text, region: region)
    }

    /// The only queued message, once it's queued.
    private func queued(_ model: AppModel) async throws -> (message: StateReport.Message, time: Double?) {
        await eventually { model.state().queue.count == 1 }
        let state = model.state()
        try #require(state.queue.count == 1)
        let thread = try #require(state.threads.first { $0.messages.contains { $0.id == state.queue[0] } })
        let message = try #require(thread.messages.first { $0.id == state.queue[0] })
        return (message, thread.time)
    }

    @Test("a click outside queues the words on the popover's region; an empty popover only closes")
    func clickOutside() async throws {
        defer { cleanUp() }
        let model = try await model()
        let region = try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        try await open(model, at: 12.5, region: region, text: "")
        model.closePopover(.clickOutside)
        #expect(model.draft == nil)
        #expect(model.state().threads.count == 1)

        try await open(model, at: 12.5, region: region, text: "This box")
        model.closePopover(.clickOutside)
        #expect(model.draft == nil)
        let (message, time) = try await queued(model)
        #expect(message.text == "This box")
        #expect(message.region == region)
        #expect(time == 12.5)
    }

    @Test("the × and Escape discard the words and the region; nothing is queued and no picture is written")
    func discard() async throws {
        defer { cleanUp() }
        let model = try await model()
        try await open(model, at: 12.5, region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25), text: "never mind")
        model.closePopover(.discard)
        #expect(model.draft == nil)
        try await open(model, at: 3, text: "nor this")
        #expect(model.escape())
        #expect(model.draft == nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.state().queue.isEmpty)
        #expect(model.state().threads.count == 1)
        #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("videos").path))
    }

    /// Each way the person or the operator changes the moment.
    enum Move: String, CaseIterable, CustomTestStringConvertible {
        case seek, scrub, play, togglePlay, frameStep, skip, threadClick

        var testDescription: String { rawValue }

        func run(on model: AppModel, thread: ThreadID) async throws {
            switch self {
            case .seek: try await model.seek(to: 15)
            case .scrub: model.scrub(to: 15)
            case .play: try model.play()
            case .togglePlay: model.togglePlay()
            case .frameStep: model.step(frames: 1)
            case .skip: model.skip(by: 5)
            case .threadClick: model.showThread(thread)
            }
        }
    }

    @Test("a change of the moment queues the words at the popover's own time and region", arguments: Move.allCases)
    func momentChangeQueues(move: Move) async throws {
        defer { cleanUp() }
        let model = try await model()
        // A thread elsewhere, for the timeline click to go to.
        let elsewhere = try await model.addMessage(text: "Elsewhere", at: 3)
        let region = try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25)
        try await open(model, at: 12.5, region: region, text: "On this frame")

        try await move.run(on: model, thread: try #require(ItemID(elsewhere.thread.id)))
        #expect(model.draft == nil)
        await eventually { model.state().queue.count == 2 }
        let thread = try #require(model.state().threads.first { $0.time == 12.5 })
        #expect(thread.messages.map(\.text) == ["On this frame"])
        #expect(thread.messages.first?.region == region)
        #expect(thread.messages.first?.cropPath.map { FileManager.default.fileExists(atPath: $0) } == true)
        try? model.pause()
    }

    @Test("a change of the moment discards an empty popover with its region: no thread is made", arguments: Move.allCases)
    func momentChangeDiscardsEmpty(move: Move) async throws {
        defer { cleanUp() }
        let model = try await model()
        let elsewhere = try await model.addMessage(text: "Elsewhere", at: 3)
        try await open(model, at: 12.5, region: try Region(x: 0.25, y: 0.2, w: 0.3, h: 0.25), text: "  \n")

        try await move.run(on: model, thread: try #require(ItemID(elsewhere.thread.id)))
        #expect(model.draft == nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.state().queue.count == 1)
        #expect(!model.state().threads.contains { $0.time == 12.5 })
        try? model.pause()
    }

    @Test("a message the operator writes on another frame is a change of the moment too: the popover's words keep their frame")
    func operatorWrite() async throws {
        defer { cleanUp() }
        let model = try await model()
        try await open(model, at: 12.5, text: "From the popover")
        _ = try await model.addMessage(text: "From the CLI", at: 3)
        #expect(model.draft == nil)
        let threads = model.state().threads
        #expect(threads.first { $0.time == 12.5 }?.messages.map(\.text) == ["From the popover"])
        #expect(threads.first { $0.time == 3 }?.messages.map(\.text) == ["From the CLI"])
    }

    @Test("pausing is no change of the moment: the popover stays open")
    func pauseKeepsPopover() async throws {
        defer { cleanUp() }
        let model = try await model()
        try await open(model, at: 12.5, text: "Still here")
        try model.pause()
        #expect(model.draft?.text == "Still here")
    }

    @Test("the popover names the thread it writes to: the frame's thread, or the next number")
    func threadNumber() async throws {
        defer { cleanUp() }
        let model = try await model()
        _ = try await model.addMessage(text: "First", at: 3)
        try await open(model, at: 12.5, text: "")
        #expect(model.draftThreadNumber == 2)
        #expect(model.state().popover == StateReport.Popover(thread: 2, time: 12.5, text: "", region: nil))
        model.closePopover(.discard)
        try await open(model, at: 3, text: "")
        #expect(model.draftThreadNumber == 1)
        model.closePopover(.discard)
        #expect(model.draftThreadNumber == nil)
    }

    @Test("C with the popover open keeps it; `comment open` over an open popover closes it as a click outside")
    func reopen() async throws {
        defer { cleanUp() }
        let model = try await model()
        try await open(model, at: 12.5, text: "First words")
        model.startDraft()
        #expect(model.draft?.text == "First words")
        _ = try model.openPopover(text: "", region: nil)
        #expect(model.draft?.text == "")
        let (message, time) = try await queued(model)
        #expect(message.text == "First words")
        #expect(time == 12.5)

        let empty = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        #expect(throws: AppRefusal.self) { try empty.openPopover(text: "", region: nil) }
    }

    @Test("a click outside the stage is outside the popover; one on the stage is the stage's own")
    func outsideClicks() {
        let stage = CGRect(x: 12, y: 52, width: 900, height: 500)
        #expect(OutsideClicks.isOutside(CGPoint(x: 1000, y: 300), stage: stage))
        #expect(OutsideClicks.isOutside(CGPoint(x: 300, y: 600), stage: stage))
        #expect(!OutsideClicks.isOutside(CGPoint(x: 300, y: 300), stage: stage))
        // Before the stage is laid out, no click is outside it.
        #expect(!OutsideClicks.isOutside(CGPoint(x: 300, y: 300), stage: .zero))
    }
}
