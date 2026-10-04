import Foundation
import ImageIO
import Testing
@testable import VRApp
import VRCommand
import VRLease
import VRReview
import VRStore
import VRWire

/// A frame grabber that writes a note of what was asked instead of a
/// picture, or fails.
struct FakeFrames: FrameGrabbing {
    struct Failure: LocalizedError {
        var errorDescription: String? { "the disk is full" }
    }

    /// A number a test reads while the grabber counts on another thread.
    final class Count: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int { lock.withLock { count } }
        func add() { lock.withLock { count += 1 } }
    }

    var fails = false
    var failsCrop = false
    /// Counts the crops written, when a test waits for one.
    var crops: Count?
    /// Counts the keyframes written, when a test waits for one.
    var keyframes: Count?

    func writeKeyframe(of video: URL, at seconds: Double, to file: URL) async throws -> CGSize {
        if fails { throw Failure() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("frame of \(video.lastPathComponent) at \(seconds)".utf8).write(to: file)
        keyframes?.add()
        return CGSize(width: 1920, height: 1080)
    }

    func writeCrop(of keyframe: URL, region: Region, to file: URL) async throws {
        if failsCrop { throw Failure() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("crop \(region.text) of \(keyframe.lastPathComponent)".utf8).write(to: file)
        crops?.add()
    }
}

/// A library in a folder of its own under `/tmp`, made when first written.
func scratchLibrary() -> Library {
    Library(root: URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true))
}

private let holder = Holder(key: "test", name: "Claude Code", place: "/Users/me/repo")

/// A control server over a fake player and a library of its own, for the comment tests, with the
/// fixture video open.
@MainActor
final class CommentRig {
    let player = FakePlayer()
    let library = scratchLibrary()
    let model: ReviewModel
    let server: ControlServer

    init(frames: any FrameGrabbing = FakeFrames(), socket: URL = URL(fileURLWithPath: "/tmp/vr-unused/control.sock")) {
        let model = ReviewModel(player: player, frames: frames, library: library)
        self.model = model
        server = ControlServer(
            socket: socket,
            model: model,
            desk: OperatorDesk(model: model) { _, _ in .captured },
            now: { Date(timeIntervalSince1970: 1_000) },
            quit: {}
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: library.root)
    }

    func opened() async -> CommentRig {
        _ = await send(.playerOpen(path: fixtureVideo.path))
        return self
    }

    func send(_ request: ControlRequest, json: Bool = false) async -> ControlReply {
        await server.reply(to: ControlMessage(request, holder: holder, json: json).encoded()).reply
    }

    func object(_ request: ControlRequest) async throws -> [String: Any] {
        let reply = await send(request, json: true)
        #expect(reply.ok, "\(reply.error)")
        return try #require(try JSONSerialization.jsonObject(with: Data(reply.output.utf8)) as? [String: Any])
    }

    /// The comments in `state --json`.
    func comments() async throws -> [[String: Any]] {
        try #require(try await object(.state)["comments"] as? [[String: Any]])
    }

    func queue() async throws -> [String] {
        try #require(try await object(.state)["queue"] as? [String])
    }

    /// What the timeline marks.
    var markers: [Timeline.Marker] {
        Timeline.markers(for: model.comments, selection: model.selection)
    }

    func crop(_ id: String) -> URL {
        library.cropURL(model.video?.info.contentHash ?? "", comment: id)
    }

    func keyframe(_ id: String) -> URL {
        library.keyframeURL(model.video?.info.contentHash ?? "", comment: id)
    }
}

private func exists(_ file: URL) -> Bool {
    FileManager.default.fileExists(atPath: file.path)
}

