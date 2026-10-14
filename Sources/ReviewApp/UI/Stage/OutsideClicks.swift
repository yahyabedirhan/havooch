import AppKit

enum OutsideClicks {
    static func install(for app: AppModel) {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            MainActor.assumeIsolated {
                if let model = app.windows.window(showing: event.window) { handle(event, model) }
            }
            return event
        }
    }

    private static func handle(_ event: NSEvent, _ model: WindowModel) {
        guard model.draft != nil, let window = event.window, window.isMainWindow, window.attachedSheet == nil,
              let content = window.contentView
        else { return }
        let point = content.convert(event.locationInWindow, from: nil)
        let fromTop = CGPoint(x: point.x, y: content.isFlipped ? point.y : content.bounds.height - point.y)
        if isOutside(fromTop, stage: model.stageArea) { model.closePopover(.clickOutside) }
    }

    static func isOutside(_ point: CGPoint, stage: CGRect) -> Bool {
        !stage.isEmpty && !stage.contains(point)
    }
}
