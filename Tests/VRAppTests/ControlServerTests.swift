import Foundation
import Testing
@testable import VRApp
import VRCommand
import VRLease
import VRWire

/// A player that keeps its time and nothing else.
@MainActor
final class FakePlayer: Playing {
    var time = 0.0
    var isPlaying = false
    var loaded: URL?
    var loadFailure: (any Error)?

    func load(_ url: URL) async throws {
        if let loadFailure { throw loadFailure }
        loaded = url
        time = 0
        isPlaying = false
    }

    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func seek(to seconds: Double) async { time = seconds }
}

/// The repo's fixture video: 21.233 s of picture.
let fixtureVideo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("fixtures/sample/sample.mp4")
    .standardizedFileURL

private let holder = Holder(key: "test", name: "Claude Code", place: "/Users/me/repo")

/// The time the app reads, set by the test, and what the app does later
/// (`Later`): a call the app asked for is made when the test moves the time
/// past it with `advance`, at once and on the test's own path. No test
/// waits for real seconds.
@MainActor
final class FakeClock {
    var now = Date(timeIntervalSince1970: 0)
    private var calls: [(id: Int, due: Date, then: @MainActor () -> Void)] = []
    private var asked = 0

    /// Sets the time. No call the app asked for is made: `advance` makes them.
    func set(_ seconds: TimeInterval) {
        now = Date(timeIntervalSince1970: seconds)
    }

    /// The app's `Later` on this clock.
    var later: Later {
        Later { [self] seconds, then in
            asked += 1
            let id = asked
            calls.append((id, now.addingTimeInterval(seconds), then))
            return { [self] in calls.removeAll { $0.id == id } }
        }
    }

    /// How many calls the app asked for and are still to make.
    var waiting: Int { calls.count }

    /// Moves the time on by `seconds`, making each call that falls due on
    /// the way, in order, at its own time.
    func advance(by seconds: TimeInterval) {
        let end = now.addingTimeInterval(seconds)
        while let next = calls.filter({ $0.due <= end }).min(by: { $0.due < $1.due }) {
            calls.removeAll { $0.id == next.id }
            now = max(now, next.due)
            next.then()
        }
        now = end
    }
}

/// A control server over a fake player, with no window to capture, a clock
/// the test sets and times named in UTC.
@MainActor
struct Rig {
    let player = FakePlayer()
    let clock = FakeClock()
    let model: ReviewModel
    let server: ControlServer

    init(
        socket: URL = URL(fileURLWithPath: "/tmp/vr-unused/control.sock"),
        demo: URL? = nil,
        lease: ControlLease = ControlLease()
    ) {
        let model = ReviewModel(player: player, frames: FakeFrames(), library: scratchLibrary(), demoFolder: demo, later: clock.later)
        self.model = model
        server = ControlServer(
            socket: socket,
            model: model,
            desk: OperatorDesk(model: model) { file, _ in
                file.path.contains("unwritable") ? .failed(why: "couldn't write \(file.path)") : .captured
            },
            lease: lease,
            now: { [clock] in clock.now },
            timeZone: TimeZone(identifier: "UTC")!,
            later: clock.later,
            quit: {}
        )
    }

    func send(_ request: ControlRequest, by sender: Holder? = nil, json: Bool = false) async -> ControlServer.Answer {
        await server.reply(to: ControlMessage(request, holder: sender ?? holder, json: json).encoded())
    }

    /// A `take` that waits in line, sent without waiting for its answer;
    /// returns once the server has it in line as the `count`th waiter.
    func queue(_ sender: Holder, seconds: Int, as count: Int, json: Bool = false) async throws -> Task<ControlServer.Answer, Never> {
        let waiting = Task { await send(.controlTake(waitSeconds: seconds), by: sender, json: json) }
        try await untilWaiting(count)
        return waiting
    }

    /// Returns once `count` takes wait in line.
    func untilWaiting(_ count: Int, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        await settle(until: { server.lease.waiting(at: clock.now) == count }, sourceLocation: sourceLocation)
    }

    /// The reply's `output` read as a JSON object.
    func object(_ request: ControlRequest) async throws -> [String: Any] {
        let answer = await send(request, json: true)
        #expect(answer.reply.ok, "\(answer.reply.error)")
        return try #require(try JSONSerialization.jsonObject(with: Data(answer.reply.output.utf8)) as? [String: Any])
    }
}

