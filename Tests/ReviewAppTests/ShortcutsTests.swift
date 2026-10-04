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

    @Test("Up and Down jump between markers, C and Return start a comment")
    func commentKeys() {
        #expect(Shortcuts.action(keyCode: 126, modifiers: []) == .marker(forward: false))
        #expect(Shortcuts.action(keyCode: 125, modifiers: []) == .marker(forward: true))
        #expect(Shortcuts.action(keyCode: 8, modifiers: []) == .startComment)
        #expect(Shortcuts.action(keyCode: 36, modifiers: []) == .startComment)
        // Cmd+Return is not the player's key.
        #expect(Shortcuts.action(keyCode: 36, modifiers: .command) == nil)
    }

    @Test("while the person types, no key reaches the player", arguments: [49, 40, 123, 124, 125, 126, 8, 36, 76] as [UInt16])
    func typing(keyCode: UInt16) {
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: []) != nil)
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: [], isTyping: true) == nil)
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: .shift, isTyping: true) == nil)
    }

    @Test("in the comment box Return commits, Shift+Return makes a new line, Escape cancels")
    func editorKeys() {
        let newline = #selector(NSResponder.insertNewline(_:))
        #expect(CommentEditor.keyAction(for: newline, shift: false) == .commit)
        #expect(CommentEditor.keyAction(for: newline, shift: true) == .newLine)
        #expect(CommentEditor.keyAction(for: #selector(NSResponder.cancelOperation(_:)), shift: false) == .cancel)
        // Every other command is the text view's own: typing, moving, deleting.
        #expect(CommentEditor.keyAction(for: #selector(NSResponder.deleteBackward(_:)), shift: false) == nil)
        #expect(CommentEditor.keyAction(for: #selector(NSResponder.moveLeft(_:)), shift: false) == nil)
    }

    @Test("a key with Command, Option or Control, or any other key, is left alone")
    func others() {
        #expect(Shortcuts.action(keyCode: 49, modifiers: .command) == nil)
        #expect(Shortcuts.action(keyCode: 124, modifiers: .option) == nil)
        #expect(Shortcuts.action(keyCode: 123, modifiers: [.control, .shift]) == nil)
        #expect(Shortcuts.action(keyCode: 0, modifiers: []) == nil)
    }
}