@MainActor
@Suite struct CommentTests {
    @Test func aCommentFromTheCommandLineIsQueuedWithItsIdTimeTextAndKeyframe() async throws {
        let rig = await CommentRig().opened()
        _ = await rig.send(.playerSeek(seconds: 10))

        #expect(await rig.send(.commentAdd(text: " too fast ", at: nil, region: nil)) == .done("c1 at 0:10.000\n"))

        let comment = try #require(try await rig.comments().first)
        #expect(comment["id"] as? String == "c1")
        #expect(comment["time"] as? Double == 10)
        #expect(comment["text"] as? String == "too fast")
        #expect(comment["state"] as? String == "queued")
        #expect(comment["keyframePath"] as? String == rig.keyframe("c1").path)
        // The keyframe is on disk by the time the command answers, taken
        // from the video file at the comment's time.
        #expect(try String(contentsOf: rig.keyframe("c1"), encoding: .utf8) == "frame of sample.mp4 at 10.0")
        #expect(try await rig.queue() == ["c1"])
        #expect(rig.markers == [Timeline.Marker(id: "c1", time: 10, state: .queued, isSelected: true)])
    }

    @Test func aTimeGivenWithTheCommentMovesAndPausesThePlayer() async throws {
        let rig = await CommentRig().opened()
        _ = await rig.send(.playerPlay)

        let reply = await rig.send(.commentAdd(text: "here", at: 5.5, region: nil), json: true)

        #expect(reply.output == #"{"batchId":null,"cropPath":null,"id":"c1","keyframePath":"\#(rig.keyframe("c1").path)","region":null,"state":"queued","text":"here","thread":[],"time":5.5}"# + "\n")
        #expect(rig.player.time == 5.5)
        #expect(!rig.player.isPlaying)
    }

