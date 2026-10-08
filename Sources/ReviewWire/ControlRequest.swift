import Foundation

/// What the `havooch` command asks of the running app: one request per
/// connection over `control.sock`, sent as a `ControlMessage` with its
/// holder. A new request is a case here, with its `command` name and its
/// fields in `ControlMessage`.
public enum ControlRequest: Equatable, Sendable {
    /// `havooch app status`: whether the app runs, and on which data.
    case appStatus
    /// `havooch state`: everything the app shows.
    case state
    /// `havooch control take [--wait <seconds>]`: hold the lease to
    /// its cap; while another agent holds it, wait in line up to
    /// `waitSeconds`, or be refused at once without them.
    case controlTake(waitSeconds: Int?)
    /// `havooch control release`: give the lease up.
    case controlRelease
    /// `havooch app open` while the app runs: its status.
    case appOpen
    /// `havooch app quit`: the app replies, then quits.
    case appQuit
    /// `havooch app home`: the app goes home, as a click on the Havooch
    /// mark in the header does: the video closes and an in-app demo is
    /// left. A closed window shows.
    case appHome
    /// `havooch app demo`: the app runs the demo in the same window, as
    /// "Try the Demo" does. A closed window shows.
    case appDemo
    /// `havooch open <path> [--project <slug>]`: the video at the
    /// absolute `path` opened for a person, playing, with the app brought
    /// to the front: in the project `project` when it's set, else in the
    /// most recently used project that lists it, else as a plain video. No
    /// lease: opening a file never takes control of the app from the person.
    case open(path: String, project: String? = nil)
    /// `havooch player open <path>`: the video at the absolute `path`
    /// opened, paused at its start.
    case playerOpen(path: String)
    /// `havooch player play`.
    case playerPlay
    /// `havooch player pause`.
    case playerPause
    /// `havooch player seek <time>`: the player moved to exactly
    /// `seconds`, still playing or still paused.
    case playerSeek(seconds: Double)
    /// `havooch comment add <text> [--at <time>] [--region x,y,w,h]
    /// [--thread <thread>]`: a message queued at `at` seconds, or at the
    /// player's time when it's nil, on `region` of the frame when it has
    /// one. It joins the thread of that frame or starts one; with `thread`
    /// (a thread id, or a number of the open video, `0` for General) it's
    /// written on that thread.
    case commentAdd(text: String, at: Double?, region: Rectangle? = nil, thread: String? = nil)
    /// `havooch comment open [<text>] [--region x,y,w,h]`: the comment
    /// popover opened at the player's frame, as C or a drawn rectangle
    /// opens it, on `region` when it has one, with `text` in its field. An
    /// addition to the spec's contract: the popover and its region can be
    /// shown, checked and screenshotted without a click.
    case commentOpen(text: String, region: Rectangle? = nil)
    /// `havooch comment compose [<text>] [--region x,y,w,h]
    /// [--general]`: the composer at the sidebar's foot holds `text`, as
    /// the person types it, with a region chip on the player's frame and
    /// the General toggle. An addition to the contract: the composer can
    /// be shown, checked and screenshotted without typing.
    case commentCompose(text: String, region: Rectangle? = nil, general: Bool = false)
    /// `havooch comment edit <message-id> <text>`: a queued message's
    /// new text.
    case commentEdit(id: String, text: String)
    /// `havooch comment delete <message-id>`: a queued message removed.
    case commentDelete(id: String)
    /// `havooch context set <text>`: the open video's context note,
    /// which the listener gets with the sidecar's text. An empty `text`
    /// clears it.
    case contextSet(text: String)
    /// `havooch send`: every queued message of the open video sent as
    /// one send, which the listener's `wait` gets.
    case send
    /// `havooch wait [--video <path> | --project <slug>] [--timeout
    /// <seconds>]`: the next send of one review as its JSON payload: the
    /// review the video at the absolute `video` path opens in, or the
    /// project `project`'s, else the key window's. The app holds the
    /// request until a send is made, up to `timeoutSeconds`, or with no
    /// limit when it's nil. The sender is that review's listener, present
    /// while its `wait` is open.
    case wait(timeoutSeconds: Int?, video: String? = nil, project: String? = nil)
    /// `havooch ack <send-id> [<text>]`: the listener has the send.
    /// Its messages are acknowledged, and `text` is the agent's message on
    /// the General thread.
    case ack(sendID: String, text: String?)
    /// `havooch status <message-id> working|done|failed [<text>]`: how
    /// far the listener is with a message. With `working`, `text` is what
    /// the agent does now, the live line the thread view and the footer
    /// show; `done` and `failed` clear it.
    case status(messageID: String, state: Status, text: String? = nil)
    /// `havooch reply <thread> <text>`: the listener's message on a
    /// thread (a thread id, or a number of the open video).
    case reply(thread: String, text: String)
    /// `havooch ask <thread> <question> [--choice <text>]...
    /// [--wait <seconds>]`: the listener's question on a thread, with the
    /// quick replies the person may answer with in one click. The app holds
    /// the request until the person answers, up to `waitSeconds`, or with
    /// no limit when it's nil.
    case ask(thread: String, question: String, waitSeconds: Int?, choices: [String] = [])
    /// `havooch thread answer <thread> <text>`: the answer to a
    /// thread's open question, as the person gives it in the app.
    case threadAnswer(thread: String, text: String)
    /// `havooch thread choose <thread> <number>`: the open question
    /// answered with its quick-reply choice `choice` (from 1), as a click
    /// on that choice's button answers it.
    case threadChoose(thread: String, choice: Int)
    /// `havooch thread open <thread> [--frame x,y,w,h]`: the thread
    /// popover opened on the thread's frame, as a click on its pin or its
    /// badge opens it. With `frame` (0 to 1 of the video area, from its
    /// top-left corner) the popover is first kept there, as a drag and a
    /// resize leave it. An addition to the spec's contract: the CLI can't
    /// click, drag or resize.
    case threadOpen(thread: String, frame: Rectangle? = nil)
    /// `havooch thread show <thread>`: the sidebar shows the thread's
    /// view, as a click on its row in the thread list shows it.
    case threadShow(thread: String)
    /// `havooch thread list`: the sidebar shows the thread list, as
    /// Back in a thread view shows it.
    case threadList
    /// `havooch thread versions [--search <text>]`: a project's thread
    /// list with "All versions" open, its search set to `search`.
    case threadVersionsOpen(search: String?)
    /// `havooch thread versions --close`: "All versions" closes.
    case threadVersionsClose
    /// `havooch thread version <n> [--remove]`: the version `number` picked
    /// in "All versions", which adds an older version's section to the
    /// thread list and scrolls to it; with `remove`, a picked version's
    /// section leaves the list, as its close button takes it.
    case threadVersion(number: Int, remove: Bool)
    /// `havooch screenshot <abs.png> [--appearance light|dark]
    /// [--hide-agent-indicator] [--window main|settings|about|first-run|<id>]`: the
    /// app's `window` written as a PNG at the absolute `path`; for `main`,
    /// the player window the message's `window` names, else the key one, in `appearance`
    /// when it's set, as the Mac shows it otherwise. The agent-control
    /// indicator shows as the person sees it, unless `hideAgentIndicator`
    /// leaves it out. The Settings window is opened for the capture, as
    /// ⌘, opens it, and closed again when it was closed before.
    case screenshot(path: String, appearance: Appearance?, hideAgentIndicator: Bool = false, window: Window = .main)
    /// `havooch theme list`: every theme the app knows, and which one
    /// is active and pinned.
    case themeList
    /// `havooch theme set <name>`: the theme called `name` pinned, or
    /// the pin cleared for `system`, so the theme follows the system
    /// appearance again.
    case themeSet(name: String)
    /// `havooch setup status`: what Havooch detects of the setup, read
    /// from disk again: the command link, each harness and its skill, and
    /// the install.
    case setupStatus
    /// `havooch setup link [--dry-run]`: the `havooch` command linked in
    /// `~/.local/bin`, as Link does. With `dryRun`, only what it would do.
    case setupLink(dryRun: Bool = false)
    /// `havooch setup install [--harness <name>]... [--dry-run]`: the
    /// `havooch-mate` skill installed globally with `npx skills add`, for
    /// the `harnesses` named, or for every harness found without it when
    /// none is, as Install does. It starts the install and answers; `setup
    /// status` follows its log. With `dryRun`, only the command it would run.
    case setupInstall(harnesses: [String] = [], dryRun: Bool = false)
    /// `havooch setup cancel`: the running install stopped, as Cancel does.
    case setupCancel
    /// `havooch connect show`: the Connect view in the sidebar, as the
    /// header's connect button opens it.
    case connectShow
    /// `havooch connect pick <harness>`: the harness picked in the Connect
    /// view, as a click on its logo picks it: its readiness and its prompt
    /// show.
    case connectPick(harness: String)
    /// `havooch connect disconnect`: the window's agent let go, as
    /// Disconnect on the listener card does. Its open `wait` is refused.
    case connectDisconnect
    /// `havooch connect forget`: the agent the last run had is no longer
    /// waited for, as Forget does while it reconnects.
    case connectForget
    /// `havooch tour show`: the setup tour over the stage, as "Finish
    /// setup" opens it, at the step it was left on.
    case tourShow
    /// `havooch tour next`: the tour's next step, as Next or Later on its
    /// panel; after the last step the tour ends, as Finish does.
    case tourNext
    /// `havooch tour skip`: the tour ends, as Skip Tour does; it starts
    /// from the first step next time.
    case tourSkip
    /// `havooch tour close`: the tour's panel goes, as its close button
    /// does; the tour keeps its step.
    case tourClose
    /// `havooch first-run show [<step>]`: the first-run window shows, as
    /// on the first launch, on `step` (`welcome`, `tools`, `connect`,
    /// `try-it`) as a click on its progress bar shows it, else where it was.
    case firstRunShow(step: String? = nil)
    /// `havooch first-run next`: the first-run window's next step, as
    /// Get Started, Continue, Continue Anyway and Later go on.
    case firstRunNext
    /// `havooch first-run back`: the step before, as Back goes back.
    case firstRunBack
    /// `havooch first-run pick <harness>`: the harness picked on the
    /// Connect step, as a click on its logo picks it: its demo prompt shows.
    case firstRunPick(harness: String)
    /// `havooch first-run demo`: the bundled demo video opened for the
    /// person and the first-run window closed, as Open the Demo does.
    case firstRunDemo
    /// `havooch first-run skip`: the first-run window closed, as Skip
    /// Setup and its close button close it.
    case firstRunSkip
    /// `havooch config dismiss`: the settings notice in the window goes,
    /// as its close button does.
    case configDismiss
    /// `havooch window list`: every window, in the order they were made,
    /// with what each holds and which one is key.
    case windowList
    /// `havooch window new`: a new empty window that shows the home
    /// screen, as File › New Window makes one.
    case windowNew
    /// `havooch window close [<id>]`: a window closed, as its close
    /// button closes it. The window is the message's `window`, else the
    /// key window.
    case windowClose
    /// `havooch project new <slug> --from <path> [--title <title>]`: a
    /// project in `config.toml` whose v1 is the video at the absolute
    /// `path`; the video's review moves into it, and its listener keeps
    /// listening (ADR 0004). No lease: the agent makes it on the person's
    /// behalf.
    case projectNew(slug: String, path: String, title: String? = nil)
    /// `havooch project add <slug> <path> [--label <label>]`: the video at
    /// the absolute `path` appended to the project as its next version,
    /// shown in the project's window, which comes forward. No lease.
    case projectAdd(slug: String, path: String, label: String? = nil)
    /// `havooch version show <n>`: the project's version `number` (from 1)
    /// on screen in the window, as a click on its segment or its row in
    /// the version picker does (E10). The playhead keeps its time.
    case versionShow(number: Int)
    /// `havooch version pick [<query>]`: the version picker open under
    /// the switcher's field, with `query` typed in its search field, as a
    /// click on the field and typing do. An addition to the contract: the
    /// picker can be shown, checked and screenshotted without a click.
    case versionPick(query: String = "")
    /// `havooch version close`: the version picker closed, as Escape
    /// closes it.
    case versionClose

