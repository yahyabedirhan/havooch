import Foundation
import VRLease
import VRWire

/// App control's server: while the app runs it listens on the control
/// socket and answers one JSON request per connection with one reply. Each
/// request is decoded, version-checked and leased before it reaches
/// `AppModel`, then answered on the main actor. Every refusal is a reply,
/// so the `video-review` command always has a line to print.
@MainActor
final class ControlServer {
    /// A reply, and whether the app quits once it's written.
    struct Answer: Sendable {
        var reply: ControlReply
        var quits = false
    }

    let socket: URL
    private let model: AppModel
    private let screenshotter: Screenshotter
    private let quit: @MainActor @Sendable () -> Void
    /// The time the lease is decided at, and the zone its refusals name it in.
    private let now: @MainActor () -> Date
    private let timeZone: TimeZone
    /// App control's lease: who may send operator requests, and until when.
    private(set) var lease: ControlLease
    private var listener: SocketListener?

    init(
        socket: URL,
        model: AppModel,
        screenshotter: Screenshotter,
        lease: ControlLease = ControlLease(),
        now: @escaping @MainActor () -> Date = { Date() },
        timeZone: TimeZone = .current,
        quit: @escaping @MainActor @Sendable () -> Void
    ) {
        self.socket = socket
        self.model = model
        self.screenshotter = screenshotter
        self.lease = lease
        self.now = now
        self.timeZone = timeZone
        self.quit = quit
    }

    // MARK: - Dispatch

    /// The answer to one request as the client sent it. An operator's
    /// request asks the lease first, and is refused with nothing done when
    /// the lease says no. A quit hands the lease back in its reply, for a
    /// relaunch to pass on.
    func reply(to data: Data) async -> Answer {
        let message: ControlMessage
        do throws(ControlProtocolError) {
            message = try ControlMessage.decode(data)
        } catch {
            return Answer(reply: .refused(error.message))
        }
        var granted: ControlLease.Term?
        if message.request.isLeased {
            let time = now()
            switch lease.use(by: message.holder, at: time).answer {
            case .success(let term): granted = term
            case .failure(let refusal): return Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone)))
            }
        }
        let json = message.json
        do throws(ActionError) {
            switch message.request {
            case .appStatus, .appOpen:
                let status = snapshot().status
                return done(json ? status.json : status.text)
            case .state:
                return done(snapshot().json)
            case .appQuit:
                return Answer(reply: ControlReply(ok: true, output: json ? "{\"quit\":true}\n" : "quit\n", lease: granted), quits: true)
            case .playerOpen(let path):
                struct Opened: Encodable {
                    @Nulled var video: StateSnapshot.Video?
                }
                let video = try await model.open(URL(fileURLWithPath: path))
                return done(json ? JSONText.line(Opened(video: snapshot().video)) : video.url.path + "\n")
            case .playerPlay:
                try model.play()
                return playhead(json)
            case .playerPause:
                try model.pause()
                return playhead(json)
            case .playerSeek(let seconds):
                try await model.seek(to: seconds)
                return playhead(json)
            case .screenshot(let path, let appearance):
                return await screenshot(to: path, appearance: appearance, json: json)
            case .controlTake, .controlRelease, .commentAdd, .commentEdit, .commentDelete, .batchSend, .threadAnswer,
                 .contextSet, .wait, .ack, .status, .reply, .ask:
                return Answer(reply: .refused("this build of video-review doesn't answer `\(message.request.command)` yet"))
            }
        } catch {
            return Answer(reply: .refused(error.message))
        }
    }

    /// What the window shows, with the lease as it is now.
    private func snapshot() -> StateSnapshot {
        model.snapshot(lease: lease.status(at: now()))
    }

    private func done(_ output: String) -> Answer {
        Answer(reply: .done(output))
    }

    /// What `player play`, `pause` and `seek` print: where the playhead is.
    private func playhead(_ json: Bool) -> Answer {
        struct Playhead: Encodable {
            var time: Double
            var playing: Bool
        }
        let player = model.player
        return done(json ? JSONText.line(Playhead(time: player.time, playing: player.playing)) : TimeText.precise(player.time) + "\n")
    }

    private func screenshot(to path: String, appearance: ControlRequest.Appearance?, json: Bool) async -> Answer {
        struct Shot: Encodable {
            var path: String
            var captured: Bool
        }
        let rendered: String?
        switch await screenshotter.capture(to: URL(fileURLWithPath: path), appearance: appearance) {
        case .captured: rendered = nil
        case .rendered(let why): rendered = why
        case .failed(let why): return Answer(reply: .refused(why))
        }
        return Answer(reply: .done(
            json ? JSONText.line(Shot(path: path, captured: rendered == nil)) : path + "\n",
            note: rendered.map { "the window was rendered, not captured: \($0)\n" } ?? ""
        ))
    }

    // MARK: - Listening

    /// Starts listening on the socket.
    func start() throws(SocketListener.Failure) {
        guard listener == nil else { return }
        listener = try SocketListener.open(at: socket) { [weak self] data in
            await self?.reply(to: data) ?? Answer(reply: .refused("video-review is quitting"))
        } quit: { [quit] in
            quit()
        }
    }

    /// Stops listening and removes the socket, so the `video-review`
    /// command finds the app gone.
    func stop() {
        listener?.close()
        listener = nil
    }
}
