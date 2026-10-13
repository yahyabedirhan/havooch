import Foundation
import ReviewWire

/// `havooch thread answer | choose`: the person's answer to the agent's
/// open question on a thread, typed or clicked.
enum ThreadCommands {
    static let commands: [Command] = [
        Command(
            name: "thread answer", synopsis: "thread answer <thread> <text>",
            summary: "answer the agent's open question on a thread (an id, or a number of the open video), as the person does"
        ) { arguments, _ throws(UsageError) in
            let words = try arguments.exactly(["<thread>", "<text>"])
            return .send(.threadAnswer(thread: words[0], text: words[1]))
        },
        Command(
            name: "thread choose", synopsis: "thread choose <thread> <number>",
            summary: "answer the agent's open question on a thread with its quick-reply choice <number> (from 1), as a click on that choice does"
        ) { arguments, _ throws(UsageError) in
            let words = try arguments.exactly(["<thread>", "<number>"])
            guard let number = Int(words[1]), number >= 1 else {
                throw UsageError("`<number>` is a choice's number from 1, not `\(words[1])`")
            }
            return .send(.threadChoose(thread: words[0], choice: number))
        },
    ]
}
