# Low-level design: Video Review (proto-1)

This is the design of the `proto-1` build of the v1 spec (#1), written before the first build ticket (#15). It says which modules exist, what each one owns, how a request travels and where every file sits. Each later ticket updates it in the same change, so it always matches the code.

## Start here

| You want to | Go to |
|---|---|
| see the modules and what links what | [Modules](#modules) |
| find a file | [Folder tree](#folder-tree) |
| add or change a CLI command | [The wire](#the-wire) and [Adding a command](#adding-a-command) |
| follow a command from the shell to the player | [Trace 1](#trace-1-one-cli-command-player-seek-010) |
| follow a batch from Cmd+Enter to `wait` | [Trace 2](#trace-2-one-batch-from-cmdenter-to-wait) |
| know what the listener session does with a batch | [The listener skill](#the-listener-skill) |
| know what is on disk | [Store: the layout on disk](#store-the-layout-on-disk) |
| know why the app looks and behaves as it does | [UX choices of this prototype](#ux-choices-of-this-prototype) |
| know which ticket builds which file | [Which ticket builds what](#which-ticket-builds-what) |
| rename the build, or drop the `proto-1` suffix | [Build identity](#build-identity) |

Sources of truth this document builds on, and doesn't restate: the spec (#1) for the CLI contract, the batch payload and the item states; `docs/adr/0001-agents-control-the-app-through-a-leased-cli.md` for agent control. The control design copies the patterns of Shipyard (`yahyabedirhan/shipyard` at commit `14b39a259e53`: `Sources/ShipyardControl/`, `Sources/ShipyardApp/Control/`, ADR 0006, ADR 0007). No Shipyard code is linked.

Words used one way throughout:

| Word | Meaning |
|---|---|
| **person** | the human at the Mac |
| **operator** | an agent that drives the UI through the CLI; it needs the lease |
| **listener** | the agent session that receives batches (`wait`, `ack`, `status`, `reply`, `ask`); it needs no lease |
| **holder** | who sent a control request: a key, a name and a place |
| **review** | everything kept for one video: its comments, batches, threads and note |
| **comment** | one piece of feedback at a time in the video, with an optional region |
| **region** | a rectangle on the frame, in normalized 0..1 coordinates, origin top left |
| **keyframe** | the PNG of the full frame at a comment's time |
| **crop** | the PNG of a comment's region, cut from its keyframe |
| **queue** | the comments of the open video in the state `queued` |
| **batch** | the queue as sent by one Cmd+Enter |
| **delivery** | one batch on its way to the listener: `pending`, then `taken`, then finished |
| **listener session** | one listener, named by its holder key |
| **support folder** | where the app keeps its data and its socket |

---

## Stage 1: Requirements

The 54 user stories of the spec are the requirements. They are grouped here into what the design must do, with the numbers of the stories each group covers.

### Capabilities

1. **Play** a local mp4, mov or m4v like QuickTime: open, play, pause, seek, scrub, change speed. (1, 2, 31)
2. **Comment** at the paused time, at once: the comment keeps its exact time and the frame at that time. (3, 4, 5, 8)
3. **Point**: draw a rectangle on the frame; a comment box opens next to it; the comment keeps the region and a crop. (6, 7)
4. **Queue**: comments collect in a queue; a queued comment can be edited or deleted; each comment is a marker on the timeline that seeks when clicked. (9, 10, 12, 13)
5. **Send**: Cmd+Enter sends the whole queue as one batch, whether or not a listener is present. (11, 14, 15)
6. **Deliver**: `wait` long-polls and returns the next batch as the spec's JSON payload, with absolute paths to PNG files, a transcript window per comment and the context once per listener session. (32 to 37)
7. **Answer**: the listener acknowledges a batch, sets a comment's status, sends messages on a comment or on the whole batch, and asks a question and waits for the answer. The person sees statuses on markers, threads on comments, a brief notice for each agent message, and answers a question in the thread. (16 to 21, 38 to 41, 43)
8. **Persist**: comments, batches, threads, statuses and the note survive a quit, and come back for the same video by its content, even renamed or moved. (22, 23, 24)
9. **Context**: `<base name>.context.md` beside the video, else `context.md`, plus an in-app note per video. (25, 26)
10. **Transcript**: from `voiceover.json`, else a `.srt` or `.vtt` sidecar, else on-device SpeechAnalyzer in the background, behind one interface. (27, 28, 54)
11. **Agent control**: every action above has a CLI command; operator commands need the lease; `state --json` and `screenshot` let an agent check the UI; demo mode keeps tests off the person's data. (44 to 52)
12. **The person wins**: an icon at the toolbar's trailing end shows while an agent holds the lease; its popover says who and how long, and its Stop ends the lease. (29, 30)
13. **Agent-side code builds and tests without the app.** (53)

### Rules and completion

- A comment moves through `draft → queued → sent → acknowledged → working → done | failed`, forward only. `done` and `failed` are final.
- Only a `queued` comment can be edited or deleted.
- A batch holds every comment that was `queued` at the send. It is finished when all its comments are `done` or `failed`.
- A batch that a listener took and didn't finish goes back to the queue of deliveries when another listener session starts.
- The context goes out with the first batch a listener session gets for a video, and again only when its text changed.
- The lease follows Shipyard's rules: renewed by each operator command, ended 60 s after the last one, ended 5 min after it was taken at most; `take --wait` queues first come, first served; Stop bars the holder for 5 min.
- A request of another protocol version is refused, naming both versions.

### Error handling

- Every refusal is one line on standard error and a non-zero exit code; the app's state doesn't change.
- Exit codes: `0` done, `1` refused or failed (another holder has the lease, the app isn't running, an unknown id, an illegal transition), `2` the command line doesn't parse, `3` a `wait --timeout` or `ask --wait` ran out with nothing to return.
- A keyframe or crop that can't be written fails the `comment add` that needed it, since the payload promises both paths.
- A file on disk that doesn't read (a damaged `review.json`) is moved aside as `review.json.unreadable` and the review starts empty; the app never crashes on its own data.

### Scope

In: all of the above, for one window and one video at a time, and one listener at a time.

Out (from the spec, kept out of the design): video editing, formats AVPlayer can't play, video URLs, system-wide hotkeys, more than one listener, shapes other than rectangles, the transcription research, Developer ID signing. Also out, decided here because nothing asks for them: more than one window, undo, a list of recent videos, macOS notifications for agent messages, delivering a person's message that doesn't answer a question.

### Requirement to module

| Capability | Module that owns the rule | Other modules it passes through |
|---|---|---|
| 1 Play | App (`Player/`) | |
| 2, 3, 4 Comment, point, queue | Review (`Review`, `Region`) | App (`Comments/`, `Overlay/`, `Timeline`), Store (PNG paths) |
| 5 Send | Review (`Review.sendBatch`) | App (`ReviewDesk`), Store |
| 6 Deliver | Review (`ListenerLedger`, `BatchPayload`) | App (`Mate/ListenerQueue`), Wire, Command |
| 7 Answer | Review (state machine, threads) | App (`Mate/`, `Comments/`), Wire, Command |
| 8 Persist | Store | App (`ReviewDesk`) |
| 9 Context | Review (`ContextText`) | App (`Mate/ContextSource`), Store (the note) |
| 10 Transcript | Transcript | Store (cache), App (starts it) |
| 11 Agent control | Wire, Command | App (`Control/`) |
| 12 The person wins | Lease | App (`Control/LeaseBanner`) |
| 13 Builds without the app | `Package.swift` | |

---

## Stage 2: Entities and relationships

A noun that holds changing state or enforces a rule is an entity. A noun that is only information on another is a field.

### Entities

| Entity | Holds | Enforces |
|---|---|---|
| **AppModel** | the open video, and one of each entity below | nothing itself: it is the orchestrator; every action a person or an agent can take is one method on it |
| **PlayerEngine** | the `AVPlayer`, the time, the rate, the duration | seeking is exact; a seek answers when it has landed |
| **Review** | one video's comments, batches, batch threads, note and id counters | the comment state machine; who may edit what; what a batch contains |
| **ReviewDesk** | the reviews in memory, by content hash; the draft | every change to a review is saved, and its images written, before it is answered |
| **ListenerLedger** | the listener session and the deliveries | which batch goes to whom; requeue on a new session; context once per session; presence |
| **ListenerQueue** | the open `wait` and `ask` connections, the ledger, the batches whose reply is being written | a batch is taken only once its reply was written, and is never handed to two waits; one listener session at a time |
| **ControlLease** | the lease's term, the line of waiters, the bars | the lease rules |
| **ControlServer** | the socket and the one `ControlLease` | every request is decoded, version-checked and leased before it reaches `AppModel` |
| **ReviewStore** | the files under the support folder | the layout on disk; atomic writes; demo data apart from real data |
| **Transcriber** | the timed lines of a video, as far as they exist | the source order |

Fields, not entities: a **region** (on a comment), a **thread message** (in a comment's or a batch's thread), a **keyframe** and a **crop** (files named by the comment's id), a **holder** (on a request and on the lease), a **notice** (the last agent message, on `AppModel`), **presence** (derived from the ledger and the open connections, never stored).

### Relationships

```text
Person ──keys, mouse──▶ Views ─┐
                               ├─▶ AppModel ─▶ PlayerEngine ─▶ AVPlayer
Agent ─▶ video-review (CLI)    │      │
           │  Wire             │      ├─▶ ReviewDesk ─▶ Review (rules)
           ▼                   │      │        ├─▶ ReviewStore ─▶ disk
      control.sock ─▶ ControlServer   │        └─▶ FrameGrabber ─▶ PNG files
                         │            │
                         └─▶ ControlLease
                                      ├─▶ ListenerQueue ─▶ ListenerLedger (rules)
                                      │        └─▶ BatchPayload (rules)
                                      └─▶ Transcriber ─▶ sources
```

- `AppModel` **has** one `PlayerEngine`, one `ReviewDesk`, one `ListenerQueue` and one `Transcriber`.
- `ControlServer` **has** the one `ControlLease` and **uses** `AppModel`. The views use `AppModel` too. Neither reaches past it, so the UI and the CLI can't drift apart: a new action is a new `AppModel` method with two callers.
- `ReviewDesk` **has** the reviews and **uses** `ReviewStore` and `FrameGrabber`. A `Review` is a value: the desk changes a copy through the review's own methods, saves it, then publishes it.
- `ListenerQueue` **has** the `ListenerLedger` and **uses** `ReviewDesk` (to read a batch and to change comment states) and the desk's `ReviewStore`, which keeps the ledger.
- Rules live with the state they guard: comment and batch rules in `Review`, delivery and context rules in `ListenerLedger`, lease rules in `ControlLease`. All three are pure values given the time on each call, so they test without the app.

---

## Stage 3: Class design

### Modules

The spec's seven modules are SwiftPM targets. The prefix `VR` keeps a module's name apart from the types inside it (`Review`, `ControlLease`) and from SwiftUI's `App`.

| Spec module | Target | Kind | Owns | Depends on |
|---|---|---|---|---|
| **Lease** | `VRLease` | library, agent side | `Holder` and how it is found; `ControlLease`, the lease rules as a pure value | nothing |
| **Wire** | `VRWire` | library, agent side | the build identity; the protocol version; `ControlRequest`, `ControlMessage`, `ControlReply`; the socket's place, the demo pointer; the socket client | `VRLease` |
| **Command** | `VRCommand` + `VRCLI` | library + executable, agent side | the command table: arguments to a `ControlRequest`, a reply to output and an exit code; launching the app. `VRCLI` is its `main.swift` only | `VRWire`, `VRLease` |
| **Review** | `VRReview` | library, app side, pure | `Review` and its state machine; `Region`; `BatchPayload`; `ListenerLedger`; `Presence`; `ContextText` | nothing |
| **Transcript** | `VRTranscript` | library, app side | `Transcriber`, `TimedLine`, the three sources, the window cut | nothing (Foundation, AVFoundation, Speech) |
| **Store** | `VRStore` | library, app side | the layout on disk, the content hash, loading and saving reviews, the ledger, the transcript cache | `VRReview`, `VRTranscript` |
| **App** | `VRApp` | executable, the only UI code | the window, the player, the overlay, the control server, the listener queue | all six |

```text
VRCLI ─▶ VRCommand ─▶ VRWire ─▶ VRLease          agent side: never links below this line
─────────────────────────────────────────────
VRApp ─▶ VRWire, VRLease
VRApp ─▶ VRStore ─▶ VRReview
            └─────▶ VRTranscript
VRApp ─▶ VRReview, VRTranscript
```

`Package.swift` is the guard: `VRCLI` and `VRCommand` list only `VRWire` and `VRLease`. An agent-side target importing `VRReview`, `VRStore` or `VRTranscript` is a design change, not a shortcut.

`Package.swift` lists eight targets: the four agent-side ones (`VRLease`, `VRWire`, `VRCommand`, `VRCLI`), then `VRReview`, `VRTranscript`, `VRStore` and `VRApp`. Each library and the app has a test target of its own.

Two choices keep the agent side thin:

- **The CLI never reads a payload.** The app builds every output, text or JSON, and puts it in the reply's `output`. The CLI prints it. So `BatchPayload` and the state snapshot live on the app's side, and the CLI needs no type from `VRReview`.
- **`VRReview` and `VRTranscript` don't know each other.** The payload has its own `Line` (`start`, `end`, `text`); the app copies a `TimedLine` into it. Each module is built and tested alone.

Products: `VideoReview` (the app's executable, from `VRApp`) and `video-review-cli` (from `VRCLI`; `make bundle` copies it into the app as `Contents/Helpers/video-review`).

### Build identity

One setting names the build: `Identity.variant` in `Sources/VRWire/Identity.swift`.

```swift
public enum Identity {
    /// The one build setting. "proto-1" for this prototype; "" for the real product.
    public static let variant = "proto-1"
    public static let version = "0.1.0"

    public static var appName: String        // "Video Review (proto-1)"   | "Video Review"
    public static var bundleID: String       // "com.yahyabedirhan.video-review.proto-1" | "…video-review"
    public static var supportFolderName: String   // = appName
}
```

- The app and the CLI both link `VRWire`, so they can't disagree about the support folder or the bundle id.
- The `Makefile` reads the same line with `sed` (as Shipyard reads its version from `Version.swift`) and derives `APP_NAME` and `BUNDLE_ID` the same way. It stamps them into `Packaging/Info.plist` (`__APP_NAME__`, `__BUNDLE_ID__`, `__VERSION__`) and names the bundle `build/$(APP_NAME).app`.
- Clearing the string to `""` gives `Video Review.app`, `com.yahyabedirhan.video-review` and `~/Library/Application Support/Video Review/`. Nothing else changes.
- The CLI keeps the name `video-review`. Run it from this build's bundle, `/Applications/Video Review (proto-1).app/Contents/Helpers/video-review`, never from `PATH`: another prototype's CLI would speak to another prototype's socket. The listener skill finds it without knowing the variant ([The listener skill](#the-listener-skill)).
- The app's executable is `VideoReview` in every prototype, so `make install` never uses `pkill -x`. It quits this build only, by its full path: `pkill -f` with `/Applications/$(APP_NAME).app/Contents/MacOS/`. `pkill -f` reads a regular expression, so the `Makefile` escapes the name's parentheses and dots first (`RUNNING`); unescaped, the pattern would match no process.

### Folder tree

```text
Package.swift                         the eight targets and their links; swift-tools-version 6.2, macOS 26
Makefile                              build, test, bundle, install, acceptance, run, clean; reads Identity.variant
Packaging/
  Info.plist                          the bundle's template: name, bundle id, version, video document types, usage strings

Sources/
  VRLease/                            ── agent side ──
    Holder.swift                      who sends a request; Holder.find from the session id, the ancestor process or the key variable
    ProcessTable.swift                the process table Holder.find walks (sysctl on macOS, /proc on Linux), and its protocol for tests
    ControlLease.swift                the lease rules: use, take, release, stop, settle, giveUp, status
  VRWire/
    Identity.swift                    the build setting and the names made from it
    SupportFolder.swift               the support folder, the variables that move it
    ControlSocket.swift               where control.sock and demo.sock are; DemoPointer (demo.json)
    ControlRequest.swift              every request as an enum case; isLeased; the protocol version
    ControlMessage.swift              a request plus its holder as one JSON object; decode refuses another version
    ControlReply.swift                {ok, output, error, lease?}
    ControlClient.swift               one request sent, one reply read; ControlTransport for tests
    UnixSocket.swift                  the POSIX calls both ends share (package access)
  VRCommand/
    CLI.swift                         CLI.run(arguments, environment) -> CommandResult: parse, send, print, exit code; CommandEnvironment
    CommandTable.swift                every command: its words, its usage line, its summary, its parser; Arguments, Invocation
    TimeArgument.swift                "10", "10.5", "0:10", "1:02:03" to seconds
    RegionArgument.swift              "x,y,w,h" to four numbers; whether they lie inside the frame is the app's to say
    AppCommand.swift                  app status, app open [--demo], app quit: launch, relaunch, hand the lease over
    AppLauncher.swift                 AppLaunching; WorkspaceLauncher starts the bundle the CLI sits in
    CommandResult.swift               standard output, standard error, exit code
  VRCLI/
    main.swift                        calls CLI.run with the real environment and exits with its code

  VRReview/                           ── app side, pure ──
    Identifiers.swift                 CommentID, BatchID ("<hash8>-c3", "<hash8>-b1")
    Region.swift                      normalized rectangle; validation; from two corners; the pixel rectangle for a frame size
    Comment.swift                     Comment, CommentState and its allowed moves
    ThreadMessage.swift               author (person, agent), kind (message, question, answer), text, time
    Batch.swift                       id, sentAt, its comments' ids, its thread, the transcript lines captured at the send
    Review.swift                      one video's review and every rule that changes it
    ReviewError.swift                 why a change is refused, in words
    BatchPayload.swift                the JSON object `wait` prints; made from a batch, a review, paths and a context
    ListenerLedger.swift              the listener session, the deliveries, requeue, presence, context once per session
    Presence.swift                    listening, working, absent; derived by the ledger
    ContextText.swift                 the sidecar names to look for; sidecar text and note joined
  VRTranscript/
    TimedLine.swift                   start, end, text
    Transcriber.swift                 the interface: prepare(video), lines(for:in:), status(for:); TranscriptStatus
    OrderedTranscriber.swift          the first source that has the video, in the spec's order
    TranscriptWindow.swift            the cut: lines that overlap time ± 15 s
    Sources/
      TranscriptSource.swift          what a source is: a name, and what it has for a video so far (SourceTranscript)
      VoiceoverSource.swift           voiceover.json; scene times from scene lengths and the frame rate
      SubtitleSource.swift            .srt and .vtt with the video's base name
      SpeechSource.swift              recognition in the background; partial lines; the cache it is given (TranscriptCaching)
      SpeechRecognition.swift         SpeechAnalyzer and SpeechTranscriber on the file's audio track: what SpeechSource runs
  VRStore/
    SupportLayout.swift               every path under a support folder, in one place
    ContentHash.swift                 the hash that names a video
    ReviewStore.swift                 load and save review.json, listener.json, app.json; `AppState`
    StoredFile.swift                  one versioned JSON file: read or moved aside, written whole
    TranscriptCache.swift             transcript.json; implements SpeechSource's cache

  VRApp/                              ── the app ──
    VideoReviewApp.swift              @main: the one Window, the menus, the composition root
    Theme.swift                       the pastel colours, one per meaning, and the shared sizes (both footers' height, the sidebar's width)
    AppModel.swift                    the orchestrator; one method per action
    Player/
      PlayerEngine.swift              AVPlayer: open, play, pause, exact seek, time, rate, duration
      PlayerSurface.swift             the AVPlayerLayer in a view, no AVKit controls
      TransportBar.swift              play button, time, speed, the timeline
      Timeline.swift                  the scrubber and the comment markers
      TimeText.swift                  a time as text: 0:10 in the window, 0:10.000 in a command's output
      Shortcuts.swift                 the player's keys as a pure table, and the key monitor that runs them only while no text field has the focus
      EmptyState.swift                "Open a video": the button and the drop target
    Overlay/
      FrameGeometry.swift             where the frame sits in the view; view points to and from normalized; where the comment box goes
      RegionDraw.swift                a rectangle being drawn, from the press to the release, as a pure value
      RegionOverlay.swift             drag to draw; the draft's and the selected comment's region; places the comment box
      Composer.swift                  the comment box, over the frame's foot or next to the region
    Comments/
      ReviewDesk.swift                the reviews, read at launch; each change saved and its images written
      FrameGrabber.swift              the keyframe and the crop as PNG files
      Sidebar.swift                   the queue, the sent comments grouped by batch, and the send bar at its foot
      CommentCard.swift               one comment as a plain row: keyframe, time, text, status, thread, edit, delete
      ThreadView.swift                a comment's thread: MessageRow for each message, and the answer box while a question waits
      BatchCard.swift                 BatchHeader, the head of a batch's group, and BatchCard, the messages for a whole batch
      StatusStyle.swift               one colour and symbol per comment state, and one for a question that waits, for markers and rows
      ContextNote.swift               the in-app note and the sidecar it found
    Mate/
      ListenerQueue.swift             open waits and asks; delivery; what the presence indicator and `state` show of the listener
      ContextSource.swift             reads the context sidecar of a video
      PresencePill.swift              listening, working, absent as a dot and a word in the sidebar's send bar; PresenceStyle, its words and colours
      NoticeToast.swift               Notice, an agent message as the window announces it, and the brief notice that shows it
    Control/
      ControlServer.swift             decode, lease, route to AppModel, reply
      SocketListener.swift            the listening socket off the main actor; heartbeat on a waiting connection
      StateSnapshot.swift             what `state --json` and `app status` print
      Screenshotter.swift             the app's own window as a PNG, in an appearance
      LeaseBanner.swift               LeaseButton, the toolbar icon while an agent holds the lease, with who, time left and Stop in its popover; LeaseIndicator, the lease as the window shows it

Tests/
  VRLeaseTests/                       ControlLeaseTests (time-driven tables), HolderTests, SystemProcessTableTests (the real table: this process, its parent, a pid nobody has)
  VRWireTests/                        ControlMessageTests (round trip, version refusal), DemoPointerTests
  VRCommandTests/                     CommandTableTests, TimeArgumentTests, RegionArgumentTests, AppCommandTests, Doubles (fake transport, launcher)
  VRReviewTests/                      ReviewTests (state machine), ReviewAnswerTests (statuses as a table, threads, questions), BatchPayloadTests, ListenerLedgerTests, RegionTests
  VRTranscriptTests/                  WindowTests (the cut on the fixture's scenes), SourceOrderTests (sidecars in a temporary folder), VoiceoverSourceTests (the fixture's scene times), SubtitleSourceTests (SRT and WebVTT), SpeechSourceTests (a recognition run by hand), Doubles (the fixture's scenes, a fixed source, a cache in memory, that recognition)
  VRStoreTests/                       ContentHashTests (renamed copy, samples, the keyframe's path), TranscriptCacheTests (round trip, renamed copy, a file moved aside), ReviewStoreTests (a full review, the ledger and the last video read back; a renamed copy; two folders apart; a file moved aside; a save that fails)
  VRAppTests/                         ShortcutsTests (each key, and none while typing), FrameGeometryTests (letterboxed and pillarboxed, at several window sizes), RegionDrawTests (press, drag, Escape, release), RegionCommentTests (the drawn and the `--region` comment on the fixture: same crop), ControlServerTests (the server's leasing at a clock of the test's, and over the real socket), ListenerWaitTests (a batch from `batch send` to `wait` on the fixture: in memory at a clock of the test's, and over the real socket with a short heartbeat), TranscriptBatchTests (the transcript in the payload and in `state`: from the fixture's voiceover, and from a speech recognition run by hand that is still running at the send), ListenerAnswerTests (`ack`, `status`, `reply`, `ask` and `thread answer` on the fixture: in memory at a clock of the test's, and `ask` over the real socket), RestartTests (a model let go and another made on the same support folder: the same `state`, the listener's batches, the next ids, a renamed copy, another folder, a file that doesn't read, a typed note)

scripts/
  acceptance.sh                       the v1 acceptance scenario through the CLI, against an installed app in demo mode; its one setting is the CLI's path
assets/screenshots/v1-proto-1/        the acceptance run's light and dark screenshots, and its output
.agents/skills/video-review-mate/     ── the listener skill ──
  SKILL.md                            the loop a listener session follows: listen, read the batch, work each comment, answer
  scripts/vr.sh                       finds the app's CLI and runs it; `listen` is `wait`, then `ack` at once
.claude/skills/video-review-mate      a link to that folder, which is where Claude Code looks
fixtures/sample/                      the sample video and its sidecars
```

Layout rules: a folder is one concern; siblings are peers; the three transcript sources sit in their own folder beside the interface they implement; a helper with one user lives in that user's file.

### Lease: `VRLease`

Copied from Shipyard's `Holder` and `ControlLease`, renamed.

```swift
public struct Holder: Codable, Hashable, Sendable {
    public var key: String      // "CLAUDE_CODE_SESSION_ID=…" | "process:<pid>@<start µs>" | the value of VIDEO_REVIEW_CONTROL_KEY
    public var name: String     // "Claude Code", or the process's name
    public var place: String    // "Herdr pane <id>", else the working folder
    public static func find(variables: [String: String], workingDirectory: URL, processes: some ProcessTable) -> Holder
}

public struct ControlLease: Equatable, Sendable {
    public static let renewal: TimeInterval = 60
    public static let cap: TimeInterval = 5 * 60
    public static let bar: TimeInterval = 5 * 60

    public struct Term: Codable, Equatable, Sendable { public var holder: Holder; public var taken, ends: Date
                                                       public var capped: Date                       // taken + cap
                                                       public func secondsLeft(at: Date) -> Int
                                                       public func held(timeZone: TimeZone) -> String }   // what `control take` prints
    public enum Transition { case started(Holder), renewed(Holder), ended(Holder, Ending) }
    public enum Ending { case expired, capped, released, stopped }
    public enum Refusal: Error { case inUse(Term), queued(Term), waitedOut(seconds: Int, Term), stopped
                                 public func message(at: Date, timeZone: TimeZone) -> String }
    public struct Decision { public var answer: Result<Term, Refusal>; public var transitions: [Transition] }
    public struct Status: Codable { public var holder, place: String; public var secondsLeft, waiting: Int }

    public init()
    public init(environment: [String: String], at now: Date)          // a relaunch hands the lease over
    public static func handover(_ term: Term) -> [String: String]     // VIDEO_REVIEW_CONTROL_LEASE

    public func current(at now: Date) -> Term?
    public func status(at now: Date) -> Status?
    public func waiting(at now: Date) -> Int                          // the takes in line, their waits not run out
    public func nextEnd(after now: Date) -> Date?                     // when the app settles next
    public mutating func settle(at now: Date) -> [Transition]         // ends a lease that ran out, hands it to the first waiter
    public mutating func use(by: Holder, at: Date) -> Decision                         // every operator command
    public mutating func take(by: Holder, at: Date, waitingUntil: Date?) -> Decision   // control take [--wait]
    public mutating func giveUp(by: Holder, waited: Int, at: Date) -> Decision         // a wait in line ran out
    public mutating func release(by: Holder, at: Date) -> [Transition]                 // control release
    public mutating func stop(at: Date) -> [Transition]                                // the lease button's Stop
}
```

The key order is `VIDEO_REVIEW_CONTROL_KEY`, then `CLAUDE_CODE_SESSION_ID`, then the nearest ancestor process that isn't a shell. A refusal names the holder, its place and the lease's end as `HH:mm:ss`.

The rules, each a row of the time-driven tables in `VRLeaseTests`:

- **Use.** An operator command takes a free lease for `renewal` (60 s), or renews its holder's to 60 s from now. A renewal never shortens the lease and never passes `taken + cap` (5 min). Another holder is refused (`inUse`), and the refusal renews nothing.
- **Take.** `control take` holds the lease to its cap at once: a new lease for 5 min, or the holder's own to 5 min after it was first taken. From another holder it is refused at once without `--wait`. With a wait it joins the line (`queued`): one place per holder key, first come, first served; a second waiting take keeps the place and the later deadline.
- **The line.** Every change settles first: a lease that ran out ends (`capped` at its cap, else `expired`), waiters whose waits ran out leave, and the first waiter left gets a new lease held to its cap. A wait that runs out is refused with `waitedOut`, or takes the lease if it is free at that moment (`giveUp`).
- **Release.** The holder's lease ends and the first waiter gets it. From anyone else it changes nothing.
- **Stop.** The lease ends, its holder is barred for `bar` (5 min from the Stop), and the first waiter gets the lease. A barred holder's commands and takes are refused with `stopped`, and it never joins the line. Stop on a free lease changes nothing. The bars are private to the lease: nothing lifts one early.
- **Handover.** `init(environment:at:)` reads the term `handover` wrote into `VIDEO_REVIEW_CONTROL_LEASE`, cuts its end to its cap, and starts free when it has ended or doesn't read.

The words: `video-review is in use by <name> in <place> until <HH:mm:ss> (<n>s left); `video-review control take --wait <seconds>` to queue`, `waited <n>s; video-review is still in use by …`, `the person took video-review back; ask them before using it again`, and for a take that holds, `you hold video-review until <HH:mm:ss>`. The clock is written with a fixed `HH:mm:ss` format in the app's time zone, whatever the Mac's own formats are.

### Wire: `VRWire`

#### Where the socket is

```swift
public enum SupportFolder {
    public static let overrideVariable = "VIDEO_REVIEW_SUPPORT_DIR"
    public static func real() -> URL                                  // ~/Library/Application Support/<Identity.supportFolderName>/
    public static func demo(environment: [String: String]) -> URL?    // the override when it is absolute: what makes a run a demo run
    public static func current(environment: [String: String]) -> URL  // demo(environment) ?? real()
}
public enum ControlSocket {
    public static func real(in support: URL) -> URL      // <real support>/control.sock
    public static func demo(in support: URL) -> URL      // <real support>/demo.sock
    public static func locate(support: URL) -> URL       // demo.sock when demo.json is there and the socket exists, else control.sock
}
public enum DemoPointer {                                // <real support>/demo.json: {"support": "/abs/folder", "version": 1}
    public static func recorded(in support: URL) -> URL?
    public static func record(_ demo: URL, in support: URL) throws
    public static func remove(in support: URL) throws
}
```

A demo run keeps its data in the folder given to `--demo`, but listens on `demo.sock` in the real support folder. A Unix socket's path holds 104 bytes at most, and a demo folder inside a worktree goes past that; the real support folder never does. The socket files are mode 0600 and exist only while the app runs.

#### The request

One JSON object per connection. The client writes it and shuts down its write side. Fields beside `version`, `command`, `holder` and `json` belong to the command.

```json
{"command":"player.seek","holder":{"key":"CLAUDE_CODE_SESSION_ID=…","name":"Claude Code","place":"/Users/me/repo"},"json":false,"seconds":10,"version":1}
```

| CLI | `command` | Fields | Role |
|---|---|---|---|
| `app status` | `app.status` | | free |
| `state --json` | `state` | | free |
| `control take [--wait <s>]` | `control.take` | `waitSeconds?` | free |
| `control release` | `control.release` | | free |
| `app open [--demo <folder>]` | `app.open` | | operator |
| `app quit` | `app.quit` | | operator |
| `player open <path>` | `player.open` | `path` (absolute) | operator |
| `player play` | `player.play` | | operator |
| `player pause` | `player.pause` | | operator |
| `player seek <time>` | `player.seek` | `seconds` | operator |
| `comment add <text> [--at <time>] [--region x,y,w,h]` | `comment.add` | `text`, `at?`, `region?` `{x,y,w,h}` | operator |
| `comment edit <id> <text>` | `comment.edit` | `id`, `text` | operator |
| `comment delete <id>` | `comment.delete` | `id` | operator |
| `batch send` | `batch.send` | | operator |
| `thread answer <comment-id> <text>` | `thread.answer` | `id`, `text` | operator |
| `context set <text>` | `context.set` | `text` | operator |
| `screenshot <abs.png> [--appearance light\|dark]` | `screenshot` | `path` (absolute), `appearance?` | operator |
| `wait [--timeout <s>]` | `wait` | `timeoutSeconds?` | listener |
| `ack <batch-id> [<text>]` | `ack` | `id`, `text?` | listener |
| `status <comment-id> working\|done\|failed` | `status` | `id`, `state` | listener |
| `reply <comment-id\|batch-id> <text>` | `reply` | `id`, `text` | listener |
| `ask <comment-id> <question> [--wait <s>]` | `ask` | `id`, `text`, `waitSeconds?` | listener |

```swift
public enum ControlRequest: Equatable, Sendable {
    case appStatus, state, controlTake(waitSeconds: Int?), controlRelease
    case appOpen, appQuit
    case playerOpen(path: String), playerPlay, playerPause, playerSeek(seconds: Double)
    case commentAdd(text: String, at: Double?, region: WireRegion?), commentEdit(id: String, text: String), commentDelete(id: String)
    case batchSend, threadAnswer(id: String, text: String), contextSet(text: String)
    case screenshot(path: String, appearance: Appearance?)
    case wait(timeoutSeconds: Int?), ack(id: String, text: String?), status(id: String, state: String)
    case reply(id: String, text: String), ask(id: String, text: String, waitSeconds: Int?)

    public static let version = 1
    public static let longestWait = 3600        // the longest `take --wait`, `wait --timeout` and `ask --wait`, in seconds
    public var command: String                  // the wire name of the table above: "player.seek"
    public var isLeased: Bool                   // true for the operator rows above, false for the others
}
public struct WireRegion: Codable, Equatable, Sendable { public var x, y, w, h: Double }
public struct ControlMessage: Equatable, Sendable {
    public var request: ControlRequest; public var holder: Holder; public var json: Bool
    public func encoded() -> Data
    public static func decode(_ data: Data) throws(ControlProtocolError) -> ControlMessage
}
public enum ControlProtocolError: Error { case unreadable(String), otherVersion(Int), unknownCommand(String); public var message: String }
```

`decode` checks the version before anything else: it reads `version` alone first, so a request of another version is told so even when its other fields have another shape. `decode` also refuses a relative `path`, an unknown `appearance`, a negative `seconds`, and a take's or an ask's `waitSeconds` or a wait's `timeoutSeconds` outside 0 to 3600. Another version is refused with: `the video-review command speaks control version 2 and the app version 1: run the command from this app's bundle (Contents/Helpers/video-review) so both come from one build`.

Ids travel as plain strings: the wire knows nothing of what an id means. The app checks them.

#### The reply

```swift
public struct ControlReply: Codable, Equatable, Sendable {
    public var ok: Bool
    public var output: String              // printed on standard output as it is
    public var error: String               // printed on standard error; with ok false it is the refusal
    public var lease: ControlLease.Term?   // only on the reply to app.quit, for a relaunch to hand over
}
```

The CLI maps a reply to an exit code: `ok` gives 0, `ok` false gives 1. One exception: a `wait` or an `ask` that ran out answers `ok` true with an empty `output`, and the CLI, which knows it sent a waiting request, exits 3 with `no batch within 30 s` or `no answer within 30 s` on standard error. The reply's shape stays the spec's four fields (`CLI.run`, `CommandResult.ranOut`). A batch's payload and an answer are never empty (an answer without text is refused), so nothing to print can only mean that the wait ran out.

#### What each command prints

Text is for people and shell variables. With `--json` the output is one JSON object.

| Command | Text | `--json` |
|---|---|---|
| `app status` | lines: running, version, variant, data, video, lease, listener; `not running` (exit 0) when nothing answers | `{running, version, variant, demo, support, video, lease, listener}`, each part as in `state`; `{"running":false}` |
| `state` | always the state object, with or without `--json` | see [StateSnapshot](#app-vrapp) |
| `control take` | `you hold video-review until 12:05:00` | `{holder, place, secondsLeft, waiting}` |
| `control release` | `released` | `{"released":true}` |
| `app open` | the status lines | the status object |
| `app quit` | `quit` | `{"quit":true}` |
| `player open` | the video's path | `{video:{path, contentHash, duration, title}}` |
| `player play`, `pause`, `seek` | the time as `m:ss.mmm` | `{time, playing}` |
| `comment add`, `comment edit` | the comment's id | the comment, as in `state` |
| `comment delete` | `deleted <id>` | `{"deleted":"<id>"}` |
| `batch send` | the batch's id | `{batchId, commentIds}`, the ids in time order |
| `thread answer` | `answered <id>` | the comment |
| `context set` | `context note set` | `{"note":"…"}` |
| `screenshot` | the PNG's path | `{path, captured}`; a note on standard error when the window was rendered, not captured |
| `wait` | the batch payload, always JSON, on one line | the same |
| `ack` | `acknowledged <batch-id>` | `{batchId, commentIds}` |
| `status` | `<comment-id> <state>` | the comment |
| `reply` | `replied <id>` | the comment, or `{batchId}` |
| `ask` | the answer's text | `{commentId, answer}` |

#### The client

```swift
public protocol ControlTransport: Sendable {
    func exchange(_ request: Data, socket: URL, idleTimeout: TimeInterval) throws(ControlTransportFailure) -> Data
}
public struct ControlClient: Sendable {
    public init(socket: URL, holder: Holder, transport: any ControlTransport, idleTimeout: TimeInterval = 15)
    public func send(_ request: ControlRequest, json: Bool) -> Result<ControlReply, Failure>   // .notRunning, .timedOut, .failed(String)
}
```

The timeout is an idle timeout: the longest silence the client accepts, not the longest exchange. It is the same 15 s for every request, a waiting one too, since the app's heartbeat breaks the silence. See the long-poll below.

### How a long-poll holds one connection

`wait`, `ask` and `control take --wait` each stay one request on one connection, as ADR 0001 says. The app simply doesn't answer yet.

1. The client writes the request, shuts down its write side and reads until the app closes the connection.
2. `SocketListener` reads the request and awaits `ControlServer.reply(to:)` in a task. The handler suspends on a continuation kept by `ListenerQueue` (for `wait` and `ask`) or by `ControlServer` (for a `take` in line). The main actor is free meanwhile.
3. While the task hasn't answered, `SocketListener` writes one space to the connection every 2 s (`SocketListener.heartbeat`; a test gives a shorter one). It does so for every request, so a slow screenshot is covered too. This **heartbeat** does two jobs:
   - The client's idle timeout (15 s) never fires on a healthy wait, however long. A JSON reader skips leading spaces, so the reply still reads as one JSON object.
   - A heartbeat that can't be written (the listener was killed, the shell closed) cancels the task. The `wait`'s cancellation handler removes the waiter and resumes it, so presence drops within about 2 s and no batch is handed to a dead connection.
4. When the handler resumes (a batch arrived, an answer arrived, the timeout ran out, the app is quitting), the heartbeat is stopped and waited for, so a space never lands inside the reply or on a closed connection. Then the reply is written and the connection closed.
5. An answer that hands something over goes back to the server: `written` when its reply was written, `undelivered` when it couldn't be. A batch is marked `taken` only in `written`; in `undelivered` it stays `pending`, and a lease a `take` just got is released, as in Shipyard.

Between the moment a batch is handed to a `wait` and the moment the server hears how the write went, the batch is **in flight**: still `pending` in the ledger, and kept out of every other `wait` by `ListenerQueue.inFlight`. So a batch can't go to two waits, and a failed write loses nothing. A batch sent in the two seconds before a dead listener is found out is handed to it, fails to write, and is pending again; a test proves both ways over the real socket.

The take, the `wait` and the `ask` are built this way. An `ask` hands nothing over, so its reply needs no `written`: the answer is in the thread before the `ask` hears of it, and an `ask` whose client has gone finds it there when it asks again. A `take` in line suspends on a continuation in `ControlServer`, which has no cancellation handler: a take whose client has gone keeps its place until it is granted the lease, and gives it back then (`undelivered`).

A `wait` without `--timeout` waits without limit. A `--timeout` is whole seconds from 0 to 3600; 0 answers at once, with a pending batch or with nothing. The app answers every open wait with a refusal (`video-review is quitting`) when it quits, so the listener's loop sees exit 1, not a hang: the `app.quit` route does it before its own reply, while the app can still write, and `stop()` does it again for a quit from the window. A `wait` that comes after is refused the same way. An open `ask` is answered and refused in the same two places. An `ask` without `--wait` waits without limit; `--wait` is whole seconds from 0 to 3600, and 0 answers at once, with the answer that is there or with nothing.

A write to a Unix stream socket whose peer has closed fails at once on macOS 26 (`MSG_NOSIGNAL` on each `send`), so the heartbeat finds a dead listener with no read source on the connection. `ListenerWaitTests` proves it over the real socket.

### Command: `VRCommand`

```swift
public enum CLI {
    /// Everything the executable does, testable with a fake transport and launcher.
    public static func run(arguments: [String], environment: CommandEnvironment) -> CommandResult
}
public struct CommandEnvironment { variables, workingDirectory, processes: any ProcessTable, transport: any ControlTransport, launcher: any AppLaunching,
                                   bundle: URL?, support: URL, pause: (TimeInterval) -> Void;  public static func live() -> CommandEnvironment }
public struct CommandResult: Error, Equatable { public var output, error: String; public var exitCode: Int32 }

struct Command {                       // one row of CommandTable.all
    var words: [String]                // ["player", "seek"]
    var usage: String                  // "player seek <seconds|mm:ss>"
    var summary: String                // its line in `video-review help`
    var parse: (inout Arguments) throws(UsageError) -> Invocation
}
enum Invocation { case send(ControlRequest), appStatus, appOpen(demo: URL?), appQuit }
```

`support` is the real support folder (the sockets and the demo pointer) and `pause` the wait between two looks at an app that starts or quits; tests give both. A row's parser returns an `Invocation`: one request to send, or one of the three `app` commands, which have steps of their own (`AppCommand`).

- `CommandTable.all` is the one list of commands; `video-review help` and a usage error print from it.
- `--json` is accepted anywhere on the line before a `--` and travels as the message's `json`.
- `--` ends the options. `CLI.run` splits the line at the first one, and `Arguments` keeps the words after it apart (`literal`): `positional` takes them as they are, after the words before the `--`, and `option` never looks at them. So a text may start with `--` or be `--json` (`reply <id> -- '--force is gone'`). Before the `--`, a positional that starts with `--` is refused as an unknown option, as an option nobody asked for is.
- Help is the line's first word: `help`, `-h` or `--help`. Anywhere else those are words like any other, so `thread answer <id> -h` answers with `-h`.
- A relative `player open` path and `--demo` folder are made absolute against the working folder; `screenshot` refuses a relative path, since the spec says `<abs.png>`.
- Every command but the `app` ones is: parse, find the holder, locate the socket, send, print, exit.
- `app status` prints `not running` and exits 0 when nothing answers. `app quit` sends `app.quit`, then waits up to 10 s until nothing answers on the socket.

`app open` is the one command with logic of its own, since the app may not be running:

```text
app open [--demo <folder>]
  wanted = the demo folder made absolute, made when it is missing and then standardized, or nil for the person's data
                                                         one spelling for the comparison, the pointer and the launch: a path
                                                         standardizes differently once it exists (/private/tmp/x → /tmp/x)
  ask `app.status` on demo.sock, then on control.sock    both, so a stale pointer or socket hides no running app
  if one answers:                                        demo.sock's data is the pointer's folder, control.sock's the person's
      same data as wanted  → send `app.open` (leased; renews the lease), print its status
      other data           → send `app.quit` (leased); keep the lease from its reply; wait for the socket to go
  record the demo pointer, refusing a folder that couldn't be made (wanted != nil), or remove the pointer (wanted == nil)
  launcher.launch(bundle: the .app this CLI sits in, environment:
      VIDEO_REVIEW_SUPPORT_DIR = wanted, VIDEO_REVIEW_CONTROL_LEASE = the lease handed over)
  send `app.open` every quarter second, up to 10 s, until the app answers; print its status
  a demo that doesn't come to run leaves no pointer behind
```

`WorkspaceLauncher` starts the bundle that contains the CLI (`…/Contents/Helpers/video-review` gives `…`), through `NSWorkspace`, without bringing it to the front. So a build's CLI can only ever start its own build. Outside a bundle (`swift run`), it falls back to `Identity.bundleID`. This is the only AppKit use on the agent side.

### Review: `VRReview`

```swift
public struct CommentID: RawRepresentable, Hashable, Codable, Sendable { public let rawValue: String }   // "7f3a9c21-c3"
public struct BatchID: RawRepresentable, Hashable, Codable, Sendable { public let rawValue: String }     // "7f3a9c21-b1"
// Each is stored and sent as its text alone. CommentID(contentHash:number:) and BatchID(contentHash:number:) make one;
// VideoPrefix.length is the 8. BatchID.number is the 1 of "7f3a9c21-b1", for the sidebar's "Batch 1".
// The first eight hex digits of the video's content hash, then a counter per video.
// An id names its video, so `status <comment-id>` works whatever video is open. A number is never used twice.

public struct Region: Codable, Equatable, Sendable {
    public let x, y, w, h: Double                       // 0..1, origin top left
    public init?(x: Double, y: Double, w: Double, h: Double)   // nil unless inside the frame with w, h > 0
    public static func checked(x: Double, y: Double, w: Double, h: Double) throws(ReviewError) -> Region   // or regionOutsideFrame
    public static func spanning(from: (x: Double, y: Double), to: (x: Double, y: Double)) -> Region?       // two corners, any order, brought onto the frame
    public func pixels(in size: (width: Int, height: Int)) -> (x: Int, y: Int, width: Int, height: Int)
}

public enum CommentState: String, Codable, Sendable { case draft, queued, sent, acknowledged, working, done, failed
                                                       public func canMove(to next: CommentState) -> Bool }   // the table below, without `requeue`

public struct ThreadMessage: Codable, Equatable, Sendable {
    public enum Author: String, Codable { case person, agent }
    public enum Kind: String, Codable { case message, question, answer }
    public var author: Author; public var kind: Kind; public var text: String; public var at: Date
}

public struct Comment: Codable, Equatable, Identifiable, Sendable {
    public var id: CommentID; public var time: Double; public var text: String
    public var region: Region?; public var state: CommentState
    public var batch: BatchID?; public var thread: [ThreadMessage]; public var createdAt: Date
    public var lastQuestion: ThreadMessage? { get }     // the agent's latest question, answered or not
    public var lastAnswer: ThreadMessage? { get }       // the person's answer to it, once there is one
    public var openQuestion: ThreadMessage? { get }     // the latest question while nothing answers it
}

public struct Batch: Codable, Equatable, Identifiable, Sendable {
    public var id: BatchID; public var sentAt: Date; public var comments: [CommentID]
    public var thread: [ThreadMessage]                  // the acknowledgement's text, replies to the batch id
    public var transcripts: [CommentID: [BatchPayload.Line]]   // captured at the send
}

public struct VideoInfo: Codable, Equatable, Sendable { public var contentHash, path, title: String; public var duration: Double }

public struct Review: Codable, Equatable, Sendable {
    public var video: VideoInfo
    public private(set) var comments: [Comment]         // kept in time order
    public private(set) var batches: [Batch]
    public private(set) var note: String
    public var queue: [Comment] { get }                 // state == .queued, in time order
    public func comment(_ id: CommentID) throws(ReviewError) -> Comment
    public func batch(_ id: BatchID) throws(ReviewError) -> Batch
    public func checkedText(_ text: String, at time: Double) throws(ReviewError) -> String   // what addComment would keep, or its refusal; changes nothing

    // the person and the operator
    public mutating func addComment(text: String, time: Double, region: Region?, now: Date) throws(ReviewError) -> Comment   // → queued
    public mutating func editComment(_ id: CommentID, text: String) throws(ReviewError) -> Comment      // queued only
    public mutating func deleteComment(_ id: CommentID) throws(ReviewError)                             // queued only
    public mutating func sendBatch(transcripts: [CommentID: [BatchPayload.Line]], now: Date) throws(ReviewError) -> Batch
    public mutating func answer(_ id: CommentID, text: String, now: Date) throws(ReviewError) -> Comment   // needs an open question
    public mutating func setNote(_ text: String)                                                        // kept without the blank space around it; empty clears it

    // the listener
    public mutating func acknowledge(_ id: BatchID, text: String?, now: Date) throws(ReviewError) -> Batch // its sent comments → acknowledged
    public mutating func setStatus(_ id: CommentID, to: CommentState) throws(ReviewError) -> Comment       // working | done | failed
    public mutating func reply(toComment: CommentID, text: String, now: Date) throws(ReviewError) -> Comment
    public mutating func reply(toBatch: BatchID, text: String, now: Date) throws(ReviewError) -> Batch
    public mutating func ask(_ id: CommentID, question: String, now: Date) throws(ReviewError) -> Comment  // the same open question isn't posted twice

    // delivery
    public func isFinished(_ id: BatchID) -> Bool                    // every comment done or failed; false for a batch that isn't here
    public mutating func requeue(_ id: BatchID)                      // its unfinished comments → sent
}
```

The state machine, in one place (`Comment.swift`):

| From | To | Caused by |
|---|---|---|
| `draft` | `queued` | the composer's Return; `comment add` skips `draft` and starts at `queued` |
| `queued` | `sent` | `sendBatch` |
| `sent` | `acknowledged` | `acknowledge` on its batch |
| `sent`, `acknowledged` | `working` | `setStatus` |
| `sent`, `acknowledged`, `working` | `done`, `failed` | `setStatus` |
| `acknowledged`, `working` | `sent` | `requeue` only |

Everything else is refused with `ReviewError.illegalMove(_:from:to:)`, which names the comment: `7f3a9c21-c1 is done and can't become working; a comment only moves forward: sent, acknowledged, working, then done or failed, which are final`. `setStatus` may skip a step forward (the acceptance scenario takes one comment from `acknowledged` to `done`), never back, and never to the state the comment is already in. `acknowledge` moves only the batch's comments that are `sent`, so a second `ack`, or one that comes after a status, moves nothing back. A `draft` is the comment being typed: it exists only in memory, on `ReviewDesk`, and has no id until it is queued.

`ReviewError` cases: `emptyText`, `timeOutsideVideo(Double, duration:)`, `regionOutsideFrame`, `unknownComment(String)`, `unknownBatch(String)`, `notQueued(CommentID, CommentState)`, `emptyQueue`, `emptyMessage`, `notSent(CommentID, CommentState)`, `noOpenQuestion(CommentID)`, `illegalMove(CommentID, from:to:)`. Each has one `message` line; `emptyQueue` reads `the queue is empty: there is no comment to send`, `unknownComment` reads ``there is no comment `<id>` `` (a listener's command names a comment of any video, not only the open one's), and `noOpenQuestion` reads `<id> has no question waiting for an answer`. `no video is open` is the app's refusal (`ActionError.noVideo`): a review always has its video.

Built so far (the two comment tickets): `CommentID`, `BatchID`, `Region`, `CommentState` with `canMove`, `ThreadMessage`, `Comment` without `openQuestion`, `VideoInfo`, and `Review` with `comments`, `queue`, `comment`, `checkedText`, `addComment(text:time:region:now:)`, `editComment` and `deleteComment`; the errors `emptyText`, `timeOutsideVideo`, `regionOutsideFrame`, `unknownComment` and `notQueued`. With the send: `Batch`, `batches`, `batch`, `sendBatch`, `isFinished` and `requeue`, and the errors `unknownBatch` and `emptyQueue`. With the listener's answers: `acknowledge`, `setStatus`, `reply(toComment:)`, `reply(toBatch:)`, `ask`, `answer`, the three question properties of `Comment`, and the errors `emptyMessage`, `notSent`, `noOpenQuestion` and `illegalMove`. `setNote` comes with its ticket.

Rules of a batch:

- `sendBatch` takes every queued comment, in time order, makes them `sent` and names the batch on each. It keeps only the transcript lines of the comments it took. An empty queue is refused.
- A batch's number counts up per video and is never used twice, as a comment's.
- `requeue` writes `sent` over `acknowledged` and `working` directly. It is the one move backwards, so it isn't in `canMove`. Threads stay as they are: what the listener before said is still what was said.

Rules of a thread:

- A comment's thread is its messages in the order they came. Each keeps its author (`person`, `agent`), its kind (`message`, `question`, `answer`), its text and its time. `reply` posts an agent `message`, `ask` an agent `question`, `answer` a person's `answer`. A batch has a thread of its own for what is about all its comments: the text of an `ack`, and each `reply` to the batch's id.
- A message's text is kept without the blank space around it. Nothing left is refused (`emptyMessage`). An `ack` without text, or with blank text, acknowledges and posts nothing.
- A listener answers only a comment that was sent: `reply` and `ask` on a queued comment are refused (`notSent`). Both are allowed on a comment that is `done` or `failed`, since a thread may go on after the work.
- The open question is the latest question while no answer comes after it. `answer` is refused when there is none (`noOpenQuestion`), so a question gets one answer.
- `ask` with the same text as the comment's latest question posts nothing, answered or not: it is that question asked again. Another text is a new question, and the one before, when it was still open, stays unanswered in the thread.

Rules of a region:

- It is four parts of the frame from 0 to 1, with the origin at the top left. It must lie inside the frame and have an area: `x`, `y` at least 0, `w`, `h` above 0, `x + w` and `y + h` at most 1 (a sum may pass 1 by a billionth, since `0.7 + 0.3` isn't exactly 1 in binary). Numbers that aren't finite are refused.
- A region can't be made any other way: its fields are constants, `init?` checks them, and a stored region outside the frame doesn't decode. `checked` is the same rule as a refusal (`regionOutsideFrame`), for the numbers `comment add --region` brings.
- `spanning` is how a drag becomes a region: two opposite corners in any order, each brought onto the frame first, nil when nothing is left between them.
- `pixels(in:)` puts each edge at the nearest pixel edge, inside the frame, at least one pixel each way. `0.48,0.3,0.28,0.12` of a 1920 by 1080 frame is 537 by 130 pixels at 922, 324. It is the one rectangle a crop is cut at.

Rules of a comment's text and place:

- The text is kept without the blank space around it. Nothing left is refused (`emptyText`), on add and on edit.
- The time must be in `0...duration`.
- `comments` stays in time order. Comments at the same time keep the order they were made in.
- The review counts its comments' numbers up and never back, so a deleted comment's id isn't given again.
- `checkedText` lets a caller refuse a comment by these rules before it does the slow work (the keyframe), without a second copy of the rules.

#### The payload

```swift
public struct BatchPayload: Codable, Equatable, Sendable {
    public struct BatchPart: Codable { public var id: String; public var sentAt: String }            // ISO 8601, UTC
    public struct VideoPart: Codable { public var path, contentHash: String; public var duration: Double; public var title: String }
    public struct Line: Codable, Equatable, Sendable { public var start, end: Double; public var text: String }
    public struct CommentPart: Codable {
        public var id: String; public var time: Double; public var text: String
        public var keyframePath: String; public var region: Region?; public var cropPath: String?
        public var transcript: [Line]
    }
    public var batch: BatchPart; public var video: VideoPart; public var context: String?; public var comments: [CommentPart]

    public static func make(batch: Batch, review: Review, context: String?,
                            keyframe: (CommentID) -> String, crop: (CommentID) -> String) -> BatchPayload
    public func encoded() -> Data          // one line: sorted keys, slashes not escaped, null written for context, region and cropPath
}
```

`make` lists the batch's comments that aren't `done` or `failed`, in time order: all of them on the first delivery, the unfinished ones on a redelivery. `region` is `{x, y, w, h}`, normalized. Times are seconds. `crop` is asked only for a comment with a region; the others get `null`. `sentAt` is written as `2026-10-04T12:00:00Z`. Each part has a public initializer, so a test states the payload it expects.

A comment's `transcript` is the lines `AppModel.sendBatch` read around it at the send, which `Review.sendBatch` keeps on the batch: `[]` when the video has none yet. `context` is what `ledger.contextToSend` gives in `ListenerQueue.deliverIfPossible`; it travels with the batch to `ledger.delivered`.

#### The ledger: listener session, deliveries, context once per session

```swift
public struct ListenerLedger: Codable, Equatable, Sendable {
    public struct Session: Codable, Equatable { public var key, name, place: String; public var firstSeen, lastSeen: Date
                                                public var contextSent: [String: String] }   // content hash → the context text it last got
    public struct Delivery: Codable, Equatable { public var batch: BatchID; public var video: String; public var sentAt: Date
                                                 public var takenBy: String?; public var takenAt: Date?
                                                 public var isPending: Bool }
    public enum Standing: String { case pending, taken, finished }           // what `state` names a batch's delivery
    public static let workingWindow: TimeInterval = 120
    public private(set) var session: Session?
    public private(set) var deliveries: [Delivery]        // oldest first; a finished one is removed

    public mutating func enqueue(_ batch: BatchID, video: String, sentAt: Date)
    /// A listener command arrived. Another key than the session's starts a new session:
    /// returns the deliveries the old one took and didn't finish, now pending again.
    public mutating func attach(_ holder: (key: String, name: String, place: String), now: Date) -> [Delivery]
    public func next(except: Set<BatchID> = []) -> Delivery?                 // the oldest pending one that isn't in flight
    public func contextToSend(_ text: String, video: String) -> String?      // nil when empty, when the same as the session last got, or with no session
    public mutating func delivered(_ batch: BatchID, to key: String, context: String?, now: Date)   // taken; context remembered
    public mutating func finish(_ batch: BatchID)
    public mutating func reconcile(with reviews: [Review])                   // at launch: see "The reviews win"
    public func standing(of batch: BatchID) -> Standing                      // a batch that isn't here is finished
    public var hasTaken: Bool                                                // the session has a taken, unfinished batch
    public func presence(waitOpen: Bool, now: Date) -> Presence
}
public enum Presence: String, Codable, Sendable { case listening, working, absent }
```

- **A listener session is a holder key.** Every request already carries its holder, so a listener is told apart with nothing new on the wire: one Claude Code session is one listener session (`CLAUDE_CODE_SESSION_ID`), and a test starts another with `VIDEO_REVIEW_CONTROL_KEY`.
- **Requeue.** When a listener command arrives from a key other than the session's, the old session is over: its taken, unfinished batches become pending again and their unfinished comments go back to `sent`. The same key calling `wait` again (the skill does, before it starts work) gets nothing twice. `attach` returns the deliveries, not their ids alone, since the queue needs each one's video to requeue its comments.
- **Taken by its listener only.** `delivered` names the key the reply went to. When that key is no longer the session (another listener started while the reply was written), nothing is taken and the batch stays pending for the session there is.
- **In flight.** `next(except:)` leaves out the batches whose reply is being written. The set is the queue's, not the ledger's: it lives for one write and is never saved.
- **Context once per session.** The session remembers, per video, the context text it last got. `contextToSend` returns the text for the first batch of that video, `nil` while it is unchanged, and the text again after the sidecar or the note changed. A new session remembers nothing, so it gets the context again. The memory is written only in `delivered`, after the reply reached the listener, so a context whose reply was never written goes out again. A context that became empty goes out as `null` and leaves the memory as it was. Each video has its own memory, by content hash.
- **The ledger is saved** in `listener.json`, so an app restart neither sends the context twice to a session that goes on, nor loses a pending batch. `ListenerQueue` reads it as it is made and writes it at each change.
- **The reviews win.** `reconcile(with:)` runs once, at launch, on every review there is. The reviews say which batches exist; the ledger says only who has them. An unfinished batch that isn't in the ledger becomes pending, and a delivery whose batch is finished, or is in no review, is removed. So a quit between the two writes of one action (the review, then the ledger), or a ledger file that was lost, loses no batch.
- **Presence is derived**, never stored:

| An open `wait`? | The session has a taken, unfinished batch? | The session's last command | Presence |
|---|---|---|---|
| yes | no | | `listening` |
| yes | yes | | `working` |
| no | yes | under 120 s ago | `working` |
| no | otherwise | | `absent` |

`ContextText` is two pure functions: `candidates(for video: URL) -> [URL]` (`<base>.context.md`, then `context.md`, in the video's folder) and `compose(sidecar: String?, note: String) -> String` (the sidecar's text, a blank line, then the note under the heading `## Note from the reviewer`, each without the blank space around it; a note alone still has its heading; empty when both are).

The file is read on the app side, by `ContextSource` (`Mate/ContextSource.swift`): `read(for video: URL) -> Sidecar?` gives the first candidate that is there and reads as UTF-8 text, as `Sidecar { url, text }`, and `text(for review: Review) -> String` composes that sidecar's text with the review's note. Nothing is cached: each delivery, each `state` and the context popover read the file again, so an edit of the sidecar is in the next batch. The sidecar is looked for beside the file the video was last opened from (`review.video.path`).

### Transcript: `VRTranscript`

```swift
public struct TimedLine: Codable, Equatable, Sendable { public var start, end: TimeInterval; public var text: String }
public struct TranscriptStatus: Equatable, Sendable {                  // what `state.transcript` prints
    public var source: String?; public var complete: Bool; public var lines: Int; public var problem: String?
}

/// The one interface the app knows. The transcription research replaces what is behind it.
public protocol Transcriber: Sendable {
    func prepare(_ video: URL) async                                   // a video opened: start what takes time, without waiting for it
    func lines(for video: URL, in window: ClosedRange<TimeInterval>) async -> [TimedLine]   // what exists now; never waits
    func status(for video: URL) async -> TranscriptStatus
}

public struct SourceTranscript: Equatable, Sendable {                  // what one source has for a video so far
    public var lines: [TimedLine]; public var complete: Bool; public var problem: String?
}
public protocol TranscriptSource: Sendable {
    var name: String { get }                                           // "voiceover" | "subtitles" | "speech"
    func prepare(_ video: URL) async
    func transcript(for video: URL) async -> SourceTranscript?         // nil: this source has nothing for the video
}
public actor OrderedTranscriber: Transcriber {
    public init(sources: [any TranscriptSource])                       // the first source that isn't nil
    public init(cache: any TranscriptCaching)                          // the spec's three sources, in the spec's order
}
public enum TranscriptWindow {
    public static let radius: TimeInterval = 15
    public static func around(_ time: TimeInterval) -> ClosedRange<TimeInterval>      // max(0, t - 15) ... t + 15
    public static func cut(_ lines: [TimedLine], to window: ClosedRange<TimeInterval>) -> [TimedLine]   // whole lines that overlap, in time order
}

public protocol TranscriptCaching: Sendable {
    func load(for video: URL) -> [TimedLine]?
    func save(_ lines: [TimedLine], for video: URL)
}
public actor SpeechSource: TranscriptSource {
    public typealias Recognize = @Sendable (URL) -> AsyncThrowingStream<TimedLine, any Error>
    public init(cache: any TranscriptCaching, recognize: @escaping Recognize = SpeechRecognition.lines)
}
public struct SpeechProblem: Error { public var why: String }          // why recognition gave nothing, or stopped short
public enum SpeechRecognition { public static let lines: SpeechSource.Recognize }   // SpeechAnalyzer on the file's audio track
```

| Source | Finds | Lines |
|---|---|---|
| `VoiceoverSource` | `voiceover.json` in the video's folder | one per scene with narration; a scene lasts `ceil((durationSeconds + paddingSeconds) × fps)` frames and starts where the previous one ends; times are to the millisecond; `fps` is the video's nominal frame rate (30 when unknown), given as a closure so the test passes 30 |
| `SubtitleSource` | `<base>.srt`, then `<base>.vtt` | one per cue: a cue of several lines is one line, without its tags; a cue that doesn't read is skipped, and a file with no cue counts as absent |
| `SpeechSource` | always there | `SpeechAnalyzer` with `SpeechTranscriber` on the audio track, started by `prepare` in a background task; its lines grow as results come; it reads and writes a `TranscriptCaching` it is given, so a second open is instant |

- **The order.** `OrderedTranscriber.prepare` asks each source in turn: it prepares the source, then asks for its transcript, and stops at the first that isn't nil. So a source is prepared only when every source before it has nothing, and a video with a sidecar never starts speech recognition. It keeps the choice per video, and the transcript itself once it is complete, so a sidecar is read once per open. Opening the video again chooses again. `init(cache:)` holds the spec's order; the app gives it the cache and knows no source.
- **The cut.** A line is in the window when it is said at some moment of it (`end > lower` and `start < upper`). It is kept whole, with its own times, also when it starts before the window or ends after it.
- **Speech.** `SpeechSource` is an actor that keeps a `SourceTranscript` per video. `transcript` returns what it has so far, so a batch sent early carries the lines that exist at the send. What recognises is a function it is given, `Recognize`: a stream of lines that ends with the last one, or throws why it stopped. A test gives a stream it runs by hand; the app gives `SpeechRecognition.lines`. A recognition that ends is `complete` and goes to the cache, with no lines too (a video with no speech). One that throws keeps its lines, stays incomplete, says why in `problem`, and isn't cached; opening the video again tries again. One that runs isn't started twice.
- **`SpeechRecognition`** reads the audio track with `AVAssetReader`, decoded to the format `SpeechAnalyzer.bestAvailableAudioFormat` names, and hands the analyzer one buffer at a time as it asks for it (`analyzeSequence` over an `AsyncStream(unfolding:)`), so a long video is never decoded ahead into memory. It asks for final results only: each result is one line, with the result's `range` as its times. The language is the first of the person's languages `SpeechTranscriber` supports, exactly or as another region's form of it, else American English. A model that isn't installed is downloaded first (`AssetInventory`). Each thing that can stop it (no audio track, no supported language, no model, a read failure) is a `SpeechProblem` in words.
- **The cache.** `TranscriptCaching` takes the video's URL, not its hash: `VRStore` implements it and hashes the file itself, so Transcript depends on neither Store nor the hash.

NOTE: On macOS 26.5 `SpeechAnalyzer` on a file asked for no permission: the ad-hoc signed app transcribed the fixture with no prompt, and the English model was already installed. `Info.plist` still carries `NSSpeechRecognitionUsageDescription`, in case a later system asks.

### Store: `VRStore`

```swift
public enum ContentHash {
    /// SHA-256 over the file's size and three 1 MiB samples (start, middle, end); the whole file when it is 3 MiB or less.
    public static func of(_ file: URL) throws -> String        // 64 hex digits
}
public struct SupportLayout: Sendable {
    public let root: URL
    public init(root: URL)
    public var listenerFile: URL; public var appFile: URL; public var videosFolder: URL
    public func folder(_ hash: String) -> URL; public func reviewFile(_ hash: String) -> URL
    public func keyframe(_ id: CommentID, of hash: String) -> URL; public func crop(_ id: CommentID, of hash: String) -> URL
    public func transcriptFile(_ hash: String) -> URL
}
public struct AppState: Codable, Equatable, Sendable {
    public struct LastVideo { public var path, contentHash: String; public var time: Double }
    public var lastVideo: LastVideo?
}
public struct ReviewStore: Sendable {
    public let layout: SupportLayout
    public init(layout: SupportLayout)
    public func loadReview(_ hash: String) -> Review?           // nil when there is none, or it doesn't read
    public func loadReviews() -> [Review]                       // every review under the folder, in the order of their hashes
    public func save(_ review: Review) throws
    public func loadLedger() -> ListenerLedger; public func save(_ ledger: ListenerLedger) throws
    public func loadAppState() -> AppState; public func save(_ state: AppState) throws
}
public struct TranscriptCache: TranscriptCaching { public init(layout: SupportLayout) }

protocol StoredFile: Codable { static var current: Int { get }; var version: Int { get } }   // internal: one JSON file of the store
extension StoredFile {
    static func read(at url: URL, valid: (Self) -> Bool = { _ in true }) -> Self?
    func write(to url: URL) throws
}
```

A path takes the video's whole hash beside the id, so `SupportLayout` is pure: it never reads the disk to turn an id's eight digits into a folder. Whoever holds the review has the hash; a listener's command, which has only an id, asks `ReviewDesk.hash(naming:)`, which looks among the reviews it read at launch. `ContentHash` hashes the file's size as eight big-endian bytes, then the bytes.

`StoredFile` is the one way a JSON file of the store is read and written; `ReviewStore`'s three files and `TranscriptCache`'s are each a private struct that conforms to it.

- **Read.** A file that isn't there is none. A file that doesn't decode, whose `version` isn't the one this build writes, or that `valid` turns down (a `review.json` that names another video than its folder) is moved aside, as `review.unreadable.json` beside it, and counts as none. So nothing is ever written over a file this build can't read, and a launch never fails on one. A second unreadable file replaces the one moved aside before.
- **Write.** The whole file, sorted keys, to a temporary file that then replaces the old one (`Data.write(options: .atomic)`), after the folders above it are made. A reader finds the old file or the new one.
- **The forms.** `review.json` is `{"review": {…}, "version": 1}`, with the `Review` as `Codable` writes it: `video`, `comments`, `batches`, `note` and the two counters `nextComment` and `nextBatch`, so an id is never given twice across runs. A batch's `transcripts` are one object, each comment's id naming its lines (`Batch` encodes itself for that; a dictionary keyed by `CommentID` would otherwise be written as a list of pairs). `listener.json` is `{"ledger": {"session", "deliveries"}, "version": 1}`. `app.json` is `{"lastVideo": {"path", "contentHash", "time"}, "version": 1}`. Times are written as `Date` encodes them by default (seconds, as a number), so a time reads back to the same instant and a review read back equals the one written.
- **What isn't kept.** The comment being typed, the notice, the lease, the open `wait`s and `ask`s, the batches in flight and presence: each is rebuilt or gone after a restart. A keyframe's and a crop's path isn't kept either: `SupportLayout` gives it from the id.
- **A review that was moved aside** leaves its keyframes and crops in the folder. The video then starts a new review whose counters start at 1, so those images are written over as the ids come again.

`TranscriptCache` is `VRTranscript`'s `TranscriptCaching`: it hashes the video it is given and reads or writes `transcript.json` in that video's folder, as `{"lines": [{"start", "end", "text"}], "version": 1}`. A file that doesn't read, or that a newer build wrote, is moved aside as `transcript.unreadable.json` and counts as none, so the video is recognised again. A transcript that can't be written is only recognised again at the next open.

#### Store: the layout on disk

```text
~/Library/Application Support/Video Review (proto-1)/      the real support folder
  control.sock            the app on the person's data listens here
  demo.sock               the app on demo data listens here
  demo.json               the demo pointer: which folder the demo run uses
  app.json                ┐
  listener.json           │ the person's data, laid out as below
  videos/…                ┘

<demo folder>/            given to `app open --demo`; made when missing; never holds a socket
  app.json                the last video: path, content hash, time
  listener.json           the listener session and the deliveries
  videos/
    <content hash>/       64 hex digits: one video, whatever its name or place
      review.json         the video's info, comments with threads, batches, note, id counters
      transcript.json     the SpeechAnalyzer result, when it finished
      frames/<comment id>.png     the keyframe
      crops/<comment id>.png      the crop, for a comment with a region
```

- **Keyed by content.** `ContentHash.of` reads at most 3 MiB, so a large video opens at once. A renamed or moved copy gives the same hash and so the same folder. `review.json` keeps the last path it was opened from, for the payload's `video.path`.
- **Demo apart from real.** The app's root is `SupportFolder.current(environment)`: the demo folder when `VIDEO_REVIEW_SUPPORT_DIR` is set, else the real folder. Everything is under that root, so the two can't mix. The only things a demo run puts in the real folder are `demo.json` and `demo.sock`.
- **Writes** are whole-file and atomic. Every JSON file has a `version`; a newer or unreadable file is moved aside, never overwritten (`StoredFile`).
- **Read once.** Every `review.json`, `listener.json` and `app.json` are read at launch and never again: from then on memory is what counts and the files follow it, so a file can't win over a newer change. Reading every review at launch is what lets a listener's command find a video that isn't open; it costs one small file per video ever commented on.
- **Written with the action.** A review is saved inside the action that changes it, on the main actor, before the action is answered: what a command printed is on disk. A write is one small file at the rate of a person's or a listener's actions. The two things that change faster aren't written at their rate: the note is saved when the typing rests (`ReviewDesk.changeTyped`), and the playhead's place only at the quit.
- **Paths in the payload** are these files' absolute paths.

### App: `VRApp`

#### AppModel, the orchestrator

```swift
@MainActor @Observable final class AppModel {
    let player: PlayerEngine
    let desk: ReviewDesk
    let listener: ListenerQueue
    let transcriber: any Transcriber
    init(environment: [String: String], transcriber: (any Transcriber)? = nil,               // nil: OrderedTranscriber(cache: TranscriptCache(layout))
         now: @escaping @MainActor () -> Date = { Date() })                                  // the time a batch is sent at, and the listener queue's
    private(set) var notice: Notice?                 // the last agent message, shown for 5 s
    private(set) var selection: CommentID?           // the marker and card in focus

    // one method per action; the views and ControlServer are its only callers
    func open(_ video: URL) async throws(ActionError) -> VideoInfo       // hashes the file, opens it in the player, loads its review with nothing awaited between, then prepares its transcript
    func play() throws(ActionError);  func pause() throws(ActionError)
    func seek(to seconds: Double) async throws(ActionError) -> Double    // exact; refused outside 0...duration
    func scrub(to seconds: Double);  func setSpeed(_ speed: Double)      // the scrubber's drag and the speed menu: the person's only
    func openForPerson(_ video: URL);  func chooseVideo();  func togglePlayback()   // the person's ways into the actions: a refusal is shown, not thrown
    func attempt<T>(_ action: () throws(ActionError) -> T) -> T?         // runs an action for the person: its refusal goes to `failure`
    func commitDraftForPerson(text: String) async -> Bool
    func perform(_ action: PlayerAction)                                 // what a player key does
    func select(_ id: CommentID)                                         // a click on a marker or a card: seek, pause, focus

    private(set) var draw: RegionDraw                                    // the rectangle being dragged on the frame
    func beginRegion(at point: CGPoint);  func dragRegion(to point: CGPoint)   // the press, and each move: the move that makes a rectangle pauses
    func endRegion(in geometry: FrameGeometry)                           // the release: a region opens the composer, a click plays or pauses
    func cancelRegion() -> Bool                                          // Escape while drawing

    func startDraft(region: Region?) throws(ActionError)                 // pauses; the composer opens
    func commitDraft(text: String) async throws(ActionError) -> Comment  // Return in the composer
    func discardDraft()                                                  // Escape
    func addComment(text: String, at: Double?, region: Region?) async throws(ActionError) -> Comment   // the CLI's path
    func editComment(_ id: CommentID, text: String) throws(ActionError) -> Comment
    func deleteComment(_ id: CommentID) throws(ActionError)
    func sendBatch() async throws(ActionError) -> Batch                  // Cmd+Enter, the Send button and `batch send`
    func sendBatchForPerson();  var canSend: Bool                        // the person's way in; whether a comment is queued or text is in the comment box
    func answer(_ id: CommentID, text: String) throws(ActionError) -> Comment   // the answer box and `thread answer`: into the thread, then to the open `ask`
    func answerForPerson(_ id: CommentID, text: String) -> Bool          // Return in the answer box: a refusal is shown, not thrown
    func show(_ notice: Notice);  func openNotice()                      // an agent message arrived; a click on the notice: select its comment, take it down
    func setNote(_ text: String) throws(ActionError) -> String           // `context set`; saved at once; the note as the review keeps it
    func typeNote(_ text: String) throws(ActionError);  func endNote()   // the context popover: each key counts at once and is saved when the typing rests; the popover closed
    func reopenLastVideo() async                                         // at launch: the video `app.json` names, at its playhead's place
    func leaving()                                                       // at the quit: saves what was typed, and the playhead's place
    var sidecar: ContextSource.Sidecar? { get }                          // the open video's context sidecar, as it is on disk now

    func transcriptStatus() async -> TranscriptStatus?                   // the open video's; ControlServer asks it, then takes the snapshot
    func snapshot(lease: ControlLease.Status?, transcript: TranscriptStatus? = nil) -> StateSnapshot
}
```

`ActionError` wraps a `ReviewError`, or says `no video is open`, `can't open <path>: <why>`, `<time> is outside the video, which ends at <duration>`, `no comment is being written`, `can't keep the comment's keyframe: <why>`, `can't keep the comment's crop: <why>`, `can't keep the change: <why>` (`store(String)`: the review couldn't be written to the support folder, so the change wasn't made), or carries a line of the listener queue's own (`listener(String)`: one listener at a time, an unknown status, the app quitting). A review's `timeOutsideVideo` is worded as the seek's, so both read `0:30.000 is outside the video, which ends at 0:21.233`. Its `message` is the refusal line. What the person does can't throw to anyone, so `AppModel.failure` keeps the line and the window shows it in an alert.

The comment box and `comment add` meet in one private method, `queueComment(text:time:region:frame:)`: `commitDraft` gives it the draft's time, the draft's region and the frame the draft is already reading, `addComment` the `--at` time (or the playhead), the `--region` and no frame. It asks `review.checkedText` first, so an empty text or a time outside the video is refused before any frame is read; then it awaits the frame and calls `desk.add`, which writes the keyframe and the crop. So a drawn region and a `--region` are the same `Region` handed to the same call, and their crops can't differ. The new comment becomes the selection, from either way in.

A region is drawn in four steps, each a method the overlay calls with the pointer's place in the frame's view:

```text
beginRegion(at:)      draw: idle → pressed
dragRegion(to:)       pressed → drawing once the pointer is 8 points from the press: the video pauses here,
                      so the frame drawn on is the frame commented on
endRegion(in:)        a click        → togglePlayback
                      a region       → the composer opens on it (a draft at the playhead, with the region)
                      nothing of the frame in the rectangle → nothing; a video that was playing plays on
cancelRegion()        Escape while drawing → the rectangle is given up; a video that was playing plays on
```

`RegionDraw` (in `Overlay/`) is the pure value behind them: `idle`, `pressed`, `drawing`, `cancelled`. A cancelled draw stays cancelled until the button is let go, so the rest of that drag draws nothing. `startDraft(region:)` and `endRegion` open the composer through one private `openDraft`: with the composer already open at the same frame, a new rectangle only replaces that draft's region, so what was typed stays; with the playhead moved since, the draft starts over at the frame on screen.

Across runs, `AppModel` keeps one thing of its own, in `app.json`: the last video. `open` writes the video's path and hash with the time 0, and `leaving` (from `applicationWillTerminate`) writes the playhead's place, so the place is written once per run and not as the video plays. `reopenLastVideo` opens the file at that path when it is still there and, when its hash is the one kept, seeks to the place. The path names the file and the hash the history: a file that was moved or renamed isn't looked for, so the app starts with no video, and the file gets its history back when it is opened; another video at the old path opens as itself. A file that can't be opened is passed over without an alert.

`AppModel` also knows the run's data folder (`support`, `isDemo`, from `SupportFolder`) and the app's one window, which `Screenshotter` captures.

The listener's actions (`wait`, `ack`, `status`, `reply`, `ask`) are methods on `ListenerQueue`, since they act on a batch by its id whatever video is open. `answer` is on `AppModel`, as every action of the person and the operator is: it finds the review by the id's video (`desk.hash(naming:)`), has the review take the answer, and tells the queue (`listener.answered`), which resumes the `ask` that waits. The answer box calls it through `answerForPerson` and `thread answer` through the server, so the two can't differ.

The notice is the last agent message, kept on `AppModel` for `Notice.duration` (5 s): `ListenerQueue` calls its `announce` closure, which `AppModel` sets to `show`, for each `reply`, each new question and each `ack` that says something. A status announces nothing, since the marker shows it. A later notice replaces the one that is up, and a task takes it down when its time is up, unless it was replaced or clicked first.

#### Player

`PlayerEngine` wraps one `AVPlayer`. `open` loads the video track's length, shown size and frame rate, refuses a file AVPlayer can't play, and answers once the item is ready to play, so a seek or a screenshot right after finds the frame there. When two opens overlap, the later one wins and the earlier is refused. The `duration` is the video track's, to the millisecond (21.233 for the fixture, whose audio runs to 21.248): every time up to it has a frame. `seek` uses zero tolerance and returns when the seek has landed, so `state` after `player seek 0:10` reads exactly 10. A periodic time observer publishes `time` 30 times a second, to the millisecond and never past `duration`, and `playing` from the player's rate. `play` at the video's end starts again from 0. `PlayerSurface` hosts the `AVPlayerLayer` alone: AVKit's own controls are off, because the timeline has to carry the markers.

`Shortcuts.swift` holds the player's keys in two parts:

```swift
enum PlayerAction: Equatable { case togglePlayback, skip(seconds: Double), step(frames: Int), comment, deleteSelection
                               var repeats: Bool }       // only skip and step repeat while the key is held
enum Shortcuts {     // pure: the whole table, and the rule that typing never reaches it
    static func action(characters: String, modifiers: NSEvent.ModifierFlags, typing: Bool) -> PlayerAction?
}
@MainActor final class ShortcutMonitor { init(model: AppModel); func start() }
```

`ShortcutMonitor` is a local `NSEvent` monitor for key-down events, started by the `AppDelegate`. For each key it asks `Shortcuts.action` with `typing` set to whether the window's first responder is a text view (`NSText`: the field editor of every text field, and every text view). A player key is done through `AppModel.perform` and swallowed; any other event travels on untouched. Before any of that, Escape goes to `AppModel.cancelRegion`: while a rectangle is being drawn it gives the rectangle up and the key goes no further, with the comment box open or not. The monitor also steps aside for another window (the open panel), under a sheet (the alert), with no video open, and while the comment box is open, which covers the moment before the box has taken the focus. `Shortcuts.action` returns nil when `typing` is true, and for a key with Command, Control or Option, so the rule is one pure function that `ShortcutsTests` covers for every key. No plain key is a menu shortcut, since a menu shortcut would fire while typing. Menu items carry only Command shortcuts (Cmd+O, and Cmd+Return on "Send Comments" in the File menu). A menu shortcut is asked before the focused field gets the key, so Cmd+Return sends from the comment box too. The item and the sidebar's Send button are off while `canSend` is false.

A monitor was chosen over SwiftUI's `onKeyPress`, which reaches the focused view only: the player's keys must work wherever the focus is, as long as it isn't in a text field, and the monitor asks exactly that question.

#### Keyframes and crops

`FrameGrabber` makes both from the video file, never from the screen:

```text
FrameGrabber.frame(of video, at seconds) -> CGImage :
    AVAssetImageGenerator(asset) with zero time tolerance, the track's transform applied, full natural size
    image(at: seconds); when nothing is found exactly there (past the last frame's start), the frame before
FrameGrabber.write(image, to file) :
    the folders above made when missing → PNG → videos/<hash>/frames/<id>.png
FrameGrabber.crop(image, to region) -> CGImage :
    region.pixels(in: image size) → the keyframe's CGImage cropped (an image's rectangle has its origin top left, as a region has)
    → write → videos/<hash>/crops/<id>.png
```

So a keyframe is the exact frame at the comment's time, at the video's own resolution, whatever the window's size; and the UI and the CLI get the same crop, because both hand `FrameGrabber` the same normalized region. `ReviewDesk.add` writes both files before the comment is published. A draft's frame is read from the moment the composer opens, so Return is instant. `Screenshotter` reads the frame at the playhead through `FrameGrabber` too, when it has to render the window itself.

`FrameGeometry` is the one place that knows where the frame sits in the view (aspect-fit, letterboxed) and turns view points into a normalized region and back. The overlay draws a stored region through it on every layout, so a region stays on the same pixels when the window changes size.

```swift
struct FrameGeometry: Equatable {
    let frame: CGSize; let view: CGSize                 // the video's shown size (only its shape matters); the view's size in points
    var frameRect: CGRect                               // the frame fitted whole into the view and centred, as AVPlayerLayer shows it
    func region(from: CGPoint, to: CGPoint) -> Region?  // two view points → Region.spanning; what is over the bars is left out
    func rect(of region: Region) -> CGRect              // a region → view points, at the view's size now
    func origin(ofBox size: CGSize, beside rect: CGRect, gap: CGFloat = 12, margin: CGFloat = 8) -> CGPoint
}
```

Points have their origin at the view's top left, as SwiftUI's have and as a region has. `origin(ofBox:beside:)` is where the comment box goes next to a region: to its right, else to its left, else below it, else above it, never nearer than the margin to the view's edge; when no side has the room (a region that fills the frame), as near to the right as the view allows, over the region. A box that fits in the view is always whole in it. The sidebar's keyframe thumbnail outlines the region through the same `rect(of:)`.

#### ReviewDesk

```swift
@MainActor @Observable final class ReviewDesk {
    struct Draft { var time: Double; var region: Region?; var resumes: Bool; var frame: Task<Result<CGImage, FrameFailure>, Never>
                   var text = "" }                      // what is typed so far: here, not in the comment box, so a send can queue it
    private(set) var open: Review?                      // the playing video's review
    private(set) var draft: Draft?                      // its time, its region, whether to play on afterwards, the frame being read
    let layout: SupportLayout;  let store: ReviewStore
    init(layout: SupportLayout)                         // reads every review under the folder
    var all: [Review]                                   // every review there is, open or not, in the order of their hashes
    func load(_ video: VideoInfo) -> Review             // the one kept under the hash, with the file it was opened from now, or a new one
    func close()                                        // no video is open any more
    func startDraft(time: Double, region: Region?, resumes: Bool, video: URL);  func pointDraft(at region: Region?);  func endDraft()
    func typeDraft(_ text: String)                      // the comment box's binding writes here
    func review(_ hash: String) -> Review?              // any video this run has seen, open or not
    func add(text: String, time: Double, region: Region?, frame: CGImage, to hash: String) throws(ActionError) -> Comment
    func delete(_ id: CommentID, from hash: String) throws(ActionError)      // the comment, then its keyframe and crop files
    func keyframe(of id: CommentID) -> URL;  func crop(of id: CommentID) -> URL   // in the folder of the video its id names
    func hash(naming id: String) -> String?                                  // the video a comment's or a batch's id names by its first eight digits, open or not
    func change<T>(_ hash: String, _ body: (inout Review) throws(ReviewError) -> T) throws(ActionError) -> T
    func changeTyped(_ hash: String, _ body: (inout Review) -> Void) throws(ActionError)   // published at once, saved when the typing rests
    func settle()                                                            // saves what was typed and isn't saved yet
}
```

`change` is the only way a review changes: copy, apply the review's own method, save through `ReviewStore`, publish. A refused change saves nothing. `add` and `delete` are a change with a file beside it: `add` writes the keyframe and, for a comment with a region, the crop before it publishes, so a file that can't be written refuses the comment and takes no id; `delete` removes the files after the comment is gone. A review that can't be saved is a refusal too (`ActionError.store`), so nothing is shown that isn't on disk. A change that changed nothing (a second acknowledgement, the same question asked again) writes nothing.

The desk reads every review once, as it is made, and keeps them by content hash; no file is read after that. `load` gives the review kept under the video's hash the file it was opened from this time, and saves it when that path is a new one (a renamed or moved copy); a video with no review gets a new one, which is in no file until its first change.

`changeTyped` is for the one change that comes a key at a time, the note typed in the context popover. The review is published at once, so a batch delivered meanwhile carries the note as typed, and it is saved when no key came for `rest` (600 ms), at the review's next `change`, or at `settle`, which the popover's close and the quit call. A save that fails there is logged and tried again at the next `settle`.

#### ListenerQueue

```swift
@MainActor @Observable final class ListenerQueue {
    struct Handed { var batch: BatchID; var listener: String; var context: String? }   // a batch handed to a wait, until its reply is written or not
    init(desk: ReviewDesk, now: @escaping @MainActor () -> Date)                       // reads the ledger, reconciles it with the desk's reviews
    private(set) var ledger: ListenerLedger
    var session: ListenerLedger.Session?
    var presence: Presence;  func presence(at: Date) -> Presence;  var presenceRunsOut: Bool
    func standing(of batch: BatchID) -> ListenerLedger.Standing

    func enqueue(_ batch: Batch, video: VideoInfo)                                     // from AppModel.sendBatch
    func wait(holder: Holder, timeout: Int?) async -> WaitOutcome                      // .batch(Handed, payload:) | .timedOut | .refused(String) | .gone
    func delivered(_ handed: Handed);  func undelivered(_ handed: Handed)              // the reply was written, or couldn't be
    func acknowledge(_ id: String, text: String?, holder: Holder) throws(ActionError) -> Batch
    func setStatus(_ id: String, _ state: String, holder: Holder) throws(ActionError) -> Comment
    func reply(_ id: String, text: String, holder: Holder) throws(ActionError) -> ReplyTarget
    func ask(_ id: String, question: String, wait: Int?, holder: Holder) async -> AskOutcome   // .answer(String) | .timedOut | .refused(String) | .gone
    var announce: @MainActor (Notice) -> Void                                          // each agent message, for the window's notice
    func answered(_ comment: Comment)                                                  // from AppModel.answer: resumes the ask
    func quitting()                                                                    // answers every open wait and ask
}
```

- It keeps the open `wait`s and the open `ask`s, a continuation each, oldest first. An `ask` is kept with its comment's id and its question's text.
- Every listener command starts with one step, `admit(holder)`: refused while the app quits and while another listener's `wait` is open; then `ledger.attach`, and for a new listener the requeue of what the one before took.
- `ReplyTarget` is `.comment(Comment)` or `.batch(Batch)`: `reply` tells the two kinds of id apart by their form (`-b<n>` after the video's eight digits is a batch), so a comment's id that names nothing is refused as a comment.
- `setStatus` refuses a state that isn't `working`, `done` or `failed` in its own words, before the review is asked. After the change it asks `review.isFinished` for the comment's batch and, when it is, calls `ledger.finish`: the batch's delivery is `finished` from that moment, and the listener has nothing taken.
- An `ask` ends in one place, `endAsk(ticket, with:)`, whoever ends it: the answer (`answered`), its `--wait`, its cancelled connection (`.gone`), another question on its comment, or the quit.
- Another question on a comment ends the asks that waited on the one before, refused with ``another question was asked on <id> since: `<question>` ``, since nobody will answer theirs.
- A `wait` from another key while a `wait` is open is refused: `<name> in <place> is already listening; one listener at a time`. A refused `wait` doesn't touch the session. Several waits of one key may be open; the oldest gets the batch.
- `enqueue` and `wait` both end in the same step, `deliverIfPossible`: while there is a pending delivery that isn't in flight and an open wait, build the payload, mark the batch in flight and resume the oldest wait with it. `delivered` and `undelivered` take the batch out of flight and run the step again.
- A delivery whose batch is finished, or whose review this run doesn't have, is taken out of the ledger there instead of being sent with no comment.
- A `wait` ends in one place, `end(ticket, with:)`, whoever ends it: the delivery, its timeout, its cancelled connection (`.gone`), or the quit. The waiter is removed first, so only the first of them answers it.
- Presence is not stored: `presence(at:)` asks the ledger with whether a `wait` or an `ask` is open, since either is a connection the listener holds. Both are observed, so the presence indicator follows them. Only the 120 s rule changes by time alone; while `presenceRunsOut` says it can, the pill redraws every second, and `state` asks at the request's time.
- `ask` without `--wait` waits without limit, as the spec says the command exits with the answer. An `ask` with the same text as the comment's last question attaches to that question: when it is already answered, it returns the answer at once, so a listener that timed out can ask again and lose nothing.
- The ledger changes in one place, `record`: the change is applied to a copy, and a ledger that differs is saved to `listener.json` through the desk's store. A ledger that can't be saved is logged and goes on in memory. `delivered` records only after the reply was written, so a batch whose reply never reached its listener is still pending on disk.
- `init` takes up where the last run stopped: it reads the ledger, runs `ledger.reconcile(with: desk.all)`, and gives every pending delivery's unfinished comments the state `sent` again (`review.requeue`), which covers a quit between a new listener's `attach` and the requeue of its comments. A batch a listener had taken stays taken by that session: the same key goes on with it after the restart, and gets no context twice; another key starts a new session, and `admit` requeues the batch, as in one run.

#### ControlServer

Shipyard's server, with this app's routes.

```swift
@MainActor final class ControlServer {
    struct Answer { var reply: ControlReply; var quits = false; var granted: ControlLease.Term?; var delivery: ListenerQueue.Handed?
                    var handsOver: Bool }           // a lease or a batch: the server must hear how the write went
    private(set) var lease: ControlLease                // every change runs leaseChanged()
    let indicator: LeaseIndicator                       // what the lease button reads
    func start() throws;  func stop()
    func reply(to data: Data) async -> Answer
    func written(_ answer: Answer);  func undelivered(_ answer: Answer)
    func stopLease()                                    // the lease button's Stop
    func settleLease()                                  // the timer at the lease's end
}
```

The server owns the one `ControlLease`. Every change to it runs `leaseChanged`, the one place a change is applied:

1. The lease is copied to `LeaseIndicator`, so the toolbar's lease button follows it.
2. Each waiting `take` of the holder that now has the lease is answered, and its timeout cancelled.
3. A timer is set for `lease.nextEnd(after:)` and replaces the last one. When it fires, `settleLease` ends the lease and hands it to the first waiter, with no request.

A `take` in line is a `Waiter` in the server: its holder, its wait, whether it wants JSON, its continuation and its timeout task. The timeout calls `lease.giveUp`, never before the deadline the take was given. `stop()` answers every waiter with `video-review is quitting`. The server takes its time from a `now` closure and its zone from `timeZone`, so `VRAppTests` drives it with a clock of its own.

The person's Stop is `stopLease()`, which only calls `lease.stop(at:)`. The server puts it in `LeaseIndicator.stop`, and the Stop button in the lease button's popover calls that closure. So the Stop path is the pure rule plus one call, and tests reach it without a click.

```text
reply(to data):
    message = ControlMessage.decode(data)          else refused(error.message)      ← version checked here
    if message.request.isLeased:
        decision = lease.use(by: message.holder, at: now)                          ← taken or renewed here
        if refused: return refused(refusal.message)
    switch message.request:                         one line per command
        .playerSeek(s)      → model.seek(to: s)                → done(time)
        .commentAdd(…)      → model.addComment(…)              → done(id | comment JSON)
        .wait(t)            → listener.wait(holder, t)         → done(payload) with delivery | done("") | refused
        .controlTake(w)     → lease.take(…), waiting in line if queued → done(held | status JSON) with granted
        .controlRelease     → lease.release(…)                 → done("released")
        .appQuit            → done("quit"), lease in the reply, quits = true
        …
    an ActionError → refused(error.message)
```

The wire carries a region as any four numbers (`WireRegion`). The `comment.add` route turns them into a `Region` through `Region.checked`, so numbers outside the frame are refused in the review's words before anything is read or written, and `RegionArgument` in the command only refuses what isn't four numbers (exit 2, with the usage).

`SocketListener` owns the POSIX side off the main actor: bind (0600), listen, accept, read one request to its end (8 MB at most), await `reply(to:)` with the heartbeat running, write, close, then tell the server `written` or `undelivered` for an answer that hands something over.

Every request of the contract has its route. `written` marks a `wait`'s batch taken; `undelivered` leaves the batch pending and releases a lease a `take` was granted.

The app listens on `demo.sock` when `VIDEO_REVIEW_SUPPORT_DIR` makes it a demo run, else on `control.sock`, both in the real support folder. A socket file nothing answers on (left by an app that was killed) is replaced.

`StateSnapshot` is what `state` prints. It is built by `AppModel.snapshot` and encoded with sorted keys:

```json
{
  "app": {"version": "0.1.0", "variant": "proto-1", "demo": true, "support": "/abs/demo"},
  "video": {"path": "/abs/sample.mp4", "contentHash": "7f3a…", "title": "sample", "duration": 21.233},
  "player": {"time": 10, "playing": false, "rate": 1},
  "draft": null,
  "comments": [
    {"id": "7f3a9c21-c1", "time": 10, "text": "…", "region": null, "state": "done", "batchId": "7f3a9c21-b1",
     "keyframePath": "/abs/…/frames/7f3a9c21-c1.png", "cropPath": null,
     "thread": [{"author": "agent", "kind": "question", "text": "…", "at": "2026-10-04T12:00:00Z"}]}
  ],
  "queue": ["7f3a9c21-c3"],
  "batches": [{"id": "7f3a9c21-b1", "sentAt": "…", "commentIds": ["7f3a9c21-c1"], "delivery": "finished", "thread": []}],
  "context": {"sidecarPath": "/abs/sample.context.md", "note": ""},
  "transcript": {"source": "voiceover", "complete": true, "lines": 3, "problem": null},
  "listener": {"presence": "absent", "name": null, "place": null},
  "lease": {"holder": "Claude Code", "place": "/abs/repo", "secondsLeft": 58, "waiting": 0},
  "notice": null
}
```

`comments` are in time order; `queue` lists the ids of the queued ones in the same order; `video`, `draft`, `lease` and `notice` are `null` when there is none. `draft` is `{"time": 10, "region": null}` while the comment box is open, with its region as `{"x": 0.48, "y": 0.3, "w": 0.28, "h": 0.12}` once one is drawn. A comment's `region` is the same four numbers and its `cropPath` the crop's absolute path; both are `null` for a comment on the whole frame. `batches` are the open video's, in the order they were sent; a batch's `delivery` is `pending`, `taken` or `finished`. `listener` names the listener and its place only while it is `listening` or `working`. With no video open, `comments`, `queue` and `batches` are empty. The object is one line. Every key is there from the first build: a part whose ticket hasn't landed carries its empty value (`[]`, `null`, `""`, presence `absent`), and `transcript` is `{"source": null, "complete": false, "lines": 0, "problem": null}` with no video open. `transcript.source` is `voiceover`, `subtitles` or `speech`; `lines` counts the lines of the whole video so far. While speech recognition runs it is `{"source": "speech", "complete": false, "lines": 2, "problem": null}`, with `lines` growing; when recognition stopped short, `complete` stays false and `problem` says why in words (`"the video has no audio track"`). `player.time` and `video.duration` are to the millisecond; `player.rate` is the speed playback runs at while it plays. `context` is the open video's: `sidecarPath` is the absolute path of the sidecar found beside it now (`null` when there is none, or no video), `note` the reviewer's note (`""` when there is none). A thread message is `{author, kind, text, at}`, on a comment and on a batch alike. `notice` is the agent message the window announces right now, `{"batchId": "7f3a9c21-b1", "commentId": "7f3a9c21-c1", "kind": "question", "text": "…"}`, with `commentId` `null` for a message about the whole batch, and `null` once it is gone.

`Screenshotter` captures the app's own window through ScreenCaptureKit limited to this process (`SCShareableContent.currentProcess`), which needs no Screen Recording permission. With `--appearance` it sets the app's appearance, waits 350 ms for the redraw, captures, and puts the appearance back. If the capture fails, it draws the window's content view itself and then the frame at the playhead, read from the file, where the player's layer shows it (`AVPlayerLayer.videoRect`), since a player layer doesn't draw into a bitmap; the title bar's place stays blank, and the reply says on standard error that the PNG was rendered. A window that isn't on screen (closed, minimized, hidden) is refused.

#### Views

```text
┌─ toolbar ───────────────────────────────────────────────────────────────────┐
│ sample.mp4                          [Context]   [Sidebar]   [⌖ lease only]  │
├──────────────────────────────────────────────────┬──────────────────────────┤
│                                                  │ Queue 2                  │
│                                                  │ ○ 0:04  the title is…    │
│            the video frame                       │ ▢ 0:10  this box…        │
│      ┌ ─ ─ ─ ─ ┐  ┌───────────────────┐          │ ──────────────────────── │
│        region     │ comment box       │          │ Batch 1 · acknowledged   │
│      └ ─ ─ ─ ─ ┘  └───────────────────┘          │ ✓ 0:15  done             │
│                          ┌ notice ─────────┐     │   └ agent: fixed in a1b2 │
│                          │ agent · 0:15 …  │     │ ? 0:18  question         │
│                          └─────────────────┘     │   └ [answer…           ] │
├──────────────────────────────────────────────────┼──────────────────────────┤
│ ▶  0:10 / 0:21   ──○───▢────●────?──   1×        │ ● Listening  2 [Send ⌘↩] │
└──────────────────────────────────────────────────┴──────────────────────────┘
```

One `Window` scene. `RegionOverlay` lies over the player's surface and is the only thing the pointer meets there. Its surface takes the press anywhere in the view, with a crosshair pointer over the frame (`pointerStyle(.rectSelection)`), and hands the drag to `AppModel`'s four region methods. It draws one rectangle at most: the one being drawn (white edge, the rest of the frame dimmed, its size in the frame's pixels under it), else the draft's region (the same, without the size), else the selected comment's region (an accent edge, nothing dimmed), which shows only while the video is paused within half a frame of that comment's time, since on any other frame it would point at something else. It also holds the one `Composer` and places it: centred over the frame's foot for a comment without a region, and at `FrameGeometry.origin(ofBox:beside:)` for one with a region, measured again whenever the box grows. One composer for both places keeps what was typed when a region is drawn while the box is open.

The frame above the transport bar is one column, the sidebar the other, side by side in an `HStack` with a divider between them, both on the window's background under one toolbar. The sidebar is not an `inspector`: an inspector's column has its own glass background that reaches into the title bar, and it looked like another app beside the frame. The transport bar and the sidebar's send bar are both `Theme.footerHeight` tall, so the dividers above them line up across the window. The sidebar toggle animates with a critically damped spring, and with a short fade when Reduce Motion is on. Views read `AppModel` and call its methods; they keep no rule. Closing the window quits the app, since there is only one. `VideoReviewApp.swift` holds the `App`, the `AppDelegate` that is the composition root (it makes `AppModel`, `Screenshotter`, `LeaseIndicator`, `ControlServer` and `ShortcutMonitor`, starts the monitor at launch, then reopens the last run's video and only then starts the server, and at quit stops the server and calls `model.leaving()`) and `MainView`, the window's content.

The server starts after `reopenLastVideo` so that `app open`, which answers once the socket does, is followed by a `state` that already shows the video and its history. A video that takes longer than 4 s to open doesn't hold the server back. A video the person opened the app with (`application(_:open:)`) is opened instead of the last one.

A comment's row (`CommentCard`, a plain row with no box: only the selected one has a soft accent fill, as in a source list) is its keyframe, its mark, its time, its state in a word and its text, and under them its thread (`ThreadView`). A thread is one `MessageRow` per message: the agent's on the leading side under `Agent` or, for a question, `Agent asks`, in a grey bubble (honey-tinted for a question); the person's answer on the trailing side under `You`, in a soft accent-tinted bubble. Messages are the one place with boxes, as in a chat. The question that waits has a honey hairline and the line `Waiting for your answer` under it, and right below it the answer box: a text field and a send button, Return sends. The box is there only while a question waits. A message's clock time is in its tooltip, not in the row, where it would read as a time in the video. `StatusStyle.of(comment)` is what a card's mark and a marker both draw: the question's style while one waits, else the state's.

A batch's group in the sidebar is its head (`BatchHeader`: number, time sent, and where it stands: `Waiting for a listener`, `Delivered to the listener`, `Acknowledged`, `Acknowledged · 1 of 2 finished`, `Finished · 1 done, 1 failed`), then `BatchCard` with the messages for the whole batch when there are any, as bubbles under a small label and no box, then its comments' rows. Groups are parted by space and a thin divider, with sentence-case headers (`Queue`, `Batch 1`). At the sidebar's foot is the send bar: the presence indicator, the queued count and Send. The sidebar scrolls the comment in focus into sight, so a click on a marker or on a notice finds its row.

`NoticeToast` is an overlay at the bottom right of the frame's area, above the region overlay: who speaks and about what (`Agent · 0:10`, `Agent asks · 0:04`, `Agent · Batch 1`), then up to three lines of the message. It is a button: a click calls `openNotice`. It is drawn dark in both appearances, since it always lies over the frame or its black surround.

The lease button is the one view that doesn't read `AppModel`: the lease belongs to `ControlServer`, not to the model. `Control/LeaseBanner.swift` holds three small things. `LeaseIndicator` is the observable copy of the lease that the server keeps current, with the `stop` closure. `LeaseBannerText` makes the words from a `ControlLease.Status` (`Claude Code controls Video Review (proto-1)`, `/repo · 42 s left · 1 waiting`) and is tested. `LeaseButton` is the view: a toolbar item at the trailing end, an apricot `cursorarrow.rays` icon, there only while a lease is in force. A click opens its popover: the title and the detail, with a `TimelineView` that ticks the seconds, and the Stop button. The icon is part of the window, so `screenshot` shows it; the popover is a window of its own, so it doesn't.

`Comments/ContextNote.swift` is the toolbar's Context button, before the sidebar button, and its popover. The button is off with no video open; its document icon is filled while the open video has a sidecar or a note, and hovering says which. The popover names the sidecar file that was found beside the video, or says that there is none and which two file names it looks for, and holds the note in a text editor that has the focus as the popover opens. Each change to what is typed goes to `AppModel.typeNote`, which makes the review's `setNote` change as `context set` does and saves it once the typing rests; closing the popover calls `endNote`, which saves at once. So there is no Save button. The popover keeps what is typed in its own state, since the review keeps the note without the blank space around it, and takes the review's note over when it differs from what is typed (another video, or `context set` while it is open). It reads the sidecar when the video changes, when it opens or closes and when the note changes. The popover is a window of its own, so `screenshot` shows the button, not the popover, and the player's keys don't act while the person types in it.

### The listener skill

`.agents/skills/video-review-mate/` is what a Claude Code session in any repository runs to be the listener. It links nothing of this package and speaks only the spec's CLI contract, so it is the same skill for every prototype and for the product. Two files:

- **`SKILL.md`** is the loop: start `listen` in the background; on a batch, listen again first, read the context and each comment's keyframe, crop and transcript, decide each comment's intent, and for each one set `working`, do the work, commit once when files changed, `reply`, then `done` or `failed`; `ask` in the background when a comment isn't clear and go on with the next; one `reply` to the batch's id at the end. It also says what each exit code means for the loop and what each refusal asks for.
- **`scripts/vr.sh`** is the only code. Every command of the skill goes through it.

`vr.sh` finds the CLI, never on `PATH`, in this order: the path in `VIDEO_REVIEW_CLI`; `/Applications/Video Review.app`; the only `Video Review*.app` in `/Applications`; among several, the only one whose app runs. An app runs when its `state --json` exits 0: the contract fixes that command and its exit code, and leaves the shape of `app status --json` to each build. The last choice is kept for the session in `$TMPDIR/video-review-mate/cli-<session id>`, so a second prototype that starts later doesn't make the commands of a running loop ambiguous. With no app, or several and no single one running, it refuses and names `VIDEO_REVIEW_CLI`. `vr.sh which` prints the choice and its reason. So the variant's name is in no rule of the skill: clearing `Identity.variant` changes nothing in it.

`vr.sh listen` is `wait`, then `ack <batch id>` at once, then the payload on standard output and in `$TMPDIR/video-review-mate/<batch id>.json`. The batch's id is read with `plutil`, which every Mac has. The acknowledgement is the script's and not the session's on purpose: a session that is mid-task, in a long test run, wakes only when that tool call ends, and the person would wait for the acknowledgement that long. A `wait` refused because the app isn't running makes `listen` wait until `app status` says it runs, then wait again; any other refusal, and exit 3, pass through.

What the skill leans on in the design above:

- The session is the listener by `CLAUDE_CODE_SESSION_ID`, so only the session itself runs `vr.sh`; its sub-agents do work and report.
- `listen` again before the work keeps a `wait` open, so presence is `working` and a second batch is taken and acknowledged while the first is worked.
- `reply` before `status done`, so the person never sees a finished comment without its answer. The batch's own message goes last; `reply` to a batch needs no open delivery.
- An `ask` that ended without its answer is asked again with the same words and attaches to the question in the thread.
- At the end of a session the skill stops its `listen` and `ask` commands and leaves unfinished comments as they are: the next listener session's first command requeues them.

Claude Code reads skills from `.claude/skills/`, so `.claude/skills/video-review-mate` is a tracked link to the folder. Another repository gets the skill by installing it from this one (`npx skills add yahyabedirhan/video-review -s video-review-mate`), or by a link of its own to a clone.

The skill has no test in `make test`. `vr.sh` was run against stand-in command lines in a temporary `VIDEO_REVIEW_APPS_DIR`, which is what that variable is for; the loop is checked by a real session against the installed app.

### Build and test

- `Package.swift`: `swift-tools-version: 6.2`, `platforms: [.macOS(.v26)]`, Swift 6 language mode, no outside package. Tests use Swift Testing.
- `Makefile`, after Shipyard's:

| Target | Does |
|---|---|
| `make build` | `swift build -c release` for `VideoReview` and `video-review-cli` |
| `make test` | `swift test`; with the Command Line Tools alone it adds the flags that find the Testing framework, and shares one module cache, as Shipyard does |
| `make bundle` | `build/<APP_NAME>.app`: the executable in `Contents/MacOS/VideoReview`, the CLI as `Contents/Helpers/video-review`, the stamped `Info.plist`; signs the CLI, then the bundle, ad hoc |
| `make install` | quits this build's running app by its path, replaces `/Applications/<APP_NAME>.app`; doesn't start it |
| `make acceptance` | `scripts/acceptance.sh` with the installed app's CLI path; drives the installed app in a demo folder of its own |
| `make run`, `make clean` | as named |

`APP_NAME` contains spaces and parentheses, so every recipe quotes it and no target is named after a file that contains it.

- `make test` never drives the Mac. The pure modules are tested directly (lease tables with a clock value, the review's state machine, the payload, the ledger, the window cut, the source order, the version refusal, the content hash of a renamed copy). `VRCommandTests` runs `CLI.run` with a fake transport and launcher. `VRAppTests` covers the player's keys (`Shortcuts`), `FrameGeometry`, `RegionDraw` and the server's routing and leasing: it runs `ControlServer` on a real `AppModel` with no video and no window, at times the test sets, in memory and over the real socket in a temporary folder. `RegionCommentTests` alone opens the fixture video, in a model with no window and a muted player, and drives the pointer's path through `AppModel`'s region methods: the drawn comment and the `--region` comment must keep the same keyframe and the same crop, every decoded pixel equal. It compares pixels and not the files' bytes: each frame read carries a colour profile stamped with the second it was made in, so two PNG files of one frame can differ in that byte. It tests no view.
- The highest seam is `scripts/acceptance.sh`: the eight steps of the spec's scenario through the installed CLI in demo mode. See [The acceptance scenario](#the-acceptance-scenario).

#### The acceptance scenario

`scripts/acceptance.sh <path to Contents/Helpers/video-review>` (or `VIDEO_REVIEW_CLI`) runs the spec's eight steps against an installed app and prints one `PASS` or `FAIL` line per check, then `PASSED: 8 of 8 steps, 69 checks` (exit 0) or `FAILED: …` with the steps that failed (exit 1). `make acceptance` gives it this build's path, made from `Identity.variant`; the script itself knows nothing of the build, so the same file runs against any build that keeps the spec's CLI contract. It needs `bash`, `jq`, `sips` and `xxd`, which macOS ships, and exits 2 naming the one that is missing before it touches the app.

- **A run of its own.** Each run makes a new folder under `$TMPDIR` with the demo folder, the payload and the screenshots in it (`ACCEPTANCE_SCREENSHOTS` moves the screenshots), opens the video from `fixtures/sample/`, and quits the app at the end, passed or not. It never reads the person's data.
- **Two shells.** The operator and the listener are two holders, set through `VIDEO_REVIEW_CONTROL_KEY`. The operator's first leased command takes the lease and `app quit` hands it to the app that opens next, so the script never calls `control take`. After its first `wait` returns the batch, the listener keeps a second `wait` open in the background, as the skill does, so the app shows it present; the script ends that `wait` before the quit.
- **Ids come from the payload.** The spec fixes the payload's fields and not what `comment add` prints, so the two comments are found in the payload, by whether they have a region.
- **What is checked.** Step 5: the keyframes are PNG files at absolute paths, 1920 by 1080; the crop is a PNG of the region's size in the frame's pixels, a pixel either way; the transcript windows hold "Press command enter" (at 0:10) and "Pause any video" (at 0:04); `context` holds every line of `sample.context.md`. Step 6: `thread answer` is tried until the app takes it, since it is refused until the background `ask` has put its question; `ask` then exits 0 with the answer. The region comment goes through `working`, the other from `acknowledged` straight to `done`. Step 7: `state` is refused after the quit; after `app open` and `player open` on the same video, the comments with their statuses and threads equal the ones read before the quit, and the keyframes and the crop are still on disk.
- **What the spec leaves open** is in one block at the head of the script: the shape of `state --json` (`.app.support`, `.video.path`, and `.comments[]` with `id`, `time`, `text`, `region`, `state` and `thread[]` of `author`, `kind`, `text`), and the names inside a payload's `region` (`x`, `y`, `w`, `h`) and transcript line (`text`). Another build changes those filters and nothing else. Everything else is exit codes, the payload's fields and the item states.
- **Screenshots.** `review-light.png` and `review-dark.png` are taken at the end of step 6, paused on the region comment's frame: that comment is still the one in focus, as the last one added, so its rectangle is on the frame. `restart-light.png` and `restart-dark.png` are step 8, after the restart: the same review read back from disk, with no comment in focus, since focus isn't kept across runs and the contract has no command that selects a comment. The pull request's copies are in `assets/screenshots/v1-proto-1/`, beside `acceptance-output.txt`, the output of the run that made them.

The script drives the installed app, so it isn't part of `make test`. It was run on a clean `make install`.

---

## Stage 4: Implementation

The methods that carry the logic, then two traces and two refusals.

### Sending a batch

```text
AppModel.sendBatch():
    desk.open                                  else refuse "no video is open"
    if the draft has text: commitDraft(text)   Cmd+Enter in the composer sends what is being typed too
    review = desk.open                         read again: queueing the draft waited for its frame
    for comment in queue:                      the transcript as it exists now: what speech recognition has so far
        lines[comment.id] = transcriber.lines(video, TranscriptWindow.around(comment.time))   already cut to the window
    batch = desk.change(hash) { $0.sendBatch(transcripts: lines, now) }      queued → sent; refused "the queue is empty: …"
    listener.enqueue(batch, video)             ledger.enqueue; deliver if a wait is open
    return batch
```

### Delivering

```text
ListenerQueue.wait(holder, timeout):
    if the app is quitting: return .refused
    if another session's wait is open: return .refused
    requeued = ledger.attach(holder, now)      a new key: the old session's unfinished batches are pending again
    for delivery in requeued: desk.change(delivery.video) { $0.requeue(delivery.batch) }
    add a waiter; start its timeout if any
    deliverIfPossible()
    suspend until ended                        by a delivery, the timeout, a cancelled connection, or quitting

ListenerQueue.deliverIfPossible():
    while let waiter = oldest waiter, let delivery = ledger.next(except: inFlight):
        review   = desk.review(delivery.video)       finished or missing: ledger.finish, and on to the next
        text     = ContextSource.text(for: review)         the sidecar beside review.video.path, read now, and review.note, composed
        context  = ledger.contextToSend(text, video)       nil when the session has this text, or there is none
        payload  = BatchPayload.make(batch, review, context, keyframe: layout.keyframe, crop: layout.crop)
        inFlight.insert(batch)
        end waiter with .batch(Handed(batch, waiter's key, context), payload.encoded())

ControlServer.written(answer) with a delivery:     listener.delivered → out of flight; ledger.delivered(batch, to: key, context, now)
ControlServer.undelivered(answer) with a delivery: listener.undelivered → out of flight; still pending; deliverIfPossible()
```

### Answering

```text
ListenerQueue.admit(holder):                   the first step of every listener command
    the app is quitting, or another listener's wait is open: refuse
    requeued = ledger.attach(holder, now)      a new key: the old session's unfinished batches are pending again
    for delivery in requeued: desk.change(delivery.video) { $0.requeue(delivery.batch) };  deliverIfPossible()

ListenerQueue.acknowledge(id, text, holder):   admit; hash = desk.hash(naming: id) else "there is no batch"
    batch = desk.change(hash) { $0.acknowledge(id, text, now) }       its sent comments → acknowledged
    a message was posted: announce(Notice(batch))
ListenerQueue.setStatus(id, state, holder):    admit; state is working | done | failed, else refuse
    comment = desk.change(hash) { $0.setStatus(id, to: state) }       refused: illegalMove
    review.isFinished(comment.batch): ledger.finish(batch)
ListenerQueue.reply(id, text, holder):         admit; a batch's id → reply(toBatch:), else reply(toComment:); announce
ListenerQueue.ask(id, question, wait, holder):
    admit; comment = desk.change(hash) { $0.ask(id, question, now) }  the same text as the latest question posts nothing
    a question was posted: announce
    comment.lastAnswer is there: return .answer(text)                  asked again after the answer came
    end the asks that wait on another question of this comment
    wait == 0: return .timedOut
    add an asker; start its timeout if any; suspend until ended        by the answer, the timeout, a cancelled connection, or quitting

AppModel.answer(id, text):                     the answer box and `thread answer`
    comment = desk.change(hash) { $0.answer(id, text, now) }          refused: noOpenQuestion
    listener.answered(comment)                 every ask on that comment ends with .answer(text)
```

So a person's answer is in the thread whether or not an `ask` waits for it: an `ask` that ran out (exit 3) or lost its connection is asked again with the same text and returns the answer at once.

### Trace 1: one CLI command, `player seek 0:10`

The fixture is open and paused at 0. The holder `A` has no lease yet.

```text
$ video-review player seek 0:10
main                                                  Sources/VRCLI/main.swift
└─ CLI.run(arguments, environment)                    Sources/VRCommand/CLI.swift
   ├─ CommandTable: ["player","seek"] → parse         Sources/VRCommand/CommandTable.swift
   │  └─ TimeArgument("0:10") → 10.0                  Sources/VRCommand/TimeArgument.swift
   │     ⇒ ControlRequest.playerSeek(seconds: 10)
   ├─ Holder.find(variables, cwd, processes) ⇒ A      Sources/VRLease/Holder.swift
   ├─ ControlSocket.locate(support)                   Sources/VRWire/ControlSocket.swift
   │     demo.json is there and demo.sock exists ⇒ demo.sock
   └─ ControlClient.send(.playerSeek, json: false)    Sources/VRWire/ControlClient.swift
      ├─ ControlMessage.encoded()                     Sources/VRWire/ControlMessage.swift
      └─ UnixSocketTransport.exchange                 Sources/VRWire/ControlClient.swift, over UnixSocket.swift
            connect, write, shut down the write side, read to the end
════════════════════ demo.sock ════════════════════
SocketListener: accept, read the request              Sources/VRApp/Control/SocketListener.swift
└─ ControlServer.reply(to: data)                      Sources/VRApp/Control/ControlServer.swift
   ├─ ControlMessage.decode: version 1 = 1            Sources/VRWire/ControlMessage.swift
   ├─ isLeased ⇒ lease.use(by: A, at: now)            Sources/VRLease/ControlLease.swift
   │     state: lease free → Term(A, taken: now, ends: now + 60 s); transition .started(A)
   │     ⇒ LeaseButton appears in the toolbar         Sources/VRApp/Control/LeaseBanner.swift
   ├─ model.seek(to: 10)                              Sources/VRApp/AppModel.swift
   │  └─ player.seek(to: 10)                          Sources/VRApp/Player/PlayerEngine.swift
   │        AVPlayer.seek, zero tolerance; awaits the completion
   │     state: player.time 0 → 10; playing stays false
   └─ Answer(reply: .done("0:10.000\n"))
SocketListener: write the reply, close
════════════════════════════════════════════════════
CLI.run: reply.ok ⇒ prints "0:10.000", exit 0
```

Afterwards `video-review state --json | jq .player.time` prints `10`, and `.lease.holder` names `A`.

**A refusal.** A second holder `B` runs `video-review player play` 5 s later. The path is the same down to `lease.use(by: B, at: now)`: the term belongs to `A` and hasn't ended, so the answer is `.failure(.inUse(term))`. The server returns `refused("video-review is in use by Claude Code in /repo until 12:01:00 (55s left); `video-review control take --wait <seconds>` to queue")` before `AppModel` is reached. The player's state is unchanged. The CLI prints the line on standard error and exits 1.

### Trace 2: one batch, from Cmd+Enter to `wait`

The fixture is open in demo mode. The queue holds `c1` (at 10 s) and `c2` (at 4 s, with a region). A listener session `L` already runs `video-review wait` in another shell.

```text
(earlier) $ video-review wait
… CLI → socket → ControlServer.reply: not leased           Sources/VRApp/Control/ControlServer.swift
   └─ listener.wait(holder: L, timeout: nil)               Sources/VRApp/Mate/ListenerQueue.swift
      ├─ ledger.attach(L, now) ⇒ no session before: session = L; nothing to requeue
      │                                                    Sources/VRReview/ListenerLedger.swift
      ├─ waiters = [L]; presence: absent → listening ⇒ PresencePill turns green
      └─ no pending delivery ⇒ suspended; SocketListener writes a heartbeat every 2 s

The person presses Cmd+Enter
Menu command "Send Comments" (Cmd+Return)                  Sources/VRApp/VideoReviewApp.swift
└─ model.sendBatch()                                       Sources/VRApp/AppModel.swift
   ├─ transcriber.lines(video, 0...25) and (0...19)        Sources/VRTranscript/OrderedTranscriber.swift
   │     VoiceoverSource has the three scenes              Sources/VRTranscript/Sources/VoiceoverSource.swift
   │     TranscriptWindow.cut keeps the scenes that overlap Sources/VRTranscript/TranscriptWindow.swift
   ├─ desk.change { $0.sendBatch(transcripts:, now) }      Sources/VRApp/Comments/ReviewDesk.swift
   │  ├─ Review.sendBatch                                  Sources/VRReview/Review.swift
   │  │     state: c1, c2 queued → sent; batch b1 = [c2, c1] with their transcript lines
   │  └─ store.save(review) ⇒ review.json                  Sources/VRStore/ReviewStore.swift
   │     ⇒ both markers turn to the sent colour; the sidebar moves them under "Batch 1"
   └─ listener.enqueue(b1, video)                          Sources/VRApp/Mate/ListenerQueue.swift
      ├─ ledger.enqueue(b1) ⇒ deliveries = [b1 pending]; listener.json saved
      └─ deliverIfPossible()
         ├─ ContextSource.read ⇒ sample.context.md's text  Sources/VRApp/Mate/ContextSource.swift
         ├─ ContextText.compose(sidecar, note: "")         Sources/VRReview/ContextText.swift
         ├─ ledger.contextToSend(text, video) ⇒ text       L got nothing for this video yet
         ├─ BatchPayload.make(b1, review, context, paths)  Sources/VRReview/BatchPayload.swift
         └─ resume L's waiter with .batch(b1, json)

ControlServer.reply returns Answer(.done(json), delivery: b1)
SocketListener: write the reply, close ⇒ written           Sources/VRApp/Control/SocketListener.swift
└─ listener.delivered(b1, context: text)
   └─ ledger.delivered ⇒ b1 takenBy L; L.contextSent[video] = text; listener.json saved
      state: waiters = []; presence: listening → working (L has a taken, unfinished batch)

$ video-review wait        prints the payload, exit 0
{"batch":{"id":"7f3a9c21-b1","sentAt":"…"},
 "video":{"path":"/…/sample.mp4","contentHash":"7f3a…","duration":21.233,"title":"sample"},
 "context":"# Context: sample…",
 "comments":[{"id":"7f3a9c21-c2","time":4,…,"region":{"x":0.1,"y":0.2,"w":0.3,"h":0.2},"cropPath":"/…/crops/7f3a9c21-c2.png",…},
             {"id":"7f3a9c21-c1","time":10,…,"region":null,"cropPath":null,"transcript":[{"start":0,…},{"start":6.067,…},{"start":14.333,…}]}]}
```

The trace's variants, each one branch of the same code:

- **No listener at the send.** `deliverIfPossible` finds no waiter. `b1` stays pending in `listener.json`, through a quit too. The next `wait` attaches, and `deliverIfPossible` runs from `wait`.
- **The second batch for `L`.** `contextToSend` finds the same text in `L.contextSent`, so the payload has `"context": null`. After `context set` or an edit of the sidecar, the text differs and goes out again.
- **A new listener session `M`** calls `wait` while `b1` is taken by `L` and unfinished. `attach` replaces the session, returns `[b1]`; the desk requeues it (its unfinished comments go back to `sent`); `deliverIfPossible` hands `b1` to `M`, with the context, since `M` remembers nothing.
- **The listener dies mid-wait.** The next heartbeat can't be written; the task is cancelled; the waiter is removed; presence goes to `absent`. Nothing was taken. A batch sent before that heartbeat is handed to the dead wait, its reply can't be written, and `undelivered` leaves it pending.
- **The wait's `--timeout` runs out.** The waiter is removed and answered with nothing; the CLI exits 3. A batch sent a moment later finds no waiter and stays pending.

**The listener's side.** `L` is a Claude Code session with the skill, and its `wait` above was `vr.sh listen`, run as a background command. What follows the payload:

```text
vr.sh listen                                               .agents/skills/video-review-mate/scripts/vr.sh
├─ video-review wait        exit 0, the payload            kept in $TMPDIR/video-review-mate/7f3a9c21-b1.json
├─ plutil reads batch.id ⇒ 7f3a9c21-b1
├─ video-review ack 7f3a9c21-b1                            ListenerQueue.acknowledge: c2, c1 sent → acknowledged
│     ⇒ both markers show the tick; the batch's head says "Acknowledged"
└─ prints the payload, exit 0 ⇒ the session wakes

L, by SKILL.md
├─ vr.sh listen again, in the background                   waiters = [L]; presence stays working (b1 is taken)
├─ reads the context, then each keyframe and crop
├─ c2: vr.sh status 7f3a9c21-c2 working                    acknowledged → working ⇒ the marker turns orange
│      the work, one commit
│      vr.sh reply 7f3a9c21-c2 '… (4f1c2ab)'               the thread gets the message ⇒ a notice on the frame
│      vr.sh status 7f3a9c21-c2 done                       working → done ⇒ green
├─ c1: vr.sh ask 7f3a9c21-c1 '…', in the background        the question waits; L goes on, or waits for the answer
│      the person answers in the thread ⇒ the ask exits 0 with the answer
│      status working, the work, reply, status done        review.isFinished(b1) ⇒ ledger.finish(b1); presence → listening
└─ vr.sh reply 7f3a9c21-b1 '…'                             the message for the whole batch
```

**A refusal.** After the send, `video-review comment edit 7f3a9c21-c1 "new text"` reaches `Review.editComment`, which finds `c1` in the state `sent` and throws `notQueued(c1, .sent)`. `desk.change` saves nothing. The reply is `refused("7f3a9c21-c1 is sent; only a queued comment can be edited or deleted")`, exit 1.

### What the traces showed

- The lease is asked before `AppModel` is reached, so a refused command can't change anything.
- A batch becomes `taken` only after its reply was written, so no failure between the send and the listener loses it.
- The transcript lines are captured at the send and kept on the batch, so a redelivery after a restart needs neither the video open nor the transcriber running. The context is read at delivery, since it depends on who receives it.
- An id carries its video's prefix, so listener commands work after the person opened another video.

### Adding a command

A new action is four small edits, each in the file that owns that step, and no change to the framing:

1. `AppModel` (or `ListenerQueue`): the method.
2. `ControlRequest` and `ControlMessage`: the case, its wire name and fields, and `isLeased`.
3. `CommandTable`: the row that parses its arguments.
4. `ControlServer.reply`: the line that routes it and words its output.

Then the view that calls the same method.

---

## UX choices of this prototype

The spec fixes the CLI, the payload and the states. Everything below is this prototype's own choice.

| # | Choice | Reason |
|---|---|---|
| 1 | One window, one video. Opening another video replaces the current one. | The task is reviewing one video; one window keeps `state` and `screenshot` unambiguous. |
| 2 | The frame fills the window above a fixed transport bar. The controls never float over the video. | QuickTime's floating controls would cover the frame the person points at, and would hide the markers when they fade. |
| 3 | The timeline is the app's own, with a pin per comment just above the track: a mark (a circle for a comment at a time, a rounded square for one with a region) and a thin stem in its colour down to its moment on the track. Small, quiet time labels sit under the track, at a round step that leaves each its room. The mark on a comment's row has the same shape, and the row's keyframe outlines the region. | AVKit's scrubber can't carry markers. The shape tells the two kinds apart before a click. Above the track, a marker is never hidden under the playhead, and a click on it can't be taken for a scrub. |
| 4 | A marker's colour and symbol show its state: hollow grey queued, plain sky sent, sky with a tick acknowledged, apricot with three dots that move (unless Reduce Motion is on) working, sage with a tick done, coral with a cross failed, and a honey question mark while a question waits, whatever the state. The colours are pastel (`Theme`), each with a light and a dark variant, and the symbol is a dark ink, since white is faint on them. The sidebar rows use the same style, with the state in a grey word beside the mark. | Story 16: one look at the timeline tells which comments are done. One style table serves markers and rows, so they can't disagree. The maintainer asked for pastel colours, not flashy ones, and no pink: the question was system purple, which shows as magenta. |
| 5 | Playback keys follow QuickTime and editors: Space plays and pauses, Left and Right move 5 s, `,` and `.` pause and step one frame, J and L move 10 s back and forward, K plays and pauses, a click on the frame plays or pauses. | Story 2: nothing to learn. Frame steps let the person land on the exact frame before commenting. J K L are the web players' keys, not an editor's shuttle: a review needs jumps, not reverse playback. |
| 6 | Return or C opens the comment box and pauses; so does the comment button in the transport bar. The box sits over the foot of the frame, names the time it comments on, and has the focus at once. | Story 3: one key from watching to typing. The time in the box tells the person which moment the comment keeps. |
| 7 | Dragging on the frame draws a region, pauses, and opens the comment box next to the rectangle. The pointer is a crosshair over the frame. While drawing, the rest of the frame is dimmed and the rectangle's size in the frame's pixels shows under it. A drag under 8 points counts as a click. A drag may start on the bars beside the frame or run over them: only what is on the frame is kept. | Stories 6 and 7: the same gesture as Cmd+Shift+4, with no mode to enter first. The video pauses the moment the rectangle begins, so the person draws on a still frame. |
| 8 | In the comment box, Return queues the comment, Shift+Return makes a new line, Escape cancels the box and its region. Return with nothing typed does nothing. Escape while the rectangle is still being drawn gives up the rectangle alone, and a video that was playing plays on. | The common act gets the plain key. Escape cancelling the region is the ticket's rule, and Cmd+Shift+4's. |
| 8a | The comment box sits to the right of the region, else to its left, below it or above it, and is always whole inside the frame's view. Drawing another rectangle while the box is open moves that comment's region and keeps what was typed. | Story 7: the person writes where they point, and can correct the rectangle without starting over. |
| 8b | A comment that was just added, from the box or the command line, is the selected one. | Its card and marker show where it went, and its region stays on the frame while the video is paused there. It is also how a screenshot shows a region without a click. |
| 9 | After a comment is queued, playback resumes if the video was playing when the box opened. | Pause, comment, carry on: the fastest loop for a run of small notes. |
| 10 | The comment box is a standard text field. | Story 8: Wispr Flow dictates into any standard field, so dictation needs no code. |
| 11 | Player keys act only while no text field has the focus, and no plain key is a menu shortcut. | The ticket's rule that typing must never trigger a player shortcut, held by one question (is the first responder a text view?), not by a list of exceptions. |
| 12 | Cmd+Return sends the queue from anywhere. Typed text in an open comment box is queued first, then sent. | Story 11: one keystroke, and nothing the person typed is left behind. |
| 13 | The sidebar is a plain column on the right, on the window's background like the frame's column: the queue on top with its count, sent comments below, grouped by batch with the newest batch first, in time order inside a batch. A batch's head has its number, the time it was sent and where it stands. A sent comment's row has its mark in the sent colour and the word `Sent`. Rows have no box; groups are parted by space and dividers. The send bar (presence, queued count, Send) is at its foot, as tall as the transport bar. It can be hidden. | The queue is what the person acts on next; the frame keeps the larger share. The newest batch is the one the person just sent. The maintainer found the inspector's glass column detached from the frame, and a card around everything too heavy; proto-3's plain columns parted by background were the direction he liked. |
| 14 | A queued comment is edited in place in its row (double-click or the pencil; Return keeps the new text, Escape the old) and deleted with the trash button, or with Delete while it is the comment in focus. Each card shows its keyframe, small. | Story 10, without a separate editor. The keyframe shows which frame the agent will get. |
| 15 | Clicking a marker or a row seeks to the comment's time, pauses, selects it in both places and draws its region on the frame. The region shows only while the video is paused at that time. | Story 13: the marker, the card and the region are one selection. |
| 16 | A thread shows under its comment's row, as a conversation in soft bubbles: the agent's messages on the left under its name, the person's answers on the right tinted with the accent colour, a question tinted honey. The question that waits says `Waiting for your answer`, and the answer box sits right under it, only while it waits. | Stories 18 and 20: the answer goes where the question is. A person's message with no question has no command to deliver it, so the box isn't offered. |
| 17 | Messages for a whole batch show as bubbles under a small `For the whole batch` label, at the head of that batch's group. The batch's head says where it stands in words: `Acknowledged`, `Acknowledged · 1 of 2 finished`, `Finished · 1 done, 1 failed`. | Story 21: the overall result sits above the comments it is about. |
| 18 | An agent message shows as a notice at the bottom right of the frame for 5 s, with the comment's time, or the batch's number for a message about the whole batch. A question's notice has a honey icon and says `Agent asks`. A click selects the comment, which brings its row into sight. A later message replaces the notice. A status change shows no notice. The notice is dark in both appearances. | Story 19: seen while watching, away from the centre of the frame, and gone by itself. A status is on the marker already, and a notice per status would triple the interruptions of a batch. Over a frame and its black surround, a light notice turned grey and hid its title. |
| 18a | An `ack` without text shows no notice: the markers turn to acknowledged and the batch's head says `Acknowledged`. With text it is a message for the batch, and shows as one. | Story 17 without an empty notice. |
| 18b | A thread message's clock time is in its tooltip, not beside its author. | Beside the comments' video times (`0:10`), a clock time (`00:25`) read as one of them. |
| 19 | Presence is a dot and a word at the left of the sidebar's send bar: sage Listening, apricot Working, grey No listener. Hovering names the listener and its folder. | Story 14: the answer to "will my batch reach someone" sits next to Send, where the person asks it. It hides with the sidebar, which keeps the toolbar quiet. |
| 20 | Sending with no listener works. The batch's head says "Waiting for a listener" in orange, then "Delivered to the listener" once a `wait` took it. | Story 15: the person isn't blocked, and knows why nothing answers yet. |
| 20a | The Send button and the menu item are off while nothing is queued and nothing is typed in the comment box. | Cmd+Return with nothing to send does nothing, in place of an alert. |
| 21 | While an agent holds the lease, an apricot icon sits at the toolbar's trailing end. Its popover names the agent, its folder, the seconds left and how many agents wait, with a Stop button. Stop ends the lease and refuses that agent for 5 minutes; an agent in line gets the lease at once. The person's own clicks and keys always work. A screenshot shows the icon, since it is in the window, but not the popover. | Stories 29 and 30, which ask for a banner: the maintainer chose an icon instead, since a banner took too much room just to say that an agent controls the app. The person never needs the lease. |
| 22 | The context note is a popover from a toolbar button. It also names the sidecar file that was found, or says that there is none. The button's icon is filled while there is a context to send. The note is kept as it is typed. | Story 26: rarely used, so out of the way, and it shows what the agent will get. |
| 23 | The app follows the Mac's appearance with system colours and materials. The frame's surround is black in both. | Story 31. Black around a video is what players do, and it keeps the frame's colours honest. |
| 24 | The app reopens the last video, paused where it was, when it starts. | Stories 22 and 23, and the acceptance scenario's restart step: the history is there without a click. |
| 25 | With no video open, the window shows "Open a video", a button and a drop target. Cmd+O opens too. | Story 1, by the three usual ways. |
| 26 | `comment add --at` from the CLI doesn't move the playhead. | An agent adding several comments shouldn't yank the person's view; the marker shows where it went. |

---

## Stage 5: Extensibility

| Change | What you touch |
|---|---|
| Become the real product | `Identity.variant = ""`. The bundle, the bundle id and the support folder follow. |
| A new CLI command | The four edits of [Adding a command](#adding-a-command). |
| The transcription research lands | One new `TranscriptSource` in `Sources/VRTranscript/Sources/`, and its place in the list of `OrderedTranscriber.init(cache:)`. One that only recognises speech better is a new `SpeechSource.Recognize` function. Or a whole new `Transcriber`, given to `AppModel`. Nothing else knows. |
| A new comment state | `CommentState`, the move table in `Comment.swift`, one row in `StatusStyle`. |
| A new field in the payload | `BatchPayload` and its `make`. The CLI prints whatever the app built. |
| A breaking wire change | `ControlRequest.version` goes up; an old CLI is refused in words. |
| Another agent's session variable | One row in `Holder.sessionVariables`. |
| A new store file or a moved folder | `SupportLayout` only; a format change bumps that file's `version`. |
| Delivering a person's free message to the listener | A new payload kind from `ListenerQueue.deliverIfPossible`; the thread and its storage already hold person messages. |

Refused for now, since no requirement asks for them:

- **More than one listener.** The ledger holds one session. Several would need deliveries addressed to a session, and a rule for who gets a new batch.
- **More than one window.** `AppModel` is one per app; `state` and `screenshot` would need a window argument in the contract.
- **Shapes other than rectangles.** `Region` is four numbers on the wire, in the payload and on disk.
- **Undo.** Every change goes through `ReviewDesk.change`, so it has one place to land when it is wanted.
- **An interface in front of `ReviewStore` or `FrameGrabber`.** Each has one implementation; tests use a temporary folder and the fixture.

---

## Which ticket builds what

Later tickets fill this structure in; they don't re-decide it. A ticket that has to move away from it updates this document in the same change.

| Ticket | Creates or fills |
|---|---|
| #3 Control: play and drive | `Package.swift`, `Makefile`, `Packaging/`; `VRWire` whole; `VRLease/Holder.swift`, `ProcessTable.swift` and a `ControlLease` that grants every request; `VRCommand` (without `RegionArgument`) and `VRCLI` with the `app`, `player`, `state` and `screenshot` rows; `VRApp`: `VideoReviewApp`, `AppModel` (player actions), `Player/` without markers and without `Shortcuts`, `Control/` without the banner; `VRWireTests`, `VRCommandTests` |
| #4 Control: lease | `VRLease/ControlLease.swift` in full; `control take` and `release`; the take's wait, the settle timer, `stopLease` and `undelivered` in `ControlServer`; `ControlRequest.silence` (taken out again with the heartbeat); `LeaseBanner` with `LeaseIndicator`; `VRLeaseTests`, and `VRAppTests` with `ControlServerTests` |
| #5 Comment: timestamped | `VRReview`: `Identifiers`, `Comment`, `ThreadMessage`, `Review` (add, edit, delete), `ReviewError`; `VRStore`: `SupportLayout`, `ContentHash`; `Comments/ReviewDesk` (in memory), `FrameGrabber` (keyframe), `Sidebar` (the queue), `CommentCard`, `StatusStyle`; `Overlay/Composer`; markers in `Timeline`; `Shortcuts`; the `comment` rows; the comments, the queue and the draft in `StateSnapshot`; `VRReviewTests`, `VRStoreTests` (`ContentHashTests`), `VRAppTests` (`ShortcutsTests`) |
| #6 Comment: region | `VRReview/Region.swift`, `regionOutsideFrame`, `region` on `Comment` and `addComment`; `SupportLayout.crop`; `VRCommand/RegionArgument.swift` and `--region`; `Overlay/FrameGeometry`, `RegionDraw`, `RegionOverlay`, the composer placed next to the region; the region methods of `AppModel` and Escape in `ShortcutMonitor`; the crop in `FrameGrabber` and `ReviewDesk`; `region` and `cropPath` in `StateSnapshot`; the square marker; `RegionTests`, `RegionArgumentTests`, `FrameGeometryTests`, `RegionDrawTests`, `RegionCommentTests` |
| #7 Mate: send and wait | `Batch`, `Review.sendBatch`, `batch`, `isFinished`, `requeue`, `BatchPayload`, `ListenerLedger` (without `contextToSend`), `Presence`; `Mate/ListenerQueue` (the `wait` side, in memory), `PresencePill`; the heartbeat, `written` and a batch's `undelivered` in `SocketListener` and `ControlServer`; `batch send`, `wait`, exit 3; Cmd+Return, the Send button, the draft's text on `ReviewDesk`, the sent comments in `Sidebar`; `batches` and `listener` in `StateSnapshot`; `BatchPayloadTests`, `ListenerLedgerTests`, `ListenerWaitTests` |
| #8 Transcript | `VRTranscript` whole; `VRStore/TranscriptCache` and `SupportLayout.transcriptFile`; the transcriber prepared in `AppModel.open` and the lines captured in `AppModel.sendBatch`; `transcript` in `StateSnapshot`, with `problem`; `VRTranscriptTests`, `TranscriptCacheTests`, `TranscriptBatchTests` |
| #9 Mate: context | `ContextText`; `Review.note` and `setNote` (in memory until #11); `Mate/ContextSource`; `ledger.contextToSend`, called in `ListenerQueue.deliverIfPossible`; `AppModel.setNote` and `sidecar`; `Comments/ContextNote`; `context set`; `context` in `StateSnapshot`; `ContextTextTests`, `ContextTests`, the context table in `ListenerLedgerTests` |
| #10 Mate: answers | `acknowledge`, `setStatus`, `reply`, `ask`, `answer` in `Review`, the question properties of `Comment`, the errors `emptyMessage`, `notSent`, `noOpenQuestion`, `illegalMove`; `ReviewDesk.hash(naming:)`; `admit`, `acknowledge`, `setStatus`, `reply`, `ask`, `answered` and `ledger.finish` in `ListenerQueue`; `AppModel.answer`, the notice; `ThreadView`, `BatchCard` (with `BatchHeader`, moved out of `Sidebar`), `NoticeToast`, the question's style in `StatusStyle`; `notice` in `StateSnapshot`; the rows and routes of `ack`, `status`, `reply`, `ask`, `thread answer`, exit 3 for `ask`; `ReviewAnswerTests`, `ListenerAnswerTests` |
| #11 Comment: persist | `VRStore/ReviewStore`, `StoredFile`, `AppState`, the rest of `SupportLayout`; `TranscriptCache` on `StoredFile`; `Batch`'s stored form; `ListenerLedger.reconcile`; `ReviewDesk` reading at launch, saving in `change` and `add`, `changeTyped` and `settle`; `ListenerQueue.record` and its launch; `AppModel.reopenLastVideo`, `leaving`, `typeNote`, `endNote`, `ActionError.store`; the server started after the reopen; `ReviewStoreTests`, `RestartTests`, the reconcile cases of `ListenerLedgerTests` |
| #12 Mate: the skill | `.agents/skills/video-review-mate/SKILL.md` and `scripts/vr.sh`; the link `.claude/skills/video-review-mate`; the skill's rows in `AGENTS.md` |
| #13 Proto: acceptance | `scripts/acceptance.sh`, `make acceptance`, `assets/screenshots/v1-proto-1/` (four screenshots and the run's output) |

#4 and #5 can run side by side (lease files against review files; both add rows to `CommandTable` and routes to `ControlServer`, in separate lines). #8, #9 and #10 can run side by side after #7 (Transcript against context against threads; they meet only in `AppModel.sendBatch`, `ListenerQueue.deliverIfPossible` and the command table).
