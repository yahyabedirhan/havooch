import AppKit
import Observation
import ReviewConfig
import ReviewCore
import ReviewStore
import ReviewTranscript
import ReviewWire
import UniformTypeIdentifiers

/// The app: its windows, the data the run is on, the theme and the recent
/// videos, and every action that is the app's and not one window's. A
/// window's own actions are its `WindowModel`'s. Opening a video for the
/// person finds its window here: the window that holds it comes forward,
/// else an empty key window takes it, else a new window does (ADR 0003).
@Observable
final class AppModel: AppControlling {
    /// The data the run is on now: the support folder it started on, or
    /// the demo folder while an in-app demo runs (L27). Every window is on it.
    private(set) var data: DataFolder
    /// The reviews of every window, and the one path for changing them.
    var desk: ReviewDesk { data.desk }
    /// The listeners, one per review: each window's video has its own
    /// sends in line and its own agent.
    var listeners: ListenerHub { data.listeners }
    /// The transcripts of the videos opened on this data in this run.
    var transcripts: TranscriptDesk { data.transcripts }
    /// `config.toml`: the settings a person or an agent sets on purpose,
    /// beside the folder the run started on (`ConfigLocation`), also during
    /// an in-app demo. App-wide: its notice shows in every window.
    let config: ConfigDesk
    /// The active theme and the pin `config.toml` names.
    let themes: ThemeDesk
    /// What Havooch detects of the person's setup, Link and the skill
    /// install: app-wide, whatever data the run is on.
    let setup: SetupDesk
    /// The sidebar's width the person left, in `settings.json` on the
    /// folder the run started on: app state, not a setting, the same in
    /// every window.
    private(set) var keptSidebarWidth: Double?
    /// Whether an agent ever connected on the person's data, kept in
    /// `settings.json`: setup then counts as working, whatever was
    /// detected (L57, ADR 0005).
    private(set) var agentConnectedOnce = false
    /// Whether the person used the app on their data, kept in
    /// `settings.json`: Get Started or a later step, Skip Setup, a video
    /// opened, or an agent connected. Until then the first-run window shows
    /// by itself at each launch (L65).
    private(set) var firstRunDone = false
    /// The first-run window: Welcome, Tools, Connect, Try it (H1).
    let firstRun: FirstRun
    /// Whether `settings.json` read at launch: one that doesn't is never
    /// written over.
    @ObservationIgnored private let settingsRead: Bool
    /// Where the run keeps its data now: the person's own, or a demo's.
    var support: URL { data.support }
    /// The folder the run started on: the person's, or the one
    /// `app open --demo` named. The control socket and the theme stay on
    /// it, and leaving an in-app demo comes back to it.
    let launchSupport: URL
    /// Where "Try the Demo" keeps the demo's data.
    let demoFolder: URL
    /// The video "Try the Demo" opens: the one bundled in the app, nil in
    /// a build that has none.
    let demoVideo: URL?
    /// Whether the run started on demo data (`app open --demo`).
    let isDemoRun: Bool
    /// Whether an in-app demo runs: "Try the Demo" switched the run to
    /// the demo folder.
    private(set) var isInAppDemo = false
    /// Whether the run is on demo data: started there, or in an in-app
    /// demo. The header's demo words follow it.
    var isDemo: Bool { isDemoRun || isInAppDemo }
    /// The windows, which one is key, and which one holds which video.
    let windows = WindowRegistry()
    /// Brings the app to the front once a window is forward, as `havooch
    /// open` does; the app sets it.
    @ObservationIgnored var bringToFront: (WindowModel) -> Void = { _ in }
    /// The content hashes of the files opened in this run, so opening one
    /// again skips reading it whole (L51).
    @ObservationIgnored let hashes = ContentHashCache()
    /// Turns a video's sound into lines, on every data folder of the run.
    @ObservationIgnored let speech: any SpeechRecognizing
    /// The recent videos' thumbnails, made as their cards first show and
    /// kept in memory for this run.
    let thumbnails = Thumbnails()
    /// Files Finder handed over before the launch's first scene appeared:
    /// they open as it appears.
    @ObservationIgnored private var filesWaiting: [URL] = []
    /// The latest files from Finder opening, so the next ones wait for them.
    @ObservationIgnored private var finderOpens: Task<Void, Never>?
    /// The notifications that tell which window is key and which closed.
    @ObservationIgnored private var watching: [any NSObjectProtocol] = []

