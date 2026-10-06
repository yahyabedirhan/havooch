import AppKit
@testable import ReviewApp
import ReviewWire
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

    /// Space, Return and the keypad's Enter.
    @Test("while a control has the keyboard focus, Space and Return press it; other keys stay the player's",
          arguments: [49, 36, 76] as [UInt16])
    func focusedControlKeys(keyCode: UInt16) {
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: [], isControlFocused: true) == .pressControl)
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: .numericPad, isControlFocused: true) == .pressControl)
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: .shift, isControlFocused: true) != .pressControl)
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: .command, isControlFocused: true) != .pressControl)
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: [], isTyping: true, isControlFocused: true) == nil)
        #expect(Shortcuts.action(keyCode: keyCode, modifiers: []) != .pressControl)
        #expect(Shortcuts.action(keyCode: 125, modifiers: [], isControlFocused: true) == .marker(forward: true))
        #expect(Shortcuts.action(keyCode: 40, modifiers: [], isControlFocused: true) == .togglePlay)
    }

    @Test("Space on a focused control presses it and doesn't play; with no control focused, Space plays and pauses")
    func spaceOnFocusedControl() {
        #expect(Shortcuts.action(keyCode: 49, modifiers: [], isControlFocused: true) == .pressControl)
        #expect(Shortcuts.action(keyCode: 49, modifiers: [], isControlFocused: false) == .togglePlay)
        #expect(Shortcuts.action(keyCode: 36, modifiers: [], isControlFocused: false) == .startMessage)
    }

    @Test("Space presses the control that has the keyboard focus: a notice card, a symbol button, a chip or a row")
    func pressFocusedControl() {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        var pressed: [String] = []
        let notice = UUID(), symbol = UUID()
        #expect(!model.isControlFocused)
        #expect(!model.pressFocusedControl())

        model.focusControl(notice) { pressed.append("notice") }
        #expect(model.isControlFocused)
        #expect(model.pressFocusedControl())
        #expect(pressed == ["notice"])

        // Tab gives the next control the focus before the last one hears
        // that it lost it: the late loss leaves the new control focused.
        model.focusControl(symbol) { pressed.append("symbol") }
        model.blurControl(notice)
        #expect(model.pressFocusedControl())
        #expect(pressed == ["notice", "symbol"])

        // The focus leaves for the video: Space is the player's again.
        model.blurControl(symbol)
        #expect(!model.isControlFocused)
        #expect(!model.pressFocusedControl())
        #expect(pressed == ["notice", "symbol"])
    }

    @Test("when a popover's control loses the focus, the control still focused in the player's window gets Space again")
    func blurRestoresEarlierControl() {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("havooch-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let model = AppModel(environment: [SupportFolder.overrideVariable: support.path])
        var pressed: [String] = []
        let row = UUID(), stop = UUID()

        model.focusControl(row) { pressed.append("row") }
        // The agent-control popover opens, and its Stop button takes the focus.
        model.focusControl(stop) { pressed.append("stop") }
        #expect(model.pressFocusedControl())
        #expect(pressed == ["stop"])

        // The popover closes: the row in the player's window has the focus again.
        model.blurControl(stop)
        #expect(model.isControlFocused)
        #expect(model.pressFocusedControl())
        #expect(pressed == ["stop", "row"])

        // A control that takes the focus again is the one Space presses.
        model.focusControl(stop) { pressed.append("stop") }
        model.focusControl(row) { pressed.append("row") }
        model.blurControl(row)
        #expect(model.pressFocusedControl())
        #expect(pressed == ["stop", "row", "stop"])

        model.blurControl(stop)
        #expect(!model.isControlFocused)
        #expect(!model.pressFocusedControl())
    }

    @Test("an AppKit control with the focus takes Space only while keyboard navigation is on; a SwiftUI control that reports the focus always does")
    func appKitControlFocus() {
        #expect(Shortcuts.isControlFocused(reported: false, firstResponderIsControl: true, keyboardNavigation: true))
        #expect(!Shortcuts.isControlFocused(reported: false, firstResponderIsControl: true, keyboardNavigation: false))
        #expect(Shortcuts.isControlFocused(reported: true, firstResponderIsControl: false, keyboardNavigation: false))
        #expect(Shortcuts.isControlFocused(reported: true, firstResponderIsControl: true, keyboardNavigation: false))
        #expect(!Shortcuts.isControlFocused(reported: false, firstResponderIsControl: false, keyboardNavigation: true))
        // With keyboard navigation off and nothing reported, Space plays and pauses.
        let focused = Shortcuts.isControlFocused(reported: false, firstResponderIsControl: true, keyboardNavigation: false)
        #expect(Shortcuts.action(keyCode: 49, modifiers: [], isControlFocused: focused) == .togglePlay)
    }

    @Test("a key with Command, Option or Control, or any other key, is left alone")
    func others() {
        #expect(Shortcuts.action(keyCode: 49, modifiers: .command) == nil)
        #expect(Shortcuts.action(keyCode: 124, modifiers: .option) == nil)
        #expect(Shortcuts.action(keyCode: 123, modifiers: [.control, .shift]) == nil)
        #expect(Shortcuts.action(keyCode: 0, modifiers: []) == nil)
    }
}
