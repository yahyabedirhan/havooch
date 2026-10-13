import Foundation
import ReviewWire

/// `havooch popover open`: the comment popover on the player's frame. With
/// no `--thread` it opens for a new message, as C or a drawn rectangle
/// does; with `--thread` it opens on that thread's frame, as a click on its
/// pin or its badge does. The two take different words, so one command
/// refuses the other's.
enum PopoverCommands {
    static let commands: [Command] = [
        Command(
            name: "popover open", synopsis: "popover open [<text>] [--region x,y,w,h] | --thread <thread> [--frame x,y,w,h]",
            summary: "open the comment popover at the player's frame, as C or a drawn rectangle does, with <text> in its field; a seek or play then closes it by the popover's rules; --thread opens a thread's popover on its frame, as a click on its pin or its badge does, and --frame first keeps it there, 0 to 1 of the video area from its top-left corner, as a drag and a resize leave it",
            valuedOptions: ["--region", "--thread", "--frame"]
        ) { arguments, _ throws(UsageError) in
            guard let thread = arguments.options["--thread"] else {
                if arguments.options["--frame"] != nil { throw UsageError("`--frame` goes with `--thread`") }
                guard arguments.words.count <= 1 else { throw UsageError("unexpected `\(arguments.words[1])`") }
                return .send(.commentOpen(text: arguments.words.first ?? "", region: try MessageCommands.region(arguments)))
            }
            if let word = arguments.words.first { throw UsageError("`--thread` takes no text, not `\(word)`") }
            if arguments.options["--region"] != nil { throw UsageError("`--thread` takes no `--region`; its popover has `--frame`") }
            var frame: ControlRequest.Rectangle?
            if let numbers = arguments.options["--frame"] {
                guard let rectangle = ControlRequest.Rectangle(numbers) else {
                    throw UsageError(
                        "`\(numbers)` isn't a frame; write x,y,w,h as four numbers from 0 to 1, from the video area's top-left corner (`0.55,0.1,0.4,0.5`)"
                    )
                }
                frame = rectangle
            }
            return .send(.threadOpen(thread: thread, frame: frame))
        },
    ]
}
