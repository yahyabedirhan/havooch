import AppKit
import Foundation
import Observation
import ReviewCore
import ReviewStore

/// The active theme: the catalog of built-in and user themes, the pin and
/// the overrides from `settings.json`, and the system appearance. It
/// watches the theme files and the settings, and resolves the theme again
/// when one changes, so a person who edits a theme file sees it at once.
@Observable
final class ThemeDesk {
    /// The theme every view draws with.
    private(set) var theme: ResolvedTheme
    private(set) var catalog: ThemeCatalog
    private(set) var settings: Settings
    /// The system appearance, which picks Default Light or Default Dark
    /// while no theme is pinned.
    private(set) var appearance: ThemeKind
    /// Why `settings.json` didn't read; nil while it reads or isn't there.
    /// A pin isn't written over a file that doesn't read.
    private(set) var settingsProblem: String?

    /// The word `theme set` takes to unpin.
    static let system = "system"

    @ObservationIgnored private let layout: SupportLayout
    @ObservationIgnored private let builtInFolder: URL?
    /// Where each theme was read from, by name, for `theme list`.
    @ObservationIgnored private var paths: [String: URL] = [:]
    @ObservationIgnored private var watchers: [any DispatchSourceFileSystemObject] = []
    @ObservationIgnored private var pendingReload: Task<Void, Never>?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    /// Why each theme file or `settings.json` left out was left out.
    @ObservationIgnored private(set) var problems: [String] = []
    /// The problems already written to standard error, so each shows once.
    @ObservationIgnored private var reported: Set<String> = []
    /// `settings.json` as the last reload found it: a change in the support
    /// folder reloads only when this differs, so the outbox's and the
    /// reviews' saves there don't.
    @ObservationIgnored private var settingsStamp: FileStamp?
    /// How many times the themes and the settings were read.
    @ObservationIgnored private(set) var reloads = 0

    /// Reads the themes and the settings once. Nothing is watched until
    /// `startWatching`.
    init(layout: SupportLayout, builtIn builtInFolder: URL? = ThemeDesk.builtInFolder, appearance: ThemeKind = .light) {
        self.layout = layout
        self.builtInFolder = builtInFolder
        self.appearance = appearance
        catalog = ThemeCatalog(builtIn: [], user: [])
        settings = Settings()
        theme = ResolvedTheme(name: "", kind: appearance, colors: [:])
        reload()
    }

