import AppKit
import Foundation
import Observation
import ReviewCore
import ReviewStore

@Observable
final class ThemeDesk {
    private(set) var theme: ResolvedTheme
    private(set) var catalog: ThemeCatalog
    private(set) var appearance: ThemeKind

    static let system = "system"

    @ObservationIgnored let config: ConfigDesk
    @ObservationIgnored private let userFolder: URL
    @ObservationIgnored private let builtInFolder: URL?
    @ObservationIgnored private var paths: [String: URL] = [:]
    @ObservationIgnored private var watchers: [any DispatchSourceFileSystemObject] = []
    @ObservationIgnored private var pendingReload: Task<Void, Never>?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private(set) var problems: [String] = []
    @ObservationIgnored private var reported: Set<String> = []
    @ObservationIgnored private(set) var reloads = 0

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

    static var builtInFolder: URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Themes", isDirectory: true)
        if let bundled, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Packaging/Themes", isDirectory: true)
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }

    var pinned: String? {
        config.config.theme.flatMap { catalog.entry(named: $0)?.name }
    }

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

    func setAppearance(_ appearance: ThemeKind) {
        guard appearance != self.appearance else { return }
        self.appearance = appearance
        resolve()
    }

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

    private func report(_ problems: [String]) {
        for problem in problems where !reported.contains(problem) {
            FileHandle.standardError.write(Data("Havooch: \(problem)\n".utf8))
        }
        reported = Set(problems)
    }

    func followSystemAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] app, _ in
            MainActor.assumeIsolated {
                let dark = app.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                self?.setAppearance(dark ? .dark : .light)
            }
        }
    }

    func startWatching() {
        try? FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
        rearm()
    }

    func stopWatching() {
        for watcher in watchers { watcher.cancel() }
        watchers = []
        pendingReload?.cancel()
        appearanceObservation = nil
    }

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

    private func changed() {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            self.reload()
            self.rearm()
        }
    }

    var report: StateReport.Theme {
        StateReport.Theme(
            active: theme.name, kind: theme.kind.rawValue, pinned: pinned, appearance: appearance.rawValue,
            accentFill: theme[.accentFill]?.text
        )
    }

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

extension AppModel {
    func themeList() -> StateReport.ThemeList {
        themes.list
    }

    func setTheme(_ name: String) throws(AppRefusal) -> StateReport.Theme {
        try themes.set(name)
        return themes.report
    }
}
