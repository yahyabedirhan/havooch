import AppKit
import Observation
import ReviewConfig
import ReviewCore
import ReviewStore
import ReviewTranscript
import ReviewWire
import UniformTypeIdentifiers

@Observable
final class AppModel: AppControlling {
    private(set) var data: DataFolder
    var desk: ReviewDesk { data.desk }
    var listeners: ListenerHub { data.listeners }
    var transcripts: TranscriptDesk { data.transcripts }
    let config: ConfigDesk
    let themes: ThemeDesk
    let setup: SetupDesk
    private(set) var keptSidebarWidth: Double?
    private(set) var agentConnectedOnce = false
    private(set) var firstRunDone = false
    let firstRun: FirstRun
    let sound: Sound
    @ObservationIgnored private let settingsRead: Bool
    var support: URL { data.support }
    let launchSupport: URL
    let demoFolder: URL
    let demoVideo: URL?
    let isDemoRun: Bool
    private(set) var isInAppDemo = false
    var isDemo: Bool { isDemoRun || isInAppDemo }
    let windows = WindowRegistry()
    @ObservationIgnored var bringToFront: (WindowModel) -> Void = { _ in }
    @ObservationIgnored let hashes = ContentHashCache()
    @ObservationIgnored let speech: any SpeechRecognizing
    let thumbnails = Thumbnails()
    @ObservationIgnored private var filesWaiting: [URL] = []
    @ObservationIgnored private var finderOpens: Task<Void, Never>?
    @ObservationIgnored private var watching: [any NSObjectProtocol] = []