@MainActor
@Suite struct ControlServerTests {
    @Test func openingTheFixtureThenSeekingGivesTimeTenInState() async throws {
        let rig = Rig()

        let opened = await rig.send(.playerOpen(path: fixtureVideo.path))
        #expect(opened.reply == .done("opened sample (0:21.233)\n"))
        let sought = await rig.send(.playerSeek(seconds: 10))
        #expect(sought.reply == .done("at 0:10.000\n"))

        let state = try await rig.object(.state)
        #expect(state["time"] as? Double == 10)
        let player = try #require(state["player"] as? [String: Any])
        #expect(player["time"] as? Double == 10)
        #expect(player["playing"] as? Bool == false)
        let video = try #require(state["video"] as? [String: Any])
        #expect(video["path"] as? String == fixtureVideo.path)
        #expect(video["title"] as? String == "sample")
        #expect(video["duration"] as? Double == 21.233)
        #expect((video["contentHash"] as? String)?.count == 64)
    }

    @Test func stateAsJSONIsOneLineWithNullsWhereThereIsNothing() async {
        let rig = Rig()
        let answer = await rig.send(.state, json: true)
        #expect(answer.reply.output ==
            #"{"app":{"demo":null,"variant":"\#(AppIdentity.variant)","version":"\#(AppIdentity.version)"},"batches":[],"comments":[],"context":null,"lease":null,"listener":{"name":null,"presence":"absent"},"notices":[],"player":{"playing":false,"time":0},"queue":[],"time":0,"transcript":null,"video":null}"# + "\n")
    }

