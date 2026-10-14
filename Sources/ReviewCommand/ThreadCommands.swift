import Foundation
import ReviewWire

enum ThreadCommands {
    static let group = CommandGroup(
        name: "thread", summary: "answer the agent on a thread", section: .drive, commands: [
            Command(
                name: "thread answer", arguments: "<thread> <text>", summary: "answer the agent's open question on a thread",
                description: "As the person types an answer. The thread is its id, or its number in the open video.",
                examples: ["1 \"The intro\""], role: .operator
            ) { arguments, _ throws(UsageError) in
                let words = try arguments.exactly(["<thread>", "<text>"])
                return .send(.threadAnswer(thread: words[0], text: words[1]))
            },
            Command(
                name: "thread choose", arguments: "<thread> <number>",
                summary: "answer the agent's open question on a thread with a quick reply",
                description: "As a click on that choice does. The choices count from 1.",
                examples: ["1 2"], role: .operator
            ) { arguments, _ throws(UsageError) in
                let words = try arguments.exactly(["<thread>", "<number>"])
                guard let number = Int(words[1]), number >= 1 else {
                    throw UsageError("`<number>` is a choice's number from 1, not `\(words[1])`")
                }
                return .send(.threadChoose(thread: words[0], choice: number))
            },
        ].map { $0.onAWindow() }
    )
}
