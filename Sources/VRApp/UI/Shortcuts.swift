import AppKit

/// What a key does to the player: the keys QuickTime and editors use.
enum PlayerKey: Equatable {
    case togglePlay
    case back, forward
    case previousFrame, nextFrame

    /// How far the arrow keys move, in seconds.
    static let skip = 5.0

    /// The key pressed, or nil when it isn't the player's: Space or K play
    /// and pause, ← and → move 5 s, `,` and `.` move one frame. A key held
    /// with Command, Control or Option belongs to the menu.
    init?(characters: String?, keyCode: UInt16, hasCommandModifiers: Bool) {
        guard !hasCommandModifiers else { return nil }
        switch (keyCode, characters?.lowercased()) {
        case (123, _): self = .back
        case (124, _): self = .forward
        case (_, " "), (_, "k"): self = .togglePlay
        case (_, ","): self = .previousFrame
        case (_, "."): self = .nextFrame
        default: return nil
        }
    }
}

/// The player's keys, watched for the whole app and given up while a text
/// view has the focus: typing "k" in a text field must not pause the video.
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
            let key = PlayerKey(
                characters: event.charactersIgnoringModifiers,
                keyCode: event.keyCode,
                hasCommandModifiers: !event.modifierFlags.isDisjoint(with: [.command, .control, .option])
            )
            guard let key, let window = event.window, Self.isPlayers(window) else { return event }
            // The monitor runs on the main thread, where events are handled.
            let handled = MainActor.assumeIsolated { self?.perform(key) ?? false }
            // A key the player took is swallowed; the rest pass on.
            return handled ? nil : event
        }
    }

    /// Whether a key pressed in `window` is the player's to take: not in a
    /// panel (the open panel's file list uses Space and the arrows itself),
    /// not under a sheet, and not while a text view has the focus.
    private static func isPlayers(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.attachedSheet == nil && !(window.firstResponder is NSText)
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
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
        }
        return true
    }
}
