import Foundation
import ReviewSetup

extension StateReport {
    nonisolated struct Setup: Encodable, Equatable {
        var commandLine: CommandLine
        var harnesses: [HarnessEntry]
        var install: Install?
        var agentConnectedOnce = false
        var needsFinishing = false

        struct CommandLine: Encodable, Equatable {
            var detection: String
            var path: String
            var destination: String?
            var command: String?
            var failure: String?
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

        struct HarnessEntry: Encodable, Equatable {
            var name: String
            var installName: String
            var presence: String
            var skill: String
            var skillFolder: String?
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

        struct Install: Encodable, Equatable {
            var state: String
            var harnesses: [String]
            var command: String
            var repositoryCommand: String
            var exitStatus: Int?
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
            try container.encode(agentConnectedOnce, forKey: .agentConnectedOnce)
            try container.encode(needsFinishing, forKey: .needsFinishing)
        }

        private enum CodingKeys: String, CodingKey {
            case commandLine, harnesses, install, agentConnectedOnce, needsFinishing
        }

        init(commandLine: CommandLine, harnesses: [HarnessEntry], install: Install? = nil) {
            self.commandLine = commandLine
            self.harnesses = harnesses
            self.install = install
        }

        @MainActor init(_ desk: SetupDesk, target: PromptTarget?, agentConnectedOnce: Bool = false) {
            self.agentConnectedOnce = agentConnectedOnce
            needsFinishing = !desk.isDetected && !agentConnectedOnce
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

        var line: String {
            let skills = harnesses.filter { $0.skill == Detection.detected.rawValue }.map(\.name)
            let skillWords = skills.isEmpty ? "skill not detected for any harness" : "skill detected for \(skills.joined(separator: ", "))"
            let installWords = install.map { "; install \($0.state)" } ?? ""
            return "setup: command line \(Self.words(commandLine.detection)); \(skillWords)\(installWords)"
        }

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

        static let logLinesShown = 20

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