    /// The four numbers of `--region x,y,w,h` as they were written. The
    /// app decides whether they're a region of the frame.
    public struct Rectangle: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var w: Double
        public var h: Double

        public init(x: Double, y: Double, w: Double, h: Double) {
            (self.x, self.y, self.w, self.h) = (x, y, w, h)
        }

        /// Reads `x,y,w,h`; nil when it isn't four numbers.
        public init?(_ text: String) {
            let numbers = text.split(separator: ",", omittingEmptySubsequences: false)
                .map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard numbers.count == 4, let x = numbers[0], let y = numbers[1], let w = numbers[2], let h = numbers[3],
                  [x, y, w, h].allSatisfy(\.isFinite)
            else { return nil }
            self.init(x: x, y: y, w: w, h: h)
        }
    }

    /// What `status` can say of a message.
    public enum Status: String, Equatable, Sendable, CaseIterable {
        case working, done, failed
    }

    /// The appearance `screenshot` draws in.
    public enum Appearance: String, Equatable, Sendable, CaseIterable {
        case light, dark
    }

    /// The window `screenshot` captures: a player window (the message's
    /// `window`), Settings, the About panel or the first-run window.
    public enum Window: String, Equatable, Sendable, CaseIterable {
        case main, settings, about
        case firstRun = "first-run"
    }

    /// Who may send a request.
    public enum Role: Equatable, Sendable {
        /// Anyone, at any time: it changes nothing a person sees.
        case free
        /// A person, or an agent on a person's behalf: it changes what the
        /// person sees as their own click would, with no lease and no
        /// agent-control icon.
        case person
        /// An agent that drives the UI: one at a time, under the lease.
        case `operator`
        /// The agent that receives sends, beside the person: no lease.
        case listener
    }

    /// The request's role, so the app and the command agree on which
    /// requests take the lease without a table.
    public var role: Role {
        switch self {
        case .appStatus, .state, .controlTake, .controlRelease, .themeList, .windowList: .free
        case .open, .projectNew, .projectAdd: .person
        case .themeSet, .configDismiss, .windowNew, .windowClose: .operator
        case .appOpen, .appQuit, .appHome, .appDemo, .playerOpen, .playerPlay, .playerPause, .playerSeek, .screenshot: .operator
        case .contextSet: .operator
        case .commentAdd, .commentOpen, .commentCompose, .commentEdit, .commentDelete, .send: .operator
        case .threadAnswer, .threadChoose, .threadOpen, .threadShow, .threadList: .operator
        case .threadVersionsOpen, .threadVersionsClose, .threadVersion: .operator
        case .wait, .ack, .status, .reply, .ask: .listener
        case .setupStatus: .free
        case .setupLink, .setupInstall, .setupCancel: .operator
        case .connectShow, .connectPick, .connectDisconnect, .connectForget: .operator
        case .tourShow, .tourNext, .tourSkip, .tourClose: .operator
        case .firstRunShow, .firstRunNext, .firstRunBack, .firstRunPick, .firstRunDemo, .firstRunSkip: .operator
        case .versionShow, .versionPick, .versionClose: .operator
        }
    }

    /// How long the app may keep the connection before it answers, past the
    /// client's usual timeout; nil for no limit. A `take` waits in line for
    /// its `waitSeconds`, a `wait` for a send for its `timeoutSeconds`,
    /// and an `ask` for its answer for its `waitSeconds`.
    public var holdSeconds: TimeInterval? {
        switch self {
        case .controlTake(let waitSeconds): TimeInterval(waitSeconds ?? 0)
        case .wait(let timeoutSeconds, _, _): timeoutSeconds.map(TimeInterval.init)
        case .ask(_, _, let waitSeconds, _): waitSeconds.map(TimeInterval.init)
        default: 0
        }
    }

    /// The longest a `control take --wait` may wait in line, in seconds.
    public static let longestWait = 3600

    /// The longest `wait --timeout` or `ask --wait` a listener may ask for,
    /// in seconds: a day. Without the option neither has a limit.
    public static let longestListen = 86400

    /// The most bytes the app reads of one request.
    public static let largestMessage = 1 << 20
}
