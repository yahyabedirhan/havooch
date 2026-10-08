import AppKit
import ReviewCore
import ReviewLease
import ReviewWire

/// Why the app refuses an action, as the one line the command prints.
nonisolated struct AppRefusal: Error, Equatable {
    var reason: String

    init(_ reason: String) {
        self.reason = reason
    }
}

/// The app as the control server drives it: its windows, and what isn't
/// one window's. `AppModel` is the real one; the server's tests use a fake.
protocol AppControlling: AnyObject {
    /// What the window `window` names shows, else the key window's, with
    /// every window. Refused for a window that isn't there.
    func state(window: String?) throws(AppRefusal) -> StateReport
    /// The window an operator command acts on: the one `id` names, else
    /// the key window. With `making`, a new window when there is none.
    func controlledWindow(_ id: String?, making: Bool) throws(AppRefusal) -> any WindowControlling
    /// `havooch open`: opens the video for the person, in the project
    /// `project` or the one that lists it, plays it and brings its window
    /// and the app to the front: the window that holds it, else an empty
    /// key window, else a new one. A file that doesn't play changes nothing.
    @discardableResult
    func openInFront(_ url: URL, project: String?) async throws(AppRefusal) -> any WindowControlling
    /// The review a `wait` listens to: the one the video at `video`
    /// (`--video`) opens in, or the project `project`, else the key
    /// window's. Refused for a path with no file, an unknown project, and
    /// with neither when the key window holds no video.
    func listenedReview(video: String?, project: String?) async throws(AppRefusal) -> ReviewKey
    /// `havooch project new`: the project in `config.toml`, v1 the video,
    /// with the video's review moved into it.
    func projectNew(_ slug: String, from url: URL, title: String?) async throws(AppRefusal) -> StateReport.Project
    /// `havooch project add`: the next version, shown in the project's
    /// window, in front.
    @discardableResult
    func projectAdd(_ slug: String, video url: URL, label: String?) async throws(AppRefusal) -> any WindowControlling
    /// Every window, in the order they were made.
    func windowList() -> [StateReport.Window]
    /// A new empty window, as File › New Window makes one.
    func openWindow() -> StateReport.Window
    /// Closes the window `id` names, else the key window.
    func closeWindow(_ id: String?) throws(AppRefusal) -> StateReport.Window
    /// Every theme, and the files left out.
    func themeList() -> StateReport.ThemeList
    /// Pins the theme called `name`, or follows the system for `system`.
    func setTheme(_ name: String) throws(AppRefusal) -> StateReport.Theme
    /// What Havooch detects of the setup, read from disk again.
    func setupStatus() -> StateReport.Setup
    /// Links the `havooch` command in `~/.local/bin`, as Link does, or
    /// with `dryRun` says what it would do; the line says which.
    func linkCommand(dryRun: Bool) throws(AppRefusal) -> (line: String, setup: StateReport.Setup)
    /// Starts installing the skill for the harnesses `harnesses` name, or
    /// every harness found without it, as Install does; with `dryRun` only
    /// plans it.
    func installSkill(harnesses: [String], dryRun: Bool) throws(AppRefusal) -> StateReport.Setup.Install
    /// Stops the running install, as Cancel does, once it has stopped.
    func cancelInstall() async throws(AppRefusal) -> StateReport.Setup.Install
    /// Closes the settings notice, as its close button does; false when
    /// none was up.
    func dismissConfigNotice() -> Bool
}