    /// The built-in themes: in the app bundle's resources, or in the
    /// source tree's `Packaging/Themes/` for a build that isn't bundled
    /// (`swift test`, `swift run`).
    static var builtInFolder: URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Themes", isDirectory: true)
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Packaging/Themes", isDirectory: true)
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }

    /// The name of the pinned theme as it is in the catalog; nil while the
    /// theme follows the system, or the pinned theme is gone.
    var pinned: String? {
        settings.theme.flatMap { catalog.entry(named: $0)?.name }
    }

    // MARK: - Changes

    /// Reads the theme files and the settings again and resolves the
    /// active theme. A theme or a settings file that doesn't read is left
    /// out, with a line on standard error.
    func reload() {
        reloads += 1
        settingsStamp = FileStamp(layout.settingsFile)
        let builtIn = builtInFolder.map(ThemeFiles.read) ?? ThemeFiles.Reading()
        let user = ThemeFiles.user(layout)
        let catalog = ThemeCatalog(builtIn: builtIn.files, user: user.files)
        var settings = self.settings
        var settingsProblem: String?
        do throws(Library.Failure) {
            settings = try Settings.load(layout)
        } catch {
            settingsProblem = error.reason
        }
        var paths: [String: URL] = [:]
        for found in builtIn.found + user.found { paths[found.file.name.lowercased()] = found.url }
        self.paths = paths
        if catalog != self.catalog { self.catalog = catalog }
        if settings != self.settings { self.settings = settings }
        if settingsProblem != self.settingsProblem { self.settingsProblem = settingsProblem }
        problems = builtIn.problems + user.problems + catalog.problems + [settingsProblem].compactMap(\.self)
        report(problems)
        resolve()
    }

    /// The system appearance changed.
    func setAppearance(_ appearance: ThemeKind) {
        guard appearance != self.appearance else { return }
        self.appearance = appearance
        resolve()
    }

    /// Pins the theme called `name`, or unpins for `system`, and keeps the
    /// choice in `settings.json`. Returns the name of the theme now active.
    @discardableResult
    func set(_ name: String) throws(AppRefusal) -> String {
        var next = settings
        if name.lowercased() == Self.system {
            next.theme = nil
        } else {
            guard let entry = catalog.entry(named: name) else { throw AppRefusal(ThemeRefusal.unknown(name).line) }
            next.theme = entry.name
        }
        if let settingsProblem { throw AppRefusal(settingsProblem) }
        do throws(Library.Failure) {
            try next.save(layout)
        } catch {
            throw AppRefusal(error.reason)
        }
        reload()
        return theme.name
    }

    /// Keeps the sidebar's `width` in `settings.json`, beside the theme.
    /// A settings file that doesn't read is left as it is.
    func keepSidebarWidth(_ width: Double) throws(AppRefusal) {
        if let settingsProblem { throw AppRefusal(settingsProblem) }
        var next = settings
        next.sidebarWidth = width
        do throws(Library.Failure) {
            try next.save(layout)
        } catch {
            throw AppRefusal(error.reason)
        }
        settings = next
    }

    private func resolve() {
        let name = catalog.active(pinned: settings.theme, appearance: appearance)
        let resolved = (try? catalog.resolve(name, overrides: settings.overrides))
            ?? ResolvedTheme(name: name, kind: appearance, colors: [:])
        if resolved != theme { theme = resolved }
    }

    /// Each problem not reported before, on standard error.
    private func report(_ problems: [String]) {
        for problem in problems where !reported.contains(problem) {
            FileHandle.standardError.write(Data("Havooch: \(problem)\n".utf8))
        }
        reported = Set(problems)
    }

    // MARK: - Watching

    /// Follows the system appearance from now on: `NSApp`'s effective
    /// appearance, which a screenshot in another appearance changes too.
    func followSystemAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] app, _ in
            MainActor.assumeIsolated {
                let dark = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                self?.setAppearance(dark ? .dark : .light)
            }
        }
    }

    /// Watches `Themes/` and each file in it, and `settings.json`: a change
    /// reloads the themes a moment later. The support folder is watched for
    /// a `settings.json` that comes or is replaced, and nothing else in it.
    /// The folder `Themes/` is made, so a person finds where their themes
    /// go.
    func startWatching() {
        try? FileManager.default.createDirectory(at: layout.themesFolder, withIntermediateDirectories: true)
        rearm()
    }

    /// Stops every watch.
    func stopWatching() {
        for watcher in watchers { watcher.cancel() }
        watchers = []
        pendingReload?.cancel()
        appearanceObservation = nil
    }

    /// Watches the folders and the files there are now. A file written by
    /// replacing it (as most editors save) is a new file: the watches are
    /// made again after each reload.
    private func rearm() {
        for watcher in watchers { watcher.cancel() }
        let targets = [layout.themesFolder, layout.settingsFile] + ThemeFiles.jsonFiles(in: layout.themesFolder)
        watchers = targets.compactMap { watch($0) }
        // The outbox and every review are saved in the support folder too:
        // only a `settings.json` other than the one last read is a change.
        let settings = layout.settingsFile
        let root = watch(layout.root) { [weak self] in
            self.map { FileStamp(settings) != $0.settingsStamp } ?? false
        }
        if let root { watchers.append(root) }
    }

    private func watch(
        _ url: URL, when isChange: @escaping @MainActor () -> Bool = { true }
    ) -> (any DispatchSourceFileSystemObject)? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                if isChange() { self?.changed() }
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    /// A watched file changed: reload once things settle, since an editor
    /// writes a file in more than one step.
    private func changed() {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            self.reload()
            self.rearm()
        }
    }

    // MARK: - Reports

    /// The theme as `state` reports it.
    var report: StateReport.Theme {
        StateReport.Theme(
            active: theme.name, kind: theme.kind.rawValue, pinned: pinned, appearance: appearance.rawValue,
            overrides: settings.overrides.count
        )
    }

    /// Every theme as `theme list` reports it, with the ones left out.
    var list: StateReport.ThemeList {
        let pinned = pinned
        return StateReport.ThemeList(
            themes: catalog.entries.map { entry in
                StateReport.ThemeEntry(
                    name: entry.name, kind: entry.file.kind.rawValue, source: entry.source.rawValue,
                    path: paths[entry.name.lowercased()]?.path, active: entry.name == theme.name, pinned: entry.name == pinned
                )
            },
            problems: problems
        )
    }
}

/// A file as far as a watch needs it: which file it is and when it was
/// last written. Nil for a file that isn't there.
private struct FileStamp: Equatable {
    var number: Int
    var modified: Date

    init?(_ url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = attributes[.systemFileNumber] as? Int,
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        self.number = number
        self.modified = modified
    }
}

// MARK: - The model's theme actions

extension AppModel {
    func themeList() -> StateReport.ThemeList {
        themes.list
    }

    /// Pins a theme, or follows the system for `system`.
    func setTheme(_ name: String) throws(AppRefusal) -> StateReport.Theme {
        try themes.set(name)
        return themes.report
    }
}
