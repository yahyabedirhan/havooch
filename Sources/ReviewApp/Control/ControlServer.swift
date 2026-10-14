import AppKit
import ReviewCore
import ReviewLease
import ReviewWire

nonisolated struct AppRefusal: Error, Equatable {
    var reason: String

    init(_ reason: String) {
        self.reason = reason
    }
}

protocol AppControlling: AnyObject {
    func state(window: String?) throws(AppRefusal) -> StateReport
    func controlledWindow(_ id: String?, making: Bool) throws(AppRefusal) -> any WindowControlling
    @discardableResult
    func openInFront(_ url: URL, project: String?) async throws(AppRefusal) -> any WindowControlling
    func listenedReview(video: String?, project: String?) async throws(AppRefusal) -> ReviewKey
    func projectNew(_ slug: String, from url: URL, title: String?) async throws(AppRefusal) -> StateReport.Project
    @discardableResult
    func projectAdd(_ slug: String, video url: URL, label: String?) async throws(AppRefusal) -> any WindowControlling
    func windowList() -> [StateReport.Window]
    func openWindow() -> StateReport.Window
    func closeWindow(_ id: String?) throws(AppRefusal) -> StateReport.Window
    func themeList() -> StateReport.ThemeList
    func setTheme(_ name: String) throws(AppRefusal) -> StateReport.Theme
    func setupStatus() -> StateReport.Setup
    func linkCommand(dryRun: Bool) throws(AppRefusal) -> (line: String, setup: StateReport.Setup)
    func installSkill(harnesses: [String], dryRun: Bool) throws(AppRefusal) -> StateReport.Setup.Install
    func cancelInstall() async throws(AppRefusal) -> StateReport.Setup.Install
    func dismissConfigNotice() -> Bool
    func firstRun(_ action: FirstRunAction) async throws(AppRefusal) -> (line: String, firstRun: StateReport.FirstRun)
    func changeSound(_ change: SoundChange) -> StateReport.Sound
}

enum SoundChange: Equatable {
    case mute, unmute
    case volume(percent: Int)
}

protocol WindowControlling: AnyObject {
    var id: String { get }
    var nsWindow: NSWindow? { get }
    func resize(width: Int) async throws(AppRefusal) -> Int
    func setSidebarVisible(_ visible: Bool)
    func state() -> StateReport
    func open(_ url: URL) async throws(AppRefusal)
    func goHome() async
    func openDemo() async throws(AppRefusal)
    func play() throws(AppRefusal)
    func pause() throws(AppRefusal)
    func seek(to seconds: Double) async throws(AppRefusal)
    func setSoundPanel(open: Bool) throws(AppRefusal)
    var soundReport: StateReport.Sound { get }
    func addMessage(
        text: String, at: Double?, region: Region?, thread: String?
    ) async throws(AppRefusal) -> (message: StateReport.Message, thread: StateReport.Thread)
    func openPopover(text: String, region: Region?) throws(AppRefusal) -> StateReport.Popover
    func editMessage(_ id: String, text: String) throws(AppRefusal) -> StateReport.Message
    func deleteMessage(_ id: String) throws(AppRefusal) -> StateReport.Message
    func setContextNote(_ text: String) throws(AppRefusal) -> String
    func sendQueue() async throws(AppRefusal) -> StateReport.Send
    func answer(_ thread: String, text: String) throws(AppRefusal) -> (message: StateReport.Message, number: Int)
    func choose(_ thread: String, choice number: Int) throws(AppRefusal) -> (message: StateReport.Message, number: Int)
    func openThread(_ thread: String, frame: PopoverFrame?) async throws(AppRefusal) -> StateReport.Popover
    func showThread(_ thread: String) async throws(AppRefusal) -> (sidebar: StateReport.Sidebar, number: Int)
    func showThreadList() -> StateReport.Sidebar
    func openVersionMenu(search: String?) throws(AppRefusal) -> StateReport.Sidebar
    func closeVersionMenu() -> StateReport.Sidebar
    func pickVersion(_ number: Int) throws(AppRefusal) -> StateReport.Sidebar
    func removePickedVersion(_ number: Int) throws(AppRefusal) -> StateReport.Sidebar
    func compose(text: String, region: Region?, general: Bool) throws(AppRefusal) -> StateReport.Sidebar.Composer
    func showConnect() throws(AppRefusal) -> StateReport.Sidebar
    func pickHarness(named name: String) throws(AppRefusal) -> StateReport.Sidebar
    func disconnectAgent() throws(AppRefusal) -> String
    func forgetAgent() throws(AppRefusal) -> String
    func showTour() throws(AppRefusal) -> StateReport.Tour
    func nextTourStep() throws(AppRefusal) -> StateReport.Tour
    func skipTour() throws(AppRefusal) -> StateReport.Tour
    func closeTour() throws(AppRefusal) -> StateReport.Tour
    func switchVersion(to number: Int) async throws(AppRefusal)
    func openVersionPicker(query: String) throws(AppRefusal) -> VersionSwitch
    func closeVersionPicker() -> Bool
    func openCompare() throws(AppRefusal)
    func pickCompareSide(_ side: CompareSide, query: String) throws(AppRefusal)
    func setCompare(_ change: CompareChange) async throws(AppRefusal)
    func swapCompare() throws(AppRefusal)
    func startCompare() async throws(AppRefusal)
    @discardableResult
    func exitCompare() -> Bool
}

