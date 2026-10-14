import Foundation
import Observation
import ReviewConfig
import ReviewCore
import ReviewStore

@Observable
final class ConfigDesk {
    struct Notice: Equatable {
        enum Kind: String, Equatable {
            case moved
            case rejected
        }

        var kind: Kind
        var title: String
        var lines: [String]
    }

    enum Outcome: Equatable {
        case changed
        case unchanged
        case rejected
    }

    let location: ConfigLocation
    private(set) var config = ConfigFile()
    private(set) var verdict: ConfigVerdict
    private(set) var notes: [String] = []
    private(set) var notice: Notice?

    @ObservationIgnored var applied: [@MainActor () -> Void] = []
    @ObservationIgnored private let support: URL
    @ObservationIgnored private var watcher: ConfigWatcher?
    @ObservationIgnored private(set) var reloads = 0

    init(location: ConfigLocation, layout: SupportLayout) {
        self.location = location
        support = layout.root
        verdict = ConfigVerdict(checked: Date(), config: location.file, configModified: nil, problems: [], warnings: [])
        do throws(ConfigWriteFailure) {
            try location.createIfMissing()
        } catch {
            notes.append("Havooch couldn't make \(location.file.path): \(error.reason).")
        }
        notes += moveFormerSettings(from: layout)
        if !notes.isEmpty {
            notice = Notice(kind: .moved, title: "Your settings moved to config.toml", lines: notes)
        }
        reload()
    }

    static func sentence(_ problem: ConfigIssue) -> String {
        let text = problem.description.prefix(1).uppercased() + problem.description.dropFirst()
        return text.hasSuffix(".") ? text : text + "."
    }

    @discardableResult
    func dismissNotice() -> Bool {
        defer { notice = nil }
        return notice != nil
    }

    @discardableResult
    func reload() -> Outcome {
        reloads += 1
        let (verdict, decoded) = location.check()
        let before = self.verdict
        self.verdict = verdict
        do throws(ConfigWriteFailure) {
            try verdict.write(in: support)
        } catch {
            FileHandle.standardError.write(Data("Havooch: \(error.reason)\n".utf8))
        }
        guard let decoded else {
            if before.problems != verdict.problems {
                notice = Notice(
                    kind: .rejected, title: "config.toml wasn't applied",
                    lines: verdict.problems.map(Self.sentence)
                        + ["Havooch keeps the last valid settings. Fix the file, then run havooch config check."]
                )
            }
            return .rejected
        }
        if notice?.kind == .rejected { notice = nil }
        guard decoded.config != config else { return .unchanged }
        config = decoded.config
        for action in applied { action() }
        return .changed
    }

    func setTheme(_ name: String?) throws(AppRefusal) {
        do throws(ConfigWriteFailure) {
            try location.setTheme(name)
        } catch {
            throw AppRefusal("\(location.file.path) wasn't changed: \(error.reason)")
        }
        reload()
    }

    func addProject(slug: String, title: String?, firstVersion: ProjectEntry.Version) throws(AppRefusal) {
        do throws(ConfigWriteFailure) {
            try location.addProject(slug: slug, title: title, firstVersion: firstVersion)
        } catch {
            throw AppRefusal("\(location.file.path) wasn't changed: \(error.reason)")
        }
        reload()
    }

    func addVersion(_ version: ProjectEntry.Version, toProject slug: String) throws(AppRefusal) {
        do throws(ConfigWriteFailure) {
            try location.addVersion(version, toProject: slug)
        } catch {
            throw AppRefusal("\(location.file.path) wasn't changed: \(error.reason)")
        }
        reload()
    }

    func outline(_ slug: String) -> ProjectOutline? {
        config.project(slug).map { outline(of: $0) }
    }

    func outline(of project: ProjectEntry) -> ProjectOutline {
        ProjectOutline(
            slug: project.slug, title: project.displayTitle,
            versions: project.versions.map {
                ProjectOutline.Version(path: location.expand($0.path).standardizedFileURL.path, label: $0.label)
            }
        )
    }

