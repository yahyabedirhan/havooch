import AVFoundation
import Observation
import ReviewWire

@Observable
final class PlayerPair {
    private(set) var left: PlayerEngine
    private(set) var right: PlayerEngine
    var lead: CompareSide {
        didSet { hearLead() }
    }

    nonisolated static let driftTolerance = 0.04
    nonisolated static let startAhead = 0.1
    nonisolated static let correctionGap = 0.5

    @ObservationIgnored private var lastCorrection = ContinuousClock.now - .seconds(1)

    init(left: PlayerEngine, right: PlayerEngine, lead: CompareSide) {
        self.left = left
        self.right = right
        self.lead = lead
        listen()
        hearLead()
    }

    func engine(_ side: CompareSide) -> PlayerEngine {
        side == .left ? left : right
    }

    func side(of engine: PlayerEngine) -> CompareSide? {
        if engine === left { return .left }
        if engine === right { return .right }
        return nil
    }

    var isPlaying: Bool { left.isPlaying || right.isPlaying }

    func swap() {
        (left, right) = (right, left)
        lead = lead.other
    }

    @discardableResult
    func replace(_ side: CompareSide, with engine: PlayerEngine) -> PlayerEngine {
        let old = self.engine(side)
        old.ticked = nil
        if side == .left { left = engine } else { right = engine }
        old.player.isMuted = false
        listen()
        hearLead()
        return old
    }

    func play() {
        let lead = engine(self.lead)
        let start = lead.time >= lead.duration - lead.frameDuration / 2 ? 0 : lead.time
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock()) + CMTime(seconds: Self.startAhead, preferredTimescale: 1_000_000_000)
        for engine in [left, right] {
            engine.play(from: min(start, engine.duration), atHostTime: hostTime)
        }
        lastCorrection = .now
    }

    func pause() {
        left.pause()
        right.pause()
        let time = engine(lead).time
        let follower = engine(lead.other)
        follower.player.seek(
            to: PlayerEngine.exact(min(time, follower.duration)), toleranceBefore: .zero, toleranceAfter: .zero
        )
    }

    func seek(to seconds: Double) async {
        let (left, right) = (self.left, self.right)
        async let leftDone: Void = left.seek(to: min(seconds, left.duration))
        async let rightDone: Void = right.seek(to: min(seconds, right.duration))
        _ = await (leftDone, rightDone)
    }

    func setSpeed(_ speed: Double) {
        left.speed = speed
        right.speed = speed
    }

    func end() {
        for engine in [left, right] {
            engine.ticked = nil
            engine.player.isMuted = false
            engine.player.automaticallyWaitsToMinimizeStalling = true
        }
    }

    private func hearLead() {
        engine(lead).player.isMuted = false
        engine(lead.other).player.isMuted = true
    }

    private func listen() {
        for side in CompareSide.allCases {
            engine(side).ticked = { [weak self] in self?.tick(from: side) }
        }
    }

    private func tick(from side: CompareSide) {
        guard side == lead else { return }
        let lead = engine(lead)
        let follower = engine(lead === left ? .right : .left)
        guard lead.isPlaying else {
            if follower.isPlaying { follower.pause() }
            return
        }
        guard ContinuousClock.now - lastCorrection >= .seconds(Self.correctionGap) else { return }
        let target = lead.time
        guard target < follower.duration - follower.frameDuration else { return }
        let drift = abs(follower.time - target)
        guard !follower.isPlaying || drift > Self.driftTolerance else { return }
        lastCorrection = .now
        let ahead = CMTime(seconds: Self.startAhead, preferredTimescale: 1_000_000_000)
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock()) + ahead
        let leadThen = lead.player.currentTime().seconds + Self.startAhead * Double(lead.player.rate)
        follower.play(from: leadThen, atHostTime: hostTime)
    }
}
