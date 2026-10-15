import AppKit

enum Shortcuts {
    static let skip: Double = 5
    static let longSkip: Double = 10

    enum Action: Equatable {
        case togglePlay
        case skip(seconds: Double)
        case step(frames: Int)
        case marker(forward: Bool)
        case startMessage
        case cancel
        case send
        case pressControl
        case flip
        case toggleMute
    }

    static func action(
        keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isTyping: Bool = false, isControlFocused: Bool = false
    ) -> Action? {
        let held = modifiers.intersection([.command, .option, .control, .shift])
        if held == .command, keyCode == KeyCode.returnKey || keyCode == KeyCode.keypadEnter { return .send }
        guard !isTyping, held.isDisjoint(with: [.command, .option, .control]) else { return nil }
        if isControlFocused, held.isEmpty, [KeyCode.space, KeyCode.returnKey, KeyCode.keypadEnter].contains(keyCode) { return .pressControl }
        let shift = modifiers.contains(.shift)
        switch keyCode {
        case KeyCode.space, KeyCode.k: return shift ? nil : .togglePlay
        case KeyCode.leftArrow: return shift ? .step(frames: -1) : .skip(seconds: -skip)
        case KeyCode.rightArrow: return shift ? .step(frames: 1) : .skip(seconds: skip)
        case KeyCode.j: return shift ? nil : .skip(seconds: -longSkip)
        case KeyCode.l: return shift ? nil : .skip(seconds: longSkip)
        case KeyCode.comma: return shift ? nil : .step(frames: -1)
        case KeyCode.period: return shift ? nil : .step(frames: 1)
        case KeyCode.upArrow: return shift ? nil : .marker(forward: false)
        case KeyCode.downArrow: return shift ? nil : .marker(forward: true)
        case KeyCode.c, KeyCode.returnKey, KeyCode.keypadEnter: return shift ? nil : .startMessage
        case KeyCode.escape: return .cancel
        case KeyCode.backslash: return shift ? nil : .flip
        case KeyCode.m: return shift ? nil : .toggleMute
        default: return nil
        }
    }

    static func isControlFocused(reported: Bool, firstResponderIsControl: Bool, keyboardNavigation: Bool) -> Bool {
        reported || (keyboardNavigation && firstResponderIsControl)
    }

    static func install(for app: AppModel) {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated {
                app.windows.window(showing: event.window).map { handle(event, $0) } ?? false
            }
            return handled ? nil : event
        }
    }

    private static func handle(_ event: NSEvent, _ model: WindowModel) -> Bool {
        guard model.video != nil, !model.isContextShown,
              let window = event.window, window.isKeyWindow, window.attachedSheet == nil,
              let action = action(
                  keyCode: event.keyCode, modifiers: event.modifierFlags, isTyping: window.firstResponder is NSText,
                  isControlFocused: isControlFocused(
                      reported: model.isControlFocused, firstResponderIsControl: window.firstResponder is NSControl,
                      keyboardNavigation: NSApp.isFullKeyboardAccessEnabled
                  )
              )
        else { return false }
        switch action {
        case .togglePlay: model.togglePlay()
        case .skip(let seconds): model.skip(by: seconds)
        case .step(let frames): model.step(frames: frames)
        case .marker(let forward): model.jumpToMarker(forward: forward)
        case .startMessage: model.startDraft()
        case .cancel: return model.escape()
        case .send: model.send()
        case .pressControl: return model.pressFocusedControl()
        case .flip: return model.flipCompare()
        case .toggleMute: model.app.toggleMuteForPerson()
        }
        return true
    }
}
