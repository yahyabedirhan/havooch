import AVFoundation
import Observation

@Observable
final class Sound {
    private(set) var level: Double
    private(set) var unmuteLevel: Double
    let isMutedForCheck: Bool
    private(set) var kept: (level: Double, unmuteLevel: Double)

    @ObservationIgnored private var players: [WeakPlayer] = []

    init(level: Double? = nil, unmuteLevel: Double? = nil, mutedForCheck: Bool = false) {
        let level = Self.clamped(level ?? 1)
        let kept = Self.clamped(unmuteLevel ?? 1)
        let unmute = level > 0 ? level : (kept > 0 ? kept : 1)
        self.level = level
        self.unmuteLevel = unmute
        isMutedForCheck = mutedForCheck
        self.kept = (level, unmute)
    }

    var isMuted: Bool { isMutedForCheck || level == 0 }

    var volume: Float { isMuted ? 0 : Float(level) }

    func set(_ level: Double) {
        self.level = Self.clamped(level)
        if self.level > 0 { unmuteLevel = self.level }
        changed()
    }

    func mute() {
        guard level > 0 else { return }
        unmuteLevel = level
        level = 0
        changed()
    }

    func unmute() {
        guard level == 0 else { return }
        level = unmuteLevel
        changed()
    }

    func toggleMute() {
        level == 0 ? unmute() : mute()
    }

    func attach(_ engine: PlayerEngine) {
        players.removeAll { $0.engine == nil }
        players.append(WeakPlayer(engine: engine))
        engine.player.volume = volume
    }

    private func changed() {
        if !isMutedForCheck { kept = (level, unmuteLevel) }
        players.removeAll { $0.engine == nil }
        for player in players { player.engine?.player.volume = volume }
    }

    private static func clamped(_ level: Double) -> Double {
        level.isFinite ? min(max(level, 0), 1) : 1
    }

    private struct WeakPlayer {
        weak var engine: PlayerEngine?
    }
}
