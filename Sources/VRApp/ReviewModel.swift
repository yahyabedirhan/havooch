import Foundation
import Observation

/// Why the model won't do what was asked, as one line.
struct ModelRefusal: Error, Equatable {
    var reason: String

    init(_ reason: String) {
        self.reason = reason
    }
}

/// The orchestrator the views and the control desks call. A person and an
/// operator agent reach the same methods here, so nothing the window can do
/// skips the model, and every action has a command.
@MainActor
@Observable
final class ReviewModel {
    /// The open video, or nil before one is opened.
    private(set) var video: VideoFile?
    /// The demo folder in a demo run (`app open --demo`), else nil.
    let demoFolder: URL?
    /// Why the last open a person asked for didn't work, for the window to
    /// show; nil once it's been read.
    var openFailure: String?

    @ObservationIgnored private let player: any Playing

    init(player: any Playing, demoFolder: URL? = nil) {
        self.player = player
        self.demoFolder = demoFolder
    }

    var time: Double { player.time }
    var isPlaying: Bool { player.isPlaying }
    /// The open video's length in seconds; 0 with none.
    var duration: Double { video?.info.duration ?? 0 }

    // MARK: - What a person and an operator can do

    /// Opens the video at `url`, paused at its start. A file the player
    /// can't play is refused with the reason, and the open video stays.
    func open(_ url: URL) async throws(ModelRefusal) {
        let file = try await VideoFile.read(url)
        do {
            try await player.load(url)
        } catch {
            throw ModelRefusal("couldn't open \(url.path): \(error.localizedDescription)")
        }
        video = file
    }

    /// Plays from where the player is; from the start when it's at the end.
    func play() async throws(ModelRefusal) {
        let video = try openVideo()
        if player.time >= video.info.duration - Self.endMargin {
            await player.seek(to: 0)
        }
        player.play()
    }

    func pause() throws(ModelRefusal) {
        _ = try openVideo()
        player.pause()
    }

    /// Moves the player to `seconds`, exactly. A time outside the video is
    /// refused.
    func seek(to seconds: Double) async throws(ModelRefusal) {
        let video = try openVideo()
        guard (0...video.info.duration).contains(seconds) else {
            throw ModelRefusal(
                "\(TimeText.exact(seconds)) is outside the video (\(TimeText.exact(0)) to \(TimeText.exact(video.info.duration)))"
            )
        }
        await player.seek(to: seconds)
    }

    /// How close to the end counts as at the end, in seconds.
    private static let endMargin = 0.05

    private func openVideo() throws(ModelRefusal) -> VideoFile {
        guard let video else {
            throw ModelRefusal("no video is open; `video-review player open <path>`")
        }
        return video
    }

    // MARK: - A person's gestures

    // The window's buttons, keys and drags: the calls above, with a time
    // kept inside the video rather than refused, and nothing to answer.

    /// Opens `url`; a refusal lands in `openFailure` for the window to show.
    func openByPerson(_ url: URL) {
        Task {
            do throws(ModelRefusal) {
                try await open(url)
            } catch {
                openFailure = error.reason
            }
        }
    }

    func togglePlay() {
        if player.isPlaying {
            try? pause()
        } else {
            Task { try? await play() }
        }
    }

    /// Moves to `seconds`, kept inside the video.
    func scrub(to seconds: Double) {
        guard video != nil else { return }
        let target = min(max(0, seconds), duration)
        Task { try? await seek(to: target) }
    }

    func skip(by seconds: Double) {
        scrub(to: player.time + seconds)
    }

    /// Pauses and moves by whole frames of the open video.
    func step(frames: Int) {
        guard let video, video.frameRate > 0 else { return }
        try? pause()
        scrub(to: player.time + Double(frames) / video.frameRate)
    }
}
