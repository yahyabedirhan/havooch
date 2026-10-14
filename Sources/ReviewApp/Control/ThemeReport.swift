import Foundation
import ReviewConfig

extension StateReport {
    nonisolated struct Theme: Encodable, Equatable {
        var active: String
        var kind: String
        var pinned: String?
        var appearance: String
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

        var line: String {
            "theme: \(active) (\(kind)), \(pinned == nil ? "follows the system" : "pinned")"
        }

        var setLine: String {
            pinned.map { "theme \($0) pinned" } ?? "theme follows the system (\(active))"
        }
    }

    nonisolated struct ThemeEntry: Encodable, Equatable {
        var name: String
        var kind: String
        var source: String
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

    nonisolated struct ThemeList: Encodable, Equatable {
        var themes: [ThemeEntry]
        var problems: [String]

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

extension StateReport {
    nonisolated struct Config: Encodable, Equatable {
        var path: String
        var themes: String
        var status: String
        var accepted: Bool
        var problems: [ConfigIssue]
        var warnings: [ConfigIssue]
        var notes: [String]
        var notice: Notice?

        struct Notice: Encodable, Equatable {
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

        var lines: String {
            let head = "config: \(path), \(accepted ? "applied" : "not applied, the last valid settings stay")"
            return ([head] + problems.map { "  problem, \($0.description)" } + warnings.map { "  warning, \($0.description)" })
                .joined(separator: "\n")
        }
    }
}
