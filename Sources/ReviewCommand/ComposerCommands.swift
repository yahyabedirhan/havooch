import Foundation
import ReviewWire

/// `havooch composer set`: the composer at the sidebar's foot, written in
/// as the person types.
enum ComposerCommands {
    static let commands: [Command] = [
        Command(
            name: "composer set", synopsis: "composer set [<text>] [--region x,y,w,h] [--general]",
            summary: "put <text> in the composer at the sidebar's foot, as the person types it, for the target it shows; --region adds a region chip on the player's frame; --general turns the General toggle on in the thread list",
            valuedOptions: ["--region"], flags: ["--general"]
        ) { arguments, _ throws(UsageError) in
            guard arguments.words.count <= 1 else { throw UsageError("unexpected `\(arguments.words[1])`") }
            return .send(
                .commentCompose(
                    text: arguments.words.first ?? "", region: try MessageCommands.region(arguments),
                    general: arguments.flags.contains("--general")
                )
            )
        },
    ]
}
