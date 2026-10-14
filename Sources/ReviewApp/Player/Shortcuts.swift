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
        if held == .command, keyCode == 36 || keyCode == 76 { return .send }
        guard !isTyping, held.isDisjoint(with: [.command, .option, .control]) else { return nil }
        if isControlFocused, held.isEmpty, [49, 36, 76].contains(keyCode) { return .pressControl }
        let shift = modifiers.contains(.shift)
        switch keyCode {
        case 49, 40: return shift ? nil : .togglePlay
        case 123: return shift ? .step(frames: -1) : .skip(seconds: -skip)
        case 124: return shift ? .step(frames: 1) : .skip(seconds: skip)
        case 38: return shift ? nil : .skip(seconds: -longSkip)
        case 37: return shift ? nil : .skip(seconds: longSkip)
        case 43: return shift ? nil : .step(frames: -1)
        case 47: return shift ? nil : .step(frames: 1)
        case 126: return shift ? nil : .marker(forward: false)
        case 125: return shift ? nil : .marker(forward: true)
        case 8, 36, 76: return shift ? nil : .startMessage
        case 53: return .cancel
        case 42: return shift ? nil : .flip
        case 46: return shift ? nil : .toggleMute
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