/// One window as the control server drives it: the actions an operator
/// can take in it. `WindowModel` is the real one.
protocol WindowControlling: AnyObject {
    /// The window's name for `--window`: `w1`.
    var id: String { get }
    /// The AppKit window that shows it, for a screenshot; nil off screen.
    var nsWindow: NSWindow? { get }
    func state() -> StateReport
    func open(_ url: URL) async throws(AppRefusal)
    /// Goes home, as a click on the Havooch mark does: the video closes
    /// and an in-app demo is left.
    func goHome() async
    /// Runs the demo in the window, as "Try the Demo" does.
    func openDemo() async throws(AppRefusal)
    func play() throws(AppRefusal)
    func pause() throws(AppRefusal)
    func seek(to seconds: Double) async throws(AppRefusal)
    /// Queues a message on the thread of the frame at `at`, or at the
    /// player's time, or on `thread`, on `region` of the frame when it has
    /// one, once the keyframe and the crop are on disk.
    func addMessage(
        text: String, at: Double?, region: Region?, thread: String?
    ) async throws(AppRefusal) -> (message: StateReport.Message, thread: StateReport.Thread)
    /// Opens the popover at the player's frame, on `region` when
    /// it has one, with `text` in its field, as C or a drawn rectangle does.
    func openPopover(text: String, region: Region?) throws(AppRefusal) -> StateReport.Popover
    func editMessage(_ id: String, text: String) throws(AppRefusal) -> StateReport.Message
    func deleteMessage(_ id: String) throws(AppRefusal) -> StateReport.Message
    /// Sets the open video's context note, without the space around it,
    /// and returns it as it's kept. An empty text clears the note.
    func setContextNote(_ text: String) throws(AppRefusal) -> String
    /// Sends every queued message as one send, and hands it to the
    /// listener queue.
    func sendQueue() async throws(AppRefusal) -> StateReport.Send
    /// Answers the open question on a thread, as the answer field does.
    func answer(_ thread: String, text: String) throws(AppRefusal) -> (message: StateReport.Message, number: Int)
    /// Answers the open question on a thread with its quick-reply choice
    /// `number` (from 1), as a click on that choice's button does.
    func choose(_ thread: String, choice number: Int) throws(AppRefusal) -> (message: StateReport.Message, number: Int)
    /// Opens a thread's popover on its frame, as a click on its pin does,
    /// first keeping it at `frame` when there is one.
    func openThread(_ thread: String, frame: PopoverFrame?) async throws(AppRefusal) -> StateReport.Popover
    /// Shows a thread's view in the sidebar, as a click on its row does:
    /// the player pauses on the thread's frame.
    func showThread(_ thread: String) async throws(AppRefusal) -> (sidebar: StateReport.Sidebar, number: Int)
    /// Shows the thread list in the sidebar, as Back does.
    func showThreadList() -> StateReport.Sidebar
    /// Puts words, a region chip and the General toggle in the composer at
    /// the sidebar's foot, as the person types, draws and clicks.
    func compose(text: String, region: Region?, general: Bool) throws(AppRefusal) -> StateReport.Sidebar.Composer
    /// Shows the Connect view in the sidebar, as the connect button does.
    func showConnect() throws(AppRefusal) -> StateReport.Sidebar
    /// Picks a harness in the Connect view, as a click on its logo does.
    func pickHarness(named name: String) throws(AppRefusal) -> StateReport.Sidebar
    /// Lets the connected agent go, as Disconnect does; its name.
    func disconnectAgent() throws(AppRefusal) -> String
    /// Stops waiting for the agent that reconnects, as Forget does; its name.
    func forgetAgent() throws(AppRefusal) -> String
    /// Shows the setup tour, as "Finish setup" does.
    func showTour() throws(AppRefusal) -> StateReport.Tour
    /// The tour's next step, as Next does; after the last one it ends.
    func nextTourStep() throws(AppRefusal) -> StateReport.Tour
    /// Ends the tour, as Skip Tour does.
    func skipTour() throws(AppRefusal) -> StateReport.Tour
    /// Closes the tour's panel, as its close button does; it keeps its step.
    func closeTour() throws(AppRefusal) -> StateReport.Tour
}

