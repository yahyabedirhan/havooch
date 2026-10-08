import Foundation
import ReviewWire

/// `havooch player open | play | pause | seek | mute | unmute | volume |
/// sound`.
enum PlayerCommands {
    static let commands: [Command] = [
        Command(name: "player open", synopsis: "player open <path>", summary: "open a video file, paused at its start") {
            arguments, environment throws(UsageError) in
            // Made absolute here: the app runs in another folder.
            let path = try arguments.one("<path>")
            return .send(.playerOpen(path: URL(fileURLWithPath: path, relativeTo: environment.workingDirectory).standardizedFileURL.path))
        },
        Command(name: "player play", synopsis: "player play", summary: "play") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.playerPlay)
        },
        Command(name: "player pause", synopsis: "player pause", summary: "pause") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.playerPause)
        },
        Command(name: "player seek", synopsis: "player seek <seconds|mm:ss>", summary: "move to an exact time") {
            arguments, _ throws(UsageError) in
            let time = try arguments.one("<seconds|mm:ss>")
            guard let seconds = TimeCode.seconds(time) else {
                throw UsageError("`\(time)` isn't a time; write seconds (`90`, `12.5`) or `mm:ss` (`1:30`)")
            }
            return .send(.playerSeek(seconds: seconds))
        },
        Command(name: "player mute", synopsis: "player mute", summary: "mute the sound in every window") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.playerMute)
        },
        Command(name: "player unmute", synopsis: "player unmute", summary: "bring back the last volume") {
            arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.playerUnmute)
        },
        Command(name: "player volume", synopsis: "player volume <0 to 100>", summary: "set the volume in every window; 0 mutes") {
            arguments, _ throws(UsageError) in
            let level = try arguments.one("<0 to 100>")
            guard let percent = Int(level), (0...100).contains(percent) else {
                throw UsageError("`\(level)` isn't a volume; write a whole number from 0 to 100")
            }
            return .send(.playerVolume(percent: percent))
        },
        Command(
            name: "player sound", synopsis: "player sound [--close]",
            summary: "open the sound panel over the stage, as a click on the speaker does; --close closes it",
            flags: ["--close"]
        ) { arguments, _ throws(UsageError) in
            try arguments.none()
            return .send(.playerSound(open: !arguments.flags.contains("--close")))
        },
    ]
}
