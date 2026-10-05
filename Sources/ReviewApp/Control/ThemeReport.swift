import Foundation

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
        /// How many token overrides `settings.json` has.
        var overrides: Int

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(active, forKey: .active)
            try container.encode(kind, forKey: .kind)
            try container.encode(pinned, forKey: .pinned)
            try container.encode(appearance, forKey: .appearance)
            try container.encode(overrides, forKey: .overrides)
        }

        private enum CodingKeys: String, CodingKey {
            case active, kind, pinned, appearance, overrides
        }

        /// `theme: Dimmed (dark), pinned, 2 overrides`, or `theme: Default
        /// Light (light), follows the system`.
        var line: String {
            let choice = pinned == nil ? "follows the system" : "pinned"
            let overrideWords = overrides == 0 ? "" : ", \(overrides) override\(overrides == 1 ? "" : "s")"
            return "theme: \(active) (\(kind)), \(choice)\(overrideWords)"
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
