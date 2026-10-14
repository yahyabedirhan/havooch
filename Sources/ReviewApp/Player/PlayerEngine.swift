import AVFoundation
import Observation

@Observable
final class PlayerEngine {
    let player = AVPlayer()
    private(set) var time: Double = 0
    private(set) var isPlaying = false
    private(set) var duration: Double = 0
    private(set) var videoSize = CGSize.zero
    private(set) var frameDuration: Double = 1.0 / 30
    var speed: Double = 1 {
        didSet {
            player.defaultRate = Float(speed)
            if isPlaying { player.rate = Float(speed) }
        }
    }

    static let speeds: [Double] = [0.5, 1, 1.25, 1.5, 2]
    @ObservationIgnored private(set) var asset: AVURLAsset?

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var rateObserver: (any NSObjectProtocol)?
    @ObservationIgnored var ticked: (() -> Void)?

    private static let readyWait = Duration.seconds(10)

    init(sound: Sound? = nil) {
        sound?.attach(self)
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.moved(to: time)
                self?.ticked?()
            }
        }
        rateObserver = NotificationCenter.default.addObserver(
            forName: AVPlayer.rateDidChangeNotification, object: player, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rateChanged() }
        }
    }

    func load(_ url: URL) async throws(AppRefusal) {
        let asset = AVURLAsset(url: url)
        let track = try await Self.videoTrack(of: asset, at: url)
        let length: CMTime
        let frameRate: Float
        let shown: CGSize
        do {
            (length, frameRate) = (try await track.load(.timeRange).duration, try await track.load(.nominalFrameRate))
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

    static func checkPlayable(_ url: URL) async throws(AppRefusal) {
        _ = try await videoTrack(of: AVURLAsset(url: url), at: url)
    }

    private static func videoTrack(of asset: AVURLAsset, at url: URL) async throws(AppRefusal) -> AVAssetTrack {
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
        return track
    }

    func close() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        asset = nil
        duration = 0
        videoSize = .zero
        time = 0
    }

    nonisolated static func frameDuration(nominalRate rate: Double) -> Double {
        guard rate.isFinite, rate > 0 else { return 1.0 / 30 }
        let whole = rate.rounded()
        if abs(rate - whole) < 0.001 { return 1 / whole }
        let ntsc = (rate * 1001 / 1000).rounded()
        if abs(rate - ntsc * 1000 / 1001) < 0.001 { return 1001 / (ntsc * 1000) }
        return 1 / rate
    }

    func play() {
        if time >= duration - frameDuration / 2 {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
    }

    func play(from seconds: Double, atHostTime hostTime: CMTime) {
        guard player.currentItem?.status == .readyToPlay else { return }
        player.automaticallyWaitsToMinimizeStalling = false
        guard seconds < duration - frameDuration / 2 else {
            player.seek(to: Self.exact(duration), toleranceBefore: .zero, toleranceAfter: .zero)
            return
        }
        player.setRate(Float(speed), time: Self.exact(max(seconds, 0)), atHostTime: hostTime)
    }

    func retire() {
        close()
        ticked = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let rateObserver { NotificationCenter.default.removeObserver(rateObserver) }
        timeObserver = nil
        rateObserver = nil
    }

    func pause() {
        player.pause()
        moved(to: player.currentTime())
    }

    func seek(to seconds: Double) async {
        let target = Self.exact(seconds)
        if await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) {
            moved(to: player.currentTime())
        }
    }

    nonisolated static let timescale: CMTimeScale = 60_000

    nonisolated static func exact(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: timescale)
    }

    func frameTime(of seconds: Double) -> Double {
        Self.frameTime(of: seconds, frameDuration: frameDuration, duration: duration)
    }

    nonisolated static func frameTime(of seconds: Double, frameDuration: Double, duration: Double) -> Double {
        guard frameDuration > 0 else { return 0 }
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