    /// The files the Open panel offers: what the spec names.
    static let videoTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, UTType("com.apple.m4v-video")].compactMap(\.self)

    /// The run on the support folder `environment` names: demo data when
    /// `app open --demo` launched it (`SupportFolder.isDemoRun`). `speech`
    /// turns a video's sound into lines when it has no sidecar, and
    /// `demoFolder` is where "Try the Demo" keeps its data and
    /// `demoVideo` the video it opens; tests give their own, and their own
    /// `setup` on a fake file system.
    init(
        environment: [String: String], speech: any SpeechRecognizing = AppleSpeechRecognizer(),
        demoFolder: URL = DemoRun.folder(), demoVideo: URL? = DemoRun.video(), setup: SetupDesk? = nil
    ) {
        launchSupport = SupportFolder.app(environment: environment)
        isDemoRun = SupportFolder.isDemoRun(environment: environment)
        self.demoFolder = demoFolder
        self.demoVideo = demoVideo
        self.speech = speech
        data = DataFolder(support: launchSupport, speech: speech)
        let launchLayout = SupportLayout(root: launchSupport)
        config = ConfigDesk(
            location: ConfigLocation(variables: environment, movedSupport: SupportFolder.moved(environment: environment)),
            layout: launchLayout
        )
        themes = ThemeDesk(config: config)
        self.setup = setup ?? SetupDesk(environment: environment)
        firstRun = FirstRun(setup: self.setup)
        do throws(Library.Failure) {
            let settings = try Settings.load(launchLayout)
            keptSidebarWidth = settings.sidebarWidth
            agentConnectedOnce = settings.agentConnectedOnce ?? false
            firstRunDone = settings.firstRunDone ?? false
            settingsRead = true
        } catch {
            settingsRead = false
        }
        listenToAgent()
        firstRun.used = { [weak self] in self?.markFirstRunDone() }
    }

    /// The settings notice's close button, in any window, and `config dismiss`.
    @discardableResult
    func dismissConfigNotice() -> Bool {
        config.dismissNotice()
    }

    /// What an agent says on the data the run is on, and a takeover, shows
    /// as a notice in the window that holds its video; a bare thread
    /// number is the key window's.
    private func listenToAgent() {
        listeners.announce = { [weak self] key, notice in self?.windows.holding(key)?.raise(notice) }
        listeners.keyReview = { [weak self] in self?.windows.key?.reviewKey }
        listeners.outline = { [weak self] slug in self?.config.outline(slug) }
        listeners.connected = { [weak self] key in self?.agentConnected(to: key) }
    }

    /// An agent's `wait` opened on the review `key`: setup works, so the
    /// connect button's dot goes for good. An agent on the in-app demo
    /// counts too: it runs in the person's own harness. The tour of the
    /// window that holds the review moves on from its connect step.
    private func agentConnected(to key: ReviewKey) {
        windows.holding(key)?.tourNoticedAgent()
        markFirstRunDone()
        guard !agentConnectedOnce else { return }
        agentConnectedOnce = true
        saveSettings()
    }

    // MARK: - Listeners

    /// The review a `wait` listens to: the review the video at `path`
    /// (`--video`) opens in, as `open` resolves it (its project, else the
    /// plain video), open in a window or not; the project `project`
    /// (`--project`); with neither, the key window's (L56). Refused for a
    /// path with no file, a project `config.toml` doesn't have, and with
    /// neither when the key window holds no video.
    func listenedReview(video path: String?, project: String? = nil) async throws(AppRefusal) -> ReviewKey {
        if let project {
            try needProject(project)
            return .project(slug: project)
        }
        if let path {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            try Self.needFile(url)
            guard let hash = await WindowModel.contentHash(of: url, in: hashes) else {
                throw AppRefusal("can't read \(url.path)")
            }
            return try resolveTarget(url, contentHash: hash, project: nil).reviewKey
        }
        guard let key = windows.key?.reviewKey else {
            throw AppRefusal("no window holds a video to listen to; name one with `havooch wait --video <path>`")
        }
        return key
    }

    // MARK: - Windows

    /// A new window, holding nothing, among the app's windows. A scene
    /// that appears with no window waiting for it shows one; tests use it
    /// with no scene.
    @discardableResult
    func makeWindow() -> WindowModel {
        let window = WindowModel(app: self, id: windows.nextID())
        windows.add(window)
        return window
    }

    /// File › New Window, the Dock icon with no window, and `window new`:
    /// a new empty window, which shows the home screen.
    @discardableResult
    func newWindow() -> WindowModel {
        let window = makeWindow()
        windows.show(window)
        return window
    }

    /// A window's scene appeared with `target`: the window made for it,
    /// else a new empty one. Files Finder handed over before any scene
    /// could open (a launch by Open With) open now (`openFromFinder`).
    func sceneAppeared(target: WindowTarget?) -> WindowModel {
        let window = windows.place(target) ?? makeWindow()
        if !filesWaiting.isEmpty, windows.openScene != nil {
            let files = filesWaiting
            filesWaiting = []
            openFromFinder(files)
        }
        return window
    }

    /// `nsWindow` shows `window` now.
    func attach(_ nsWindow: NSWindow, to window: WindowModel) {
        guard window.nsWindow !== nsWindow else { return }
        window.nsWindow = nsWindow
        if nsWindow.isKeyWindow { windows.becameKey(window) }
    }

    /// `window` closed: its video pauses, keeps its position for its
    /// recent-video entry, and the window is gone. The app keeps running.
    func windowClosed(_ window: WindowModel) {
        window.closed()
        windows.remove(window)
    }

    /// `window` comes forward and becomes key.
    func focus(_ window: WindowModel) {
        window.nsWindow?.makeKeyAndOrderFront(nil)
        windows.becameKey(window)
    }

    /// Starts following which window is key and which closes, for as
    /// long as the app runs.
    func watchWindows() {
        let center = NotificationCenter.default
        watching.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            let nsWindow = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let window = self.windows.window(showing: nsWindow) else { return }
                self.windows.becameKey(window)
            }
        })
        watching.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            let nsWindow = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let window = self.windows.window(showing: nsWindow) else { return }
                self.windowClosed(window)
            }
        })
    }

    /// The window an operator command acts on: the one `id` names, else
    /// the key window. With `making`, a command that shows something (a
    /// video, home, the demo) makes a new window when there is none.
    func window(_ id: String?, making: Bool = false) throws(AppRefusal) -> WindowModel {
        if let id {
            guard let window = windows.window(id) else {
                throw AppRefusal("no window `\(id)`; the windows are \(windows.names)")
            }
            return window
        }
        if let key = windows.key { return key }
        guard making else { throw AppRefusal("no window is open; open one with `havooch window new`") }
        return newWindow()
    }

    func controlledWindow(_ id: String?, making: Bool) throws(AppRefusal) -> any WindowControlling {
        try window(id, making: making)
    }

    /// `window list`: every window, in the order they were made.
    func windowList() -> [StateReport.Window] {
        let key = windows.key
        return windows.windows.map { $0.report(isKey: $0 === key) }
    }

    /// `window new`.
    func openWindow() -> StateReport.Window {
        let window = newWindow()
        return window.report(isKey: window === windows.key)
    }

    /// `window close`: the window `id` names, else the key window, closes
    /// as its close button closes it. Its report, as it was.
    func closeWindow(_ id: String?) throws(AppRefusal) -> StateReport.Window {
        let window = try window(id)
        let report = window.report(isKey: window === windows.key)
        window.nsWindow?.close()
        // A window with no scene, or one that didn't close, goes all the same.
        if windows.window(window.id) != nil {
            window.nsWindow?.orderOut(nil)
            windowClosed(window)
        }
        return report
    }

    /// `state`: the window `id` names, else the key window, with every
    /// window. With no window open, the app with no video.
    func state(window id: String?) throws(AppRefusal) -> StateReport {
        if id == nil, windows.windows.isEmpty {
            var report = StateReport(
                app: appReport, video: nil, player: StateReport.Player(time: 0, playing: false)
            )
            report.theme = themes.report
            report.setup = setupReport
            report.firstRun = firstRunReport
            report.config = config.report
            report.recents = recents
            report.projects = homeProjects
            report.screen = .none
            return report
        }
        return try window(id).state()
    }

    /// The app as `state` reports it.
    var appReport: StateReport.App {
        StateReport.App(version: Version.app, demo: isDemo, support: support.path, active: NSApp?.isActive ?? false)
    }

    // MARK: - Opening a video for the person

    /// `havooch open`, and Finder's Open With (`openFromFinder`): opens `url`
    /// for the person, playing, in front. The window that holds the video
    /// comes forward; else the key window takes it when it's empty; else a
    /// new window does. A file that doesn't play is refused before anything
    /// changes: an in-app demo stays, and every window stays as it was. No
    /// lease: it's the person's open, whoever asks for it.
    @discardableResult
    func openInFront(_ url: URL, project: String? = nil) async throws(AppRefusal) -> any WindowControlling {
        let url = url.standardizedFileURL
        try Self.needFile(url)
        if let project { try needProject(project) }
        try await PlayerEngine.checkPlayable(url)
        // The person's video, on their own data, as the Open panel opens it.
        await leaveDemo()
        let window = try await windowFor(url, project: project, from: nil)
        // Play is a change of the moment: words in a popover of the window
        // that held the video already are queued first.
        try window.play()
        focus(window)
        bringToFront(window)
        return window
    }

    /// Finder's Open With, a drop on the Dock icon and `open -a Havooch
    /// <file>` (decision C3): each file opens as `havooch open` opens it
    /// (`openInFront`), one after the other, so the first fills an empty
    /// key window and the next ones open in new windows. A file that
    /// doesn't play shows why in the key window, or in a new one with
    /// none. Before the launch's first scene appears no window can show,
    /// so the files wait for it (`sceneAppeared`). Returns the opens, for
    /// tests to wait on; nil while the files wait.
    @discardableResult
    func openFromFinder(_ urls: [URL]) -> Task<Void, Never>? {
        guard windows.openScene != nil else {
            filesWaiting += urls
            return nil
        }
        // Opens one after another, also across two handovers in a row.
        let previous = finderOpens
        let opens = Task {
            await previous?.value
            for url in urls {
                do throws(AppRefusal) {
                    try await openInFront(url)
                } catch {
                    (windows.key ?? newWindow()).problem = WindowModel.Problem(
                        title: "The video didn't open", reason: error.reason
                    )
                }
            }
        }
        finderOpens = opens
        return opens
    }

    /// The Open panel, a drop and a recent video's card in `window` (nil
    /// with no window): opens `url` for the person, who is shown why when
    /// it doesn't play. An in-app demo is left first. The window that
    /// holds the video comes forward; else `window` opens it.
    func openForPerson(_ url: URL, from window: WindowModel?) {
        Task {
            await leaveDemo()
            do throws(AppRefusal) {
                let opened = try await windowFor(url.standardizedFileURL, from: window)
                focus(opened)
            } catch {
                (window ?? windows.key)?.problem = WindowModel.Problem(title: "The video didn't open", reason: error.reason)
            }
        }
    }

    /// Cmd+O and the Open button, in `window` or with none: the file the
    /// person picks.
    func openFromPanel(from window: WindowModel?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.videoTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a video to review"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openForPerson(url, from: window)
    }

    /// The window `url` opens in, with it open there, in the project
    /// `project` when it's set, else in the review `resolveTarget` picks:
    /// the window that holds that video or project, showing `url`; else
    /// `from`; else the key window when it holds nothing; else a new window.
    private func windowFor(_ url: URL, project: String? = nil, from: WindowModel?) async throws(AppRefusal) -> WindowModel {
        try Self.needFile(url)
        guard let hash = await WindowModel.contentHash(of: url, in: hashes) else {
            throw AppRefusal("can't read \(url.path)")
        }
        let target = try resolveTarget(url, contentHash: hash, project: project)
        let slug = target.reviewKey.slug
        if let holder = windows.holding(target.reviewKey) {
            // A project's window shows the version asked for.
            if slug != nil, holder.video?.url != url { try await holder.open(url, project: slug) }
            return holder
        }
        if let window = from ?? windows.key.flatMap({ $0.video == nil ? $0 : nil }) {
            try await window.open(url, project: slug)
            return window
        }
        let window = makeWindow()
        do throws(AppRefusal) {
            try await window.open(url, project: slug)
        } catch {
            windows.remove(window)
            throw error
        }
        windows.show(window)
        return window
    }

    // MARK: - Projects (ADR 0004)

    /// What the video at `url` with `contentHash` opens as (decision C4):
    /// the project `project` when it's set, which must list the file; else
    /// the most recently opened project that lists it; else the plain
    /// video. Refused for a project `config.toml` doesn't have, or that
    /// doesn't list the file.
    func resolveTarget(_ url: URL, contentHash: String, project: String?) throws(AppRefusal) -> WindowTarget {
        let path = url.standardizedFileURL.path
        if let project {
            guard let outline = config.outline(project) else { throw unknownProject(project) }
            guard outline.number(of: path) != nil else {
                throw AppRefusal(
                    "the project \(project) doesn't list \(path); add it with `havooch project add \(project) \(path)`"
                )
            }
            return .project(slug: project)
        }
        let listing = config.config.projects.map(config.outline(of:)).filter { $0.number(of: path) != nil }
        guard !listing.isEmpty else { return .video(contentHash: contentHash, path: path) }
        let used = desk.library.projectsUsed()
        // The most recently opened first; one never opened, in the file's order, after.
        let latest = listing.enumerated().max { first, second in
            let (a, b) = (used[first.element.slug], used[second.element.slug])
            if a != b { return (a ?? .distantPast) < (b ?? .distantPast) }
            return first.offset > second.offset
        }
        return .project(slug: latest?.element.slug ?? listing[0].slug)
    }

    /// The projects as the home screen shows them: the most recently
    /// opened first, then the others in the file's order.
    var homeProjects: [StateReport.HomeProject] {
        // Read so a view that shows the list follows a project opened.
        _ = recentsRevision
        let used = desk.library.projectsUsed()
        let projects = config.config.projects.map(config.outline(of:)).enumerated().sorted { first, second in
            let (a, b) = (used[first.element.slug], used[second.element.slug])
            if a != b { return (a ?? .distantPast) > (b ?? .distantPast) }
            return first.offset < second.offset
        }
        return projects.map { _, outline in
            let latest = outline.versions.last?.path
            return StateReport.HomeProject(
                slug: outline.slug, title: outline.title, versions: outline.versions.count, latestPath: latest,
                available: latest.map { FileManager.default.fileExists(atPath: $0) } ?? false, openedAt: used[outline.slug]
            )
        }
    }

    /// A click on a project's card on the home screen, in `window`: its
    /// latest version opens in its window, as `havooch open <path>
    /// --project <slug>` opens it.
    func openProject(_ slug: String, from window: WindowModel?) {
        guard let latest = config.outline(slug)?.versions.last else { return }
        Task {
            await leaveDemo()
            do throws(AppRefusal) {
                let opened = try await windowFor(URL(fileURLWithPath: latest.path), project: slug, from: window)
                focus(opened)
            } catch {
                (window ?? windows.key)?.problem = WindowModel.Problem(title: "The project didn't open", reason: error.reason)
            }
        }
    }

    /// `havooch project new <slug> --from <path> [--title]` (decisions E3
    /// and E7): the project goes into `config.toml` with the video as v1.
    /// When no other project lists the video, its plain review moves into
    /// the project with every thread anchored to v1, its ids unchanged;
    /// its listener keeps listening, now to the project, and a window that
    /// holds the video holds the project. When another project lists it,
    /// the new project starts with fresh threads (E7). Refused for a slug
    /// in use, a path with no file, a file that doesn't play, and a
    /// `config.toml` with a problem; nothing changes then.
    func projectNew(_ slug: String, from url: URL, title: String?) async throws(AppRefusal) -> StateReport.Project {
        let url = url.standardizedFileURL
        try Self.needFile(url)
        guard config.config.project(slug) == nil else {
            throw AppRefusal("a project called `\(slug)` is in config.toml already; pick another slug, or add the video with `havooch project add`")
        }
        try await PlayerEngine.checkPlayable(url)
        guard let hash = await WindowModel.contentHash(of: url, in: hashes) else { throw AppRefusal("can't read \(url.path)") }
        let elsewhere = !config.config.projects.map(config.outline(of:)).filter { $0.number(of: url.path) != nil }.isEmpty
        let video = ReviewKey.video(contentHash: hash)
        // A review that doesn't read stops the project before the file changes.
        if !elsewhere { _ = try desk.readable(video) }
        try config.addProject(slug: slug, title: title, firstVersion: .init(path: url.path))
        guard let outline = config.outline(slug) else { throw unknownProject(slug) }
        let project = ReviewKey.project(slug: slug)
        guard !elsewhere else { return StateReport.Project(outline, onScreen: url.path) }
        try desk.adopt(video, into: slug, anchor: VersionAnchor(path: url.path))
        listeners.rekey(video, to: project)
        windows.holding(video)?.moveIntoProject(slug)
        desk.library.recordProjectOpened(slug, at: Date())
        refreshRecents()
        return StateReport.Project(outline, onScreen: url.path)
    }

    /// `havooch project add <slug> <path> [--label]` (decision E3): the
    /// video goes into `config.toml` as the project's next version, and
    /// shows in the project's window (else the empty key window, else a new
    /// one), which comes forward. Refused for a project `config.toml`
    /// doesn't have, a path with no file or one the project lists already,
    /// and a file that doesn't play; nothing changes then.
    @discardableResult
    func projectAdd(_ slug: String, video url: URL, label: String?) async throws(AppRefusal) -> any WindowControlling {
        let url = url.standardizedFileURL
        try Self.needFile(url)
        guard let outline = config.outline(slug) else { throw unknownProject(slug) }
        if let number = outline.number(of: url.path) {
            throw AppRefusal("\(url.lastPathComponent) is v\(number) of \(slug) already")
        }
        try await PlayerEngine.checkPlayable(url)
        try config.addVersion(.init(path: url.path, label: label), toProject: slug)
        await leaveDemo()
        let window = try await windowFor(url, project: slug, from: nil)
        focus(window)
        bringToFront(window)
        return window
    }

    /// Refused for a project `config.toml` doesn't have.
    private func needProject(_ slug: String) throws(AppRefusal) {
        guard config.config.project(slug) != nil else { throw unknownProject(slug) }
    }

    /// `no project x; the projects are a, b`.
    private func unknownProject(_ slug: String) -> AppRefusal {
        let known = config.config.projects.map(\.slug)
        return AppRefusal(
            "no project `\(slug)` in config.toml; " + (known.isEmpty
                ? "make one with `havooch project new \(slug) --from <video>`"
                : "the projects are \(known.joined(separator: ", "))")
        )
    }

    /// Refused when there's no file at `url`.
    static func needFile(_ url: URL) throws(AppRefusal) {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue else {
            throw AppRefusal("no video file at \(url.path)")
        }
    }

    // MARK: - The demo

    /// "Try the Demo" and `app demo` in `window`: the bundled launch video
    /// on demo data (`enterDemo`). Refused in a build with no bundled video.
    func openDemo(in window: WindowModel) async throws(AppRefusal) {
        guard let demoVideo else {
            throw AppRefusal("this build has no bundled demo video; run `make bundle`")
        }
        try await enterDemo(demoVideo, in: window)
    }

    /// Enters the demo: the run switches to the demo folder and `window`
    /// opens `video` there, so demo threads never mix with the person's
    /// (L17, L27). Every window is on the run's data, so the other windows
    /// go home. A run already on demo data (an in-app demo, or `app open
    /// --demo`) opens it where it is. When the video doesn't open, the
    /// demo this call entered is left again.
    func enterDemo(_ video: URL, in window: WindowModel) async throws(AppRefusal) {
        let entered = isDemo ? false : await switchData(to: demoFolder)
        do throws(AppRefusal) {
            try await window.open(video)
        } catch {
            if entered { await leaveDemo() }
            throw error
        }
    }

    /// Leaves an in-app demo: every window's video closes and the run is
    /// back on the folder it started on. Nothing changes otherwise, so a
    /// run started with `app open --demo` stays on its folder.
    func leaveDemo() async {
        guard isInAppDemo else { return }
        await switchData(to: launchSupport)
    }

    /// Puts the run on the data in `folder`. In every window, words in the
    /// popover are first queued on the video they were written on, on that
    /// video's data; then the video closes. The listener's held `wait` and
    /// `ask`s end as when the app quits, so their commands connect again
    /// and reach the new data. Returns whether this call switched: another
    /// one may have switched to `folder` while the words were queued.
    @discardableResult
    private func switchData(to folder: URL) async -> Bool {
        for window in windows.windows { await window.settle() }
        guard data.support != folder else { return false }
        for window in windows.windows { window.leaveData() }
        let left = data
        data = DataFolder(support: folder, speech: speech)
        isInAppDemo = folder != launchSupport
        listenToAgent()
        // The home screen shows the recent videos of the new data.
        recentsRevision += 1
        left.listeners.announce = nil
        left.listeners.stop()
        return true
    }

    // MARK: - Recent videos

    /// The recent videos of this run's data folder, the newest first, with
    /// whether each file is there now: the home screen's cards.
    var recents: [StateReport.Recent] {
        // Read so a view that shows the list follows its changes.
        _ = recentsRevision
        return desk.library.recents().map(StateReport.Recent.init)
    }

    /// Grows each time the recent videos change: `recents` reads the
    /// library, which observation doesn't follow.
    private var recentsRevision = 0

    /// Has the home screen read the recent videos again, with whether each
    /// file is there now: going home, a window's position kept and the app
    /// coming to the front call it, since nothing tells the app that a file moved.
    func refreshRecents() {
        recentsRevision += 1
    }

    /// Takes the video with `contentHash` off the recent videos. Its review
    /// stays on disk.
    func removeRecent(_ contentHash: String) {
        desk.library.removeRecent(contentHash)
        recentsRevision += 1
    }

    /// Keeps where every window's playhead is, as the app quits.
    func savePositions() {
        for window in windows.windows { window.savePosition() }
    }

    // MARK: - The sidebar's width, the same in every window

    /// The sidebar's width: the kept one, inside the limits, else the
    /// default.
    var sidebarWidth: CGFloat { WindowModel.sidebarWidth(kept: keptSidebarWidth) }

    /// The person let go of a sidebar's edge at `width`: it is kept in
    /// the settings, inside the limits, for every window, this run and the next.
    func keepSidebarWidth(_ width: CGFloat) {
        let width = WindowModel.sidebarWidth(kept: Double(width.rounded()))
        guard width != sidebarWidth else { return }
        keptSidebarWidth = Double(width)
        saveSettings()
    }

    /// Writes the app state `settings.json` keeps. A settings file that
    /// doesn't read is left as it is: a width and a dot are comforts, not
    /// the person's work, so they're only lost.
    private func saveSettings() {
        guard settingsRead else { return }
        try? Settings(
            sidebarWidth: keptSidebarWidth, agentConnectedOnce: agentConnectedOnce ? true : nil, firstRunDone: firstRunDone ? true : nil
        )
        .save(SupportLayout(root: launchSupport))
    }

    /// The person used the app: the first-run window never shows by itself again.
    func markFirstRunDone() {
        guard !firstRunDone else { return }
        firstRunDone = true
        saveSettings()
    }

    /// Whether `settings.json` read at launch, so what is kept in it can be
    /// kept: the first run shows by itself only then.
    var keepsSettings: Bool { settingsRead }
}
