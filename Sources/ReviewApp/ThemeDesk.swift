import AppKit
import Foundation
import Observation
import ReviewCore
import ReviewStore

/// The active theme: the catalog of built-in and user themes, the pin
/// `config.toml` names (`ConfigDesk`), and the system appearance. It
/// watches the person's theme files, and resolves the theme again when one
/// changes or the settings file pins another, so a person who edits a
/// theme file sees it at once.
@Observable
final class ThemeDesk {
    /// The theme every view draws with.
    private(set) var theme: ResolvedTheme
    private(set) var catalog: ThemeCatalog
    /// The system appearance, which picks Default Light or Default Dark
    /// while no theme is pinned.
    private(set) var appearance: ThemeKind

    /// The word `theme set` takes to unpin.
    static let system = "system"

    /// The settings file, which names the pinned theme.
    @ObservationIgnored let config: ConfigDesk
    /// The person's own themes: `themes/` beside `config.toml`.
    @ObservationIgnored private let userFolder: URL
    @ObservationIgnored private let builtInFolder: URL?
    /// Where each theme was read from, by name, for `theme list`.
    @ObservationIgnored private var paths: [String: URL] = [:]
    @ObservationIgnored private var watchers: [any DispatchSourceFileSystemObject] = []
    @ObservationIgnored private var pendingReload: Task<Void, Never>?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    /// Why each theme file left out was left out, and a pin no theme has.
    @ObservationIgnored private(set) var problems: [String] = []
    /// The problems already written to standard error, so each shows once.
    @ObservationIgnored private var reported: Set<String> = []
    /// How many times the themes were read.
    @ObservationIgnored private(set) var reloads = 0

    /// Reads the themes once, and again each time `config` applies other
    /// settings. Theme files are not watched until `startWatching`.
    init(config: ConfigDesk, builtIn builtInFolder: URL? = ThemeDesk.builtInFolder, appearance: ThemeKind = .light) {
        self.config = config
        userFolder = config.location.themesFolder
        self.builtInFolder = builtInFolder
        self.appearance = appearance
        catalog = ThemeCatalog(builtIn: [], user: [])
        theme = ResolvedTheme(name: "", kind: appearance, colors: [:])
        reload()
        config.applied.append { [weak self] in self?.reload() }
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
        config.config.theme.flatMap { catalog.entry(named: $0)?.name }
    }

    // MARK: - Changes

    /// Reads the theme files again and resolves the active theme. A theme
    /// that doesn't read is left out, and a pin no theme has follows the
    /// system, each with a line on standard error.
    func reload() {
        reloads += 1
        let builtIn = builtInFolder.map(ThemeFiles.read) ?? ThemeFiles.Reading()
        let user = ThemeFiles.read(userFolder)
        let catalog = ThemeCatalog(builtIn: builtIn.files, user: user.files)
        var paths: [String: URL] = [:]
        for found in builtIn.found + user.found { paths[found.file.name.lowercased()] = found.url }
        self.paths = paths
        if catalog != self.catalog { self.catalog = catalog }
        let unknownPin = config.config.theme.flatMap { name in
            catalog.entry(named: name) == nil
                ? "config.toml pins the theme \(name), which no theme file has; the theme follows the system" : nil
        }
        problems = builtIn.problems + user.problems + catalog.problems + [unknownPin].compactMap(\.self)
        report(problems)
        resolve()
    }

    /// The system appearance changed.
    func setAppearance(_ appearance: ThemeKind) {
        guard appearance != self.appearance else { return }
        self.appearance = appearance
        resolve()
    }

    /// Pins the theme called `name`, or unpins for `system`: the `theme`
    /// line of `config.toml` is written, and nothing else in it. Returns
    /// the name of the theme now active. Refused for a theme the catalog
    /// doesn't have, and while `config.toml` has a problem.
    @discardableResult
    func set(_ name: String) throws(AppRefusal) -> String {
        var pin: String?
        if name.lowercased() != Self.system {
            guard let entry = catalog.entry(named: name) else { throw AppRefusal(ThemeRefusal.unknown(name).line) }
            pin = entry.name
        }
        try config.setTheme(pin)
        return theme.name
    }

    private func resolve() {
        let name = catalog.active(pinned: config.config.theme, appearance: appearance)
        let resolved = (try? catalog.resolve(name)) ?? ResolvedTheme(name: name, kind: appearance, colors: [:])
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

    /// Watches `themes/` and each file in it: a change reloads the themes a
    /// moment later. The folder is made, so a person finds where their
    /// themes go. `config.toml` is `ConfigDesk`'s to watch.
    func startWatching() {
        try? FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
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
        let targets = [userFolder] + ThemeFiles.jsonFiles(in: userFolder)
        watchers = targets.compactMap { watch($0) }
    }

    private func watch(_ url: URL) -> (any DispatchSourceFileSystemObject)? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
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
            accentFill: theme[.accentFill]?.text
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
