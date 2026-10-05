import AVFoundation
import Observation

/// The player: one `AVPlayer`, its time, and whether it plays. Opening a
/// file waits until it's ready, and a seek is exact and returns once it has
/// finished, so what `state` reports is what was asked for.
@Observable
final class PlayerEngine {
    let player = AVPlayer()
    /// The current time in seconds.
    private(set) var time: Double = 0
    private(set) var isPlaying = false
    /// The open video's length in seconds; 0 with no video.
    private(set) var duration: Double = 0
    /// The size of the open video's picture as it's shown; zero with no
    /// video.
    private(set) var videoSize = CGSize.zero
    /// One frame's length in seconds.
    private(set) var frameDuration: Double = 1.0 / 30
    /// The speed playback runs at, one of `speeds`.
    var speed: Double = 1 {
        didSet {
            player.defaultRate = Float(speed)
            if isPlaying { player.rate = Float(speed) }
        }
    }

    /// The speeds the player bar offers.
    static let speeds: [Double] = [0.5, 1, 1.25, 1.5, 2]
    /// The open video, for reading its frames; nil with no video.
    @ObservationIgnored private(set) var asset: AVURLAsset?

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var rateObserver: (any NSObjectProtocol)?

    /// How long a file gets to become ready to play.
    private static let readyWait = Duration.seconds(10)

    init() {
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.moved(to: time) }
        }
        rateObserver = NotificationCenter.default.addObserver(
            forName: AVPlayer.rateDidChangeNotification, object: player, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rateChanged() }
        }
    }

    /// Opens the file at `url`, paused at its start. A file that doesn't
    /// play is refused with the reason, and the video that was open stays.
    func load(_ url: URL) async throws(AppRefusal) {
        let asset = AVURLAsset(url: url)
        let playable: Bool
        let track: AVAssetTrack?
        do {
            playable = try await asset.load(.isPlayable)
            track = try await asset.loadTracks(withMediaType: .video).first
        } catch {
            throw AppRefusal("can't play \(url.path): \(error.localizedDescription)")
        }
        guard playable, let track else {
            throw AppRefusal("can't play \(url.path): it has no video this Mac can play")
        }
        let length: CMTime
        let frameRate: Float
        let shown: CGSize
        do {
            // The video track's own length: a sound track may run a few
            // milliseconds past the last frame.
            (length, frameRate) = (try await track.load(.timeRange).duration, try await track.load(.nominalFrameRate))
            // The picture as it's shown: a rotated video's sides are swapped.
            let box = CGRect(origin: .zero, size: try await track.load(.naturalSize))
                .applying(try await track.load(.preferredTransform))
            shown = CGSize(width: abs(box.width), height: abs(box.height))
        } catch {
            throw AppRefusal("can't play \(url.path): \(error.localizedDescription)")
        }
        guard length.seconds.isFinite, length.seconds > 0 else {
            throw AppRefusal("can't play \(url.path): its video has no length")
        }

        let previous = player.currentItem
        let item = AVPlayerItem(asset: asset)
        player.pause()
        player.replaceCurrentItem(with: item)
        let deadline = ContinuousClock.now + Self.readyWait
        while item.status == .unknown, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard item.status == .readyToPlay else {
            let why = item.error?.localizedDescription ?? "it wasn't ready within 10 seconds"
            player.replaceCurrentItem(with: previous)
            throw AppRefusal("can't play \(url.path): \(why)")
        }
        self.asset = asset
        duration = length.seconds
        videoSize = shown
        frameDuration = Self.frameDuration(nominalRate: Double(frameRate))
        time = 0
    }

    /// One frame's length from the track's nominal rate, which comes as a
    /// `Float` a hair off the real rate (29.999998 for 30). A rate that
    /// close to a whole one, or to an NTSC one (n × 1000 / 1001), is that
    /// rate, so a thread's frame time names the frame and not the one
    /// before it.
    nonisolated static func frameDuration(nominalRate rate: Double) -> Double {
        guard rate.isFinite, rate > 0 else { return 1.0 / 30 }
        let whole = rate.rounded()
        if abs(rate - whole) < 0.001 { return 1 / whole }
        let ntsc = (rate * 1001 / 1000).rounded()
        if abs(rate - ntsc * 1000 / 1001) < 0.001 { return 1001 / (ntsc * 1000) }
        return 1 / rate
    }

    /// Plays; from the start when the video is at its end.
    func play() {
        if time >= duration - frameDuration / 2 {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
    }

    func pause() {
        player.pause()
        // Where it stopped, not where the last tick saw it.
        moved(to: player.currentTime())
    }

    /// Moves to exactly `seconds`, still playing or still paused, and
    /// returns once the player is there.
    func seek(to seconds: Double) async {
        let target = Self.exact(seconds)
        // False when a newer seek took over: the time is then that seek's.
        if await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) {
            moved(to: player.currentTime())
        }
    }

    /// Fine enough to hold a millisecond exactly.
    nonisolated static let timescale: CMTimeScale = 60_000

    /// `seconds` as the time the player and the frame reader are asked
    /// for: both take a thread's time, which is in milliseconds, and a
    /// coarser time could name the frame before the thread's.
    nonisolated static func exact(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: timescale)
    }

    /// The frame time of the moment `seconds`: a thread's key.
    func frameTime(of seconds: Double) -> Double {
        Self.frameTime(of: seconds, frameDuration: frameDuration, duration: duration)
    }

    /// The start of the frame shown at `seconds`, from the nominal frame
    /// rate, raised to the next millisecond. Two moments inside one frame
    /// give one time, and the time names that frame, not the one before:
    /// a frame rarely starts on a whole millisecond (7.2333… s at 30 frames
    /// a second). The video's end is past its last frame, which it names.
    nonisolated static func frameTime(of seconds: Double, frameDuration: Double, duration: Double) -> Double {
        guard frameDuration > 0 else { return 0 }
        // The player's own noise, far below a frame or a millisecond, is no move.
        let last = max(((duration - frameDuration / 2) / frameDuration).rounded(.down), 0)
        let frame = min((max(seconds, 0) / frameDuration + 1e-6).rounded(.down), last)
        let milliseconds = (frame * frameDuration * 1000 - 1e-6).rounded(.up)
        return max(milliseconds, 0) / 1000
    }

    private func moved(to time: CMTime) {
        guard time.seconds.isFinite else { return }
        self.time = min(max(time.seconds, 0), duration)
    }

    private func rateChanged() {
        isPlaying = player.rate != 0
    }
}