    static let videoTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie, UTType("com.apple.m4v-video")].compactMap(\.self)

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
        let mutedForCheck = MutedRun.isMuted(environment: environment)
        do throws(Library.Failure) {
            let settings = try Settings.load(launchLayout)
            keptSidebarWidth = settings.sidebarWidth
            agentConnectedOnce = settings.agentConnectedOnce ?? false
            firstRunDone = settings.firstRunDone ?? false
            sound = Sound(level: settings.volume, unmuteLevel: settings.unmuteVolume, mutedForCheck: mutedForCheck)
            settingsRead = true
        } catch {
            sound = Sound(mutedForCheck: mutedForCheck)
            settingsRead = false
        }
        listenToAgent()
        firstRun.used = { [weak self] in self?.markFirstRunDone() }
    }

    @discardableResult
    func dismissConfigNotice() -> Bool {
        config.dismissNotice()
    }

    private func listenToAgent() {
        listeners.announce = { [weak self] key, notice in self?.windows.holding(key)?.raise(notice) }
        listeners.keyReview = { [weak self] in self?.windows.key?.reviewKey }
        listeners.outline = { [weak self] slug in self?.config.outline(slug) }
        listeners.connected = { [weak self] key in self?.agentConnected(to: key) }
    }

    private func agentConnected(to key: ReviewKey) {
        windows.holding(key)?.tourNoticedAgent()
        markFirstRunDone()
        guard !agentConnectedOnce else { return }
        agentConnectedOnce = true
        saveSettings()
    }

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

    @discardableResult
    func makeWindow() -> WindowModel {
        let window = WindowModel(app: self, id: windows.nextID())
        windows.add(window)
        return window
    }

    @discardableResult
    func newWindow() -> WindowModel {
        let window = makeWindow()
        windows.show(window)
        return window
    }

    func sceneAppeared(target: WindowTarget?) -> WindowModel {
        let window = windows.place(target) ?? makeWindow()
        if !filesWaiting.isEmpty, windows.openScene != nil {
            let files = filesWaiting
            filesWaiting = []
            openFromFinder(files)
        }
        return window
    }

    func attach(_ nsWindow: NSWindow, to window: WindowModel) {
        guard window.nsWindow !== nsWindow else { return }
        window.nsWindow = nsWindow
        if nsWindow.isKeyWindow { windows.becameKey(window) }
    }

    func windowClosed(_ window: WindowModel) {
        window.closed()
        windows.remove(window)
    }

    func focus(_ window: WindowModel) {
        window.nsWindow?.makeKeyAndOrderFront(nil)
        windows.becameKey(window)
    }

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

    func windowList() -> [StateReport.Window] {
        let key = windows.key
        return windows.windows.map { $0.report(isKey: $0 === key) }
    }

    func openWindow() -> StateReport.Window {
        let window = newWindow()
        return window.report(isKey: window === windows.key)
    }

    func closeWindow(_ id: String?) throws(AppRefusal) -> StateReport.Window {
        let window = try window(id)
        let report = window.report(isKey: window === windows.key)
        window.nsWindow?.close()
        if windows.window(window.id) != nil {
            window.nsWindow?.orderOut(nil)
            windowClosed(window)
        }
        return report
    }

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
            report.sound = StateReport.Sound(sound, panelOpen: false)
            report.screen = .none
            return report
        }
        return try window(id).state()
    }

    var appReport: StateReport.App {
        StateReport.App(version: Version.app, demo: isDemo, support: support.path, active: NSApp?.isActive ?? false)
    }

    @discardableResult
    func openInFront(_ url: URL, project: String? = nil) async throws(AppRefusal) -> any WindowControlling {
        let url = url.standardizedFileURL
        try Self.needFile(url)
        if let project { try needProject(project) }
        try await PlayerEngine.checkPlayable(url)
        await leaveDemo()
        let window = try await windowFor(url, project: project, from: nil)
        try window.play()
        focus(window)
        bringToFront(window)
        return window
    }

    @discardableResult
    func openFromFinder(_ urls: [URL]) -> Task<Void, Never>? {
        guard windows.openScene != nil else {
            filesWaiting += urls
            return nil
        }
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

    func openFromPanel(from window: WindowModel?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.videoTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a video to review"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openForPerson(url, from: window)
    }

    private func windowFor(_ url: URL, project: String? = nil, from: WindowModel?) async throws(AppRefusal) -> WindowModel {
        try Self.needFile(url)
        guard let hash = await WindowModel.contentHash(of: url, in: hashes) else {
            throw AppRefusal("can't read \(url.path)")
        }
        let target = try resolveTarget(url, contentHash: hash, project: project)
        let slug = target.reviewKey.slug
        if let holder = windows.holding(target.reviewKey) {
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
        let latest = listing.enumerated().max { first, second in
            let (a, b) = (used[first.element.slug], used[second.element.slug])
            if a != b { return (a ?? .distantPast) < (b ?? .distantPast) }
            return first.offset > second.offset
        }
        return .project(slug: latest?.element.slug ?? listing[0].slug)
    }

    var homeProjects: [StateReport.HomeProject] {
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

    private func needProject(_ slug: String) throws(AppRefusal) {
        guard config.config.project(slug) != nil else { throw unknownProject(slug) }
    }

    private func unknownProject(_ slug: String) -> AppRefusal {
        let known = config.config.projects.map(\.slug)
        return AppRefusal(
            "no project `\(slug)` in config.toml; " + (known.isEmpty
                ? "make one with `havooch project new \(slug) --from <video>`"
                : "the projects are \(known.joined(separator: ", "))")
        )
    }

    static func needFile(_ url: URL) throws(AppRefusal) {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue else {
            throw AppRefusal("no video file at \(url.path)")
        }
    }

    func openDemo(in window: WindowModel) async throws(AppRefusal) {
        guard let demoVideo else {
            throw AppRefusal("this build has no bundled demo video; run `make bundle`")
        }
        try await enterDemo(demoVideo, in: window)
    }

    func enterDemo(_ video: URL, in window: WindowModel) async throws(AppRefusal) {
        let entered = isDemo ? false : await switchData(to: demoFolder)
        do throws(AppRefusal) {
            try await window.open(video)
        } catch {
            if entered { await leaveDemo() }
            throw error
        }
    }

    func leaveDemo() async {
        guard isInAppDemo else { return }
        await switchData(to: launchSupport)
    }

    @discardableResult
    private func switchData(to folder: URL) async -> Bool {
        for window in windows.windows { await window.settle() }
        guard data.support != folder else { return false }
        for window in windows.windows { window.leaveData() }
        let left = data
        data = DataFolder(support: folder, speech: speech)
        isInAppDemo = folder != launchSupport
        listenToAgent()
        recentsRevision += 1
        left.listeners.announce = nil
        left.listeners.stop()
        return true
    }

    var recents: [StateReport.Recent] {
        _ = recentsRevision
        return desk.library.recents().map(StateReport.Recent.init)
    }

    private var recentsRevision = 0

    func refreshRecents() {
        recentsRevision += 1
    }

    func removeRecent(_ contentHash: String) {
        desk.library.removeRecent(contentHash)
        recentsRevision += 1
    }

    func savePositions() {
        for window in windows.windows { window.savePosition() }
    }

    var sidebarWidth: CGFloat { WindowModel.sidebarWidth(kept: keptSidebarWidth) }

    func keepSidebarWidth(_ width: CGFloat) {
        let width = WindowModel.sidebarWidth(kept: Double(width.rounded()))
        guard width != sidebarWidth else { return }
        keptSidebarWidth = Double(width)
        saveSettings()
    }

    private func saveSettings() {
        guard settingsRead else { return }
        try? Settings(
            sidebarWidth: keptSidebarWidth, agentConnectedOnce: agentConnectedOnce ? true : nil, firstRunDone: firstRunDone ? true : nil,
            volume: sound.kept.level, unmuteVolume: sound.kept.unmuteLevel
        )
        .save(SupportLayout(root: launchSupport))
    }

    func setVolume(_ level: Double, keep: Bool = true) {
        sound.set(level)
        if keep { keepSound() }
    }

    func mute() {
        sound.mute()
        keepSound()
    }

    func unmute() {
        sound.unmute()
        keepSound()
    }

    func toggleMute() {
        sound.toggleMute()
        keepSound()
    }

    func toggleMuteForPerson() {
        guard !sound.isMutedForCheck else { return }
        toggleMute()
    }

    func changeSound(_ change: SoundChange) -> StateReport.Sound {
        switch change {
        case .mute: mute()
        case .unmute: unmute()
        case .volume(let percent): setVolume(Double(percent) / 100)
        }
        return windows.key?.soundReport ?? StateReport.Sound(sound, panelOpen: false)
    }

    private func keepSound() {
        guard !sound.isMutedForCheck else { return }
        saveSettings()
    }

    func markFirstRunDone() {
        guard !firstRunDone else { return }
        firstRunDone = true
        saveSettings()
    }

    var keepsSettings: Bool { settingsRead }
}
