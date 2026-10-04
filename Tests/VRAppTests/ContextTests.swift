import Foundation
import Testing
@testable import VRApp
import VRLease
import VRReview
import VRWire

/// The video's context on its way to a listener: requests answered in
/// memory, on a copy of the fixture video in a temporary folder, so each
/// test puts the sidecars it wants beside it. No window is opened and no
/// sound is made.
@Suite(.serialized) @MainActor struct ContextTests {
    nonisolated static let operatorAgent = Holder(key: "operator", name: "Claude Code", place: "/work")
    nonisolated static let first = Holder(key: "L1", name: "Claude Code", place: "/repo")
    nonisolated static let second = Holder(key: "L2", name: "codex", place: "/blog")

    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
        .resolvingSymlinksInPath()
    /// The folder the copy of the video is in, with its sidecars.
    var videos: URL { folder.appendingPathComponent("videos-in", isDirectory: true) }
    var video: URL { videos.appendingPathComponent("sample.mp4") }
    var named: URL { videos.appendingPathComponent("sample.context.md") }
    var plain: URL { videos.appendingPathComponent("context.md") }

    /// A server on a model with the copy of the fixture open and silent,
    /// beside the sidecars given.
    func server(named: String? = nil, plain: String? = nil) async throws -> (ControlServer, AppModel) {
        try FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: RegionCommentTests.fixture, to: video)
        try named?.write(to: self.named, atomically: true, encoding: .utf8)
        try plain?.write(to: self.plain, atomically: true, encoding: .utf8)
        let model = AppModel(environment: [SupportFolder.overrideVariable: folder.appendingPathComponent("support").path])
        model.player.player.isMuted = true
        try await model.open(video)
        let server = ControlServer(
            socket: folder.appendingPathComponent("control.sock"), model: model, screenshotter: Screenshotter(model: model),
            lease: ControlLease(), indicator: LeaseIndicator(), quit: {}
        )
        return (server, model)
    }

    static func sent(_ request: ControlRequest, by holder: Holder = operatorAgent, json: Bool = false) -> Data {
        ControlMessage(request, holder: holder, json: json).encoded()
    }

    /// Sends one comment as a batch, and the `context` of the payload
    /// `listener`'s next `wait` gets. With `written`, its reply reached it.
    func nextContext(on server: ControlServer, to listener: Holder = first, written: Bool = true) async throws -> String? {
        _ = await server.reply(to: Self.sent(.commentAdd(text: "too fast", at: 10, region: nil)))
        _ = await server.reply(to: Self.sent(.batchSend))
        let answer = await server.reply(to: Self.sent(.wait(timeoutSeconds: 0), by: listener))
        if written { server.written(answer) } else { server.undelivered(answer) }
        // `null` is in the payload, not left out.
        let object = try #require(JSONSerialization.jsonObject(with: Data(answer.reply.output.utf8)) as? [String: Any])
        #expect(object.keys.contains("context"))
        return try JSONDecoder().decode(BatchPayload.self, from: Data(answer.reply.output.utf8)).context
    }

    /// The `context` part of `state`.
    func shown(by server: ControlServer) async throws -> [String: Any] {
        let reply = await server.reply(to: Self.sent(.state, by: Self.second))
        let state = try #require(JSONSerialization.jsonObject(with: Data(reply.reply.output.utf8)) as? [String: Any])
        return try #require(state["context"] as? [String: Any])
    }

    // MARK: - Once per listener session

    @Test func theFirstBatchOfAListenerSessionHasTheContextAndTheNextHasNullUntilTheFileOrTheNoteChanges() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (server, _) = try await server(named: "# Context: sample\n\nThe lease walk.\n")

        // The first batch has the sidecar's text; the next has `null`.
        #expect(try await nextContext(on: server) == "# Context: sample\n\nThe lease walk.")
        #expect(try await nextContext(on: server) == nil)

        // A change to the file puts the text in the next batch again, once.
        try "# Context: sample\n\nThe lease walk, second cut.\n".write(to: named, atomically: true, encoding: .utf8)
        #expect(try await nextContext(on: server) == "# Context: sample\n\nThe lease walk, second cut.")
        #expect(try await nextContext(on: server) == nil)

        // So does a change to the note, which goes under its heading.
        let set = await server.reply(to: Self.sent(.contextSet(text: " Look at the banner. \n")))
        #expect(set == .init(reply: .done("context note set\n")))
        let composed = "# Context: sample\n\nThe lease walk, second cut.\n\n## Note from the reviewer\n\nLook at the banner."
        #expect(try await nextContext(on: server) == composed)
        #expect(try await nextContext(on: server) == nil)

        // A new listener session gets the context again; then the first one, back, is new too.
        #expect(try await nextContext(on: server, to: Self.second) == composed)
        #expect(try await nextContext(on: server, to: Self.second) == nil)
        #expect(try await nextContext(on: server, to: Self.first) == composed)
    }

    @Test func aContextWhoseReplyNeverReachedTheListenerGoesOutAgain() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (server, _) = try await server(named: "# Context: sample\n")

        #expect(try await nextContext(on: server, written: false) == "# Context: sample")
        // The batch that stayed pending goes first, with the context still.
        #expect(try await nextContext(on: server) == "# Context: sample")
        #expect(try await nextContext(on: server) == nil)
    }

    // MARK: - Where the text comes from

    @Test func aVideoWithNoSidecarAndNoNoteHasNoContext() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (server, _) = try await server()

        #expect(try await nextContext(on: server) == nil)
        let shown = try await shown(by: server)
        #expect(shown["sidecarPath"] is NSNull)
        #expect(shown["note"] as? String == "")
    }

    @Test func aNoteAloneIsTheContextOfAVideoWithNoSidecar() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (server, model) = try await server()

        let set = await server.reply(to: Self.sent(.contextSet(text: "the lease walk,\nfrom shipyard\n"), json: true))

        #expect(set == .init(reply: .done(#"{"note":"the lease walk,\nfrom shipyard"}"# + "\n")))
        #expect(model.desk.open?.note == "the lease walk,\nfrom shipyard")
        #expect(try await shown(by: server)["note"] as? String == "the lease walk,\nfrom shipyard")
        #expect(try await nextContext(on: server) == "## Note from the reviewer\n\nthe lease walk,\nfrom shipyard")
        // An empty text clears the note: nothing new to send.
        _ = await server.reply(to: Self.sent(.contextSet(text: "")))
        #expect(model.desk.open?.note == "")
        #expect(try await nextContext(on: server) == nil)
    }

    @Test func aPlainContextFileIsTheFallbackAndTheOneNamedAfterTheVideoWins() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (server, model) = try await server(plain: "# The folder's context\n")

        #expect(ContextSource.read(for: video) == .init(url: plain, text: "# The folder's context\n"))
        #expect(try await shown(by: server)["sidecarPath"] as? String == plain.path)
        #expect(try await nextContext(on: server) == "# The folder's context")

        try "# This video's context\n".write(to: named, atomically: true, encoding: .utf8)

        #expect(model.sidecar == .init(url: named, text: "# This video's context\n"))
        #expect(try await shown(by: server)["sidecarPath"] as? String == named.path)
        #expect(try await nextContext(on: server) == "# This video's context")
    }

    // MARK: - The note

    @Test func theNoteIsKeptPerVideoAndComesBackWhenTheVideoIsOpenedAgain() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let (_, model) = try await server()
        // Another video: the same pictures with other bytes at the end.
        let other = videos.appendingPathComponent("other.mp4")
        var bytes = try Data(contentsOf: video)
        bytes.append(contentsOf: [0, 0, 0, 8, 0x66, 0x72, 0x65, 0x65])
        try bytes.write(to: other)

        try model.setNote("about the sample")
        try await model.open(other)
        #expect(model.desk.open?.note == "")
        try model.setNote("about the other")
        try await model.open(video)

        #expect(model.desk.open?.note == "about the sample")
    }

    @Test func settingTheNoteWithNoVideoOpenIsRefused() async {
        let model = AppModel(environment: [SupportFolder.overrideVariable: folder.path])
        let server = ControlServer(
            socket: folder.appendingPathComponent("control.sock"), model: model, screenshotter: Screenshotter(model: model),
            lease: ControlLease(), indicator: LeaseIndicator(), quit: {}
        )

        let refused = await server.reply(to: Self.sent(.contextSet(text: "a note")))

        #expect(refused == .init(reply: .refused("no video is open")))
    }
}
