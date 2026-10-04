import AppKit

/// What a player key asks for.
enum PlayerAction: Equatable {
    case togglePlayback
    /// Move by this many seconds.
    case skip(seconds: Double)
    /// Pause and move by this many frames.
    case step(frames: Int)
    /// Open the comment box at the playhead.
    case comment
    /// Delete the comment in focus, when it is still queued.
    case deleteSelection

    /// Whether holding the key down does it again and again.
    var repeats: Bool {
        switch self {
        case .skip, .step: true
        case .togglePlayback, .comment, .deleteSelection: false
        }
    }
}

/// The player's keys. They act only while no text field has the focus, and
/// none is a menu shortcut, so typing a comment can never play, seek or
/// delete.
enum Shortcuts {
    /// What the key that types `characters` (as `NSEvent` names it, without
    /// its modifiers) does to the player; nil when it isn't a player key,
    /// when Command, Control or Option is down, or while the person is
    /// `typing` in a text field.
    static func action(characters: String, modifiers: NSEvent.ModifierFlags, typing: Bool) -> PlayerAction? {
        guard !typing, modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        guard characters.unicodeScalars.count == 1, let key = characters.lowercased().unicodeScalars.first else { return nil }
        switch Int(key.value) {
        case NSLeftArrowFunctionKey: return .skip(seconds: -5)
        case NSRightArrowFunctionKey: return .skip(seconds: 5)
        case NSDeleteFunctionKey, NSDeleteCharacter, NSBackspaceCharacter: return .deleteSelection
        case NSCarriageReturnCharacter, NSEnterCharacter: return .comment
        default: break
        }
        switch Character(key) {
        case " ", "k": return .togglePlayback
        case "j": return .skip(seconds: -10)
        case "l": return .skip(seconds: 10)
        case ",": return .step(frames: -1)
        case ".": return .step(frames: 1)
        case "c": return .comment
        default: return nil
        }
    }
}

/// Hands the app's key presses to the player: a key that is a player key,
/// pressed in the app's window while no text field has the focus, does its
/// action and goes no further. Every other key travels on as it would.
@MainActor
final class ShortcutMonitor {
    private let model: AppModel
    private var monitor: Any?
    /// The Escape key's code.
    private static let escape: UInt16 = 53

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // AppKit calls a local monitor on the main thread.
            MainActor.assumeIsolated { self?.handle(event) == true } ? nil : event
        }
    }

    /// Whether `event` was a player key, and was done.
    private func handle(_ event: NSEvent) -> Bool {
        // Escape gives up the rectangle being drawn on the frame, before
        // anything else hears it: the comment box may be open under it.
        if event.keyCode == Self.escape, event.window === model.window, model.cancelRegion() { return true }
        // With the comment box open, every key is the box's: also in the
        // moment before the box has taken the focus.
        guard let window = model.window, event.window === window, window.attachedSheet == nil,
              model.player.video != nil, model.desk.draft == nil,
              let characters = event.charactersIgnoringModifiers,
              let action = Shortcuts.action(
                  characters: characters, modifiers: event.modifierFlags, typing: window.firstResponder is NSText
              )
        else { return false }
        // A held key moves on and on; it doesn't toggle, open or delete again.
        if event.isARepeat, !action.repeats { return true }
        model.perform(action)
        return true
    }
}
