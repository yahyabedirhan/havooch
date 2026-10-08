import AppKit

/// A click in the window outside the stage while the popover is
/// open: the popover closes as a click outside it (D 1.4), and the click
/// goes on to what it was on. A click on the stage is the stage's own: on
/// the popover it's the popover's, on the frame `RegionOverlay` closes the
/// popover without playing.
enum OutsideClicks {
    /// Starts watching the clicks in each of `app`'s windows, for as long
    /// as the app runs: a click closes the popover of the window it's in.
    static func install(for app: AppModel) {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            MainActor.assumeIsolated {
                if let model = app.windows.window(showing: event.window) { handle(event, model) }
            }
            return event
        }
    }

    private static func handle(_ event: NSEvent, _ model: WindowModel) {
        // Only the main window: a click in a popover window of its own
        // (Context, the agent-control icon) is not on the video's window.
        guard model.draft != nil, let window = event.window, window.isMainWindow, window.attachedSheet == nil,
              let content = window.contentView
        else { return }
        let point = content.convert(event.locationInWindow, from: nil)
        let fromTop = CGPoint(x: point.x, y: content.isFlipped ? point.y : content.bounds.height - point.y)
        if isOutside(fromTop, stage: model.stageArea) { model.closePopover(.clickOutside) }
    }

    /// Whether a click at `point`, from the window content's top-left
    /// corner, is outside the stage at `stage`. With no stage laid out yet,
    /// nothing is.
    static func isOutside(_ point: CGPoint, stage: CGRect) -> Bool {
        !stage.isEmpty && !stage.contains(point)
    }
}
