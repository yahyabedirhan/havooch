import Testing
@testable import ReviewApp

extension WindowModel {
    func listeners(sourceLocation: SourceLocation = #_sourceLocation) -> ListenerQueue {
        if let listener { return listener }
        Issue.record("the window holds no video, so it has no listener", sourceLocation: sourceLocation)
        return app.listeners.queue(for: .video(contentHash: "no video"))
    }
}
