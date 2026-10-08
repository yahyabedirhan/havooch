import Foundation
@testable import ReviewApp
import ReviewCore
import ReviewLease
import ReviewWire
import Testing

/// The video context: where it's read from, and when a send carries it.
/// The app's model on a copy of the fixture video in a temporary folder,
/// whose sidecar files the tests write, and the control server in front of
/// it. No window, no socket.
@Suite("The video context", .serialized)
struct ContextDeliveryTests {
    nonisolated static let operatorAgent = Holder(key: "operator", name: "Claude Code", place: "/work")
    nonisolated static let listener = Holder(key: "listener-1", name: "Claude Code", place: "/shop")
    nonisolated static let restarted = Holder(key: "listener-2", name: "Claude Code", place: "/shop")

    static let noteHeading = "## Note from the reviewer"

    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
    /// The folder the video is in, beside its sidecars.
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private var video: URL { folder.appendingPathComponent("clip.mp4") }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ text: String, to name: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// The model with a copy of the fixture open as `clip.mp4`, and the
    /// server in front of it.
    private func app() async throws -> (WindowModel, ControlServer) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: video.path) {
            try FileManager.default.copyItem(at: MessageTests.fixture, to: video)
        }
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path]).makeWindow()
        try await model.open(video)
        let server = ControlServer(
            socket: URL(fileURLWithPath: "/nowhere/control.sock"), app: model.app, listeners: { model.app.listeners },
            screenshotter: ControlServerTests.FakeScreenshotter(), quit: {}
        )
        return (model, server)
    }

    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    /// Sends one message and takes it with a `wait`: the
    /// payload's `context`, nil for `null`.
    private func contextOfNextSend(
        _ model: WindowModel, _ server: ControlServer, as holder: Holder = listener
    ) async throws -> String? {
        _ = try await model.addMessage(text: "A message", at: 3)
        _ = try await model.sendQueue()
        return try await contextOfWait(server, as: holder)
    }

    /// The `context` of the payload the next `wait` gets, nil for `null`.
    private func contextOfWait(_ server: ControlServer, as holder: Holder = listener) async throws -> String? {
        let answer = await server.replyWritten(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: holder))
        let payload = try object(answer.reply.output)
        #expect(payload.keys.contains("context"))
        return payload["context"] as? String
    }

    // MARK: - Where the context is read from

    @Test("the sidecar is <video base name>.context.md in the video's folder, else context.md, else none")
    func sidecarLookup() throws {
        defer { cleanUp() }
        #expect(ContextReader.names(for: video) == ["clip.context.md", "context.md"])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(ContextReader.sidecar(beside: video) == nil)

        try write("\nFor every video here\n\n", to: "context.md")
        #expect(ContextReader.sidecar(beside: video)
            == .init(file: folder.appendingPathComponent("context.md"), text: "For every video here"))
        // Another video's own sidecar isn't this one's.
        try write("About another clip", to: "other.context.md")
        #expect(ContextReader.sidecar(beside: video)?.text == "For every video here")

        try write("About the clip\n", to: "clip.context.md")
        #expect(ContextReader.sidecar(beside: video)
            == .init(file: folder.appendingPathComponent("clip.context.md"), text: "About the clip"))

        // A blank file of the video's own: it opts out of the folder's.
        try write("  \n", to: "clip.context.md")
        #expect(ContextReader.sidecar(beside: video)?.text == "")
        #expect(ContextReader.text(sidecar: ContextReader.sidecar(beside: video)?.text, note: "") == nil)
    }

    @Test("the fixture's own sidecar is found beside it")
    func fixtureSidecar() throws {
        let sidecar = try #require(ContextReader.sidecar(beside: MessageTests.fixture))
        #expect(sidecar.file.lastPathComponent == "sample.context.md")
        #expect(sidecar.text.hasPrefix("# Context: sample\n"))
        #expect(sidecar.text.hasSuffix("- yahyabedirhan/havooch"))
    }

    @Test("the context is the sidecar's text, then the note under its heading; null when both are empty")
    func joined() {
        #expect(ContextReader.text(sidecar: "About the clip", note: "Mind the intro")
            == "About the clip\n\n## Note from the reviewer\n\nMind the intro")
        #expect(ContextReader.text(sidecar: " About the clip\n", note: " ") == "About the clip")
        #expect(ContextReader.text(sidecar: nil, note: "\nMind the intro\n") == "## Note from the reviewer\n\nMind the intro")
        #expect(ContextReader.text(sidecar: nil, note: "") == nil)
        #expect(ContextReader.text(sidecar: " \n", note: "\n") == nil)
        #expect(ContextReader.noteHeading == Self.noteHeading)
    }

    // MARK: - When a send carries it

    @Test("the first send of a listener session has the context, the next has null, and a new note or a changed sidecar puts it in again")
    func oncePerSession() async throws {
        defer { cleanUp() }
        try write("About the clip\n", to: "clip.context.md")
        let (model, server) = try await app()

        #expect(try await contextOfNextSend(model, server) == "About the clip")
        #expect(try await contextOfNextSend(model, server) == nil)

        // The note, as an operator sets it.
        let set = await server.reply(to: ControlRequest.contextSet(text: " Mind the intro\n").sent(by: Self.operatorAgent))
        #expect(set.reply == .done("context note set (14 characters)\n"))
        let state = try object(await server.reply(to: ControlRequest.state.sent(by: Self.listener, json: true)).reply.output)
        #expect((state["video"] as? [String: Any])?["contextNote"] as? String == "Mind the intro")
        #expect(try await contextOfNextSend(model, server) == "About the clip\n\n\(Self.noteHeading)\n\nMind the intro")
        #expect(try await contextOfNextSend(model, server) == nil)

        // The sidecar changes on disk: nothing watches it, the next send reads it.
        try write("About the clip, second cut\n", to: "clip.context.md")
        #expect(try await contextOfNextSend(model, server) == "About the clip, second cut\n\n\(Self.noteHeading)\n\nMind the intro")
        #expect(try await contextOfNextSend(model, server) == nil)

        // The note cleared is a change too.
        let cleared = await server.reply(to: ControlRequest.contextSet(text: "").sent(by: Self.operatorAgent))
        #expect(cleared.reply == .done("context note cleared\n"))
        #expect(try await contextOfNextSend(model, server) == "About the clip, second cut")
    }

    @Test("a new listener session gets the context again, with the send the last one didn't finish")
    func newSession() async throws {
        defer { cleanUp() }
        try write("About the clip\n", to: "clip.context.md")
        let (model, server) = try await app()
        #expect(try await contextOfNextSend(model, server) == "About the clip")
        #expect(try await contextOfNextSend(model, server) == nil)

        // The listener restarts under another key: both sends are in line again.
        #expect(try await contextOfWait(server, as: Self.restarted) == "About the clip")
        #expect(try await contextOfWait(server, as: Self.restarted) == nil)
        #expect(model.listeners().outbox.session?.key == Self.restarted.key)
    }

    @Test("a payload that couldn't be written takes its context back: the next wait gets the text again")
    func undelivered() async throws {
        defer { cleanUp() }
        try write("About the clip\n", to: "clip.context.md")
        let (model, server) = try await app()
        _ = try await model.addMessage(text: "A message", at: 3)
        _ = try await model.sendQueue()
        let lost = await server.reply(to: ControlRequest.wait(timeoutSeconds: 0).sent(by: Self.listener))
        #expect(try object(lost.reply.output)["context"] as? String == "About the clip")

        server.undelivered(lost)

        #expect(try await contextOfWait(server) == "About the clip")
    }

    @Test("a video with no sidecar has the note alone, and null with no note")
    func noteOnly() async throws {
        defer { cleanUp() }
        let (model, server) = try await app()
        #expect(model.sidecar == nil)
        #expect(model.contextText == nil)
        #expect(try await contextOfNextSend(model, server) == nil)

        try model.setContextNote("The second scene is the one to fix")

        #expect(model.isContextDue)
        #expect(try await contextOfNextSend(model, server) == "\(Self.noteHeading)\n\nThe second scene is the one to fix")
        #expect(!model.isContextDue)
        #expect(try await contextOfNextSend(model, server) == nil)
    }

    @Test("the folder's context.md serves a video with no sidecar of its own")
    func folderSidecar() async throws {
        defer { cleanUp() }
        try write("For every video here\n", to: "context.md")
        let (model, server) = try await app()
        #expect(model.sidecar?.file.lastPathComponent == "context.md")
        #expect(try await contextOfNextSend(model, server) == "For every video here")
    }

    // MARK: - The note

    @Test("the note is kept per video, without the space around it, and is back when the video opens again")
    func notePerVideo() async throws {
        defer { cleanUp() }
        let (model, _) = try await app()
        #expect(model.state().video?.contextNote == "")

        #expect(try model.setContextNote("  Mind the intro \n") == "Mind the intro")
        #expect(model.contextNote == "Mind the intro")
        #expect(model.state().video?.contextNote == "Mind the intro")

        // The same content under another name, in another folder, is the
        // same video: its note is back.
        try await model.open(MessageTests.fixture)
        #expect(model.contextNote == "Mind the intro")
        #expect(model.sidecar?.file.lastPathComponent == "sample.context.md")
    }

    @Test("context set with no video open is refused")
    func noVideo() async throws {
        defer { cleanUp() }
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path]).makeWindow()
        #expect(throws: AppRefusal("no video is open in the window; open one with `havooch player open <path>`")) {
            try model.setContextNote("A note")
        }
    }

    // MARK: - The popover

    @Test("the popover's Save goes the way context set goes, and closes the popover")
    func saveFromThePopover() async throws {
        defer { cleanUp() }
        try write("About the clip\n", to: "clip.context.md")
        let (model, server) = try await app()
        #expect(try await contextOfNextSend(model, server) == "About the clip")
        model.isContextShown = true
        // The file changed since the video opened: the popover reads it again.
        try write("About the clip, second cut\n", to: "clip.context.md")
        model.readSidecar()
        #expect(model.sidecar?.text == "About the clip, second cut")

        model.saveContextNote("Mind the intro\n")

        #expect(!model.isContextShown)
        #expect(model.contextNote == "Mind the intro")
        #expect(model.problem == nil)
        #expect(try await contextOfNextSend(model, server) == "About the clip, second cut\n\n\(Self.noteHeading)\n\nMind the intro")
    }

    @Test("the popover says where the context comes from and when the agent gets it")
    func words() {
        let names = ["clip.context.md", "context.md"]
        let none = ContextWords(sidecar: nil, names: names, hasContext: false, isDue: false)
        #expect(none.source == "No clip.context.md or context.md beside this video")
        #expect(none.delivery == "Nothing to tell the agent yet")

        let due = ContextWords(sidecar: "clip.context.md", names: names, hasContext: true, isDue: true)
        #expect(due.source == "clip.context.md")
        #expect(due.delivery == "Goes to the agent with your next send")

        let had = ContextWords(sidecar: "context.md", names: names, hasContext: true, isDue: false)
        #expect(had.source == "context.md")
        #expect(had.delivery == "The agent has this. It goes again when it changes")
        #expect(Set([none.help, due.help, had.help]).count == 3)
    }
}
