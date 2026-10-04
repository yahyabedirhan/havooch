import AppKit
@testable import ReviewApp
import Testing

@Suite("The player's keys")
@MainActor
struct ShortcutsTests {
    @Test("Space and K play and pause, the arrows move 5 s, with Shift one frame")
    func keys() {
        #expect(Shortcuts.action(keyCode: 49, modifiers: []) == .togglePlay)
        #expect(Shortcuts.action(keyCode: 40, modifiers: []) == .togglePlay)
        #expect(Shortcuts.action(keyCode: 123, modifiers: []) == .skip(seconds: -5))
        #expect(Shortcuts.action(keyCode: 124, modifiers: []) == .skip(seconds: 5))
        #expect(Shortcuts.action(keyCode: 123, modifiers: .shift) == .step(frames: -1))
        #expect(Shortcuts.action(keyCode: 124, modifiers: .shift) == .step(frames: 1))
    }

    @Test("a key with Command, Option or Control, or any other key, is left alone")
    func others() {
        #expect(Shortcuts.action(keyCode: 49, modifiers: .command) == nil)
        #expect(Shortcuts.action(keyCode: 124, modifiers: .option) == nil)
        #expect(Shortcuts.action(keyCode: 123, modifiers: [.control, .shift]) == nil)
        #expect(Shortcuts.action(keyCode: 0, modifiers: []) == nil)
    }
}
