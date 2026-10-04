import AppKit
import Observation
import UniformTypeIdentifiers
import VRLease
import VRWire

/// Why an action is refused: its `message` is the one line a command
/// prints on standard error, and what the window shows a person.
enum ActionError: Error, Equatable {
    case noVideo
    case cannotOpen(path: String, why: String)
    case timeOutsideVideo(Double, duration: Double)

    var message: String {
        switch self {
        case .noVideo:
            "no video is open"
        case .cannotOpen(let path, let why):
            "can't open \(path): \(why)"
        case .timeOutsideVideo(let seconds, let duration):
            "\(TimeText.precise(seconds)) is outside the video, which ends at \(TimeText.precise(duration))"
        }
    }
}

/// The orchestrator: every action a person or an agent can take is one
/// method here, called by the views and by `ControlServer` alike, so the
/// window and the command line can't drift apart.
@MainActor @Observable
final class AppModel {
    let player = PlayerEngine()
    /// The folder this run keeps its data in, and whether it's a demo's.
    let support: URL
    let isDemo: Bool
    /// The last refusal of something the person did, shown until dismissed.
    var failure: String?
    /// The app's one window, for `Screenshotter`.
    @ObservationIgnored weak var window: NSWindow?

    init(environment: [String: String]) {
        support = SupportFolder.current(environment: environment)
        isDemo = SupportFolder.demo(environment: environment) != nil
    }

    // MARK: - Actions

    /// Opens `video`, replacing the one that was open.
    @discardableResult
    func open(_ video: URL) async throws(ActionError) -> OpenVideo {
        do {
            return try await player.open(video)
        } catch {
            throw .cannotOpen(path: video.path, why: error.why)
        }
    }

    func play() throws(ActionError) {
        guard player.video != nil else { throw .noVideo }
        player.play()
    }

    func pause() throws(ActionError) {
        guard player.video != nil else { throw .noVideo }
        player.pause()
    }

    /// Moves to `seconds` exactly; the time the player then stands at.
    @discardableResult
    func seek(to seconds: Double) async throws(ActionError) -> Double {
        guard let video = player.video else { throw .noVideo }
        guard seconds.isFinite, (0...video.duration).contains(seconds) else {
            throw .timeOutsideVideo(seconds, duration: video.duration)
        }
        return await player.seek(to: seconds)
    }

    /// The scrubber's drag: moves to `seconds`, kept inside the video,
    /// without waiting for the seek to land.
    func scrub(to seconds: Double) {
        player.scrub(to: seconds)
    }

    /// Sets the speed playback runs at.
    func setSpeed(_ speed: Double) {
        player.speed = speed
    }

    // MARK: - The person's ways into the actions

    /// Opens `video` for the person: a refusal is shown, not thrown.
    func openForPerson(_ video: URL) {
        Task {
            do throws(ActionError) {
                try await open(video)
            } catch {
                failure = error.message
            }
        }
    }

    /// Asks the person for a video, and opens it.
    func chooseVideo() {
        let panel = NSOpenPanel()
        // mp4, mov and m4v: the kinds the app opens.
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, UTType("com.apple.m4v-video") ?? .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a video to review"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openForPerson(url)
    }

    /// The play button, and a click on the frame.
    func togglePlayback() {
        if player.playing {
            try? pause()
        } else {
            try? play()
        }
    }

    // MARK: - State

    /// What the window shows now, for `state` and `app status`.
    func snapshot(lease: ControlLease.Status?) -> StateSnapshot {
        StateSnapshot(
            app: .init(version: Identity.version, variant: Identity.variant, demo: isDemo, support: support.path),
            video: player.video.map {
                .init(path: $0.url.path, contentHash: nil, title: $0.title, duration: $0.duration)
            },
            player: .init(time: player.time, playing: player.playing, rate: player.speed),
            lease: lease
        )
    }
}
