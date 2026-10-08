import Foundation
@testable import ReviewApp
import ReviewStore
import ReviewWire
import Testing

/// The sound: one level for the whole app, 0 to 1, where 0 is
/// muted; mute and unmute go between 0 and the last level; the level stays
/// across launches in `settings.json`; and a run started with
/// `HAVOOCH_MUTED=1` plays no sound and keeps the person's level as it was.
@Suite("The sound")
struct SoundTests {
    let support = FileManager.default.temporaryDirectory
        .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)

    private func cleanUp() {
        try? FileManager.default.removeItem(at: support)
    }

    /// A launch of the app on the test's folder, muted for an agent check
    /// when `muted`.
    private func launch(muted: Bool = false) -> AppModel {
        var environment = [SupportFolder.overrideVariable: support.path]
        if muted { environment[MutedRun.variable] = "1" }
        return AppModel(environment: environment, speech: SlowRecognizer())
    }

    @Test("a first launch plays at full volume, not muted")
    func firstLaunch() {
        defer { cleanUp() }
        let app = launch()
        #expect(app.sound.level == 1)
        #expect(!app.sound.isMuted)
        #expect(app.makeWindow().engine.player.volume == 1)
    }

    @Test("the level reaches every window's player, also windows made after it")
    func everyWindow() {
        defer { cleanUp() }
        let app = launch()
        let first = app.makeWindow()
        app.setVolume(0.4)
        let second = app.makeWindow()
        #expect(first.engine.player.volume == 0.4)
        #expect(second.engine.player.volume == 0.4)
        app.setVolume(1.7)
        #expect(app.sound.level == 1)
        app.setVolume(-1)
        #expect(app.sound.level == 0)
    }

    @Test("level 0 is muted; unmute brings back the last level, and mute toggles between 0 and it")
    func muteIsLevelZero() {
        defer { cleanUp() }
        let app = launch()
        let window = app.makeWindow()
        app.setVolume(0.4)
        app.setVolume(0)
        #expect(app.sound.isMuted)
        #expect(window.engine.player.volume == 0)
        app.unmute()
        #expect(app.sound.level == 0.4)
        #expect(window.engine.player.volume == 0.4)
        app.toggleMute()
        #expect(app.sound.isMuted)
        #expect(app.sound.level == 0)
        app.toggleMute()
        #expect(app.sound.level == 0.4)
        app.mute()
        app.mute()
        app.unmute()
        #expect(app.sound.level == 0.4)
        // Dragged up from 0: that level, and unmute later brings it back.
        app.setVolume(0)
        app.setVolume(0.25)
        app.mute()
        app.unmute()
        #expect(app.sound.level == 0.25)
    }

    @Test("the level and the mute stay across launches, in settings.json in the support folder")
    func keptAcrossLaunches() throws {
        defer { cleanUp() }
        launch().setVolume(0.3)
        let relaunched = launch()
        #expect(relaunched.sound.level == 0.3)
        #expect(relaunched.makeWindow().engine.player.volume == 0.3)
        relaunched.mute()
        let muted = launch()
        #expect(muted.sound.isMuted)
        muted.unmute()
        #expect(muted.sound.level == 0.3)
        let settings = try Settings.load(SupportLayout(root: support))
        #expect(settings.volume == 0.3)
    }

    @Test("a drag changes the level at once and keeps it when it ends")
    func dragKeepsAtTheEnd() {
        defer { cleanUp() }
        let app = launch()
        app.setVolume(0.6, keep: false)
        #expect(app.sound.level == 0.6)
        #expect(launch().sound.level == 1)
        app.setVolume(0.6)
        #expect(launch().sound.level == 0.6)
    }

    @Test("HAVOOCH_MUTED=1 plays no sound in any window, whatever the saved level, and leaves the saved level alone")
    func mutedForACheck() throws {
        defer { cleanUp() }
        launch().setVolume(0.8)
        let app = launch(muted: true)
        #expect(app.sound.isMutedForCheck)
        #expect(app.sound.isMuted)
        let first = app.makeWindow()
        let second = app.makeWindow()
        #expect(first.engine.player.volume == 0)
        #expect(second.engine.player.volume == 0)
        // An agent's command changes the run's level, and still nothing plays.
        app.setVolume(0.5)
        app.unmute()
        #expect(app.sound.level == 0.5)
        #expect(app.sound.isMuted)
        #expect(first.engine.player.volume == 0)
        // The person can't change it in that run.
        app.toggleMuteForPerson()
        #expect(app.sound.level == 0.5)
        // Nothing of the run is kept: the next launch has the person's level.
        app.keepSidebarWidth(420)
        let next = launch()
        #expect(next.sound.level == 0.8)
        #expect(!next.sound.isMuted)
        #expect(try Settings.load(SupportLayout(root: support)).sidebarWidth == 420)
    }

    @Test("only HAVOOCH_MUTED=1 mutes a run")
    func mutedVariable() {
        #expect(MutedRun.isMuted(environment: ["HAVOOCH_MUTED": "1"]))
        #expect(!MutedRun.isMuted(environment: ["HAVOOCH_MUTED": "0"]))
        #expect(!MutedRun.isMuted(environment: [:]))
    }

    @Test("M mutes and unmutes, and is no key while the person types")
    func muteKey() {
        #expect(Shortcuts.action(keyCode: 46, modifiers: []) == .toggleMute)
        #expect(Shortcuts.action(keyCode: 46, modifiers: .shift) == nil)
        #expect(Shortcuts.action(keyCode: 46, modifiers: [], isTyping: true) == nil)
    }

    @Test("the capsule's level is where the pointer is on it: the top 1, the middle 0.5, the bottom few points 0", arguments: [
        (0.0, 1.0), (60.0, 0.5), (36.0, 0.7), (120.0, 0.0), (119.0, 0.0), (-20.0, 1.0), (200.0, 0.0),
    ])
    func capsuleLevel(y: Double, level: Double) {
        #expect(abs(LevelCapsule.level(at: y, height: 120) - level) < 0.0001)
    }

    @Test("the speaker lights one, two or three waves by the level, and shows the slash while muted")
    func speaker() {
        #expect(SpeakerSymbol.band(0.1) == 0.2)
        #expect(SpeakerSymbol.band(0.5) == 0.5)
        #expect(SpeakerSymbol.band(0.9) == 1)
        #expect(SpeakerSymbol.name(isMuted: true) == "speaker.slash.fill")
        #expect(SpeakerSymbol.name(isMuted: false) == "speaker.wave.3.fill")
    }

    @Test("the speaker's tooltip says the level, muted, or why an agent check plays no sound")
    func help() {
        #expect(SoundWords.help(level: 0.7, isMuted: false, isMutedForCheck: false) == "Volume 70% (M)")
        #expect(SoundWords.help(level: 0, isMuted: true, isMutedForCheck: false) == "Muted (M)")
        #expect(SoundWords.help(level: 0.7, isMuted: true, isMutedForCheck: true)
            == "Muted for an agent check. This run started with HAVOOCH_MUTED=1, so it plays no sound.")
    }

    @Test("a click on the speaker opens the panel and a second closes it; Escape closes it first")
    func panel() {
        defer { cleanUp() }
        let window = launch().makeWindow()
        #expect(!window.isSoundPanelOpen)
        window.toggleSoundPanel()
        #expect(window.isSoundPanelOpen)
        window.toggleSoundPanel()
        #expect(!window.isSoundPanelOpen)
        window.toggleSoundPanel()
        #expect(window.escape())
        #expect(!window.isSoundPanelOpen)
        #expect(!window.escape())
    }
}
