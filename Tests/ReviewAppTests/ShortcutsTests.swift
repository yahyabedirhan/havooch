import AppKit
@testable import ReviewApp
import Testing

@Suite("The player's keys")
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

    @Test("J and L move 10 s, the comma and the period one frame")
    func quickTimeKeys() {
        #expect(Shortcuts.action(keyCode: 38, modifiers: []) == .skip(seconds: -10))
        #expect(Shortcuts.action(keyCode: 37, modifiers: []) == .skip(seconds: 10))
        #expect(Shortcuts.action(keyCode: 43, modifiers: []) == .step(frames: -1))
        #expect(Shortcuts.action(keyCode: 47, modifiers: []) == .step(frames: 1))
    }

    @Test("Up and Down jump between markers, C and Return start a comment")
    func commentKeys() {
        #expect(Shortcuts.action(keyCode: 126, modifiers: []) == .marker(forward: false))
        #expect(Shortcuts.action(keyCode: 125, modifiers: []) == .marker(forward: true))
        #expect(Shortcuts.action(keyCode: 8, modifiers: []) == .startMessage)
        #expect(Shortcuts.action(keyCode: 36, modifiers: []) == .startMessage)
    }

    /// Return and the keypad's Enter.
    @Test("Cmd+Return sends the queue, also while the person types; with any other modifier it's no key of the app",
          arguments: [36, 76] as [UInt16])
    func sendKey(keyCode: UInt16) {
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: .command) == .send)
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: .command, isTyping: true) == .send)
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: [.command, .numericPad, .capsLock], isTyping: true) == .send)
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: [.command, .shift]) == nil)
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: [.command, .option]) == nil)
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: .control, isTyping: true) == nil)
    }

    @Test("Return alone starts a comment, and Cmd with another key isn't a send")
    func returnAlone() {
        // Return alone still starts a comment, and is the text view's while typing.
        #expect(Shortcuts.action(keyCode: 36, modifiers: []) == .startMessage)
        #expect(Shortcuts.action(keyCode: 36, modifiers: [], isTyping: true) == nil)
        // Cmd with another key isn't a send.
        #expect(Shortcuts.action(keyCode: 49, modifiers: .command, isTyping: true) == nil)
    }

    @Test("while the person types, no key reaches the player", arguments: [49, 40, 38, 37, 43, 47, 123, 124, 125, 126, 8, 36, 76] as [UInt16])
    func typing(keyCode: UInt16) {
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: []) != nil)
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: [], isTyping: true) == nil)
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: .shift, isTyping: true) == nil)
    }

    @Test("in the comment box Return commits, Shift+Return makes a new line, Escape cancels, Tab and Shift+Tab move to the next and the previous control")
    func editorKeys() {
        let newline = #selector(NSResponder.insertNewline(_:))
        #expect(MessageEditor.keyAction(for: newline, shift: false) == .commit)
        #expect(MessageEditor.keyAction(for: newline, shift: true) == .newLine)
        #expect(MessageEditor.keyAction(for: #selector(NSResponder.cancelOperation(_:)), shift: false) == .cancel)
        #expect(MessageEditor.keyAction(for: #selector(NSResponder.insertTab(_:)), shift: false) == .nextControl)
        #expect(MessageEditor.keyAction(for: #selector(NSResponder.insertBacktab(_:)), shift: true) == .previousControl)
        // Every other command is the text view's own: typing, moving, deleting.
        #expect(MessageEditor.keyAction(for: #selector(NSResponder.deleteBackward(_:)), shift: false) == nil)
        #expect(MessageEditor.keyAction(for: #selector(NSResponder.moveLeft(_:)), shift: false) == nil)
    }

    @Test("a key with Command, Option or Control, or any other key, is left alone")
    func others() {
        #expect(Shortcuts.action(keyCode: 49, modifiers: .command) == nil)
        #expect(Shortcuts.action(keyCode: 124, modifiers: .option) == nil)
        #expect(Shortcuts.action(keyCode: 123, modifiers: [.control, .shift]) == nil)
        #expect(Shortcuts.action(keyCode: 0, modifiers: []) == nil)
    }
}
