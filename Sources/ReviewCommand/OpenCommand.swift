import Foundation
import ReviewWire

/// `havooch open <path>`: the person's open, for a person or an agent. The
/// video opens playing and the app comes to the front. The app is launched
/// when it doesn't run. It takes no lease, so the agent-control icon never
/// shows for it; `player open` stays the operator's leased open.
enum OpenCommand {
    static let command = Command(
        name: "open", synopsis: "open <path>",
        summary: "open a video, playing, in front; starts the app when needed, takes no lease"
    ) { arguments, environment throws(UsageError) in
        // Made absolute here: the app runs in another folder.
        let path = try arguments.one("<path>")
        return .open(URL(fileURLWithPath: path, relativeTo: environment.workingDirectory).standardizedFileURL)
    }

    /// How long a launched app gets to answer, and how often it's looked
    /// at meanwhile: often, since a cold open has 2 seconds in all.
    static let wait: TimeInterval = 10
    static let interval: TimeInterval = 0.05

    /// Asks the running app to open `file`. When none runs, the app is
    /// launched in front and asked once it answers. A path with no file is
    /// refused before anything is launched; a file that doesn't play is the
    /// app's refusal, with nothing opened.
    static func run(_ file: URL, _ context: AppCommands.Context) -> CommandResult {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isFolder), !isFolder.boolValue else {
            return .refused("havooch open: no video file at \(file.path)")
        }
        let request = ControlRequest.open(path: file.path)
        switch context.client.send(request) {
        case .failure(.notRunning): break
        case let answer: return inFront(answer, context)
        }
        do throws(AppLaunchFailure) {
            try context.launcher.launch(environment: [:], inFront: true)
        } catch {
            return .refused("havooch open: \(error.reason)")
        }
        // Asked only once the app answers, so the open is asked for once:
        // a look that times out would otherwise open the file twice.
        var look = context.client
        look.timeout = AppCommands.lookTimeout
        for _ in 0..<Int(wait / interval) {
            context.pause(interval)
            switch look.send(.appStatus) {
            case .failure(.notRunning), .failure(.timedOut): continue
            case .success(let reply) where reply.ok: return inFront(context.client.send(request), context)
            case let answer: return HavoochCLI.result(of: answer)
            }
        }
        return .refused("\(AppIdentity.appName) didn't answer within \(Int(wait)) seconds of launching")
    }

    /// What the app's answer prints, once the process its reply names is
    /// brought to the front: macOS may keep an app in the background from
    /// bringing itself there. One that doesn't come says so on standard
    /// error; the video is open all the same.
    private static func inFront(_ answer: Result<ControlReply, ControlClient.Failure>, _ context: AppCommands.Context) -> CommandResult {
        var result = HavoochCLI.result(of: answer)
        guard case .success(let reply) = answer, reply.ok, let pid = reply.pid else { return result }
        if !context.launcher.bringToFront(pid: pid) {
            result.error += "\(AppIdentity.appName) couldn't be brought to the front\n"
        }
        return result
    }
}
