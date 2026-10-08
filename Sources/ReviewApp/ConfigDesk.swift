import Foundation
import Observation
import ReviewConfig
import ReviewStore

/// `config.toml` as the app runs it (ADR 0002): the last valid settings,
/// the verdict of the last reload, and the targeted writes. It watches the
/// file and applies each valid save at once; a save with a problem keeps
/// the last valid settings. After every reload it writes the verdict to
/// `config-status.json` in the support folder, for agents.
///
/// On its first run on a support folder it moves what older builds kept
/// there: the pinned theme of `settings.json` into the file, the person's
/// themes into `themes/` beside it. Token overrides are dropped, with a
/// note (decision P7).
///
/// What the person needs to know shows as a notice in the window, which
/// never blocks: what the move did, and a new set of problems. Its close
/// button and `havooch config dismiss` close it.
@Observable
final class ConfigDesk {
    /// The settings notice in the window.
    struct Notice: Equatable {
        enum Kind: String, Equatable {
            /// What the move from an older build did.
            case moved
            /// The last save has problems; the last valid settings stay.
            case rejected
        }

        var kind: Kind
        var title: String
        /// One sentence or problem per line.
        var lines: [String]
    }

    /// What a reload did to the settings.
    enum Outcome: Equatable {
        /// The file read as other settings, which replaced the last ones.
        case changed
        /// The file read as the settings the app already runs with.
        case unchanged
        /// The file has a problem: the last valid settings stay.
        case rejected
    }

    let location: ConfigLocation
    /// The last settings the file read as: every default until a reload
    /// accepts the file.
    private(set) var config = ConfigFile()
    /// The verdict of the last reload.
    private(set) var verdict: ConfigVerdict
    /// What the move from an older build did that the person needs to
    /// know, one sentence each; empty when nothing moved.
    private(set) var notes: [String] = []
    /// The notice in the window; nil while none is up.
    private(set) var notice: Notice?

    /// Called after a reload replaced the settings, the theme desk first.
    @ObservationIgnored var applied: [@MainActor () -> Void] = []
    /// The folder `config-status.json` goes to: the support folder.
    @ObservationIgnored private let support: URL
    @ObservationIgnored private var watcher: ConfigWatcher?
    /// How many times the file was read.
    @ObservationIgnored private(set) var reloads = 0

    /// The settings at `location`: a missing file is made from the header,
    /// what older builds kept in the support folder `layout` moves into it
    /// once, and the file is read. Nothing is watched until `startWatching`.
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

    /// `line 4: …` as a sentence: a capital first, a full stop last.
    static func sentence(_ problem: ConfigIssue) -> String {
        let text = problem.description.prefix(1).uppercased() + problem.description.dropFirst()
        return text.hasSuffix(".") ? text : text + "."
    }

    /// Closes the notice; false when none was up.
    @discardableResult
    func dismissNotice() -> Bool {
        defer { notice = nil }
        return notice != nil
    }

    // MARK: - Reading

    /// Reads the file again, writes the verdict, and applies the settings
    /// when they read and differ from the ones the app runs with.
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
        // A file that reads again takes its problems' notice with it.
        if notice?.kind == .rejected { notice = nil }
        guard decoded.config != config else { return .unchanged }
        config = decoded.config
        for action in applied { action() }
        return .changed
    }

    // MARK: - Writing

    /// Pins the theme `name` in the file, or takes the pin out for nil,
    /// then reads the file again. Refused when the file has a problem: it
    /// is never written over.
    func setTheme(_ name: String?) throws(AppRefusal) {
        do throws(ConfigWriteFailure) {
            try location.setTheme(name)
        } catch {
            throw AppRefusal("\(location.file.path) wasn't changed: \(error.reason)")
        }
        reload()
    }

    // MARK: - Moving an older build's settings

    /// Moves what builds before `config.toml` kept in the support folder:
    /// the person's themes from `Themes/` to `themes/` beside the file, and
    /// the pinned theme from `settings.json` into the file, unless the file
    /// pins one already. The token overrides are dropped. `settings.json`
    /// then keeps only the sidebar width, so this happens once. While the
    /// file has a problem, `settings.json` waits for the next launch.
    /// Returns the notes for the person.
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
        // Read again, written without the theme and the overrides.
        if let kept = try? Settings.load(layout) {
            try? kept.save(layout)
        }
        return notes
    }

    /// Moves each file of `former` into the themes folder, and the folder
    /// goes once it's empty. A file whose name the themes folder has
    /// already stays where it is.
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

    // MARK: - Watching

    /// Watches the file: a save applies at once.
    func startWatching() {
        let watcher = ConfigWatcher(file: location.file) { [weak self] in self?.reload() }
        watcher.start()
        self.watcher = watcher
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    // MARK: - Reports

    /// The settings file as `state` reports it.
    var report: StateReport.Config {
        StateReport.Config(
            path: location.file.path, themes: location.themesFolder.path,
            status: support.appendingPathComponent(ConfigVerdict.fileName).path,
            accepted: verdict.accepted, problems: verdict.problems, warnings: verdict.warnings, notes: notes,
            notice: notice.map { StateReport.Config.Notice(kind: $0.kind.rawValue, title: $0.title, lines: $0.lines) }
        )
    }
}

/// Watches the settings file and calls `onChange` once changes have been
/// quiet for 200 ms. After Swift Lab's `ConfigurationWatcher`
/// (yahyabedirhan/swift-lab at ccb82cb), itself after Shipyard's.
///
/// Editors and agents usually save by writing a new file and renaming it
/// over the old one, which leaves a watch on the old file's descriptor
/// looking at a file that is gone. So the file's folder is watched, which
/// sees every create, rename and delete in it. An in-place write (`>>`)
/// does not touch the folder, so the file itself is watched too, and both
/// watches open again after every change. When the folder does not exist
/// yet, its nearest existing ancestor is watched instead.
///
/// Nothing the app writes on each reload may sit in the watched folder, or
/// each write would start another reload: the verdict goes to the support
/// folder.
final class ConfigWatcher {
    private let file: URL
    private let onChange: @MainActor () -> Void
    // Written on the main actor only; `deinit` cancels them, which closes the descriptors.
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

    /// Opens both watches again on whatever is at the paths now.
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

    /// Something changed: wait for the burst of events a save makes to end.
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

    /// `url`, or its closest ancestor that exists.
    private static func nearestExisting(_ url: URL) -> URL {
        var candidate = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }
}