final class ControlServer {
    nonisolated struct Answer: Equatable {
        var reply: ControlReply
        var quits = false
        var granted: LeaseTerm?
        var delivered: SendRef?
        var silent = false
    }

    let socket: URL
    private let app: any AppControlling
    private let currentListeners: @MainActor () -> ListenerHub
    private var listeners: ListenerHub { currentListeners() }
    private var deliveredBy: [SendRef: ListenerQueue] = [:]
    private let screenshotter: any Screenshotting
    private let quit: @MainActor () -> Void
    private let now: @MainActor () -> Date
    private let timeZone: TimeZone
    private(set) var lease: ControlLease {
        didSet { leaseChanged() }
    }
    let indicator: AgentControlIcon
    private var settling: Task<Void, Never>?
    private var waiters: [UUID: Waiter] = [:]
    private var listener: SocketListener?

    private struct Waiter {
        var holder: Holder
        var seconds: Int
        var json: Bool
        var answer: CheckedContinuation<Answer, Never>
        var timeout: Task<Void, Never>?
    }

    init(
        socket: URL,
        app: any AppControlling,
        listeners: @escaping @MainActor () -> ListenerHub,
        screenshotter: any Screenshotting,
        lease: ControlLease = ControlLease(),
        indicator: AgentControlIcon = AgentControlIcon(),
        now: @escaping @MainActor () -> Date = { Date() },
        timeZone: TimeZone = .current,
        quit: @escaping @MainActor () -> Void
    ) {
        self.socket = socket
        self.app = app
        currentListeners = listeners
        self.screenshotter = screenshotter
        self.lease = lease
        self.indicator = indicator
        self.now = now
        self.timeZone = timeZone
        self.quit = quit
        leaseChanged()
    }

