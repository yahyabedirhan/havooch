import Foundation
import ReviewWire

enum PlayerCommands {
    static let group = CommandGroup(
        name: "player", summary: "load, play, seek and set the sound", section: .drive, commands: [
            Command(
                name: "player load", arguments: "<path>", summary: "load a video file, paused at its start",
                description: "Unlike open, it is the operator's: the video stays paused and the app stays where it is.",
                examples: ["~/Movies/launch.mp4", "fixtures/sample.mp4 --window w2"], role: .operator
            ) { arguments, environment throws(UsageError) in
                let path = try arguments.one("<path>")
                return .send(.playerOpen(path: URL(fileURLWithPath: path, relativeTo: environment.workingDirectory).standardizedFileURL.path))
            },
            Command(name: "player play", summary: "play the video", examples: [""], role: .operator) {
                arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.playerPlay)
            },
            Command(name: "player pause", summary: "pause the video", examples: [""], role: .operator) {
                arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.playerPause)
            },
            Command(
                name: "player seek", arguments: "<seconds|m:ss>", summary: "move to an exact time",
                description: "It prints the time the player is at. An open comment popover closes, as a change of the moment.", examples: ["12.5", "1:05 --window w2"],
                role: .operator, exitCodes: "1 when no video is open or the time is past the end."
            ) { arguments, _ throws(UsageError) in
                let time = try arguments.one("<seconds|m:ss>")
                guard let seconds = TimeCode.seconds(time) else {
                    throw UsageError("`\(time)` isn't a time; write seconds (`90`, `12.5`) or `m:ss` (`1:30`)")
                }
                return .send(.playerSeek(seconds: seconds))
            },
            Command(name: "player mute", summary: "mute the sound in every window", examples: [""], role: .operator) {
                arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.playerMute)
            },
            Command(name: "player unmute", summary: "bring back the last volume", examples: [""], role: .operator) {
                arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.playerUnmute)
            },
            Command(
                name: "player volume", arguments: "<0-100>", summary: "set the volume in every window",
                description: "0 mutes.", examples: ["40", "0"], role: .operator
            ) { arguments, _ throws(UsageError) in
                let level = try arguments.one("<0-100>")
                guard let percent = Int(level), (0...100).contains(percent) else {
                    throw UsageError("`\(level)` isn't a volume; write a whole number from 0 to 100")
                }
                return .send(.playerVolume(percent: percent))
            },
            Command(
                name: "player sound", arguments: "[--close]", summary: "open the sound panel over the stage",
                description: "As a click on the speaker does. --close closes it.", examples: ["", "--close"],
                role: .operator, flags: ["--close"]
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .send(.playerSound(open: !arguments.flags.contains("--close")))
            },
        ].map { $0.onAWindow() }
    )
}
