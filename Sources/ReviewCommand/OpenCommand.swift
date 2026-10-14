import Foundation
import ReviewWire

enum OpenCommand {
    static let command = Command(
        name: "open", arguments: "<path> [--project <slug>]",
        summary: "open a video for the person, playing",
        description: "The app comes to the front with the video, in the project --project names, else in the most recently "
            + "used project that lists it. It starts the app when it isn't running, and takes no lease.",
        examples: ["~/Movies/launch.mp4", "renders/v3.mp4 --project launch-video"], role: .person,
        valuedOptions: ["--project"]
    ) { arguments, environment throws(UsageError) in
        let path = try arguments.one("<path>")
        return .open(URL(fileURLWithPath: path, relativeTo: environment.workingDirectory).standardizedFileURL, project: arguments.options["--project"])
    }

    static let wait: TimeInterval = 10
    static let interval: TimeInterval = 0.05

    static func run(_ file: URL, project: String? = nil, _ context: AppCommands.Context) -> CommandResult {
        ask(.open(path: file.path, project: project), about: file, named: "open", inFront: true, context)
    }

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