/// App control's server: it decodes each request, checks the lease and
/// dispatches it, one JSON request per connection with one reply. The
/// socket, each connection and the heartbeat are `SocketListener`'s, which
/// reads each request off the main actor and hands it here
/// (`reply(to:)`). Every refusal is a reply, so the `havooch`
/// command always has a line to print. The server owns the one lease: an
/// operator request asks it first, and a `take`'s reply granting it that
/// can't be written (its client gone) gives it up at once. A listener's
/// requests go to the `ListenerHub`, with no lease: a `wait` and an `ask`
/// are held like a `take` in line, and a send whose reply can't be written
/// goes back to the front of the listener's line.
final class ControlServer {
    /// A reply, whether the app quits once it's written, and what only the
    /// client would know, undone when the reply can't be written
    /// (`undelivered`): the lease a `control take`'s reply grants, and the
    /// send a `wait`'s reply carries.
    nonisolated struct Answer: Equatable {
        var reply: ControlReply
        var quits = false
        var granted: LeaseTerm?
        var delivered: SendRef?
        /// Nothing is written: the connection just closes, as it does when
        /// the app isn't there, so a `wait` connects again.
        var silent = false
    }

    let socket: URL
    private let app: any AppControlling
    /// The listeners on the data the app is on now, one per review: the open `wait`s
    /// and the sends in line. Asked at each request, since an in-app demo
    /// switches the app's data (L27).
    private let currentListeners: @MainActor () -> ListenerHub
    /// The listener's side on the data the app is on now.
    private var listeners: ListenerHub { currentListeners() }
    /// The queue that handed out each send whose reply is being written:
    /// its `written` or `undelivered` goes back there, also when the app
    /// switched its data meanwhile.
    private var deliveredBy: [SendRef: ListenerQueue] = [:]
    private let screenshotter: any Screenshotting
    private let quit: @MainActor () -> Void
    /// The time the lease is decided at, and the zone its refusals name it in.
    private let now: @MainActor () -> Date
    private let timeZone: TimeZone
    /// App control's lease: who may send operator requests, and until when.
    /// Each change is shown (`indicator`) and its end looked out for.
    private(set) var lease: ControlLease {
        didSet { leaseChanged() }
    }
    /// The agent-control icon, which follows the lease.
    let indicator: AgentControlIcon
    /// Ends the lease once it runs out, when no request comes to.
    private var settling: Task<Void, Never>?
    /// The `take`s waiting in line, each holding its connection open until
    /// it gets the lease or its wait runs out.
    private var waiters: [UUID: Waiter] = [:]
    private var listener: SocketListener?

    /// A `take` waiting in line: who sent it, how long it waits, and how it
    /// gets its answer.
    private struct Waiter {
        var holder: Holder
        var seconds: Int
        var json: Bool
        var answer: CheckedContinuation<Answer, Never>
        /// Ends the wait when it runs out; cancelled once it's answered.
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
        // `didSet` doesn't run in `init`: a lease a relaunch handed over is
        // shown, and its end looked out for, from the start.
        leaseChanged()
    }

    // MARK: - Dispatch