    @Test func stateListsTheQueueAndTheCommentsInTimeOrder() async throws {
        let rig = await CommentRig().opened()
        for time in [15.0, 3, 10] {
            _ = await rig.send(.commentAdd(text: "at \(time)", at: time, region: nil))
        }

        #expect(try await rig.queue() == ["c2", "c3", "c1"])
        #expect(try await rig.comments().map { $0["time"] as? Double } == [3, 10, 15])
        #expect(rig.markers.map(\.id) == ["c2", "c3", "c1"])
        #expect(await rig.send(.state).output == """
            video: sample (0:21.233) \(fixtureVideo.path)
            player: paused at 0:10.000
            transcript: voiceover, 3 lines
            comments: 3, 3 queued
              c2 queued at 0:03.000: at 3.0
              c3 queued at 0:10.000: at 10.0
              c1 queued at 0:15.000: at 15.0
            listener: absent
            lease: Claude Code in /Users/me/repo, 60s left, 0 waiting

            """)
    }

    @Test func aCommentFromTheWindowAndOneFromTheCommandLineBothShowAsMarkers() async throws {
        let rig = await CommentRig().opened()
        _ = await rig.send(.playerSeek(seconds: 4))
        _ = await rig.send(.playerPlay)

        // The window: C opens the comment box, Enter queues what it holds.
        rig.model.compose()
        #expect(!rig.player.isPlaying)
        let draft = try #require(rig.model.composing)
        #expect(try await rig.comments().map { $0["state"] as? String } == ["draft"])
        // A draft isn't marked, and isn't in the queue.
        #expect(rig.markers.isEmpty)
        #expect(try await rig.queue().isEmpty)
        #expect(rig.model.commitComposer(text: "from the window"))
        #expect(rig.model.composing == nil)

        _ = await rig.send(.commentAdd(text: "from the command line", at: 12, region: nil))

        #expect(rig.markers.map(\.id) == [draft, "c2"])
        #expect(rig.markers.map(\.time) == [4, 12])
        #expect(try await rig.queue() == ["c1", "c2"])
        // The window's comment has its keyframe too, once it's written.
        await settle { rig.model.keyframeURL(for: draft) != nil }
        #expect(try String(contentsOf: rig.keyframe(draft), encoding: .utf8) == "frame of sample.mp4 at 4.0")
    }

    @Test func theCommentBoxStaysOpenOnEmptyTextAndCancelDropsItsDraftAndFrame() async throws {
        let rig = await CommentRig().opened()
        rig.model.compose()
        let draft = try #require(rig.model.composing)
        await settle { rig.model.keyframeURL(for: draft) != nil }
        #expect(exists(rig.keyframe(draft)))

        #expect(!rig.model.commitComposer(text: " \n"))
        #expect(rig.model.composing == draft)
        // The box is open on one draft: asking again doesn't start another.
        rig.model.compose()
        #expect(rig.model.composing == draft)

        rig.model.cancelComposer()

        #expect(rig.model.composing == nil)
        #expect(try await rig.comments().isEmpty)
        #expect(!exists(rig.keyframe(draft)))
    }

    @Test func aDraftCancelledWhileItsFrameIsWrittenLeavesNoFile() async throws {
        let written = FakeFrames.Count()
        let rig = await CommentRig(frames: FakeFrames(keyframes: written)).opened()
        rig.model.compose()
        let draft = try #require(rig.model.composing)

        rig.model.cancelComposer()
        // The frame lands after the cancel, and removes itself.
        await settle { written.value == 1 }
        await settle { !exists(rig.keyframe(draft)) }

        #expect(!exists(rig.keyframe(draft)))
        #expect(rig.model.keyframeURL(for: draft) == nil)
    }

    @Test func editAndDeleteChangeTheQueueAndTheMarkers() async throws {
        let rig = await CommentRig().opened()
        _ = await rig.send(.commentAdd(text: "one", at: 10, region: nil))
        _ = await rig.send(.commentAdd(text: "two", at: 5, region: nil))

        #expect(await rig.send(.commentEdit(id: "c1", text: "one, better")) == .done("edited c1\n"))
        #expect(try await rig.comments().map { $0["text"] as? String } == ["two", "one, better"])
        #expect(rig.model.comments.map(\.text) == ["two", "one, better"])

        #expect(await rig.send(.commentDelete(id: "c1"), json: true).output == #"{"id":"c1"}"# + "\n")
        #expect(try await rig.queue() == ["c2"])
        #expect(rig.markers.map(\.id) == ["c2"])
        #expect(!exists(rig.keyframe("c1")))
        #expect(exists(rig.keyframe("c2")))

        #expect(await rig.send(.commentDelete(id: "c2")) == .done("deleted c2\n"))
        #expect(try await rig.queue().isEmpty)
        #expect(rig.markers.isEmpty)
        // A deleted comment's id isn't given again.
        #expect(await rig.send(.commentAdd(text: "three", at: nil, region: nil)).output.hasPrefix("c3 at "))
    }

    @Test func whatCannotBeDoneIsRefusedAndChangesNothing() async throws {
        let closed = CommentRig()
        let noVideo = ControlReply.refused("no video is open; `video-review player open <path>`")
        #expect(await closed.send(.commentAdd(text: "x", at: nil, region: nil)) == noVideo)
        #expect(await closed.send(.commentEdit(id: "c1", text: "x")) == noVideo)
        #expect(await closed.send(.commentDelete(id: "c1")) == noVideo)

        let rig = await CommentRig().opened()
        _ = await rig.send(.playerSeek(seconds: 10))
        #expect(await rig.send(.commentAdd(text: " ", at: 5, region: nil)) == .refused("a comment needs its text"))
        #expect(await rig.send(.commentAdd(text: "x", at: 30, region: nil)) == .refused("0:30.000 is outside the video (0:00.000 to 0:21.233)"))
        #expect(await rig.send(.commentEdit(id: "c9", text: "x")) == .refused("there's no comment c9"))
        #expect(await rig.send(.commentDelete(id: "c9")) == .refused("there's no comment c9"))
        // Nothing moved the player or left a comment.
        #expect(rig.player.time == 10)
        #expect(try await rig.comments().isEmpty)

        _ = await rig.send(.commentAdd(text: "kept", at: nil, region: nil))
        #expect(await rig.send(.commentEdit(id: "c1", text: "")) == .refused("a comment needs its text"))
        #expect(rig.model.comments.map(\.text) == ["kept"])
    }

    @Test func aCommentWhoseFrameCannotBeSavedIsRefused() async throws {
        let rig = await CommentRig(frames: FakeFrames(fails: true)).opened()

        let reply = await rig.send(.commentAdd(text: "x", at: 10, region: nil))

        #expect(reply == .refused("couldn't save the frame at 0:10.000: the disk is full"))
        #expect(try await rig.comments().isEmpty)
    }

    @Test func showingACommentSeeksPausesAndSelectsIt() async throws {
        let rig = await CommentRig().opened()
        _ = await rig.send(.commentAdd(text: "one", at: 10, region: nil))
        _ = await rig.send(.commentAdd(text: "two", at: 5, region: nil))
        _ = await rig.send(.playerPlay)

        // What a click on c1's marker does.
        try await rig.model.showComment("c1")

        #expect(rig.player.time == 10)
        #expect(!rig.player.isPlaying)
        #expect(rig.model.selection == "c1")
        #expect(rig.markers.map(\.isSelected) == [false, true])
        await #expect(throws: ModelRefusal("there's no comment c9")) { try await rig.model.showComment("c9") }
    }

    @Test func aVideoOpenedAgainHasItsComments() async throws {
        let rig = await CommentRig().opened()
        _ = await rig.send(.commentAdd(text: "one", at: 10, region: nil))

        _ = await rig.send(.playerOpen(path: fixtureVideo.path))

        #expect(try await rig.queue() == ["c1"])
        #expect(try await rig.comments().first?["keyframePath"] as? String == rig.keyframe("c1").path)
    }
}

/// The command, the server and the real frame grabber joined by a real
/// socket, without the app's window.
@MainActor
@Suite struct CommentRoundTripTests {
    @Test func theCommandAddsEditsAndDeletesACommentWithARealKeyframe() async throws {
        let support = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let rig = CommentRig(frames: FrameGrabber(), socket: ControlSocket.url(in: support))
        try rig.server.start()
        defer { rig.server.stop() }

        let table = CommandTable.standard
        var environment = CommandEnvironment.system()
        environment.variables = [AppIdentity.supportVariable: support.path, "CLAUDE_CODE_SESSION_ID": "test"]
        let run = { [table, environment] (arguments: [String]) async -> CommandResult in
            await Task.detached { table.run(arguments, environment: environment) }.value
        }

        _ = await run(["player", "open", fixtureVideo.path])
        #expect(await run(["comment", "add", "the title is too small", "--at", "0:10"]) == CommandResult(output: "c1 at 0:10.000\n"))
        #expect(await run(["comment", "add", "good pace", "--at", "3"]) == CommandResult(output: "c2 at 0:03.000\n"))

        let state = await run(["state", "--json"])
        let object = try #require(try JSONSerialization.jsonObject(with: Data(state.output.utf8)) as? [String: Any])
        #expect(object["queue"] as? [String] == ["c2", "c1"])
        let comments = try #require(object["comments"] as? [[String: Any]])
        let path = try #require(comments.last?["keyframePath"] as? String)
        #expect(path == rig.keyframe("c1").path)
        // A PNG of the whole frame.
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.png")
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 1920)
        #expect(image.height == 1080)

        #expect(await run(["comment", "edit", "c1", "the title is too small to read"]) == CommandResult(output: "edited c1\n"))
        #expect(await run(["comment", "delete", "c2"]) == CommandResult(output: "deleted c2\n"))
        #expect(await run(["comment", "delete", "c2"]) == CommandResult(error: "there's no comment c2\n", status: 1))
        #expect(rig.model.comments == [Comment(id: "c1", time: 10, text: "the title is too small to read", state: .queued)])
    }
}
