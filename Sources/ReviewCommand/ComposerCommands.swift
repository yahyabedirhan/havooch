import Foundation
import ReviewWire

/// `havooch composer set`: the composer at the sidebar's foot, written in
/// as the person types.
enum ComposerCommands {
    static let group = CommandGroup(
        name: "composer", summary: "write in the sidebar's composer", section: .drive, commands: [
            Command(
                name: "composer set", arguments: "[<text>] [--region x,y,w,h] [--general]",
                summary: "put a text in the composer at the sidebar's foot",
                description: "As the person types it, for the target the composer shows. --region adds a region chip on the "
                    + "player's frame; --general turns the General toggle on in the thread list.",
                examples: ["\"Make it shorter\"", "\"This corner\" --region 0.7,0.1,0.2,0.2", "--general"],
                role: .operator, valuedOptions: ["--region"], flags: ["--general"]
            ) { arguments, _ throws(UsageError) in
                guard arguments.words.count <= 1 else { throw UsageError("unexpected `\(arguments.words[1])`") }
                return .send(
                    .commentCompose(
                        text: arguments.words.first ?? "", region: try MessageCommands.region(arguments),
                        general: arguments.flags.contains("--general")
                    )
                )
            }.onAWindow(),
        ]
    )
}
