import Testing
@testable import VRApp

@Suite struct PlayerKeyTests {
    @Test func thePlayersKeysAreTheOnesQuickTimeAndEditorsUse() {
        #expect(PlayerKey(characters: " ", keyCode: 49, hasCommandModifiers: false) == .togglePlay)
        #expect(PlayerKey(characters: "k", keyCode: 40, hasCommandModifiers: false) == .togglePlay)
        #expect(PlayerKey(characters: "K", keyCode: 40, hasCommandModifiers: false) == .togglePlay)
        #expect(PlayerKey(characters: "\u{F702}", keyCode: 123, hasCommandModifiers: false) == .back)
        #expect(PlayerKey(characters: "\u{F703}", keyCode: 124, hasCommandModifiers: false) == .forward)
        #expect(PlayerKey(characters: ",", keyCode: 43, hasCommandModifiers: false) == .previousFrame)
        #expect(PlayerKey(characters: ".", keyCode: 47, hasCommandModifiers: false) == .nextFrame)
    }

    @Test func otherKeysAndKeysHeldWithCommandAreNotThePlayers() {
        #expect(PlayerKey(characters: "a", keyCode: 0, hasCommandModifiers: false) == nil)
        #expect(PlayerKey(characters: nil, keyCode: 0, hasCommandModifiers: false) == nil)
        #expect(PlayerKey(characters: "k", keyCode: 40, hasCommandModifiers: true) == nil)
        #expect(PlayerKey(characters: ",", keyCode: 43, hasCommandModifiers: true) == nil)
    }
}

@Suite struct TimeTextTests {
    @Test func aTimeReadsToTheMillisecond() {
        #expect(TimeText.exact(0) == "0:00.000")
        #expect(TimeText.exact(10) == "0:10.000")
        #expect(TimeText.exact(62.5) == "1:02.500")
        #expect(TimeText.exact(21.2484) == "0:21.248")
        #expect(TimeText.exact(59.9996) == "1:00.000")
        #expect(TimeText.exact(3723.25) == "1:02:03.250")
    }

    @Test func theTransportBarShowsWholeSeconds() {
        #expect(TimeText.short(9.99) == "0:09")
        #expect(TimeText.short(75) == "1:15")
        #expect(TimeText.short(3600) == "1:00:00")
    }

    @Test func theTimelineFillsByHowFarAlongTheTimeIs() {
        #expect(Timeline.fraction(of: 5, in: 20) == 0.25)
        #expect(Timeline.fraction(of: 30, in: 20) == 1)
        #expect(Timeline.fraction(of: 5, in: 0) == 0)
    }
}
