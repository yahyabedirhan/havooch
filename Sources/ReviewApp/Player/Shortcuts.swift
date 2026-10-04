import AppKit

/// The player's keys, as in QuickTime: Space or K plays and pauses, Left and
/// Right move 5 seconds, Shift+Left and Shift+Right move one frame. They're
/// off while a text field has the focus, so typing never reaches the player.
@MainActor
enum Shortcuts {
    /// The seconds Left and Right move.
    static let skip: Double = 5

    /// What a key does to the player.
    enum Action: Equatable {
        case togglePlay
        case skip(seconds: Double)
        case step(frames: Int)
    }

    /// The action of the key `keyCode` with `modifiers`, if it has one.
    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Action? {
        guard modifiers.intersection([.command, .option, .control]).isEmpty else { return nil }
        let shift = modifiers.contains(.shift)
        switch keyCode {
        case 49, 40: return shift ? nil : .togglePlay // Space, K
        case 123: return shift ? .step(frames: -1) : .skip(seconds: -skip) // Left
        case 124: return shift ? .step(frames: 1) : .skip(seconds: skip) // Right
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
        guard model.video != nil, let window = event.window, window.isKeyWindow, window.attachedSheet == nil,
              !(window.firstResponder is NSText),
              let action = action(keyCode: event.keyCode, modifiers: event.modifierFlags)
        else { return false }
        switch action {
        case .togglePlay: model.togglePlay()
        case .skip(let seconds): model.skip(by: seconds)
        case .step(let frames): model.step(frames: frames)
        }
        return true
    }
}