    /// The answer to one request as the client sent it. A request that
    /// doesn't read, or speaks another version, is refused before anything
    /// is done. An operator request asks the lease first: refused for
    /// anyone but its holder, with nothing done. A quit hands the lease
    /// back in its reply, for a relaunch to pass on. A `take` that waits in
    /// line is answered once it gets the lease or its wait runs out, other
    /// requests answered meanwhile; so is a listener's `wait`, once a send
    /// is made. `connection` names the connection the request came over,
    /// so a held `wait` ends when its client goes away (`connectionClosed`).
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
        // The window an operator command acts on: `--window`, else the key
        // window; one that shows something makes a window when there's none.
        let window = message.window
        func inWindow(making: Bool = false) throws(AppRefusal) -> any WindowControlling {
            try app.controlledWindow(window, making: making)
        }
        do throws(AppRefusal) {
            switch message.request {
            case .controlTake(let seconds):
                return await take(by: message.holder, waiting: seconds, json: json)
            case .controlRelease:
                // The next waiter's take is answered as the lease changes (`leaseChanged`).
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
            case .screenshot(let path, let appearance, let hideAgentIndicator, let which):
                // A player window is the one `--window` names, else the key one.
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
                        "the person disconnected you from this video in \(AppIdentity.appName): stop listening and tell the person"
                    ))
                case .gone:
                    return Answer(reply: .refused("\(AppIdentity.appName) is quitting"), silent: true)
                }
            case .ack(let sendID, let text):
                let send = try listeners.ack(sendID, text: text)
                let count = send.messageIds.count
                return done("\(send.id) acknowledged, \(count) message\(count == 1 ? "" : "s")", Output(send: send), json)
            case .status(let messageID, let status, let text):
                // Every status is a message state of the same name.
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
                // A frame is a rectangle of the video area, checked as a region is.
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
                return done("the tour is skipped; Finish setup or havooch tour show starts it again", Output(tour: tour), json)
            case .tourClose:
                let tour = try inWindow().closeTour()
                return done(tour.line, Output(tour: tour), json)
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
                // The command brings this process to the front, as for `open`.
                answer.reply.pid = ProcessInfo.processInfo.processIdentifier
                return answer
            case .configDismiss:
                let closed = app.dismissConfigNotice()
                return done(closed ? "the settings notice is closed" : "no settings notice was up", Output(dismissed: closed), json)
            }
        } catch {
            return Answer(reply: .refused(error.reason))
        }
    }

    /// What an action prints with `--json`: only the parts it changed.
    private struct Output: Encodable {
        var app: StateReport.App?
        /// The window the command acted on: its id.
        var window: String?
        var windows: [StateReport.Window]?
        var screen: StateReport.Screen?
        var video: StateReport.Video?
        var player: StateReport.Player?
        var project: StateReport.Project?
        var path: String?
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

        /// The thread a message went on: its id and its number.
        struct ThreadRef: Encodable {
            var id: String
            var number: Int
        }
    }

    /// `#3` for a thread a command named, or nil when it isn't one.
    private static func name(_ ref: ReviewCore.ThreadRef?) -> String? {
        switch ref {
        case .number(let number): "#\(number)"
        case .id(let id): "#\(id.number)"
        case nil: nil
        }
    }

    /// What the Connect view says of a harness's readiness, as words.
    private static func words(readiness: String) -> String {
        switch Readiness(rawValue: readiness) {
        case .ready: "ready, the skill is detected"
        case .skillNotDetected: "the skill isn't detected; paste the prompt if it's installed another way"
        case .harnessNotDetected: "the harness isn't detected; paste the prompt if it's installed another way"
        case nil: readiness
        }
    }

    /// The region `rectangle` names. Numbers that aren't a region of the
    /// frame are refused before the app is asked for anything.
    private static func region(_ rectangle: ControlRequest.Rectangle?) throws(AppRefusal) -> Region? {
        guard let rectangle else { return nil }
        do throws(ReviewRefusal) {
            return try Region(x: rectangle.x, y: rectangle.y, w: rectangle.w, h: rectangle.h)
        } catch {
            throw AppRefusal(error.line)
        }
    }

    /// What the window `window` names (else the key window) shows, with
    /// the lease and the listener as they are now.
    private func state(window: String?) throws(AppRefusal) -> StateReport {
        var state = try app.state(window: window)
        state.lease = lease.status(at: now())
        return state
    }

    private func done(_ output: String) -> Answer {
        Answer(reply: .done(output))
    }

    /// Done: `line`, or `output` as JSON when the caller passed `--json`.
    private func done(_ line: String, _ output: Output, _ json: Bool) -> Answer {
        Answer(reply: .done(json ? StateReport.json(output) : line + "\n"))
    }

    // MARK: - Taking turns

    /// `control take`: held to the cap at once when the lease is the
    /// holder's or free. While another holds it, refused at once without a
    /// wait; with one, the take waits in line, suspended so the main actor
    /// answers other requests (the holder's release among them), until
    /// `leaseChanged` finds the lease handed to it or its wait runs out.
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
        // Queued only with a wait after now.
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

    /// A waiting `take`'s wait ran out (unless it was answered already): it
    /// leaves the line, refused with who still holds the lease, or holding
    /// it should it be free by now.
    private func waitRanOut(_ ticket: UUID, deadline: Date) {
        guard let waiter = waiters.removeValue(forKey: ticket) else { return }
        // Never before the deadline the take was given, whatever the clock says.
        let time = max(now(), deadline)
        switch lease.giveUp(by: waiter.holder, waited: waiter.seconds, at: time).answer {
        case .success(let term):
            waiter.answer.resume(returning: granting(term, json: waiter.json))
        case .failure(let refusal):
            waiter.answer.resume(returning: Answer(reply: .refused(refusal.message(at: time, timeZone: timeZone))))
        }
    }

    /// A `take`'s answer holding the lease to `term`'s end, which it grants.
    private func granting(_ term: LeaseTerm, json: Bool) -> Answer {
        var answer = done(term.held(timeZone: timeZone), Output(lease: lease.status(at: now())), json)
        answer.granted = term
        return answer
    }

    /// A `take`'s reply that granted the lease couldn't be written: its
    /// client has gone (stopped, or cut off by its harness's timeout while
    /// it waited in line), so nobody knows they hold it. The lease is given
    /// up for that holder at once, and the next waiter gets it as usual,
    /// rather than it sitting unused until it runs out. A lease that has
    /// moved on meanwhile (another holder's, or a new one) is left alone.
    /// A `wait`'s reply that carried a send and couldn't be written: the
    /// listener never got the send, so it's first in its line again.
    func undelivered(_ answer: Answer) {
        if let ref = answer.delivered { handedBack(ref).undelivered(ref) }
        guard let granted = answer.granted, let term = lease.current(at: now()),
              term.holder.key == granted.holder.key, term.taken == granted.taken else { return }
        _ = lease.release(by: granted.holder, at: now())
    }

    /// A reply was written to its client: a send it carried is taken from
    /// now on.
    func written(_ answer: Answer) {
        if let ref = answer.delivered { handedBack(ref).written(ref) }
    }

    /// The queue that handed out `ref`, which hears how its reply went.
    private func handedBack(_ ref: SendRef) -> ListenerQueue {
        deliveredBy.removeValue(forKey: ref) ?? listeners.queue(for: ref.review)
    }

    /// The client of `connection` closed its socket while its request was
    /// held: a `wait` or an `ask` on it is over.
    func connectionClosed(_ connection: UUID) {
        listeners.connectionClosed(connection)
    }

    // MARK: - The person taking the app back

    /// The agent-control icon's Stop: the holder's lease ends and it's
    /// barred for five minutes (`ControlLease.stop`), and the first waiter
    /// in line gets the lease, its `take` answered as the lease changes. The person's only
    /// way into the lease.
    func stopLease() {
        _ = lease.stop(at: now())
    }

    // MARK: - The lease's end

    /// Ends the lease if it has run out by now, handing it to the first
    /// waiter in line, and lifts the bars that have ended. A timer calls it
    /// at the next of those ends, so the agent-control icon goes, and the
    /// waiter gets the lease, with no request.
    func settleLease() {
        _ = lease.settle(at: now())
    }

    /// The one place a change to the lease is applied: it's shown as it is
    /// now, a holder that got it from the line has its waiting `take`s
    /// answered, and its next end (the lease's or a bar's) is looked out
    /// for, the timer set for the last change replaced by one for this one.
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
            // A wake before the end settles nothing, and sets the timer again.
            try? await Task.sleep(for: .seconds(left))
            guard !Task.isCancelled else { return }
            self?.settleLease()
        }
    }

    // MARK: - Listening

    /// Starts listening on `socket` (`SocketListener.open`), with a
    /// heartbeat every `heartbeat` on each held connection.
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

    /// Stops listening and removes the socket, so the `havooch`
    /// command finds the app gone.
    func stop() {
        listener?.close()
        listener = nil
        settling?.cancel()
        settling = nil
        // A take waiting in line hears why, rather than a dropped connection.
        for waiter in waiters.values {
            waiter.timeout?.cancel()
            waiter.answer.resume(returning: Answer(reply: .refused("\(AppIdentity.appName) is quitting")))
        }
        waiters = [:]
        // An open `wait` ends with no reply: its command connects again.
        listeners.stop()
    }
}

