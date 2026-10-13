import Foundation
import ReviewConfig
import ReviewWire

/// `havooch project new | add | list`. A
/// project holds the versions of one video in `config.toml`. The agent
/// makes one the first time a send asks for a change (`new`, whose v1 is
/// the video under review, with its threads), and appends each new render
/// (`add`, which shows it and brings the window forward). Both go through
/// the app, which moves the review and opens the window without a lease.
/// The app launches when it isn't running. `list` reads the file
/// itself and needs no app.
enum ProjectCommands {
    static let group = CommandGroup(
        name: "project", summary: "make projects and add versions to them", section: .feedback, commands: [
            Command(
                name: "project new", arguments: "<slug> --from <path> [--title <title>]",
                summary: "make a project whose first version is a video",
                description: "The video's threads move into the project, and its listener keeps listening. The app starts "
                    + "in the background when it isn't running.",
                examples: ["launch-video --from renders/v1.mp4", "launch-video --from renders/v1.mp4 --title \"Launch video\""],
                role: .person, valuedOptions: ["--from", "--title"]
            ) { arguments, environment throws(UsageError) in
                let slug = try arguments.one("<slug>")
                guard let from = arguments.options["--from"] else { throw UsageError("missing --from <path>") }
                try needSlug(slug)
                return .projectNew(slug: slug, video: absolute(from, environment), title: arguments.options["--title"])
            },
            Command(
                name: "project add", arguments: "<slug> <path> [--label <label>]",
                summary: "add a video as a project's next version",
                description: "The app shows the new version and brings its window forward. It starts when it isn't running.",
                examples: ["launch-video renders/v2.mp4", "launch-video renders/v3.mp4 --label \"Shorter intro\""],
                role: .person, valuedOptions: ["--label"]
            ) { arguments, environment throws(UsageError) in
                let words = try arguments.exactly(["<slug>", "<path>"])
                try needSlug(words[0])
                return .projectAdd(slug: words[0], video: absolute(words[1], environment), label: arguments.options["--label"])
            },
            Command(
                name: "project list", summary: "list every project with its versions",
                description: "It reads config.toml and needs no app.",
                examples: ["", "--json"], role: .free, exitCodes: "1 when config.toml doesn't read."
            ) { arguments, _ throws(UsageError) in
                try arguments.none()
                return .projectList
            },
        ]
    )

    /// `path` made absolute here: the app runs in another folder.
    private static func absolute(_ path: String, _ environment: CommandEnvironment) -> URL {
        URL(fileURLWithPath: path, relativeTo: environment.workingDirectory).standardizedFileURL
    }

    private static func needSlug(_ slug: String) throws(UsageError) {
        guard ProjectEntry.isSlug(slug) else {
            throw UsageError("`\(slug)` isn't a slug: use lowercase letters, digits and single hyphens, such as `launch-video`")
        }
    }

    /// `project new`: the app makes the project, launched in the
    /// background when it doesn't run.
    static func new(slug: String, video: URL, title: String?, _ context: AppCommands.Context) -> CommandResult {
        OpenCommand.ask(.projectNew(slug: slug, path: video.path, title: title), about: video, named: "project new", inFront: false, context)
    }

    /// `project add`: the app appends the version and shows it in front.
    static func add(slug: String, video: URL, label: String?, _ context: AppCommands.Context) -> CommandResult {
        OpenCommand.ask(.projectAdd(slug: slug, path: video.path, label: label), about: video, named: "project add", inFront: true, context)
    }

    /// `project list`: each project with its versions, read from the file
    /// with no app; exit 1 when the file doesn't read.
    static func list(json: Bool, environment: CommandEnvironment) -> CommandResult {
        let location = ConfigCommands.location(environment)
        let projects: [ProjectEntry]
        do throws(ConfigProblems) {
            projects = try location.read().config.projects
        } catch {
            return .refused("havooch project list: \(location.file.path) doesn't read: \(error.line); run `havooch config check`")
        }
        let listed = projects.map { project in
            Listed(
                slug: project.slug, title: project.displayTitle,
                versions: project.versions.enumerated().map {
                    Listed.Version(number: $0.offset + 1, path: location.expand($0.element.path).path, label: $0.element.label)
                }
            )
        }
        if json { return ConfigCommands.encoded(["projects": listed]) }
        guard !listed.isEmpty else {
            return CommandResult(output: "no projects; make one with `havooch project new <slug> --from <video>`\n")
        }
        let lines = listed.flatMap { project in
            let count = "\(project.versions.count) version\(project.versions.count == 1 ? "" : "s")"
            return ["\(project.slug) \"\(project.title)\", \(count)"]
                + project.versions.map { "  v\($0.number) \($0.path)" + ($0.label.map { " (\($0))" } ?? "") }
        }
        return CommandResult(output: lines.joined(separator: "\n") + "\n")
    }

    /// One project as `project list --json` prints it.
    private struct Listed: Encodable {
        var slug: String
        var title: String
        var versions: [Version]

        struct Version: Encodable {
            var number: Int
            var path: String
            var label: String?

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(number, forKey: .number)
                try container.encode(path, forKey: .path)
                try container.encode(label, forKey: .label)
            }

            private enum CodingKeys: String, CodingKey {
                case number, path, label
            }
        }
    }
}
