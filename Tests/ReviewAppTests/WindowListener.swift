import Testing
@testable import ReviewApp

extension WindowModel {
    /// The window's listener, in a test that opened a video in the window
    /// first. A window with no video has none: the test is wrong, and it
    /// gets a listener of no review, which nothing sends to.
    func listeners(sourceLocation: SourceLocation = #_sourceLocation) -> ListenerQueue {
        if let listener { return listener }
        Issue.record("the window holds no video, so it has no listener", sourceLocation: sourceLocation)
        return app.listeners.queue(ofVideo: "no video")
    }
}