    @Test func stateAsLinesNamesTheVideoAndThePlayer() async {
        let rig = Rig()
        #expect(await rig.send(.state).reply.output == "video: none\nlistener: absent\nlease: free\n")

        _ = await rig.send(.playerOpen(path: fixtureVideo.path))
        _ = await rig.send(.playerSeek(seconds: 10))
        #expect(await rig.send(.state).reply.output == """
            video: sample (0:21.233) \(fixtureVideo.path)
            player: paused at 0:10.000
            transcript: voiceover, 3 lines
            listener: absent
            lease: Claude Code in /Users/me/repo, 60s left, 0 waiting

            """)
    }

    @Test func aRequestOfAnotherVersionIsRefusedNamingBothVersionsAndChangesNothing() async {
        let rig = Rig()
        let request = Data(#"{"command":"player.play","version":99,"holder":{"key":"k","name":"n","place":"p"}}"#.utf8)

        let answer = await rig.server.reply(to: request)

        #expect(answer.reply == .refused(
            "the video-review command speaks control version 99 and the app version 1: "
                + "reinstall \(AppIdentity.name) so both come from one build"
        ))
        #expect(!rig.player.isPlaying)
    }

    @Test func playAndPauseAnswerWithWhereThePlayerIs() async throws {
        let rig = Rig()
        _ = await rig.send(.playerOpen(path: fixtureVideo.path))
        _ = await rig.send(.playerSeek(seconds: 10))

        #expect(await rig.send(.playerPlay).reply == .done("playing at 0:10.000\n"))
        #expect(rig.player.isPlaying)
        #expect(await rig.send(.playerPause).reply == .done("paused at 0:10.000\n"))
        #expect(!rig.player.isPlaying)

        let playing = try await rig.object(.playerPlay)
        #expect(playing["playing"] as? Bool == true)
        #expect(playing["time"] as? Double == 10)
    }

    @Test func playAtTheEndStartsOver() async {
        let rig = Rig()
        _ = await rig.send(.playerOpen(path: fixtureVideo.path))
        _ = await rig.send(.playerSeek(seconds: 21.233))

        #expect(await rig.send(.playerPlay).reply == .done("playing at 0:00.000\n"))
    }

    @Test func aPlayerCommandWithNoVideoOpenIsRefused() async {
        let rig = Rig()
        let refusal = ControlReply.refused("no video is open; `video-review player open <path>`")
        #expect(await rig.send(.playerPlay).reply == refusal)
        #expect(await rig.send(.playerPause).reply == refusal)
        #expect(await rig.send(.playerSeek(seconds: 1)).reply == refusal)
    }

    @Test func aTimeOutsideTheVideoIsRefusedAndThePlayerStays() async {
        let rig = Rig()
        _ = await rig.send(.playerOpen(path: fixtureVideo.path))
        _ = await rig.send(.playerSeek(seconds: 10))

        let answer = await rig.send(.playerSeek(seconds: 30))

        #expect(answer.reply == .refused("0:30.000 is outside the video (0:00.000 to 0:21.233)"))
        #expect(rig.player.time == 10)
    }

    @Test func aFileThatIsNotAVideoIsRefusedAndTheOpenVideoStays() async throws {
        let rig = Rig()
        _ = await rig.send(.playerOpen(path: fixtureVideo.path))
        let notVideo = fixtureVideo.deletingLastPathComponent().appendingPathComponent("sample.srt")

        let answer = await rig.send(.playerOpen(path: notVideo.path))

        #expect(!answer.reply.ok)
        #expect(answer.reply.error.hasPrefix("sample.srt isn't a video the player can play"))
        #expect(rig.model.video?.info.title == "sample")
        #expect(rig.player.loaded == fixtureVideo)
    }

    @Test func aMissingFileIsRefused() async {
        let rig = Rig()
        #expect(await rig.send(.playerOpen(path: "/nonexistent/talk.mp4")).reply == .refused("no file at /nonexistent/talk.mp4"))
    }

    @Test func statusReportsTheVersionTheDemoAndTheVideo() async throws {
        let demo = fixtureVideo.deletingLastPathComponent()
        let rig = Rig(demo: demo)
        #expect(await rig.send(.appStatus).reply.output == """
            video-review \(AppIdentity.versionText) is running
            demo: \(demo.path)
            lease: free
            video: none
            listener: absent

            """)

        _ = await rig.send(.playerOpen(path: fixtureVideo.path))
        let status = try await rig.object(.appOpen)
        #expect(status["running"] as? Bool == true)
        #expect(status["version"] as? String == AppIdentity.version)
        #expect(status["variant"] as? String == AppIdentity.variant)
        #expect(status["demo"] as? String == demo.path)
        #expect((status["lease"] as? [String: Any])?["holder"] as? String == "Claude Code")
        #expect((status["video"] as? [String: Any])?["title"] as? String == "sample")
    }

    @Test func quitAnswersWithTheLeaseItRenewedForARelaunchToHandOverThenQuits() async {
        let rig = Rig()
        _ = await rig.send(.playerPause)
        rig.clock.set(20)

        let answer = await rig.send(.appQuit)

        let term = ControlLease.Term(holder: holder, taken: Date(timeIntervalSince1970: 0), ends: Date(timeIntervalSince1970: 80))
        #expect(answer == ControlServer.Answer(reply: ControlReply(ok: true, output: "video-review quit\n", lease: term), quits: true))
        #expect(await rig.send(.appQuit, json: true).reply.output == #"{"quit":true}"# + "\n")
    }

    @Test func aScreenshotAnswersWithItsPathOrWhyItFailed() async throws {
        let rig = Rig()
        #expect(await rig.send(.screenshot(path: "/tmp/a.png", appearance: .dark)).reply == .done("/tmp/a.png\n"))
        #expect(try await rig.object(.screenshot(path: "/tmp/a.png", appearance: nil))["path"] as? String == "/tmp/a.png")
        #expect(await rig.send(.screenshot(path: "/unwritable/a.png", appearance: nil)).reply
            == .refused("couldn't write /unwritable/a.png"))
    }
}

/// The command and the server joined by a real socket, without the app's
/// window: what `video-review` prints is what the server answered.
@MainActor
@Suite struct ControlSocketRoundTripTests {
    @Test func theCommandDrivesThePlayerThroughTheSocket() async throws {
        let support = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("vr-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let rig = Rig(socket: ControlSocket.url(in: support))
        try rig.server.start()
        defer { rig.server.stop() }

        let table = CommandTable.standard
        var environment = CommandEnvironment.system()
        environment.variables = [AppIdentity.supportVariable: support.path, "CLAUDE_CODE_SESSION_ID": "test"]
        let run = { [table, environment] (arguments: [String]) async -> CommandResult in
            // Off the main actor: the command blocks on the socket while the
            // server answers on the main actor.
            await Task.detached { table.run(arguments, environment: environment) }.value
        }

        #expect(await run(["player", "open", fixtureVideo.path]) == CommandResult(output: "opened sample (0:21.233)\n"))
        #expect(await run(["player", "seek", "0:10"]) == CommandResult(output: "at 0:10.000\n"))
        let state = await run(["state", "--json"])
        let object = try #require(try JSONSerialization.jsonObject(with: Data(state.output.utf8)) as? [String: Any])
        #expect(object["time"] as? Double == 10)
        #expect(await run(["player", "seek", "1:00"])
            == CommandResult(error: "1:00.000 is outside the video (0:00.000 to 0:21.233)\n", status: 1))

        // The socket is the user's own.
        let mode = try FileManager.default.attributesOfItem(atPath: rig.server.socket.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)

        rig.server.stop()
        #expect(await run(["state"]).status == 1)
        #expect(!FileManager.default.fileExists(atPath: rig.server.socket.path))
    }
}
