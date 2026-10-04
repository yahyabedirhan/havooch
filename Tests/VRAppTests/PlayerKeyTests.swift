import AppKit
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

    @Test func cOpensTheCommentBox() {
        #expect(PlayerKey(characters: "c", keyCode: 8, hasCommandModifiers: false) == .comment)
        #expect(PlayerKey(characters: "C", keyCode: 8, hasCommandModifiers: false) == .comment)
        // Command+C is the menu's Copy.
        #expect(PlayerKey(characters: "c", keyCode: 8, hasCommandModifiers: true) == nil)
    }
}

/// Every key the player has, as a press: characters and key code.
private let playerKeys: [(String, UInt16)] = [
    (" ", 49), ("k", 40), ("K", 40), ("c", 8), (",", 43), (".", 47), ("\u{F702}", 123), ("\u{F703}", 124),
]

@MainActor
@Suite struct KeyRoutingTests {
    @Test func typingInATextViewIsNeverThePlayers() {
        let typing = KeyFocus(inText: true)
        for (characters, keyCode) in playerKeys {
            #expect(PlayerKey.routed(characters: characters, keyCode: keyCode, hasCommandModifiers: false, focus: typing) == nil)
        }
    }

    @Test func keysInAPanelOrUnderASheetAreNotThePlayers() {
        for focus in [KeyFocus(inPanel: true), KeyFocus(underSheet: true)] {
            for (characters, keyCode) in playerKeys {
                #expect(PlayerKey.routed(characters: characters, keyCode: keyCode, hasCommandModifiers: false, focus: focus) == nil)
            }
        }
    }

    @Test func keysPressedOnThePlayerAreThePlayers() {
        let onPlayer = KeyFocus()
        #expect(PlayerKey.routed(characters: "k", keyCode: 40, hasCommandModifiers: false, focus: onPlayer) == .togglePlay)
        #expect(PlayerKey.routed(characters: "c", keyCode: 8, hasCommandModifiers: false, focus: onPlayer) == .comment)
        #expect(PlayerKey.routed(characters: " ", keyCode: 49, hasCommandModifiers: false, focus: onPlayer) == .togglePlay)
    }

    /// A window that is never shown: only its first responder is read.
    @Test func aWindowWhoseFirstResponderIsATextViewHasItsFocusInText() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
        content.addSubview(text)
        window.contentView = content

        #expect(KeyFocus(window: window) == KeyFocus())

        #expect(window.makeFirstResponder(text))
        #expect(KeyFocus(window: window) == KeyFocus(inText: true))
        #expect(PlayerKey.routed(characters: "k", keyCode: 40, hasCommandModifiers: false, focus: KeyFocus(window: window)) == nil)

        #expect(window.makeFirstResponder(nil))
        #expect(KeyFocus(window: window).isPlayers)
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
