import AppKit
import Testing
@testable import VRApp

@Suite struct ShortcutsTests {
    /// The text `NSEvent` gives for a key that types no letter.
    private static func key(_ code: Int) -> String {
        String(UnicodeScalar(UInt32(code))!)
    }

    static let playerKeys: [(String, PlayerAction)] = [
        (" ", .togglePlayback), ("k", .togglePlayback),
        (key(NSLeftArrowFunctionKey), .skip(seconds: -5)), (key(NSRightArrowFunctionKey), .skip(seconds: 5)),
        ("j", .skip(seconds: -10)), ("l", .skip(seconds: 10)),
        (",", .step(frames: -1)), (".", .step(frames: 1)),
        ("c", .comment), ("C", .comment), (key(NSCarriageReturnCharacter), .comment), (key(NSEnterCharacter), .comment),
        (key(NSDeleteCharacter), .deleteSelection), (key(NSDeleteFunctionKey), .deleteSelection),
    ]

    @Test func eachPlayerKeyDoesItsAction() {
        for (characters, action) in Self.playerKeys {
            #expect(Shortcuts.action(characters: characters, modifiers: [], typing: false) == action)
        }
    }

    @Test func typingInATextFieldNeverTriggersAPlayerKey() {
        for (characters, _) in Self.playerKeys {
            #expect(Shortcuts.action(characters: characters, modifiers: [], typing: true) == nil)
            #expect(Shortcuts.action(characters: characters, modifiers: .shift, typing: true) == nil)
        }
    }

    @Test func aKeyWithCommandControlOrOptionIsNotAPlayerKey() {
        for modifiers: NSEvent.ModifierFlags in [.command, .control, .option, [.command, .shift]] {
            for (characters, _) in Self.playerKeys {
                #expect(Shortcuts.action(characters: characters, modifiers: modifiers, typing: false) == nil)
            }
        }
    }

    @Test func theArrowKeysOwnFlagsDoNotStopThem() {
        let arrow = Self.key(NSRightArrowFunctionKey)
        #expect(Shortcuts.action(characters: arrow, modifiers: [.numericPad, .function], typing: false) == .skip(seconds: 5))
    }

    @Test func anyOtherKeyIsLeftAlone() {
        for characters in ["a", "x", "1", "", "cc", Self.key(NSUpArrowFunctionKey), Self.key(NSTabCharacter), "\u{1B}"] {
            #expect(Shortcuts.action(characters: characters, modifiers: [], typing: false) == nil)
        }
    }

    @Test func onlyMovingRepeatsWhileItsKeyIsHeld() {
        #expect(PlayerAction.skip(seconds: 5).repeats)
        #expect(PlayerAction.step(frames: 1).repeats)
        #expect(!PlayerAction.comment.repeats)
        #expect(!PlayerAction.togglePlayback.repeats)
        #expect(!PlayerAction.deleteSelection.repeats)
    }
}
