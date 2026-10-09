import Foundation
import ReviewConfig

/// The theme as `state`, `theme list` and `theme set` report it.
extension StateReport {
    /// The active theme, in `state`.
    nonisolated struct Theme: Encodable, Equatable {
        /// The theme every view draws with.
        var active: String
        /// `light` or `dark`.
        var kind: String
        /// The pinned theme; `null` while the theme follows the system.
        var pinned: String?
        /// The system appearance: `light` or `dark`.
        var appearance: String
        /// The fill of filled controls as `#rrggbb`, which white text reads
        /// on; `null` only without the built-in themes.
        var accentFill: String? = nil

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(active, forKey: .active)
            try container.encode(kind, forKey: .kind)
            try container.encode(pinned, forKey: .pinned)
            try container.encode(appearance, forKey: .appearance)
            try container.encode(accentFill, forKey: .accentFill)
        }

        private enum CodingKeys: String, CodingKey {
            case active, kind, pinned, appearance, accentFill
        }

        /// `theme: Dimmed (dark), pinned`, or `theme: Default Light
        /// (light), follows the system`.
        var line: String {
            "theme: \(active) (\(kind)), \(pinned == nil ? "follows the system" : "pinned")"
        }

        /// What `theme set` prints.
        var setLine: String {
            pinned.map { "theme \($0) pinned" } ?? "theme follows the system (\(active))"
        }
    }

    /// One theme the app knows, in `theme list`.
    nonisolated struct ThemeEntry: Encodable, Equatable {
        var name: String
        var kind: String
        /// `built-in` or `user`.
        var source: String
        /// The file it was read from.
        var path: String?
        var active: Bool
        var pinned: Bool

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(kind, forKey: .kind)
            try container.encode(source, forKey: .source)
            try container.encode(path, forKey: .path)
            try container.encode(active, forKey: .active)
            try container.encode(pinned, forKey: .pinned)
        }

        private enum CodingKeys: String, CodingKey {
            case name, kind, source, path, active, pinned
        }
    }

    /// `theme list`: every theme, and the files left out with their reasons.
    nonisolated struct ThemeList: Encodable, Equatable {
        var themes: [ThemeEntry]
        var problems: [String]

        /// One line per theme: `Dimmed  dark  built-in  active, pinned`,
        /// then a line per file left out.
        var lines: String {
            let width = themes.map(\.name.count).max() ?? 0
            let rows = themes.map { entry in
                let marks = [entry.active ? "active" : nil, entry.pinned ? "pinned" : nil].compactMap(\.self).joined(separator: ", ")
                return [entry.name.padding(toLength: width, withPad: " ", startingAt: 0), entry.kind.padding(toLength: 5, withPad: " ", startingAt: 0),
                        entry.source.padding(toLength: 8, withPad: " ", startingAt: 0), marks]
                    .joined(separator: "  ").trimmingCharacters(in: .whitespaces)
            }
            let left = problems.map { "left out: \($0)" }
            return (rows + left).joined(separator: "\n") + "\n"
        }
    }
}

/// The settings file as `state` reports it.
extension StateReport {
    nonisolated struct Config: Encodable, Equatable {
        /// `config.toml`.
        var path: String
        /// The person's own themes, beside it.
        var themes: String
        /// `config-status.json`, the verdict of the last reload.
        var status: String
        /// Whether the last reload read the file. While it is false the app
        /// runs with the last settings that read.
        var accepted: Bool
        var problems: [ConfigIssue]
        var warnings: [ConfigIssue]
        /// What the move from `settings.json` did, for the person.
        var notes: [String]
        /// The notice in the window; `null` while none is up.
        var notice: Notice?

        struct Notice: Encodable, Equatable {
            /// `moved` or `rejected`.
            var kind: String
            var title: String
            var lines: [String]
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(path, forKey: .path)
            try container.encode(themes, forKey: .themes)
            try container.encode(status, forKey: .status)
            try container.encode(accepted, forKey: .accepted)
            try container.encode(problems, forKey: .problems)
            try container.encode(warnings, forKey: .warnings)
            try container.encode(notes, forKey: .notes)
            try container.encode(notice, forKey: .notice)
        }

        private enum CodingKeys: String, CodingKey {
            case path, themes, status, accepted, problems, warnings, notes, notice
        }

        /// `config: /…/config.toml, applied`, or `config: /…/config.toml,
        /// not applied` and a line per problem.
        var lines: String {
            let head = "config: \(path), \(accepted ? "applied" : "not applied, the last valid settings stay")"
            return ([head] + problems.map { "  problem, \($0.description)" } + warnings.map { "  warning, \($0.description)" })
                .joined(separator: "\n")
        }
    }
}
