import Foundation
import ReviewWire

/// `havooch open <path> [--project <slug>]`: the person's open, for a
/// person or an agent. The video opens playing and the app comes to the
/// front: in the project `--project` names, else in the most recently
/// used project that lists it, else as a plain video. The app is launched
/// when it doesn't run. It takes no lease, so the agent-control icon never
/// shows for it; `player open` stays the operator's leased open.
enum OpenCommand {
    static let command = Command(
        name: "open", synopsis: "open <path> [--project <slug>]",
        summary: "open a video, playing, in front, in its project when one lists it; starts the app when needed, takes no lease",
        valuedOptions: ["--project"]
    ) { arguments, environment throws(UsageError) in
        // Made absolute here: the app runs in another folder.
        let path = try arguments.one("<path>")
        return .open(URL(fileURLWithPath: path, relativeTo: environment.workingDirectory).standardizedFileURL, project: arguments.options["--project"])
    }

    /// How long a launched app gets to answer, and how often it's looked
    /// at meanwhile: often, since a cold open has 2 seconds in all.
    static let wait: TimeInterval = 10
    static let interval: TimeInterval = 0.05

    /// Asks the running app to open `file`, in the project `project` when
    /// it's set. When none runs, the app is launched in front and asked
    /// once it answers. A path with no file is refused before anything is
    /// launched; a file that doesn't play is the app's refusal, with
    /// nothing opened.
    static func run(_ file: URL, project: String? = nil, _ context: AppCommands.Context) -> CommandResult {
        ask(.open(path: file.path, project: project), about: file, named: "open", inFront: true, context)
    }

    /// Asks the running app for `request`, which is about the video
    /// `file`, launching the app (`inFront`, or in the background) when
    /// none runs. A path with no file is refused first, by the command
    /// `name`. With `inFront`, the process the reply names comes to the
    /// front, as `open` brings it.
    static func ask(
        _ request: ControlRequest, about file: URL, named name: String, inFront: Bool, _ context: AppCommands.Context
    ) -> CommandResult {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isFolder), !isFolder.boolValue else {
            return .refused("havooch \(name): no video file at \(file.path)")
        }
        let answered = { (answer: Result<ControlReply, ControlClient.Failure>) in
            inFront ? Self.inFront(answer, context) : HavoochCLI.result(of: answer)
        }
        switch context.client.send(request) {
        case .failure(.notRunning): break
        case let answer: return answered(answer)
        }
        do throws(AppLaunchFailure) {
            try context.launcher.launch(environment: [:], inFront: inFront)
        } catch {
            return .refused("havooch \(name): \(error.reason)")
        }
        // Asked only once the app answers, so the request is made once:
        // a look that times out would otherwise open the file twice.
        var look = context.client
        look.timeout = AppCommands.lookTimeout
        for _ in 0..<Int(wait / interval) {
            context.pause(interval)
            switch look.send(.appStatus) {
            case .failure(.notRunning), .failure(.timedOut): continue
            case .success(let reply) where reply.ok: return answered(context.client.send(request))
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
