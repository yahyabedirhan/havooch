import AppKit

/// The player's keys, as in QuickTime: Space or K plays and pauses, Left and
/// Right move 5 seconds, J and L 10 seconds, Shift+Left, Shift+Right, the
/// comma and the period move one frame, Up and
/// Down jump to the marker before and after, C or Return starts a message,
/// Escape drops a rectangle that's being drawn, else the popover, else goes
/// back from a thread view to the thread list. They're off while a text
/// view has the focus, so typing never reaches the player. Cmd+Return sends
/// the queue, also while the person types.
enum Shortcuts {
    /// The seconds Left and Right move.
    static let skip: Double = 5
    /// The seconds J and L move.
    static let longSkip: Double = 10

    /// What a key does to the player.
    enum Action: Equatable {
        case togglePlay
        case skip(seconds: Double)
        case step(frames: Int)
        /// To the marker after the player's time, or the one before it.
        case marker(forward: Bool)
        case startMessage
        /// Escape: drops the rectangle being drawn, or the popover
        /// when its text view lost the focus, or the thread view.
        case cancel
        /// Cmd+Return: sends the queue, with the words in the popover.
        case send
    }

    /// The action of the key `keyCode` with `modifiers`, if it has one.
    /// While the person types (`isTyping`: a text view has the focus) no
    /// key has one but Cmd+Return, which sends from anywhere: every other
    /// key is the text view's.
    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isTyping: Bool = false) -> Action? {
        let held = modifiers.intersection([.command, .option, .control, .shift])
        if held == .command, keyCode == 36 || keyCode == 76 { return .send } // Return, Enter
        guard !isTyping, held.isDisjoint(with: [.command, .option, .control]) else { return nil }
        let shift = modifiers.contains(.shift)
        switch keyCode {
        case 49, 40: return shift ? nil : .togglePlay // Space, K
        case 123: return shift ? .step(frames: -1) : .skip(seconds: -skip) // Left
        case 124: return shift ? .step(frames: 1) : .skip(seconds: skip) // Right
        case 38: return shift ? nil : .skip(seconds: -longSkip) // J
        case 37: return shift ? nil : .skip(seconds: longSkip) // L
        case 43: return shift ? nil : .step(frames: -1) // comma
        case 47: return shift ? nil : .step(frames: 1) // period
        case 126: return shift ? nil : .marker(forward: false) // Up
        case 125: return shift ? nil : .marker(forward: true) // Down
        case 8, 36, 76: return shift ? nil : .startMessage // C, Return, Enter
        case 53: return .cancel // Escape
        default: return nil
        }
    }

    /// Starts handling the player's keys for `model`, for as long as the
    /// app runs.
    static func install(for model: AppModel) {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated { handle(event, model) }
            return handled ? nil : event
        }
    }

    /// Whether `event` was a player key and was acted on.
    private static func handle(_ event: NSEvent, _ model: AppModel) -> Bool {
        // While the context popover is open every key is its own: Cmd+Return
        // there must not send the queue with a note that isn't saved yet.
        guard model.video != nil, !model.isContextShown,
              let window = event.window, window.isKeyWindow, window.attachedSheet == nil,
              let action = action(
                  keyCode: event.keyCode, modifiers: event.modifierFlags, isTyping: window.firstResponder is NSText
              )
        else { return false }
        switch action {
        case .togglePlay: model.togglePlay()
        case .skip(let seconds): model.skip(by: seconds)
        case .step(let frames): model.step(frames: frames)
        case .marker(let forward): model.jumpToMarker(forward: forward)
        case .startMessage: model.startDraft()
        // With nothing to cancel, Escape stays the window's.
        case .cancel: return model.escape()
        case .send: model.send()
        }
        return true
    }
}
