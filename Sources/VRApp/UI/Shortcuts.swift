import AppKit

/// What a key does to the player: the keys QuickTime and editors use.
enum PlayerKey: Equatable {
    case togglePlay
    case back, forward
    case previousFrame, nextFrame
    /// Pause and open the comment box.
    case comment
    /// Close the comment box, and drop its draft and its region.
    case cancel

    /// How far the arrow keys move, in seconds.
    static let skip = 5.0

    /// The key pressed, or nil when it isn't the player's: Space or K play
    /// and pause, ← and → move 5 s, `,` and `.` move one frame, C comments,
    /// Escape cancels the comment being written.
    /// A key held with Command, Control or Option belongs to the menu.
    init?(characters: String?, keyCode: UInt16, hasCommandModifiers: Bool) {
        guard !hasCommandModifiers else { return nil }
        switch (keyCode, characters?.lowercased()) {
        case (123, _): self = .back
        case (124, _): self = .forward
        case (53, _): self = .cancel
        case (_, " "), (_, "k"): self = .togglePlay
        case (_, ","): self = .previousFrame
        case (_, "."): self = .nextFrame
        case (_, "c"): self = .comment
        default: return nil
        }
    }

    /// The player's key for a press where the keyboard's focus is `focus`,
    /// or nil when the press isn't the player's to take: every key typed
    /// into a text view, a panel or a window under a sheet goes there.
    static func routed(characters: String?, keyCode: UInt16, hasCommandModifiers: Bool, focus: KeyFocus) -> PlayerKey? {
        guard focus.isPlayers else { return nil }
        return PlayerKey(characters: characters, keyCode: keyCode, hasCommandModifiers: hasCommandModifiers)
    }
}

/// Cmd+Enter: send the queue. It works from anywhere in the window, also
/// from inside the comment box, which a player's key never does.
enum SendKey {
    /// Whether a press is Cmd+Enter (Return, or the keypad's Enter) with no
    /// other modifier, in the window itself: not in a panel or under a sheet.
    static func matches(keyCode: UInt16, hasCommand: Bool, hasOtherModifiers: Bool, focus: KeyFocus) -> Bool {
        (keyCode == 36 || keyCode == 76) && hasCommand && !hasOtherModifiers && !focus.inPanel && !focus.underSheet
    }
}

/// Where the keyboard's focus is when a key is pressed.
struct KeyFocus: Equatable {
    /// In a panel: the open panel's file list uses Space and the arrows.
    var inPanel = false
    var underSheet = false
    /// In a text view, such as the comment box or a card being edited:
    /// typing "k" there must not pause the video.
    var inText = false

    /// Whether a key pressed with this focus is the player's.
    var isPlayers: Bool {
        !inPanel && !underSheet && !inText
    }
}

extension KeyFocus {
    /// The focus in `window`. A text field's typing happens in the window's
    /// field editor, a text view, as a text editor's does in its own.
    @MainActor
    init(window: NSWindow) {
        self.init(
            inPanel: window is NSPanel,
            underSheet: window.attachedSheet != nil,
            inText: window.firstResponder is NSText
        )
    }
}

/// The player's keys, watched for the whole app and given up while a text
/// view has the focus, and Cmd+Enter, which sends from anywhere.
@MainActor
final class Shortcuts {
    private let model: ReviewModel
    private var monitor: Any?

    init(model: ReviewModel) {
        self.model = model
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // The monitor runs on the main thread, where events are handled.
            let handled = MainActor.assumeIsolated {
                if let window = event.window, SendKey.matches(
                    keyCode: event.keyCode,
                    hasCommand: event.modifierFlags.contains(.command),
                    hasOtherModifiers: !event.modifierFlags.isDisjoint(with: [.control, .option, .shift]),
                    focus: KeyFocus(window: window)
                ) {
                    return self?.send() ?? false
                }
                guard let window = event.window, let key = PlayerKey.routed(
                    characters: event.charactersIgnoringModifiers,
                    keyCode: event.keyCode,
                    hasCommandModifiers: !event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
                    focus: KeyFocus(window: window)
                ) else { return false }
                return self?.perform(key) ?? false
            }
            // A key the player took is swallowed; the rest pass on.
            return handled ? nil : event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Cmd+Enter: the same send as `batch send`; false when no video is
    /// open to send from.
    private func send() -> Bool {
        guard model.video != nil else { return false }
        model.sendByPerson()
        return true
    }

    /// Runs the key's action; false when no video is open to run it on.
    private func perform(_ key: PlayerKey) -> Bool {
        guard model.video != nil else { return false }
        switch key {
        case .togglePlay: model.togglePlay()
        case .back: model.skip(by: -PlayerKey.skip)
        case .forward: model.skip(by: PlayerKey.skip)
        case .previousFrame: model.step(frames: -1)
        case .nextFrame: model.step(frames: 1)
        case .comment: model.compose()
        case .cancel:
            // With no comment box open, Escape is the window's.
            guard model.composing != nil else { return false }
            model.cancelComposer()
        }
        return true
    }
}