    private func moveFormerSettings(from layout: SupportLayout) -> [String] {
        var notes = moveFormerThemes(from: layout.formerThemesFolder)
        let former: Settings.Former?
        do throws(Library.Failure) {
            former = try Settings.former(layout)
        } catch {
            return notes + ["Havooch couldn't read the theme in settings.json: \(error.reason)."]
        }
        guard let former else { return notes }
        guard let decoded = try? location.read() else {
            return notes + ["The theme in settings.json moves into config.toml once config.toml reads. Run havooch config check."]
        }
        if decoded.config.theme == nil, let theme = former.theme {
            do throws(ConfigWriteFailure) {
                try location.setTheme(theme)
            } catch {
                return notes + ["The theme in settings.json didn't move into config.toml: \(error.reason)."]
            }
        }
        if !former.overrides.isEmpty {
            let count = former.overrides.count
            notes.append(
                (count == 1
                    ? "The 1 token override in settings.json no longer applies. To keep it,"
                    : "The \(count) token overrides in settings.json no longer apply. To keep them,")
                    + " write a theme that extends another in \(location.themesFolder.path)."
            )
        }
        if let kept = try? Settings.load(layout) {
            try? kept.save(layout)
        }
        return notes
    }

    private func moveFormerThemes(from former: URL) -> [String] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: former, includingPropertiesForKeys: nil) else { return [] }
        var moved = 0
        var kept: [String] = []
        for file in files where file.lastPathComponent != ".DS_Store" {
            let target = location.themesFolder.appendingPathComponent(file.lastPathComponent)
            do {
                try fileManager.createDirectory(at: location.themesFolder, withIntermediateDirectories: true)
                guard !fileManager.fileExists(atPath: target.path) else {
                    kept.append(file.lastPathComponent)
                    continue
                }
                try fileManager.moveItem(at: file, to: target)
                if file.pathExtension.lowercased() == "json" { moved += 1 }
            } catch {
                kept.append(file.lastPathComponent)
            }
        }
        if kept.isEmpty { try? fileManager.removeItem(at: former) }
        var notes: [String] = []
        if moved > 0 {
            notes.append("Your \(moved == 1 ? "theme" : "\(moved) themes") moved to \(location.themesFolder.path).")
        }
        if !kept.isEmpty {
            notes.append("\(kept.joined(separator: ", ")) stayed in \(former.path): \(location.themesFolder.path) has a file of that name.")
        }
        return notes
    }

    func startWatching() {
        let watcher = ConfigWatcher(file: location.file) { [weak self] in self?.reload() }
        watcher.start()
        self.watcher = watcher
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    var report: StateReport.Config {
        StateReport.Config(
            path: location.file.path, themes: location.themesFolder.path,
            status: support.appendingPathComponent(ConfigVerdict.fileName).path,
            accepted: verdict.accepted, problems: verdict.problems, warnings: verdict.warnings, notes: notes,
            notice: notice.map { StateReport.Config.Notice(kind: $0.kind.rawValue, title: $0.title, lines: $0.lines) }
        )
    }
}

final class ConfigWatcher {
    private let file: URL
    private let onChange: @MainActor () -> Void
    nonisolated(unsafe) private var folderSource: (any DispatchSourceFileSystemObject)?
    nonisolated(unsafe) private var fileSource: (any DispatchSourceFileSystemObject)?
    private var pending: Task<Void, Never>?

    init(file: URL, onChange: @escaping @MainActor () -> Void) {
        self.file = file
        self.onChange = onChange
    }

    deinit {
        folderSource?.cancel()
        fileSource?.cancel()
    }

    func start() {
        watch()
    }

    func stop() {
        pending?.cancel()
        pending = nil
        folderSource?.cancel()
        fileSource?.cancel()
        folderSource = nil
        fileSource = nil
    }

    private func watch() {
        folderSource?.cancel()
        fileSource?.cancel()
        folderSource = source(at: Self.nearestExisting(file.deletingLastPathComponent()), events: [.write, .delete, .rename])
        fileSource = source(at: file, events: [.write, .extend, .delete, .rename, .attrib])
    }

    private func source(at url: URL, events: DispatchSource.FileSystemEvent) -> (any DispatchSourceFileSystemObject)? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func changed() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            self.watch()
            self.onChange()
        }
    }

    private static func nearestExisting(_ url: URL) -> URL {
        var candidate = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }
}
