import Foundation
import ReviewSetup

/// Setup as `state`, `setup status`, `setup link`, `setup install` and
/// `setup cancel` report it. Each detection is `detected`, `notDetected`
/// or `cannotKnow`: never "missing" (ADR 0005).
extension StateReport {
    nonisolated struct Setup: Encodable, Equatable {
        var commandLine: CommandLine
        /// One per harness Havooch knows, in the catalog's order.
        var harnesses: [HarnessEntry]
        /// The running install or the last one; `null` before the first.
        var install: Install?

        /// The `havooch` command's link in `~/.local/bin`.
        struct CommandLine: Encodable, Equatable {
            var detection: String
            /// The link file.
            var path: String
            /// Where the link points; `null` with no link.
            var destination: String?
            /// The command in this app's bundle that Link links; `null` in
            /// a build that isn't bundled.
            var command: String?
            /// Why the last Link failed; `null` once one works.
            var failure: String?
            /// The line that makes the link in a terminal, shown when Link
            /// failed; `null` otherwise.
            var fallback: String?

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(detection, forKey: .detection)
                try container.encode(path, forKey: .path)
                try container.encode(destination, forKey: .destination)
                try container.encode(command, forKey: .command)
                try container.encode(failure, forKey: .failure)
                try container.encode(fallback, forKey: .fallback)
            }

            private enum CodingKeys: String, CodingKey {
                case detection, path, destination, command, failure, fallback
            }
        }

        /// One harness: whether it looks installed, whether its skill is
        /// detected, and its prompt.
        struct HarnessEntry: Encodable, Equatable {
            var name: String
            /// The harness's name for `setup install --harness` and `-a`.
            var installName: String
            /// A best guess from its app and command folders.
            var presence: String
            var skill: String
            /// The skill's folder when it's detected; else `null`.
            var skillFolder: String?
            /// The prompt that makes its agent listen to the open video;
            /// `null` with no video open.
            var prompt: String?

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(name, forKey: .name)
                try container.encode(installName, forKey: .installName)
                try container.encode(presence, forKey: .presence)
                try container.encode(skill, forKey: .skill)
                try container.encode(skillFolder, forKey: .skillFolder)
                try container.encode(prompt, forKey: .prompt)
            }

            private enum CodingKeys: String, CodingKey {
                case name, installName, presence, skill, skillFolder, prompt
            }
        }

        /// One skill install.
        struct Install: Encodable, Equatable {
            /// `running`, `done`, `failed`, `cancelled` or `noNode`;
            /// `planned` in a `setup install --dry-run`'s answer.
            var state: String
            /// The install names of the harnesses it is for.
            var harnesses: [String]
            /// The command it runs.
            var command: String
            /// The same install into one repository, for the person to copy.
            var repositoryCommand: String
            /// `npx`'s exit status once it ended; else `null`.
            var exitStatus: Int?
            /// The lines it wrote, the oldest first.
            var log: [String]

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(state, forKey: .state)
                try container.encode(harnesses, forKey: .harnesses)
                try container.encode(command, forKey: .command)
                try container.encode(repositoryCommand, forKey: .repositoryCommand)
                try container.encode(exitStatus, forKey: .exitStatus)
                try container.encode(log, forKey: .log)
            }

            private enum CodingKeys: String, CodingKey {
                case state, harnesses, command, repositoryCommand, exitStatus, log
            }

            init(_ run: SetupDesk.InstallRun) {
                self.init(run.install, state: run.state.rawValue, exitStatus: run.exitStatus, log: run.log)
            }

            init(_ install: SkillInstall, state: String, exitStatus: Int32? = nil, log: [String] = []) {
                self.state = state
                harnesses = install.harnesses.map(\.installName)
                command = install.commandLine
                repositoryCommand = install.repositoryCommandLine
                self.exitStatus = exitStatus.map(Int.init)
                self.log = log
            }

            /// `install: running for Codex, Pi: npx skills add …`.
            var line: String {
                let names = harnesses.compactMap { HarnessCatalog.harness(named: $0)?.name }.joined(separator: ", ")
                let status = exitStatus.map { " (exit status \($0))" } ?? ""
                return "install: \(state)\(status) for \(names): \(command)"
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(commandLine, forKey: .commandLine)
            try container.encode(harnesses, forKey: .harnesses)
            try container.encode(install, forKey: .install)
        }

        private enum CodingKeys: String, CodingKey {
            case commandLine, harnesses, install
        }

        init(commandLine: CommandLine, harnesses: [HarnessEntry], install: Install? = nil) {
            self.commandLine = commandLine
            self.harnesses = harnesses
            self.install = install
        }

        /// `setup` as the desk has it now; prompts name `target`.
        @MainActor init(_ desk: SetupDesk, target: PromptTarget?) {
            let report = desk.report
            commandLine = CommandLine(
                detection: report.commandLine.detection.rawValue, path: report.commandLine.path,
                destination: report.commandLine.destination, command: desk.command,
                failure: desk.linkFailure?.reason, fallback: desk.linkFailure?.fallback
            )
            harnesses = report.harnesses.map { setup in
                HarnessEntry(
                    name: setup.harness.name, installName: setup.harness.installName, presence: setup.presence.rawValue,
                    skill: setup.skill.rawValue, skillFolder: setup.skillFolder, prompt: target.map(setup.harness.prompt(for:))
                )
            }
            install = desk.install.map(Install.init)
        }

        /// `setup: command line detected; skill detected for Claude Code`,
        /// the one line `state` prints.
        var line: String {
            let skills = harnesses.filter { $0.skill == Detection.detected.rawValue }.map(\.name)
            let skillWords = skills.isEmpty ? "skill not detected for any harness" : "skill detected for \(skills.joined(separator: ", "))"
            let installWords = install.map { "; install \($0.state)" } ?? ""
            return "setup: command line \(Self.words(commandLine.detection)); \(skillWords)\(installWords)"
        }

        /// What `setup status` prints: the link, a row per harness, and the
        /// install with its last lines.
        var lines: String {
            var lines = ["command line: \(Self.words(commandLine.detection)), \(commandLine.path)"
                + (commandLine.destination.map { " links to \($0)" } ?? "")]
            if let failure = commandLine.failure, let fallback = commandLine.fallback {
                lines.append("  link failed: \(failure). Run this in a terminal: \(fallback)")
            }
            lines.append("harnesses:")
            let width = harnesses.map(\.name.count).max() ?? 0
            for harness in harnesses {
                let name = harness.name.padding(toLength: width, withPad: " ", startingAt: 0)
                let folder = harness.skillFolder.map { " in \($0)" } ?? ""
                lines.append("  \(name)  harness \(Self.words(harness.presence)), skill \(Self.words(harness.skill))\(folder)")
            }
            if let install {
                lines.append(install.line)
                lines += install.log.suffix(Self.logLinesShown).map { "  \($0)" }
            }
            return lines.joined(separator: "\n") + "\n"
        }

        /// How many of the install's last lines `setup status` prints;
        /// `--json` has them all.
        static let logLinesShown = 20

        /// A detection as words: `not detected`, `cannot know`.
        static func words(_ detection: String) -> String {
            switch Detection(rawValue: detection) {
            case .detected: "detected"
            case .notDetected: "not detected"
            case .cannotKnow: "cannot know"
            case nil: detection
            }
        }
    }
}
