import AVFoundation
import Foundation
import Observation

/// What the model asks of a player: AVPlayer in the app, a fake in tests.
@MainActor
protocol Playing: AnyObject {
    /// Where the player is, in seconds.
    var time: Double { get }
    var isPlaying: Bool { get }
    /// Replaces what's loaded with the video at `url`, paused at its start.
    /// When it can't, what was loaded stays.
    func load(_ url: URL) async throws
    func play()
    func pause()
    /// Moves to `seconds` exactly, returning once the player is there.
    func seek(to seconds: Double) async
}

/// Why the player couldn't load a video.
struct PlayerFailure: LocalizedError {
    var errorDescription: String?
}

/// The app's player: one `AVPlayer`, its time and whether it plays kept as
/// observed values for the views.
@MainActor
@Observable
final class PlayerController: Playing {
    /// The player the stage's `PlayerSurface` shows.
    @ObservationIgnored let player = AVPlayer()
    private(set) var time = 0.0
    private(set) var isPlaying = false
    @ObservationIgnored private var observer: Any?

    /// How long a video gets to become ready to play.
    private static let readyTimeout = Duration.seconds(10)

    init() {
        player.actionAtItemEnd = .pause
        // Called 30 times a second while playing, and whenever the time
        // jumps or playback starts or stops, so both values follow the player.
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.time = max(0, time.seconds)
                self.isPlaying = self.player.rate != 0
            }
        }
    }

    func load(_ url: URL) async throws {
        let previous = player.currentItem
        let item = AVPlayerItem(url: url)
        player.pause()
        player.replaceCurrentItem(with: item)
        let deadline = ContinuousClock.now + Self.readyTimeout
        while item.status == .unknown, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard item.status == .readyToPlay else {
            player.replaceCurrentItem(with: previous)
            throw item.error ?? PlayerFailure(errorDescription: "the video didn't become ready to play")
        }
        time = 0
        isPlaying = false
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
        // Where the player stopped, not the last tick before it did.
        time = max(0, player.currentTime().seconds)
    }

    func seek(to seconds: Double) async {
        let target = CMTime(seconds: seconds, preferredTimescale: 60_000)
        await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        time = max(0, player.currentTime().seconds)
    }
}
