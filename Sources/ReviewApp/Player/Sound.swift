import AVFoundation
import Observation

/// The app's sound: one level for every window and both players of a
/// comparison, from 0 to 1, where 0 is muted. Mute and unmute go between 0
/// and the last level above it. The level is app state, kept in
/// `settings.json` by `AppModel`, never in `config.toml`.
///
/// A run muted for an agent's check (`HAVOOCH_MUTED=1`, `MutedRun`) plays
/// nothing, whatever the level: every player's volume is 0. An agent's
/// command may still change the run's level, which `state` reports, and
/// `kept` stays the level the person left, so nothing of the run is saved.
@Observable
final class Sound {
    /// The level, 0 to 1; 0 is muted.
    private(set) var level: Double
    /// The level unmute brings back: the last one above 0.
    private(set) var unmuteLevel: Double
    /// Whether the run started muted for an agent's check.
    let isMutedForCheck: Bool
    /// The person's level and unmute level as `settings.json` keeps them:
    /// this run's, unless it is muted for a check.
    private(set) var kept: (level: Double, unmuteLevel: Double)

    /// The players that play at the level, held weakly: a retired player
    /// drops out by itself.
    @ObservationIgnored private var players: [WeakPlayer] = []

    /// The sound at the level `settings.json` kept (full volume when it
    /// kept none), muted for a check when `mutedForCheck`.
    init(level: Double? = nil, unmuteLevel: Double? = nil, mutedForCheck: Bool = false) {
        let level = Self.clamped(level ?? 1)
        let kept = Self.clamped(unmuteLevel ?? 1)
        let unmute = level > 0 ? level : (kept > 0 ? kept : 1)
        self.level = level
        self.unmuteLevel = unmute
        isMutedForCheck = mutedForCheck
        self.kept = (level, unmute)
    }

    /// Whether nothing plays: level 0, or a run muted for a check.
    var isMuted: Bool { isMutedForCheck || level == 0 }

    /// The volume each player plays at.
    var volume: Float { isMuted ? 0 : Float(level) }

    /// The level, kept inside 0 to 1. Above 0 it is also the level unmute
    /// brings back.
    func set(_ level: Double) {
        self.level = Self.clamped(level)
        if self.level > 0 { unmuteLevel = self.level }
        changed()
    }

    /// Level 0; unmute brings back the level it had.
    func mute() {
        guard level > 0 else { return }
        unmuteLevel = level
        level = 0
        changed()
    }

    /// The last level above 0 again; nothing when it isn't muted.
    func unmute() {
        guard level == 0 else { return }
        level = unmuteLevel
        changed()
    }

    /// Mutes, or unmutes when muted.
    func toggleMute() {
        level == 0 ? unmute() : mute()
    }

    /// `engine` plays at the level from now on.
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
