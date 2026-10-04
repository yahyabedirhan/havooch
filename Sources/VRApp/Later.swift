import Foundation

/// How the app does something once a time has passed: a `wait`'s and an
/// `ask`'s time running out, a waiting `take`'s, the lease's end, a notice
/// going. In the app it's a task that sleeps; in the tests it's a clock the
/// test moves, so no test waits for real seconds.
@MainActor
struct Later {
    /// Takes back a call that wasn't made yet. After the call it does
    /// nothing.
    typealias Cancel = @MainActor () -> Void

    /// Calls `then` once `seconds` have passed, unless it's cancelled first.
    var after: @MainActor (_ seconds: TimeInterval, _ then: @escaping @MainActor () -> Void) -> Cancel

    /// The app's: a task that sleeps for that long.
    static let sleeping = Later { seconds, then in
        let task = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            then()
        }
        return { task.cancel() }
    }
}
