import Foundation
import ReviewWire

/// `video-review player open | play | pause | seek`.
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
    ]
}
