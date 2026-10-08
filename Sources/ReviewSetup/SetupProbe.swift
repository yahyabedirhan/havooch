import Foundation

/// What Havooch can say of a setup step or a harness. There is no
/// "missing": what isn't detected may be set up in a way Havooch can't see
/// (ADR 0005).
public enum Detection: String, Equatable, Sendable, CaseIterable {
    /// Havooch found it.
    case detected
    /// Havooch looked and didn't find it.
    case notDetected
    /// Havooch couldn't look: a folder on the way doesn't read.
    case cannotKnow
}

/// One harness as the probe found it.
public struct HarnessSetup: Equatable, Sendable {
    public var harness: Harness
    /// Whether the harness looks installed: a best guess.
    public var presence: Detection
    /// Whether `havooch-mate` is in one of its user skills folders.
    public var skill: Detection
    /// The skill's folder when it's detected.
    public var skillFolder: String?

    public init(harness: Harness, presence: Detection, skill: Detection, skillFolder: String? = nil) {
        self.harness = harness
        self.presence = presence
        self.skill = skill
        self.skillFolder = skillFolder
    }
}

/// Everything setup detected at one time.
public struct SetupReport: Equatable, Sendable {
    public var commandLine: CommandLink.State
    /// One per harness of the catalog, in its order.
    public var harnesses: [HarnessSetup]

    public init(commandLine: CommandLink.State, harnesses: [HarnessSetup]) {
        self.commandLine = commandLine
        self.harnesses = harnesses
    }

    /// The harnesses an install is for when none is named: those found
    /// installed whose skill isn't detected.
    public var harnessesLackingSkill: [Harness] {
        harnesses.filter { $0.presence == .detected && $0.skill != .detected }.map(\.harness)
    }
}

/// Reads what is on disk: the command link, the skill in each harness's
/// user skills folders, and each harness's presence. Only the home folder's
/// user-level places and the usual app and command folders are looked in:
/// never a repository. It changes nothing.
public struct SetupProbe: Sendable {
    public var fileSystem: any SetupFileSystem
    /// The person's home folder, which relative catalog paths start from.
    public var home: String
    public var catalog: [Harness]

    public init(fileSystem: any SetupFileSystem = LocalFileSystem(), home: String, catalog: [Harness] = HarnessCatalog.all) {
        self.fileSystem = fileSystem
        self.home = home
        self.catalog = catalog
    }

    public func probe() -> SetupReport {
        SetupReport(
            commandLine: CommandLink(fileSystem: fileSystem, home: home).state(),
            harnesses: catalog.map(setup(of:))
        )
    }

    private func setup(of harness: Harness) -> HarnessSetup {
        var skill = Detection.notDetected
        var skillFolder: String?
        for folder in harness.skillsFolders.map(path) {
            let skillFolderPath = "\(folder)/\(HarnessCatalog.skill)"
            switch fileSystem.target(at: "\(skillFolderPath)/SKILL.md") {
            case .file:
                skill = .detected
                skillFolder = skillFolderPath
            case .unreadable:
                skill = .cannotKnow
            case .missing, .folder, .link:
                continue
            }
            if skill == .detected { break }
        }
        let presence = Self.any(harness.presenceHints.map(path)) { fileSystem.target(at: $0) }
        return HarnessSetup(harness: harness, presence: presence, skill: skill, skillFolder: skillFolder)
    }

    /// Detected when any path exists; can't know when none does and one
    /// doesn't read; else not detected.
    private static func any(_ paths: [String], _ item: (String) -> FileItem) -> Detection {
        var answer = Detection.notDetected
        for path in paths {
            switch item(path) {
            case .file, .folder, .link: return .detected
            case .unreadable: answer = .cannotKnow
            case .missing: continue
            }
        }
        return answer
    }

    /// `relative` from the home folder, or itself when it's absolute.
    func path(_ relative: String) -> String {
        relative.hasPrefix("/") ? relative : "\(home)/\(relative)"
    }
}
