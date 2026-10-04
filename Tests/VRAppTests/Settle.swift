import Foundation
import Testing

/// Waits for work the test can't await: a task the model started for a
/// person's gesture, a frame written off the main actor, a command on a real
/// socket. It looks every millisecond until `done` says yes. After 5 seconds
/// it gives up and records an issue at the caller's line, so a wait that
/// timed out never passes as one that settled.
@MainActor
func settle(until done: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
    let deadline = ContinuousClock.now + .seconds(5)
    while !done(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(1))
    }
    if !done() {
        Issue.record("what the test waited for didn't happen within 5 seconds", sourceLocation: sourceLocation)
    }
}
