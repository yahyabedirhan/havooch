import AVFoundation
import Observation

/// The video that is open, as the player read it.
struct OpenVideo: Equatable, Sendable {
    var url: URL
    /// The file's name without its extension.
    var title: String
    /// The video track's length in seconds, to the millisecond: every time
    /// up to it has a frame, which an audio track that runs a little longer
    /// doesn't promise.
    var duration: Double
    /// The frame's size in pixels, as it is shown (the track's transform applied).
    var size: CGSize
    /// Frames per second; 30 when the track doesn't say.
    var frameRate: Double
}

/// One `AVPlayer`: open, play, pause, exact seek, and the time, the rate
/// and the duration the views and `state` read.
@MainActor @Observable
final class PlayerEngine {
    /// Why a video doesn't open, in words.
    struct OpenFailure: Error {
        var why: String
    }

    @ObservationIgnored let player = AVPlayer()
    private(set) var video: OpenVideo?
    /// The playhead in seconds, 0 up to the duration.
    private(set) var time: Double = 0
    private(set) var playing = false
    /// The speed playback runs at while it plays (`AppModel.setSpeed`).
    var speed: Double = 1 {
        didSet { if playing { player.rate = Float(speed) } }
    }

    static let speeds: [Double] = [0.5, 1, 1.25, 1.5, 2]

    /// How long a video gets to become ready to play.
    private static let readiness = Duration.seconds(10)
    /// Seeks and published times count in this many parts of a second.
    private static let timescale: CMTimeScale = 60_000

    init() {
        player.actionAtItemEnd = .pause
        // Fires 30 times a second while playing, and whenever the time
        // jumps or playback starts or stops.
        player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.readPlayer() }
        }
    }

    /// Opens the video at `url`, paused at its start. A file that isn't
    /// there, or that doesn't read as a video, is refused and the video
    /// that was open stays. One that reads but never becomes ready to play
    /// is refused too, and leaves no video open.
    func open(_ url: URL) async throws(OpenFailure) -> OpenVideo {
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw OpenFailure(why: "there's no readable file") }
        let asset = AVURLAsset(url: url)
        let opened: OpenVideo
        do {
            guard try await asset.load(.isPlayable) else { throw OpenFailure(why: "it isn't a video this Mac can play") }
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw OpenFailure(why: "it has no video track")
            }
            let (range, natural, transform, rate) = try await track.load(.timeRange, .naturalSize, .preferredTransform, .nominalFrameRate)
            let shown = CGRect(origin: .zero, size: natural).applying(transform)
            opened = OpenVideo(
                url: url,
                title: url.deletingPathExtension().lastPathComponent,
                duration: (range.duration.seconds * 1000).rounded() / 1000,
                size: CGSize(width: abs(shown.width), height: abs(shown.height)),
                frameRate: rate > 0 ? Double(rate) : 30
            )
        } catch let failure as OpenFailure {
            throw failure
        } catch {
            throw OpenFailure(why: error.localizedDescription)
        }
        guard opened.duration > 0 else { throw OpenFailure(why: "its video track is empty") }

        let item = AVPlayerItem(asset: asset)
        player.pause()
        player.replaceCurrentItem(with: item)
        // Ready before it's answered, so a seek or a screenshot right after
        // the open finds the frame there.
        let deadline = ContinuousClock.now + Self.readiness
        while item.status == .unknown, player.currentItem === item, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        // Two opens can overlap (the person's and an agent's): the later one wins.
        guard player.currentItem === item else { throw OpenFailure(why: "another video was opened meanwhile") }
        guard item.status == .readyToPlay else {
            let why = item.error?.localizedDescription ?? "it didn't become ready to play"
            player.replaceCurrentItem(with: nil)
            video = nil
            readPlayer()
            throw OpenFailure(why: why)
        }
        video = opened
        readPlayer()
        return opened
    }

    /// Plays at `speed`; from the start again when the video is at its end.
    func play() {
        guard let video else { return }
        if time >= video.duration - 0.5 / video.frameRate {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.rate = Float(speed)
        readPlayer()
    }

    func pause() {
        player.pause()
        readPlayer()
    }

    /// Moves to `seconds` exactly, and answers with the time once the seek
    /// has landed, so `state` right after reads that time.
    func seek(to seconds: Double) async -> Double {
        await player.seek(to: CMTime(seconds: seconds, preferredTimescale: Self.timescale), toleranceBefore: .zero, toleranceAfter: .zero)
        readPlayer()
        return time
    }

    /// Moves to `seconds` exactly without waiting for it: the scrubber's
    /// drag, where the next seek replaces this one.
    func scrub(to seconds: Double) {
        guard let video else { return }
        time = min(max(0, seconds), video.duration)
        player.seek(to: CMTime(seconds: time, preferredTimescale: Self.timescale), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Publishes the player's time and whether it plays.
    private func readPlayer() {
        guard let video else {
            time = 0
            playing = false
            return
        }
        let seconds = player.currentTime().seconds
        if seconds.isFinite {
            // To the millisecond, as `state` and the transport bar print it.
            let now = (min(max(0, seconds), video.duration) * 1000).rounded() / 1000
            if now != time { time = now }
        }
        let plays = player.rate != 0
        if plays != playing { playing = plays }
    }
}
