import AVFoundation
import Observation
import ReviewWire

/// Two players on one clock (E11, P8): the left and the right version of
/// a comparison. They start together with `setRate(_:time:atHostTime:)` on
/// one host time, pause together, seek together and run at one speed.
/// The lead is the side the window's player bar shows; on each of its
/// periodic ticks the other side's drift is corrected. A side shorter
/// than the lead stops at its own end.
@Observable
final class PlayerPair {
    private(set) var left: PlayerEngine
    private(set) var right: PlayerEngine
    /// The side the other follows: the window's active side.
    var lead: CompareSide

    /// How far the following side may drift before it is put back in
    /// step, in seconds: about one frame at 30 frames a second.
    nonisolated static let driftTolerance = 0.04
    /// How far ahead of now a start is scheduled, so both players have it
    /// before it comes, in seconds.
    nonisolated static let startAhead = 0.1
    /// The least time between two corrections, in seconds: a correction
    /// that follows another at once would only stutter.
    nonisolated static let correctionGap = 0.5

    /// When the last correction was made.
    @ObservationIgnored private var lastCorrection = ContinuousClock.now - .seconds(1)

    init(left: PlayerEngine, right: PlayerEngine, lead: CompareSide) {
        self.left = left
        self.right = right
        self.lead = lead
        listen()
    }

    /// The player of `side`.
    func engine(_ side: CompareSide) -> PlayerEngine {
        side == .left ? left : right
    }

    /// The side `engine` plays; nil for a player not in the pair.
    func side(of engine: PlayerEngine) -> CompareSide? {
        if engine === left { return .left }
        if engine === right { return .right }
        return nil
    }

    /// Whether either side plays.
    var isPlaying: Bool { left.isPlaying || right.isPlaying }

    /// The two players exchange sides; the lead stays on its player.
    func swap() {
        (left, right) = (right, left)
        lead = lead.other
    }

    /// `side` plays `engine` from now on; the player it had is returned,
    /// not retired.
    @discardableResult
    func replace(_ side: CompareSide, with engine: PlayerEngine) -> PlayerEngine {
        let old = self.engine(side)
        old.ticked = nil
        if side == .left { left = engine } else { right = engine }
        listen()
        return old
    }

    /// Both play from the lead's time, together; from the start when the
    /// lead is at its end.
    func play() {
        let lead = engine(self.lead)
        let start = lead.time >= lead.duration - lead.frameDuration / 2 ? 0 : lead.time
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock()) + CMTime(seconds: Self.startAhead, preferredTimescale: 1_000_000_000)
        for engine in [left, right] {
            engine.play(from: min(start, engine.duration), atHostTime: hostTime)
        }
        lastCorrection = .now
    }

    /// Both pause; the other side is then put on the lead's time.
    func pause() {
        left.pause()
        right.pause()
        let time = engine(lead).time
        let follower = engine(lead.other)
        // At once, so a play that follows starts after it, not under it.
        follower.player.seek(
            to: PlayerEngine.exact(min(time, follower.duration)), toleranceBefore: .zero, toleranceAfter: .zero
        )
    }

    /// Both move to `seconds`, each inside its own length, and the call
    /// returns once both are there.
    func seek(to seconds: Double) async {
        let (left, right) = (self.left, self.right)
        async let leftDone: Void = left.seek(to: min(seconds, left.duration))
        async let rightDone: Void = right.seek(to: min(seconds, right.duration))
        _ = await (leftDone, rightDone)
    }

    /// Both run at `speed`.
    func setSpeed(_ speed: Double) {
        left.speed = speed
        right.speed = speed
    }

    /// The pair ends: the players stop following each other, and wait to
    /// minimize stalling again, as a lone player does.
    func end() {
        for engine in [left, right] {
            engine.ticked = nil
            engine.player.automaticallyWaitsToMinimizeStalling = true
        }
    }

    /// Each side's ticks reach `tick`; only the lead's correct.
    private func listen() {
        for side in CompareSide.allCases {
            engine(side).ticked = { [weak self] in self?.tick(from: side) }
        }
    }

    /// A periodic tick of `side`'s time: when it is the lead's, the other
    /// side follows it. It stops when the lead stopped, and is put back in
    /// step when it drifted, or stopped while the lead plays on inside
    /// its length.
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
        // Where the lead will be a moment from now, by its own rate.
        let ahead = CMTime(seconds: Self.startAhead, preferredTimescale: 1_000_000_000)
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock()) + ahead
        let leadThen = lead.player.currentTime().seconds + Self.startAhead * Double(lead.player.rate)
        follower.play(from: leadThen, atHostTime: hostTime)
    }
}