    func reply(to data: Data, connection: UUID? = nil) async -> Answer {
        let message: ControlMessage
        do throws(ControlProtocolError) {
            message = try ControlMessage.decode(data)
        } catch {
            return Answer(reply: .refused(error.message))
        }
        let json = message.json
        var held: LeaseTerm?
        if message.request.role == .operator {
            let time = now()
            switch lease.use(by: message.holder, at: time).answer {
            case .success(let term): held = term
            case .failure(let refusal): return Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone)))
            }
        }
        let window = message.window
        func inWindow(making: Bool = false) throws(AppRefusal) -> any WindowControlling {
            try app.controlledWindow(window, making: making)
        }
        do throws(AppRefusal) {
            switch message.request {
            case .controlTake(let seconds):
                return await take(by: message.holder, waiting: seconds, json: json)
            case .controlRelease:
                _ = lease.release(by: message.holder, at: now())
                return done("released \(AppIdentity.appName)", Output(released: true), json)
            case .appStatus, .appOpen:
                let state = try state(window: nil)
                return done(json ? state.statusJSON : state.statusLines)
            case .state:
                let state = try state(window: window)
                return done(json ? state.json : state.lines)
            case .appQuit:
                let line = "\(AppIdentity.appName) quit"
                let output = json ? StateReport.json(Output(quit: true)) : line + "\n"
                return Answer(reply: ControlReply(ok: true, output: output, lease: held), quits: true)
            case .appHome:
                let shown = try inWindow(making: true)
                await shown.goHome()
                let state = shown.state()
                let count = state.recents.count
                return done(
                    "home in \(shown.id), \(count) recent video\(count == 1 ? "" : "s"), \(state.app.demo ? "demo data" : "your data")",
                    Output(app: state.app, window: shown.id, screen: state.screen), json
                )
            case .appDemo:
                let shown = try inWindow(making: true)
                try await shown.openDemo()
                let state = shown.state()
                let line = state.video.map { "opened \($0.title) (\(TimeCode.text($0.duration))) on demo data in \(shown.id)" } ?? "opened the demo"
                return done(
                    line, Output(app: state.app, window: shown.id, screen: state.screen, video: state.video, player: state.player), json
                )
            case .open(let path, let project):
                let shown = try await app.openInFront(URL(fileURLWithPath: path), project: project)
                let state = shown.state()
                let place = state.project.map { " in project \($0.slug)" + ($0.version.map { " (v\($0))" } ?? "") } ?? ""
                let line = state.video.map { "opened \($0.title) (\(TimeCode.text($0.duration)))\(place) in \(shown.id), playing" } ?? "opened \(path)"
                var answer = done(
                    line,
                    Output(app: state.app, window: shown.id, screen: state.screen, video: state.video, player: state.player, project: state.project),
                    json
                )
                // The command brings this process to the front: the app
                // asked to activate itself, but macOS may keep it behind.
                answer.reply.pid = ProcessInfo.processInfo.processIdentifier
                return answer
            case .playerOpen(let path):
                let shown = try inWindow(making: true)
                try await shown.open(URL(fileURLWithPath: path))
                let state = shown.state()
                let line = state.video.map { "opened \($0.title) (\(TimeCode.text($0.duration))) in \(shown.id)" } ?? "opened \(path)"
                return done(line, Output(window: shown.id, video: state.video, player: state.player), json)
            case .playerPlay:
                let shown = try inWindow()
                try shown.play()
                let player = shown.state().player
                return done("playing from \(TimeCode.text(player.time))", Output(player: player), json)
            case .playerPause:
                let shown = try inWindow()
                try shown.pause()
                let player = shown.state().player
                return done("paused at \(TimeCode.text(player.time))", Output(player: player), json)
            case .playerSeek(let seconds):
                let shown = try inWindow()
                try await shown.seek(to: seconds)
                let player = shown.state().player
                return done(TimeCode.text(player.time), Output(player: player), json)
            case .playerMute, .playerUnmute, .playerVolume:
                let change: SoundChange = switch message.request {
                case .playerMute: .mute
                case .playerVolume(let percent): .volume(percent: percent)
                default: .unmute
                }
                let sound = app.changeSound(change)
                return done(Self.soundLine(sound), Output(sound: sound), json)
            case .playerSound(let open):
                let shown = try inWindow()
                try shown.setSoundPanel(open: open)
                let sound = shown.soundReport
                let line = open
                    ? "sound panel open: " + (sound.mutedForCheck ? "muted for an agent check" : sound.muted ? "muted" : "volume \(sound.volume)%")
                    : "sound panel closed"
                return done(line, Output(sound: sound), json)
            case .screenshot(let path, let appearance, let hideAgentIndicator, let which):
                let player = which == .main ? try inWindow() : nil
                try await screenshotter.capture(
                    to: URL(fileURLWithPath: path), appearance: appearance, hideAgentIndicator: hideAgentIndicator, window: which,
                    player: player?.nsWindow
                )
                return done(path, Output(path: path), json)
            case .windowList:
                let windows = app.windowList()
                return done(json ? StateReport.json(Output(windows: windows)) : StateReport.windowLines(windows))
            case .windowNew:
                let made = app.openWindow()
                return done("\(made.id) opened, showing home", Output(window: made.id, windows: app.windowList()), json)
            case .windowClose:
                let closed = try app.closeWindow(window)
                return done("\(closed.id) closed", Output(window: closed.id, windows: app.windowList()), json)
            case .windowResize(let width):
                let resized = try await inWindow().resize(width: width)
                return done("window width \(resized) pt", Output(width: resized), json)
            case .sidebarVisibility(let show):
                try inWindow().setSidebarVisible(show)
                return done(show ? "sidebar shown\n" : "sidebar hidden\n")
            case .commentAdd(let text, let at, let rectangle, let thread):
                let region = try Self.region(rectangle)
                let added = try await inWindow().addMessage(text: text, at: at, region: region, thread: thread)
                let place = added.thread.time.map { " at \(TimeCode.text($0))" } ?? ""
                let area = added.message.region.map { " on the region \($0.text)" } ?? ""
                return done(
                    "\(added.message.id) queued on #\(added.thread.number)\(place)\(area)",
                    Output(message: added.message, thread: Output.ThreadRef(id: added.thread.id, number: added.thread.number)), json
                )
            case .commentOpen(let text, let rectangle):
                let popover = try inWindow().openPopover(text: text, region: try Self.region(rectangle))
                let thread = popover.thread.map { " on #\($0)" } ?? ""
                let area = popover.region.map { " on the region \($0.text)" } ?? ""
                return done("popover open\(thread) at \(TimeCode.text(popover.time))\(area)", Output(popover: popover), json)
            case .commentCompose(let text, let rectangle, let general):
                let composer = try inWindow().compose(text: text, region: try Self.region(rectangle), general: general)
                let area = composer.region.map { " with the region \($0.text)" } ?? ""
                return done("the composer says \"\(composer.target)\"\(area)", Output(composer: composer), json)
            case .commentEdit(let id, let text):
                let message = try inWindow().editMessage(id, text: text)
                return done("\(message.id) edited", Output(message: message), json)
            case .commentDelete(let id):
                let message = try inWindow().deleteMessage(id)
                return done("\(message.id) deleted", Output(deleted: message.id), json)
            case .contextSet(let text):
                let shown = try inWindow()
                let note = try shown.setContextNote(text)
                let line = note.isEmpty
                    ? "context note cleared"
                    : "context note set (\(note.count) character\(note.count == 1 ? "" : "s"))"
                return done(line, Output(video: shown.state().video), json)
            case .send:
                let send = try await inWindow().sendQueue()
                let messages = send.messageIds.count
                let threads = send.threadIds.count
                let delivered = listeners.isDelivered(send.id)
                let line = "\(send.id) sent: \(messages) message\(messages == 1 ? "" : "s") on \(threads) thread\(threads == 1 ? "" : "s"), "
                    + (delivered ? "taken by the listener" : "waiting for a listener")
                return done(line, Output(send: send), json)
            case .wait(let timeout, let video, let project):
                let queue = listeners.queue(for: try await app.listenedReview(video: video, project: project))
                switch await queue.wait(by: message.holder, timeout: timeout, connection: connection) {
                case .send(let ref, let payload):
                    deliveredBy[ref] = queue
                    return Answer(reply: .done(payload), delivered: ref)
                case .ranOut:
                    return Answer(reply: .ranOut)
                case .replaced:
                    return Answer(reply: .refused("a newer `havooch wait` took this one's place: one listener at a time"))
                case .takenOver(let agent):
                    return Answer(reply: .refused(
                        "\(agent) took over listening to this review: one listener per video or project; stop listening and tell the person"
                    ))
                case .disconnected:
                    return Answer(reply: .refused(
                        "the person disconnected you from this video or project in \(AppIdentity.appName): stop listening and tell the person"
                    ))
                case .gone:
                    return Answer(reply: .refused("\(AppIdentity.appName) is quitting"), silent: true)
                }
            case .ack(let sendID, let text):
                let send = try listeners.ack(sendID, text: text)
                let count = send.messageIds.count
                return done("\(send.id) acknowledged, \(count) message\(count == 1 ? "" : "s")", Output(send: send), json)
            case .status(let messageID, let status, let text):
                let state = MessageState(rawValue: status.rawValue) ?? .working
                let message = try listeners.status(messageID, state, text: text)
                return done("\(message.id) \(message.state ?? status.rawValue)", Output(message: message), json)
            case .reply(let thread, let text):
                let message = try listeners.reply(on: thread, text: text)
                return done("\(message.id) on \(Self.name(ThreadRef(thread)) ?? thread)", Output(message: message), json)
            case .ask(let thread, let question, let waitSeconds, let choices):
                switch try await listeners.ask(
                    on: thread, question: question, choices: choices, waitSeconds: waitSeconds, connection: connection
                ) {
                case .answered(let answer):
                    return done(answer.text, Output(answer: answer), json)
                case .ranOut:
                    return Answer(reply: .ranOut)
                case .gone:
                    return Answer(reply: .refused("\(AppIdentity.appName) is quitting"), silent: true)
                }
            case .threadAnswer(let thread, let text):
                let answered = try inWindow().answer(thread, text: text)
                return done("#\(answered.number) answered", Output(message: answered.message), json)
            case .threadChoose(let thread, let choice):
                let answered = try inWindow().choose(thread, choice: choice)
                return done("#\(answered.number) answered: \(answered.message.text)", Output(message: answered.message), json)
            case .threadOpen(let thread, let rectangle):
                let frame = try Self.region(rectangle).map { PopoverFrame(x: $0.x, y: $0.y, w: $0.w, h: $0.h) }
                let popover = try await inWindow().openThread(thread, frame: frame)
                let number = popover.thread.map { "#\($0)" } ?? thread
                return done("popover open on \(number) at \(TimeCode.text(popover.time))", Output(popover: popover), json)
            case .threadShow(let thread):
                let shown = try await inWindow().showThread(thread)
                return done("the sidebar shows #\(shown.number)", Output(sidebar: shown.sidebar), json)
            case .threadList:
                let sidebar = try inWindow().showThreadList()
                return done("the sidebar shows the thread list", Output(sidebar: sidebar), json)
            case .threadVersionsOpen(let search):
                let sidebar = try inWindow().openVersionMenu(search: search)
                return done("All versions is open", Output(sidebar: sidebar), json)
            case .threadVersionsClose:
                let sidebar = try inWindow().closeVersionMenu()
                return done("All versions is closed", Output(sidebar: sidebar), json)
            case .threadVersion(let number, let remove):
                let window = try inWindow()
                let sidebar = remove ? try window.removePickedVersion(number) : try window.pickVersion(number)
                let line = remove ? "v\(number) left the thread list" : "the thread list shows v\(number)"
                return done(line, Output(sidebar: sidebar), json)
            case .themeList:
                let list = app.themeList()
                return done(json ? StateReport.json(list) : list.lines)
            case .themeSet(let name):
                let theme = try app.setTheme(name)
                return done(theme.setLine, Output(theme: theme), json)
            case .setupStatus:
                let setup = app.setupStatus()
                return done(json ? StateReport.json(setup) : setup.lines)
            case .setupLink(let dryRun):
                let linked = try app.linkCommand(dryRun: dryRun)
                return done(linked.line, Output(setup: linked.setup), json)
            case .setupInstall(let harnesses, let dryRun):
                let install = try app.installSkill(harnesses: harnesses, dryRun: dryRun)
                let line = dryRun
                    ? "would run: \(install.command)"
                    : "\(install.line)\nhavooch setup status follows its log; havooch setup cancel stops it"
                return done(line, Output(install: install), json)
            case .setupCancel:
                let install = try await app.cancelInstall()
                return done(install.line, Output(install: install), json)
            case .connectShow:
                let sidebar = try inWindow().showConnect()
                return done("the sidebar shows the Connect view", Output(sidebar: sidebar), json)
            case .connectPick(let harness):
                let sidebar = try inWindow().pickHarness(named: harness)
                let line = sidebar.connect.map { connect in
                    "picked \(connect.harness): \(Self.words(readiness: connect.readiness))" + (connect.prompt.map { "\nprompt: \($0)" } ?? "")
                } ?? "picked \(harness)"
                return done(line, Output(sidebar: sidebar), json)
            case .connectDisconnect:
                let shown = try inWindow()
                let agent = try shown.disconnectAgent()
                return done("\(agent) disconnected", Output(sidebar: shown.state().sidebar), json)
            case .connectForget:
                let shown = try inWindow()
                let agent = try shown.forgetAgent()
                return done("\(agent) forgotten: no agent is waited for", Output(sidebar: shown.state().sidebar), json)
            case .tourShow:
                let tour = try inWindow().showTour()
                return done(tour.line, Output(tour: tour), json)
            case .tourNext:
                let tour = try inWindow().nextTourStep()
                return done(tour.open ? tour.line : "the tour is finished", Output(tour: tour), json)
            case .tourSkip:
                let tour = try inWindow().skipTour()
                return done("the tour is skipped; Finish setup or havooch tour open starts it again", Output(tour: tour), json)
            case .tourClose:
                let tour = try inWindow().closeTour()
                return done(tour.line, Output(tour: tour), json)
            case .versionShow(let number):
                let shown = try inWindow()
                try await shown.switchVersion(to: number)
                let state = shown.state()
                let version = state.project?.version.map { "v\($0)" } ?? "v\(number)"
                return done(
                    "\(version) on screen in \(shown.id) at \(TimeCode.text(state.player.time))",
                    Output(window: shown.id, video: state.video, player: state.player, project: state.project), json
                )
            case .versionPick(let query):
                let shown = try inWindow()
                _ = try shown.openVersionPicker(query: query)
                let state = shown.state()
                let picker = state.project?.switcher?.picker
                let count = picker?.matches.count ?? 0
                let line = "the version picker is open: \(count) of \(state.project?.versions.count ?? 0) versions match"
                    + (query.isEmpty ? "" : " `\(query)`") + (picker?.highlighted.map { ", v\($0) highlighted" } ?? "")
                return done(line, Output(window: shown.id, project: state.project), json)
            case .versionClose:
                let shown = try inWindow()
                let closed = shown.closeVersionPicker()
                return done(
                    closed ? "the version picker is closed" : "the version picker wasn't open",
                    Output(window: shown.id, project: shown.state().project, dismissed: closed), json
                )
            case .compareOpen:
                let shown = try inWindow()
                try shown.openCompare()
                return compared(shown, json)
            case .comparePick(let side, let query):
                let shown = try inWindow()
                try shown.pickCompareSide(side, query: query)
                return compared(shown, json)
            case .compareSet(let change):
                let shown = try inWindow()
                try await shown.setCompare(change)
                return compared(shown, json)
            case .compareSwap:
                let shown = try inWindow()
                try shown.swapCompare()
                return compared(shown, json)
            case .compareStart:
                let shown = try inWindow()
                try await shown.startCompare()
                return compared(shown, json)
            case .compareExit:
                let shown = try inWindow()
                let exited = shown.exitCompare()
                let state = shown.state()
                let version = state.project?.version.map { "v\($0)" } ?? "a removed version"
                return done(
                    exited ? "Compare is closed: \(version) on screen in \(shown.id)" : "Compare wasn't open",
                    Output(window: shown.id, player: state.player, project: state.project, dismissed: exited), json
                )
            case .projectNew(let slug, let path, let title):
                let made = try await app.projectNew(slug, from: URL(fileURLWithPath: path), title: title)
                let listed = made.versions.count
                return done(
                    "project \(made.slug) made with \(URL(fileURLWithPath: path).lastPathComponent) as v\(listed)", Output(project: made), json
                )
            case .projectAdd(let slug, let path, let label):
                let shown = try await app.projectAdd(slug, video: URL(fileURLWithPath: path), label: label)
                let state = shown.state()
                let number = state.project?.version.map { "v\($0)" } ?? "the next version"
                var answer = done(
                    "\(URL(fileURLWithPath: path).lastPathComponent) added to \(slug) as \(number), shown in \(shown.id)",
                    Output(window: shown.id, video: state.video, project: state.project), json
                )
                answer.reply.pid = ProcessInfo.processInfo.processIdentifier
                return answer
            case .firstRunShow(let step):
                return firstRunDone(try await app.firstRun(.show(step: step)), json)
            case .firstRunNext:
                return firstRunDone(try await app.firstRun(.next), json)
            case .firstRunBack:
                return firstRunDone(try await app.firstRun(.back), json)
            case .firstRunPick(let harness):
                return firstRunDone(try await app.firstRun(.pick(harness: harness)), json)
            case .firstRunDemo:
                return firstRunDone(try await app.firstRun(.demo), json)
            case .firstRunSkip:
                return firstRunDone(try await app.firstRun(.skip), json)
            case .configDismiss:
                let closed = app.dismissConfigNotice()
                return done(closed ? "the settings notice is closed" : "no settings notice was up", Output(dismissed: closed), json)
            }
        } catch {
            return Answer(reply: .refused(error.reason))
        }
    }

    private struct Output: Encodable {
        var app: StateReport.App?
        var window: String?
        var windows: [StateReport.Window]?
        var screen: StateReport.Screen?
        var video: StateReport.Video?
        var player: StateReport.Player?
        var sound: StateReport.Sound?
        var project: StateReport.Project?
        var path: String?
        var width: Int?
        var quit: Bool?
        var lease: ControlLease.Status?
        var released: Bool?
        var message: StateReport.Message?
        var thread: ThreadRef?
        var deleted: String?
        var send: StateReport.Send?
        var answer: StateReport.Message?
        var theme: StateReport.Theme?
        var popover: StateReport.Popover?
        var sidebar: StateReport.Sidebar?
        var tour: StateReport.Tour?
        var composer: StateReport.Sidebar.Composer?
        var setup: StateReport.Setup?
        var install: StateReport.Setup.Install?
        var dismissed: Bool?
        var firstRun: StateReport.FirstRun?

        struct ThreadRef: Encodable {
            var id: String
            var number: Int
        }
    }

    private static func soundLine(_ sound: StateReport.Sound) -> String {
        let level = sound.volume == 0 ? "muted" : "volume \(sound.volume)%"
        guard sound.mutedForCheck else { return level }
        return "\(level) for this run, which plays no sound: it started muted for an agent check (\(MutedRun.variable)=1)"
    }

    private static func name(_ ref: ReviewCore.ThreadRef?) -> String? {
        switch ref {
        case .number(let number): "#\(number)"
        case .id(let id): "#\(id.number)"
        case nil: nil
        }
    }

    private func compared(_ shown: any WindowControlling, _ json: Bool) -> Answer {
        let state = shown.state()
        return done(
            state.project?.compare?.line ?? "compare: closed",
            Output(window: shown.id, player: state.player, project: state.project), json
        )
    }

    private func firstRunDone(_ answer: (line: String, firstRun: StateReport.FirstRun), _ json: Bool) -> Answer {
        done(answer.line, Output(firstRun: answer.firstRun), json)
    }

    private static func words(readiness: String) -> String {
        switch Readiness(rawValue: readiness) {
        case .ready: "ready, the skill is detected"
        case .skillNotDetected: "the skill isn't detected; paste the prompt if it's installed another way"
        case .harnessNotDetected: "the harness isn't detected; paste the prompt if it's installed another way"
        case nil: readiness
        }
    }

    private static func region(_ rectangle: ControlRequest.Rectangle?) throws(AppRefusal) -> Region? {
        guard let rectangle else { return nil }
        do throws(ReviewRefusal) {
            return try Region(x: rectangle.x, y: rectangle.y, w: rectangle.w, h: rectangle.h)
        } catch {
            throw AppRefusal(error.line)
        }
    }

    private func state(window: String?) throws(AppRefusal) -> StateReport {
        var state = try app.state(window: window)
        state.lease = lease.status(at: now())
        return state
    }

    private func done(_ output: String) -> Answer {
        Answer(reply: .done(output))
    }

    private func done(_ line: String, _ output: Output, _ json: Bool) -> Answer {
        Answer(reply: .done(json ? StateReport.json(output) : line + "\n"))
    }

    private func take(by holder: Holder, waiting seconds: Int?, json: Bool) async -> Answer {
        let time = now()
        let decision = lease.take(by: holder, at: time, waitingUntil: seconds.map { time.addingTimeInterval(TimeInterval($0)) })
        switch decision.answer {
        case .success(let term):
            return granting(term, json: json)
        case .failure(.queued):
            break
        case .failure(let refusal):
            return Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone)))
        }
        let seconds = seconds ?? 0
        let deadline = time.addingTimeInterval(TimeInterval(seconds))
        let ticket = UUID()
        return await withCheckedContinuation { continuation in
            let timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                self?.waitRanOut(ticket, deadline: deadline)
            }
            waiters[ticket] = Waiter(holder: holder, seconds: seconds, json: json, answer: continuation, timeout: timeout)
        }
    }

    private func waitRanOut(_ ticket: UUID, deadline: Date) {
        guard let waiter = waiters.removeValue(forKey: ticket) else { return }
        let time = max(now(), deadline)
        switch lease.giveUp(by: waiter.holder, waited: waiter.seconds, at: time).answer {
        case .success(let term):
            waiter.answer.resume(returning: granting(term, json: waiter.json))
        case .failure(let refusal) where refusal.isWaitedOut:
            waiter.answer.resume(returning: Answer(reply: .ranOut(refusal.message(at: time, timeZone: timeZone))))
        case .failure(let refusal):
            waiter.answer.resume(returning: Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone))))
        }
    }

    private func granting(_ term: LeaseTerm, json: Bool) -> Answer {
        var answer = done(term.held(timeZone: timeZone), Output(lease: lease.status(at: now())), json)
        answer.granted = term
        return answer
    }

    func undelivered(_ answer: Answer) {
        if let ref = answer.delivered { handedBack(ref).undelivered(ref) }
        guard let granted = answer.granted, let term = lease.current(at: now()),
              term.holder.key == granted.holder.key, term.taken == granted.taken else { return }
        _ = lease.release(by: granted.holder, at: now())
    }

    func written(_ answer: Answer) {
        if let ref = answer.delivered { handedBack(ref).written(ref) }
    }

    private func handedBack(_ ref: SendRef) -> ListenerQueue {
        deliveredBy.removeValue(forKey: ref) ?? listeners.queue(for: ref.review)
    }

    func connectionClosed(_ connection: UUID) {
        listeners.connectionClosed(connection)
    }

    func stopLease() {
        _ = lease.stop(at: now())
    }

    func settleLease() {
        _ = lease.settle(at: now())
    }

    private func leaseChanged() {
        if indicator.lease != lease { indicator.lease = lease }
        settling?.cancel()
        settling = nil
        let time = now()
        if let term = lease.current(at: time) {
            for (ticket, waiter) in waiters where waiter.holder.key == term.holder.key {
                waiters[ticket] = nil
                waiter.timeout?.cancel()
                waiter.answer.resume(returning: granting(term, json: waiter.json))
            }
        }
        guard let next = lease.nextEnd(after: time) else { return }
        let left = next.timeIntervalSince(time)
        settling = Task { [weak self] in
            try? await Task.sleep(for: .seconds(left))
            guard !Task.isCancelled else { return }
            self?.settleLease()
        }
    }

    func start(heartbeat: Duration = SocketListener.heartbeat) throws(SocketListener.Failure) {
        guard listener == nil else { return }
        listener = try SocketListener.open(at: socket, heartbeat: heartbeat) { [weak self] data, connection in
            await self?.reply(to: data, connection: connection) ?? Answer(reply: .refused("\(AppIdentity.appName) is quitting"))
        } written: { [weak self] answer in
            self?.written(answer)
        } undelivered: { [weak self] answer in
            self?.undelivered(answer)
        } hungUp: { [weak self] connection in
            self?.connectionClosed(connection)
        } quit: { [weak self] in
            self?.quit()
        }
    }

    func stop() {
        listener?.close()
        listener = nil
        settling?.cancel()
        settling = nil
        for waiter in waiters.values {
            waiter.timeout?.cancel()
            waiter.answer.resume(returning: Answer(reply: .refused("\(AppIdentity.appName) is quitting")))
        }
        waiters = [:]
        listeners.stop()
    }
}

