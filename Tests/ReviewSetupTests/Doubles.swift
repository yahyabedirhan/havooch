import Foundation
import ReviewSetup
import Synchronization

/// A file system in memory: each path's item as `lstat` reads it. A link is
/// followed once, to its destination's item. Every path read is recorded.
final class FakeFileSystem: SetupFileSystem {
    private let state: Mutex<(items: [String: FileItem], reads: [String], failing: Set<String>)>

    init(_ items: [String: FileItem] = [:], failing: Set<String> = []) {
        state = Mutex((items, [], failing))
    }

    var items: [String: FileItem] { state.withLock { $0.items } }
    var reads: [String] { state.withLock { $0.reads } }

    func item(at path: String) -> FileItem {
        state.withLock { state in
            state.reads.append(path)
            return state.items[path] ?? .missing
        }
    }

    func target(at path: String) -> FileItem {
        state.withLock { state in
            state.reads.append(path)
            guard case .link(let destination) = state.items[path] ?? .missing else { return state.items[path] ?? .missing }
            return state.items[destination] ?? .missing
        }
    }

    func makeFolder(at path: String) throws {
        try state.withLock { state in
            if state.failing.contains(path) { throw FakeFailure() }
            state.items[path] = .folder
        }
    }

    func makeLink(at path: String, to destination: String) throws {
        try state.withLock { state in
            if state.failing.contains(path) { throw FakeFailure() }
            state.items[path] = .link(to: destination)
        }
    }

    func remove(at path: String) throws {
        state.withLock { state in state.items[path] = nil }
    }
}

struct FakeFailure: LocalizedError {
    var errorDescription: String? { "Operation not permitted" }
}

/// A process runner that runs nothing: each call is recorded, and answered
/// by `answer` with its lines and its exit status. With `holds`, the
/// install's run is held until its task is cancelled, as a running program
/// is, so a test can cancel it.
final class FakeRunner: ProcessRunner {
    struct Call: Equatable {
        var executable: String
        var arguments: [String]
    }

    private let state = Mutex<(calls: [Call], held: CheckedContinuation<Void, Never>?, cancelled: Bool)>(([], nil, false))
    let answer: @Sendable (Call) -> (lines: [String], status: Int32)
    let holds: Bool

    init(holds: Bool = false, answer: @escaping @Sendable (Call) -> (lines: [String], status: Int32)) {
        self.holds = holds
        self.answer = answer
    }

    var calls: [Call] { state.withLock { $0.calls } }

    func run(_ executable: String, arguments: [String], line: @escaping @Sendable (String) -> Void) async -> Int32 {
        let call = Call(executable: executable, arguments: arguments)
        state.withLock { $0.calls.append(call) }
        let (lines, status) = answer(call)
        lines.forEach(line)
        if holds, arguments.last?.hasPrefix("exec ") == true {
            // Held as a running program is, until cancelled.
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    state.withLock { state in
                        if state.cancelled { continuation.resume() } else { state.held = continuation }
                    }
                }
            } onCancel: {
                state.withLock { state in
                    state.cancelled = true
                    state.held?.resume()
                    state.held = nil
                }
            }
            return 143
        }
        return status
    }

    /// Whether a run is held now.
    var isHolding: Bool { state.withLock { $0.held != nil } }
}
