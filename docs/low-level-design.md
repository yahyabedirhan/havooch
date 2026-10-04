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
12. **The person wins**: a banner shows while an agent holds the lease, and Stop ends it. (29, 30)
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
| **ListenerQueue** | the open `wait` and `ask` connections | a batch is taken only once its reply was written; one listener session at a time |
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
- `ListenerQueue` **has** the `ListenerLedger` and **uses** `ReviewDesk` (to read a batch and to change comment states) and `ReviewStore` (to save the ledger).
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

SwiftPM refuses a target with no source file, so `Package.swift` lists a target from the ticket that writes its first file: the four agent-side targets and `VRApp` now, `VRReview` and `VRStore` with the first comment, `VRTranscript` with the transcript. Each test target joins with its first test.

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
- The CLI keeps the name `video-review`. Run it from this build's bundle, `/Applications/Video Review (proto-1).app/Contents/Helpers/video-review`, never from `PATH`: another prototype's CLI would speak to another prototype's socket.
- The app's executable is `VideoReview` in every prototype, so `make install` never uses `pkill -x`. It quits this build only, by its full path: `pkill -f` with `/Applications/$(APP_NAME).app/Contents/MacOS/`. `pkill -f` reads a regular expression, so the `Makefile` escapes the name's parentheses and dots first (`RUNNING`); unescaped, the pattern would match no process.

### Folder tree

```text
Package.swift                         the targets and their links (eight once every module has code); swift-tools-version 6.2, macOS 26
Makefile                              build, test, bundle, install, run, clean, later acceptance; reads Identity.variant
Packaging/
  Info.plist                          the bundle's template: name, bundle id, version, video document types, usage strings

Sources/
  VRLease/                            ── agent side ──
    Holder.swift                      who sends a request; Holder.find from the session id, the ancestor process or the key variable
    ProcessTable.swift                the process table Holder.find walks (sysctl), and its protocol for tests
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
    RegionArgument.swift              "x,y,w,h" to four numbers
    AppCommand.swift                  app status, app open [--demo], app quit: launch, relaunch, hand the lease over
    AppLauncher.swift                 AppLaunching; WorkspaceLauncher starts the bundle the CLI sits in
    CommandResult.swift               standard output, standard error, exit code
  VRCLI/
    main.swift                        calls CLI.run with the real environment and exits with its code

  VRReview/                           ── app side, pure ──
    Identifiers.swift                 CommentID, BatchID ("<hash8>-c3", "<hash8>-b1")
    Region.swift                      normalized rectangle; validation; the pixel rectangle for a frame size
    Comment.swift                     Comment, CommentState and its allowed moves
    ThreadMessage.swift               author (person, agent), kind (message, question, answer), text, time
    Batch.swift                       id, sentAt, its comments' ids, its thread, the transcript lines captured at the send
    Review.swift                      one video's review and every rule that changes it
    ReviewError.swift                 why a change is refused, in words
    BatchPayload.swift                the JSON object `wait` prints; made from a batch, a review, paths and a context
    ListenerLedger.swift              the listener session, the deliveries, requeue, context once per session
    Presence.swift                    listening, working, absent; derived
    ContextText.swift                 the sidecar names to look for; sidecar text and note joined
  VRTranscript/
    TimedLine.swift                   start, end, text
    Transcriber.swift                 the interface: prepare(video), lines(for:in:)
    OrderedTranscriber.swift          the first source that has lines for the video, in the spec's order
    TranscriptWindow.swift            the cut: lines that overlap time ± 15 s
    Sources/
      TranscriptSource.swift          what a source is: a name, and the lines it has for a video so far
      VoiceoverSource.swift           voiceover.json; scene times from scene lengths and the frame rate
      SubtitleSource.swift            .srt and .vtt with the video's base name
      SpeechSource.swift              SpeechAnalyzer in the background; partial lines; the cache it is given
  VRStore/
    SupportLayout.swift               every path under a support folder, in one place
    ContentHash.swift                 the hash that names a video
    ReviewStore.swift                 load and save review.json, listener.json, app.json; atomic; versioned
    TranscriptCache.swift             transcript.json; implements SpeechSource's cache

  VRApp/                              ── the app ──
    VideoReviewApp.swift              @main: the one Window, the menus, the composition root
    AppModel.swift                    the orchestrator; one method per action
    Player/
      PlayerEngine.swift              AVPlayer: open, play, pause, exact seek, time, rate, duration
      PlayerSurface.swift             the AVPlayerLayer in a view, no AVKit controls
      TransportBar.swift              play button, time, speed, the timeline
      Timeline.swift                  the scrubber and the comment markers
      TimeText.swift                  a time as text: 0:10 in the window, 0:10.000 in a command's output
      Shortcuts.swift                 the player's keys, live only while no text field has the focus
      EmptyState.swift                "Open a video": the button and the drop target
    Overlay/
      FrameGeometry.swift             where the frame sits in the view; view points to and from normalized
      RegionOverlay.swift             drag to draw; the selected comment's region
      Composer.swift                  the comment box, at the playhead or next to the region
    Comments/
      ReviewDesk.swift                the reviews in memory; each change saved and its images written
      FrameGrabber.swift              the keyframe and the crop as PNG files
      Sidebar.swift                   the queue, the sent comments, the Send button
      CommentCard.swift               one comment: time, text, status, thread, edit, delete
      ThreadView.swift                the messages and the answer box
      BatchCard.swift                 the messages for a whole batch
      StatusStyle.swift               one colour and symbol per comment state, for markers and cards
      ContextNote.swift               the in-app note and the sidecar it found
    Mate/
      ListenerQueue.swift             open waits and asks; delivery; presence
      ContextSource.swift             reads the context sidecar of a video
      PresencePill.swift              listening, working, absent in the toolbar
      NoticeToast.swift               the brief notice for an agent message
    Control/
      ControlServer.swift             decode, lease, route to AppModel, reply
      SocketListener.swift            the listening socket off the main actor; heartbeat on a waiting connection
      StateSnapshot.swift             what `state --json` and `app status` print
      Screenshotter.swift             the app's own window as a PNG, in an appearance
      LeaseBanner.swift               who controls the app, time left, Stop; LeaseIndicator, the lease as the window shows it

Tests/
  VRLeaseTests/                       ControlLeaseTests (time-driven tables), HolderTests
  VRWireTests/                        ControlMessageTests (round trip, version refusal), DemoPointerTests
  VRCommandTests/                     CommandTableTests, TimeArgumentTests, AppCommandTests, Doubles (fake transport, launcher)
  VRReviewTests/                      ReviewTests (state machine), BatchPayloadTests, ListenerLedgerTests, RegionTests
  VRTranscriptTests/                  WindowTests, SourceOrderTests, VoiceoverSourceTests, SubtitleSourceTests
  VRStoreTests/                       ContentHashTests, ReviewStoreTests (round trip, renamed copy, demo apart)
  VRAppTests/                         FrameGeometryTests, ControlServerTests (the server's leasing at a clock of the test's, and over the real socket)

scripts/
  acceptance.sh                       the v1 acceptance scenario through the CLI, against the installed app in demo mode
.agents/skills/video-review-mate/
  SKILL.md                            the listener skill
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
    public static func find(variables: [String: String], workingDirectory: URL, processes: any ProcessTable) -> Holder
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
    public mutating func stop(at: Date) -> [Transition]                                // the banner's Stop
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
    public static let longestWait = 3600        // the longest `take --wait`, in seconds
    public var silence: Double                  // how long the app may leave it unanswered on purpose: a take's wait
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

`decode` checks the version before anything else: it reads `version` alone first, so a request of another version is told so even when its other fields have another shape. `decode` also refuses a relative `path`, an unknown `appearance`, a negative `seconds` and a `waitSeconds` out of range. Another version is refused with: `the video-review command speaks control version 2 and the app version 1: run the command from this app's bundle (Contents/Helpers/video-review) so both come from one build`.

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

The CLI maps a reply to an exit code: `ok` gives 0, `ok` false gives 1. One exception: a `wait` or an `ask` that ran out answers `ok` true with an empty `output`, and the CLI, which knows it sent a waiting request, exits 3 with `no batch within 30 s` or `no answer within 30 s` on standard error. The reply's shape stays the spec's four fields.

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
| `batch send` | the batch's id | `{batchId, commentIds}` |
| `thread answer` | `answered <id>` | the comment |
| `context set` | `context note set` | `{"note":"…"}` |
| `screenshot` | the PNG's path | `{path, captured}`; a note on standard error when the window was rendered, not captured |
| `wait` | the batch payload, always JSON | the same |
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

The timeout is an idle timeout: the longest silence the client accepts, not the longest exchange. See the long-poll below.

### How a long-poll holds one connection

`wait`, `ask` and `control take --wait` each stay one request on one connection, as ADR 0001 says. The app simply doesn't answer yet.

1. The client writes the request, shuts down its write side and reads until the app closes the connection.
2. `SocketListener` reads the request and awaits `ControlServer.reply(to:)` in a task. The handler suspends on a continuation kept by `ListenerQueue` (for `wait` and `ask`) or by `ControlServer` (for a `take` in line). The main actor is free meanwhile.
3. While the task hasn't answered, `SocketListener` writes one space to the connection every 2 s. This **heartbeat** does two jobs:
   - The client's idle timeout (15 s) never fires on a healthy wait, however long. A JSON reader skips leading spaces, so the reply still reads as one JSON object.
   - A heartbeat that can't be written (the listener was killed, the shell closed) cancels the task. The cancellation handler removes the waiter and resumes it, so presence drops within about 2 s and no batch is handed to a dead connection.
4. When the handler resumes (a batch arrived, an answer arrived, the timeout ran out, the app is quitting), the reply is written and the connection closed.
5. If the reply itself can't be written, the server undoes the grant: a batch stays `pending` (it is marked `taken` only after a successful write), and a lease a `take` just got is released, as in Shipyard.

The take's part is built: a `take` in line suspends on a continuation in `ControlServer`, the app answers it when the lease changes hands or its wait runs out, and a grant whose reply can't be written is released (`undelivered`), which a test proves over the real socket. The heartbeat comes with `wait`. Until then the client accepts a longer silence for a waiting take: `ControlClient.send` adds `ControlRequest.silence` (the take's `waitSeconds`) to its idle timeout, so `control take --wait 120` waits up to 135 s for its answer. A take whose client has gone keeps its place until it is granted the lease, and gives it back then.

A `wait` without `--timeout` waits without limit. The app answers every open wait with a refusal (`the app is quitting`) when it quits, so the listener's loop sees exit 1, not a hang.

NOTE: #7 must check that a write to a Unix stream socket whose peer has closed fails at once on macOS 26 (`EPIPE`, with `SO_NOSIGPIPE` set). If it doesn't, the fallback is a `DispatchSource` read source on the connection that fires on `EV_EOF` after the peer's half-close; the rest of the design is unchanged.

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
- `--json` is accepted anywhere on the line and travels as the message's `json`.
- A relative `player open` path and `--demo` folder are made absolute against the working folder; `screenshot` refuses a relative path, since the spec says `<abs.png>`.
- Every command but the `app` ones is: parse, find the holder, locate the socket, send, print, exit.
- `app status` prints `not running` and exits 0 when nothing answers. `app quit` sends `app.quit`, then waits up to 10 s until nothing answers on the socket.

`app open` is the one command with logic of its own, since the app may not be running:

```text
app open [--demo <folder>]
  wanted = the demo folder made absolute, or nil for the person's data
  ask `app.status` on demo.sock, then on control.sock    both, so a stale pointer or socket hides no running app
  if one answers:                                        demo.sock's data is the pointer's folder, control.sock's the person's
      same data as wanted  → send `app.open` (leased; renews the lease), print its status
      other data           → send `app.quit` (leased); keep the lease from its reply; wait for the socket to go
  make the demo folder and record the demo pointer (wanted != nil), or remove the pointer (wanted == nil)
  launcher.launch(bundle: the .app this CLI sits in, environment:
      VIDEO_REVIEW_SUPPORT_DIR = wanted, VIDEO_REVIEW_CONTROL_LEASE = the lease handed over)
  send `app.open` every quarter second, up to 10 s, until the app answers; print its status
  a demo that doesn't come to run leaves no pointer behind
```

`WorkspaceLauncher` starts the bundle that contains the CLI (`…/Contents/Helpers/video-review` gives `…`), through `NSWorkspace`, without bringing it to the front. So a build's CLI can only ever start its own build. Outside a bundle (`swift run`), it falls back to `Identity.bundleID`. This is the only AppKit use on the agent side.

### Review: `VRReview`

```swift
public struct CommentID: Hashable, Codable, Sendable { public let rawValue: String }   // "7f3a9c21-c3"
public struct BatchID: Hashable, Codable, Sendable { public let rawValue: String }     // "7f3a9c21-b1"
// The first eight hex digits of the video's content hash, then a counter per video.
// An id names its video, so `status <comment-id>` works whatever video is open. A number is never used twice.

public struct Region: Codable, Equatable, Sendable {
    public var x, y, w, h: Double                       // 0..1, origin top left
    public init?(x: Double, y: Double, w: Double, h: Double)   // nil unless inside the frame with w, h > 0
    public func pixels(in size: (width: Int, height: Int)) -> (x: Int, y: Int, width: Int, height: Int)
}

public enum CommentState: String, Codable, Sendable { case draft, queued, sent, acknowledged, working, done, failed }

public struct ThreadMessage: Codable, Equatable, Sendable {
    public enum Author: String, Codable { case person, agent }
    public enum Kind: String, Codable { case message, question, answer }
    public var author: Author; public var kind: Kind; public var text: String; public var at: Date
}

public struct Comment: Codable, Equatable, Identifiable, Sendable {
    public var id: CommentID; public var time: Double; public var text: String
    public var region: Region?; public var state: CommentState
    public var batch: BatchID?; public var thread: [ThreadMessage]; public var createdAt: Date
    public var openQuestion: ThreadMessage? { get }     // the last question with no answer after it
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

    // the person and the operator
    public mutating func addComment(text: String, time: Double, region: Region?, now: Date) throws(ReviewError) -> Comment   // → queued
    public mutating func editComment(_ id: CommentID, text: String) throws(ReviewError) -> Comment      // queued only
    public mutating func deleteComment(_ id: CommentID) throws(ReviewError)                             // queued only
    public mutating func sendBatch(transcripts: [CommentID: [BatchPayload.Line]], now: Date) throws(ReviewError) -> Batch
    public mutating func answer(_ id: CommentID, text: String, now: Date) throws(ReviewError) -> Comment   // needs an open question
    public mutating func setNote(_ text: String)

    // the listener
    public mutating func acknowledge(_ id: BatchID, text: String?, now: Date) throws(ReviewError) -> Batch // its sent comments → acknowledged
    public mutating func setStatus(_ id: CommentID, to: CommentState) throws(ReviewError) -> Comment       // working | done | failed
    public mutating func reply(toComment: CommentID, text: String, now: Date) throws(ReviewError) -> Comment
    public mutating func reply(toBatch: BatchID, text: String, now: Date) throws(ReviewError) -> Batch
    public mutating func ask(_ id: CommentID, question: String, now: Date) throws(ReviewError) -> Comment  // the same open question isn't posted twice

    // delivery
    public func isFinished(_ id: BatchID) -> Bool                    // every comment done or failed
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

Everything else is refused with `ReviewError.illegalMove(from:to:)`. `setStatus` may skip a step forward (the acceptance scenario goes from `acknowledged` to `done`), never back. A `draft` is the comment being typed: it exists only in memory, on `ReviewDesk`, and has no id until it is queued.

`ReviewError` cases: `noVideo`, `emptyText`, `timeOutsideVideo(Double)`, `regionOutsideFrame`, `unknownComment(String)`, `unknownBatch(String)`, `notQueued(CommentID, CommentState)`, `emptyQueue`, `noOpenQuestion(CommentID)`, `illegalMove(from:to:)`. Each has one `message` line.

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
                            keyframe: (CommentID) -> String, crop: (CommentID) -> String?) -> BatchPayload
    public func encoded() -> Data          // sorted keys, slashes not escaped, null written for context, region and cropPath
}
```

`make` lists the batch's comments that aren't `done` or `failed`, in time order: all of them on the first delivery, the unfinished ones on a redelivery. `region` is `{x, y, w, h}`, normalized. Times are seconds.

#### The ledger: listener session, deliveries, context once per session

```swift
public struct ListenerLedger: Codable, Equatable, Sendable {
    public struct Session: Codable, Equatable { public var key, name, place: String; public var firstSeen, lastSeen: Date
                                                public var contextSent: [String: String] }   // content hash → the context text it last got
    public struct Delivery: Codable, Equatable { public var batch: BatchID; public var video: String; public var sentAt: Date
                                                 public var takenBy: String?; public var takenAt: Date? }
    public private(set) var session: Session?
    public private(set) var deliveries: [Delivery]        // oldest first; a finished one is removed

    public mutating func enqueue(_ batch: BatchID, video: String, sentAt: Date)
    /// A listener command arrived. Another key than the session's starts a new session:
    /// returns the batches the old one took and didn't finish, now pending again.
    public mutating func attach(_ holder: (key: String, name: String, place: String), now: Date) -> [BatchID]
    public func next() -> Delivery?                                          // the oldest pending one
    public func contextToSend(_ text: String, video: String) -> String?      // nil when empty, or the same as the session last got
    public mutating func delivered(_ batch: BatchID, context: String?, video: String, now: Date)   // taken; context remembered
    public mutating func finish(_ batch: BatchID)
    public func presence(waitOpen: Bool, now: Date) -> Presence
}
public enum Presence: String, Codable, Sendable { case listening, working, absent }
```

- **A listener session is a holder key.** Every request already carries its holder, so a listener is told apart with nothing new on the wire: one Claude Code session is one listener session (`CLAUDE_CODE_SESSION_ID`), and a test starts another with `VIDEO_REVIEW_CONTROL_KEY`.
- **Requeue.** When a listener command arrives from a key other than the session's, the old session is over: its taken, unfinished batches become pending again and their unfinished comments go back to `sent`. The same key calling `wait` again (the skill does, before it starts work) gets nothing twice.
- **Context once per session.** The session remembers, per video, the context text it last got. `contextToSend` returns the text for the first batch of that video, `nil` while it is unchanged, and the text again after the sidecar or the note changed. A new session remembers nothing, so it gets the context again. The memory is written only in `delivered`, after the reply reached the listener.
- **The ledger is saved** in `listener.json`, so an app restart neither sends the context twice to a session that goes on, nor loses a pending batch.
- **Presence is derived**, never stored:

| An open `wait`? | The session has a taken, unfinished batch? | The session's last command | Presence |
|---|---|---|---|
| yes | no | | `listening` |
| yes | yes | | `working` |
| no | yes | under 120 s ago | `working` |
| no | otherwise | | `absent` |

`ContextText` is two pure functions: `candidates(for video: URL) -> [URL]` (`<base>.context.md`, then `context.md`, in the video's folder) and `compose(sidecar: String?, note: String) -> String` (the sidecar's text, then the note under the heading `## Note from the reviewer`; empty when both are).

### Transcript: `VRTranscript`

```swift
public struct TimedLine: Codable, Equatable, Sendable { public var start, end: TimeInterval; public var text: String }

/// The one interface the app knows. The transcription research replaces what is behind it.
public protocol Transcriber: Sendable {
    func prepare(_ video: URL) async                                   // a video opened: start what takes time
    func lines(for video: URL, in window: ClosedRange<TimeInterval>) async -> [TimedLine]   // what exists now; never waits
    func status(for video: URL) async -> TranscriptStatus              // source name, complete?, line count
}

public protocol TranscriptSource: Sendable {
    var name: String { get }                                           // "voiceover" | "subtitles" | "speech"
    func prepare(_ video: URL) async
    func lines(for video: URL) async -> [TimedLine]?                   // nil: this source has nothing for the video
}
public struct OrderedTranscriber: Transcriber { public init(sources: [any TranscriptSource]) }   // the first source that isn't nil
public enum TranscriptWindow {
    public static let radius: TimeInterval = 15
    public static func around(_ time: TimeInterval) -> ClosedRange<TimeInterval>      // max(0, t - 15) ... t + 15
    public static func cut(_ lines: [TimedLine], to window: ClosedRange<TimeInterval>) -> [TimedLine]   // whole lines that overlap
}
```

| Source | Finds | Lines |
|---|---|---|
| `VoiceoverSource` | `voiceover.json` in the video's folder | one per scene; a scene lasts `ceil((durationSeconds + paddingSeconds) × fps)` frames and starts where the previous one ends; `fps` is the video's nominal frame rate (30 when unknown), given as a closure so the test passes 30 |
| `SubtitleSource` | `<base>.srt`, then `<base>.vtt` | one per cue |
| `SpeechSource` | always there | `SpeechAnalyzer` with `SpeechTranscriber` on the audio track, started by `prepare` in a background task; its lines grow as results come; it reads and writes a `TranscriptCaching` it is given, so a second open is instant |

`SpeechSource` is an actor that keeps the lines per video. `lines` returns what it has so far, so a batch sent early carries the lines that exist at the send. `TranscriptCaching` (`load(video hash)`, `save`) is a protocol in this module; `VRStore` implements it, so Transcript doesn't depend on Store.

NOTE: #8 must check whether SpeechAnalyzer on a file asks for Speech Recognition permission on macOS 26 and whether the model asset is installed. `Info.plist` carries `NSSpeechRecognitionUsageDescription` from the start. A permission prompt goes to the maintainer.

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
    public func keyframe(_ id: CommentID) -> URL; public func crop(_ id: CommentID) -> URL
    public func transcriptFile(_ hash: String) -> URL
    public func hash(forPrefix prefix: String) -> String?      // the video an id's first eight digits name
}
public struct ReviewStore: Sendable {
    public init(layout: SupportLayout)
    public func loadReview(_ hash: String) throws -> Review?
    public func save(_ review: Review) throws
    public func loadLedger() -> ListenerLedger; public func save(_ ledger: ListenerLedger) throws
    public func loadAppState() -> AppState; public func save(_ state: AppState) throws    // the last video: path, hash, time
}
public struct TranscriptCache: TranscriptCaching { public init(layout: SupportLayout) }
```

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
- **Writes** are whole-file and atomic. Every JSON file has a `version`; a newer or unreadable file is moved aside, never overwritten.
- **Paths in the payload** are these files' absolute paths.

### App: `VRApp`

#### AppModel, the orchestrator

```swift
@MainActor @Observable final class AppModel {
    let player: PlayerEngine
    let desk: ReviewDesk
    let listener: ListenerQueue
    let transcriber: any Transcriber
    private(set) var notice: Notice?                 // the last agent message, shown for 5 s
    var selection: CommentID?                        // the marker and card in focus

    // one method per action; the views and ControlServer are its only callers
    func open(_ video: URL) async throws(ActionError) -> OpenVideo       // the player's reading of the file; VideoInfo once reviews exist
    func play() throws(ActionError);  func pause() throws(ActionError)
    func seek(to seconds: Double) async throws(ActionError) -> Double    // exact; refused outside 0...duration
    func scrub(to seconds: Double);  func setSpeed(_ speed: Double)      // the scrubber's drag and the speed menu: the person's only
    func openForPerson(_ video: URL);  func chooseVideo();  func togglePlayback()   // the person's ways into the actions: a refusal is shown, not thrown

    func startDraft(region: Region?) throws(ActionError)                 // pauses; the composer opens
    func commitDraft(text: String) async throws(ActionError) -> Comment  // Return in the composer
    func discardDraft()                                                  // Escape
    func addComment(text: String, at: Double?, region: Region?) async throws(ActionError) -> Comment   // the CLI's path
    func editComment(_ id: CommentID, text: String) throws(ActionError) -> Comment
    func deleteComment(_ id: CommentID) throws(ActionError)
    func sendBatch() async throws(ActionError) -> Batch                  // Cmd+Enter and `batch send`
    func answer(_ id: CommentID, text: String) throws(ActionError) -> Comment
    func setNote(_ text: String) throws(ActionError)

    func snapshot(lease: ControlLease.Status?) -> StateSnapshot
}
```

`ActionError` wraps a `ReviewError`, or says `no video is open`, `can't open <path>: <why>`, `<time> is outside the video, which ends at <duration>`. Its `message` is the refusal line. What the person does can't throw to anyone, so `AppModel.failure` keeps the line and the window shows it in an alert.

`AppModel` also knows the run's data folder (`support`, `isDemo`, from `SupportFolder`) and the app's one window, which `Screenshotter` captures.

The listener's actions (`wait`, `ack`, `status`, `reply`, `ask`) are methods on `ListenerQueue`, since they act on a batch by its id whatever video is open.

#### Player

`PlayerEngine` wraps one `AVPlayer`. `open` loads the video track's length, shown size and frame rate, refuses a file AVPlayer can't play, and answers once the item is ready to play, so a seek or a screenshot right after finds the frame there. When two opens overlap, the later one wins and the earlier is refused. The `duration` is the video track's, to the millisecond (21.233 for the fixture, whose audio runs to 21.248): every time up to it has a frame. `seek` uses zero tolerance and returns when the seek has landed, so `state` after `player seek 0:10` reads exactly 10. A periodic time observer publishes `time` 30 times a second, to the millisecond and never past `duration`, and `playing` from the player's rate. `play` at the video's end starts again from 0. `PlayerSurface` hosts the `AVPlayerLayer` alone: AVKit's own controls are off, because the timeline has to carry the markers.

`Shortcuts` attaches the player's keys to the player area with `onKeyPress`, which SwiftUI delivers to the focused view only. While the composer, an answer box or the note has the focus, the player never sees a key. No plain key is a menu shortcut, since a menu shortcut would fire while typing. Menu items carry only Command shortcuts (Cmd+O, Cmd+Return).

#### Keyframes and crops

`FrameGrabber` makes both from the video file, never from the screen:

```text
keyframe(for comment, video) :
    AVAssetImageGenerator(asset) with zero time tolerance, the track's transform applied, full natural size
    image(at: comment.time) → PNG → videos/<hash>/frames/<id>.png
crop(for comment) :
    comment.region.pixels(in: keyframe size) → the keyframe's CGImage cropped → PNG → videos/<hash>/crops/<id>.png
```

So a keyframe is the exact frame at the comment's time, at the video's own resolution, whatever the window's size; and the UI and the CLI get the same crop, because both hand `FrameGrabber` the same normalized region. `ReviewDesk.add` awaits both files before it answers. A draft's keyframe is grabbed when the composer opens, so Return is instant.

`FrameGeometry` is the one place that knows where the frame sits in the view (aspect-fit, letterboxed) and turns view points into a normalized region and back. The overlay draws a stored region through it on every layout, so a region stays on the same pixels when the window changes size.

#### ReviewDesk

```swift
@MainActor @Observable final class ReviewDesk {
    private(set) var open: Review?                      // the playing video's review
    private(set) var draft: Draft?                      // time, region, the keyframe being grabbed
    func load(_ video: VideoInfo) throws -> Review      // from the store, or a new one
    func review(forID prefix: String) throws(ActionError) -> Review          // any video, by an id's first eight digits
    func change<T>(_ hash: String, _ body: (inout Review) throws(ReviewError) -> T) throws(ActionError) -> T
}
```

`change` is the only way a review changes: copy, apply the review's own method, save through `ReviewStore`, publish. A refused change saves nothing. Until #11 lands the desk keeps reviews in memory only; `change` is where saving is added.

#### ListenerQueue

```swift
@MainActor @Observable final class ListenerQueue {
    private(set) var presence: Presence
    private(set) var session: ListenerLedger.Session?

    func enqueue(_ batch: Batch, video: VideoInfo)                                     // from AppModel.sendBatch
    func wait(holder: Holder, timeout: Int?) async -> WaitOutcome                      // .batch(Delivery, json) | .timedOut | .refused(String)
    func delivered(_ delivery: Delivery, context: String?)                             // the reply was written
    func acknowledge(_ id: String, text: String?, holder: Holder) throws(ActionError) -> Batch
    func setStatus(_ id: String, _ state: String, holder: Holder) throws(ActionError) -> Comment
    func reply(_ id: String, text: String, holder: Holder) throws(ActionError) -> ReplyTarget
    func ask(_ id: String, question: String, wait: Int?, holder: Holder) async -> AskOutcome   // .answer(String) | .timedOut | .refused(String)
    func answered(_ comment: Comment)                                                  // from AppModel.answer: resumes the ask
    func quitting()                                                                    // answers every open wait and ask
}
```

- It keeps the open `wait`s (a continuation each, oldest first) and the open `ask`s (by comment id).
- A `wait` from another key while a `wait` is open is refused: `<name> in <place> is already listening`. One listener at a time.
- `enqueue` and `wait` both end in the same step: while there is a pending delivery and an open wait, build the payload and resume the oldest wait with it.
- `ask` without `--wait` waits without limit, as the spec says the command exits with the answer. An `ask` with the same text as the comment's last question attaches to that question: when it is already answered, it returns the answer at once, so a listener that timed out can ask again and lose nothing.
- Every listener command calls `ledger.attach`, saves the ledger and re-derives `presence`. A one-second timer re-derives it too, for the 120 s rule.

#### ControlServer

Shipyard's server, with this app's routes.

```swift
@MainActor final class ControlServer {
    struct Answer { var reply: ControlReply; var quits = false; var granted: ControlLease.Term?; var delivery: Delivery? }
    private(set) var lease: ControlLease                // every change runs leaseChanged()
    let indicator: LeaseIndicator                       // what the banner reads
    func start() throws;  func stop()
    func reply(to data: Data) async -> Answer
    func written(_ answer: Answer);  func undelivered(_ answer: Answer)
    func stopLease()                                    // the banner's Stop
    func settleLease()                                  // the timer at the lease's end
}
```

The server owns the one `ControlLease`. Every change to it runs `leaseChanged`, the one place a change is applied:

1. The lease is copied to `LeaseIndicator`, so the banner follows it.
2. Each waiting `take` of the holder that now has the lease is answered, and its timeout cancelled.
3. A timer is set for `lease.nextEnd(after:)` and replaces the last one. When it fires, `settleLease` ends the lease and hands it to the first waiter, with no request.

A `take` in line is a `Waiter` in the server: its holder, its wait, whether it wants JSON, its continuation and its timeout task. The timeout calls `lease.giveUp`, never before the deadline the take was given. `stop()` answers every waiter with `video-review is quitting`. The server takes its time from a `now` closure and its zone from `timeZone`, so `VRAppTests` drives it with a clock of its own.

The person's Stop is `stopLease()`, which only calls `lease.stop(at:)`. The server puts it in `LeaseIndicator.stop`, and the banner's button calls that closure. So the Stop path is the pure rule plus one call, and tests reach it without a click.

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

`SocketListener` owns the POSIX side off the main actor: bind (0600), listen, accept, read one request to its end (8 MB at most), await `reply(to:)` with the heartbeat running, write, close, then tell the server `written` or `undelivered`.

The server grows with its tickets. Today `Answer` is `{reply, quits, granted}`, and the listener reads, answers, writes, tells the server `undelivered` when a reply that grants the lease can't be written, and quits. The heartbeat, `delivery` and `written` come with `wait`. A request whose route isn't built yet is refused in words: ``this build of video-review doesn't answer `wait` yet``.

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
  "transcript": {"source": "voiceover", "complete": true, "lines": 3},
  "listener": {"presence": "absent", "name": null, "place": null},
  "lease": {"holder": "Claude Code", "place": "/abs/repo", "secondsLeft": 58, "waiting": 0},
  "notice": null
}
```

`comments` are in time order; `queue` lists the ids of the queued ones in the same order; `video`, `draft`, `lease` and `notice` are `null` when there is none. With no video open, `comments`, `queue` and `batches` are empty. The object is one line. Every key is there from the first build: a part whose ticket hasn't landed carries its empty value (`[]`, `null`, `""`, presence `absent`), `video.contentHash` is `null` until reviews are kept by it, and `transcript` is `{"source": null, "complete": false, "lines": 0}` until a source has lines. `player.time` and `video.duration` are to the millisecond; `player.rate` is the speed playback runs at while it plays.

`Screenshotter` captures the app's own window through ScreenCaptureKit limited to this process (`SCShareableContent.currentProcess`), which needs no Screen Recording permission. With `--appearance` it sets the app's appearance, waits 350 ms for the redraw, captures, and puts the appearance back. If the capture fails, it draws the window's content view itself and then the frame at the playhead, read from the file, where the player's layer shows it (`AVPlayerLayer.videoRect`), since a player layer doesn't draw into a bitmap; the title bar's place stays blank, and the reply says on standard error that the PNG was rendered. Until `FrameGrabber` exists it reads that frame with its own `AVAssetImageGenerator`. A window that isn't on screen (closed, minimized, hidden) is refused.

#### Views

```text
┌─ toolbar ───────────────────────────────────────────────────────────────────┐
│ sample.mp4                           ● Listening   [Context]   [Sidebar]    │
├─ lease banner (only while an agent holds the lease) ────────────────────────┤
│ Claude Code controls Video Review · /repo · 42 s left               [Stop]  │
├──────────────────────────────────────────────────┬──────────────────────────┤
│                                                  │ QUEUE (2)      [Send ⌘↩] │
│                                                  │ ○ 0:04  the title is…    │
│            the video frame                       │ ▢ 0:10  this box…        │
│      ┌ ─ ─ ─ ─ ┐  ┌───────────────────┐          │ SENT                     │
│        region     │ comment box       │          │ Batch 1 · acknowledged   │
│      └ ─ ─ ─ ─ ┘  └───────────────────┘          │ ✓ 0:15  done             │
│                          ┌ notice ─────────┐     │   └ agent: fixed in a1b2 │
│                          │ agent · 0:15 …  │     │ ? 0:18  question         │
│                          └─────────────────┘     │   └ [answer…           ] │
├──────────────────────────────────────────────────┤                          │
│ ▶  0:10 / 0:21   ──○───▢────●────?──   1×        │                          │
└──────────────────────────────────────────────────┴──────────────────────────┘
```

One `Window` scene. The frame and the transport bar are the content; the sidebar is an `inspector` on the trailing edge. Views read `AppModel` and call its methods; they keep no rule. Closing the window quits the app, since there is only one. `VideoReviewApp.swift` holds the `App`, the `AppDelegate` that is the composition root (it makes `AppModel`, `Screenshotter`, `LeaseIndicator` and `ControlServer`, starts the server at launch and stops it at quit) and `MainView`, the window's content.

The lease banner is the one view that doesn't read `AppModel`: the lease belongs to `ControlServer`, not to the model. `Control/LeaseBanner.swift` holds three small things. `LeaseIndicator` is the observable copy of the lease that the server keeps current, with the `stop` closure. `LeaseBannerText` makes the words from a `ControlLease.Status` (`Claude Code controls Video Review (proto-1)`, `/repo · 42 s left · 1 waiting`) and is tested. `LeaseBanner` is the view: the first row of `MainView`, drawn only while a lease is in force, with a `TimelineView` that ticks the seconds and a Stop button. It is part of the window, so `screenshot` shows it.

### Build and test

- `Package.swift`: `swift-tools-version: 6.2`, `platforms: [.macOS(.v26)]`, Swift 6 language mode, no outside package. Tests use Swift Testing.
- `Makefile`, after Shipyard's:

| Target | Does |
|---|---|
| `make build` | `swift build -c release` for `VideoReview` and `video-review-cli` |
| `make test` | `swift test`; with the Command Line Tools alone it adds the flags that find the Testing framework, and shares one module cache, as Shipyard does |
| `make bundle` | `build/<APP_NAME>.app`: the executable in `Contents/MacOS/VideoReview`, the CLI as `Contents/Helpers/video-review`, the stamped `Info.plist`; signs the CLI, then the bundle, ad hoc |
| `make install` | quits this build's running app by its path, replaces `/Applications/<APP_NAME>.app`; doesn't start it |
| `make acceptance` | `scripts/acceptance.sh` against the installed app |
| `make run`, `make clean` | as named |

`APP_NAME` contains spaces and parentheses, so every recipe quotes it and no target is named after a file that contains it.

- `make test` never drives the Mac. The pure modules are tested directly (lease tables with a clock value, the review's state machine, the payload, the ledger, the window cut, the source order, the version refusal, the content hash of a renamed copy). `VRCommandTests` runs `CLI.run` with a fake transport and launcher. `VRAppTests` covers `FrameGeometry` and the server's routing and leasing: it runs `ControlServer` on a real `AppModel` with no video and no window, at times the test sets, in memory and over the real socket in a temporary folder. It tests no view.
- The highest seam is `scripts/acceptance.sh`: the eight steps of the spec's scenario through the installed CLI in demo mode, checked with `jq` on `state --json` and the payload.

---

## Stage 4: Implementation

The methods that carry the logic, then two traces and two refusals.

### Sending a batch

```text
AppModel.sendBatch():
    review = desk.open                         else refuse "no video is open"
    if a draft has text: commitDraft(text)     Cmd+Enter in the composer sends what is being typed too
    queue = review.queue                       else refuse "the queue is empty"
    for comment in queue:                      the transcript as it exists now
        lines[comment.id] = cut(transcriber.lines(video, around(comment.time)))
    batch = desk.change(hash) { $0.sendBatch(transcripts: lines, now) }      queued → sent; saved
    listener.enqueue(batch, video)             ledger.enqueue; saved; deliver if a wait is open
    return batch
```

### Delivering

```text
ListenerQueue.wait(holder, timeout):
    if another session's wait is open: return .refused
    requeued = ledger.attach(holder, now)      a new key: the old session's unfinished batches are pending again
    for id in requeued: desk.change(…) { $0.requeue(id) }
    add a waiter; start its timeout if any; presence = derive
    deliverIfPossible()
    suspend until resumed                      by a delivery, the timeout, a cancelled connection, or quitting

ListenerQueue.deliverIfPossible():
    while let delivery = ledger.next(), let waiter = oldest waiter:
        review   = desk.review(for: delivery.video)
        text     = ContextText.compose(sidecar: ContextSource.read(review.video.path), note: review.note)
        context  = ledger.contextToSend(text, video)
        payload  = BatchPayload.make(batch, review, context, keyframe: layout.keyframe, crop: …)
        resume waiter with .batch(delivery, payload.encoded())

ControlServer.written(answer) with a delivery:   listener.delivered → ledger.delivered(batch, context, video, now); saved
ControlServer.undelivered(answer) with a delivery: nothing changes; the batch is still pending for the next wait
```

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
   │     ⇒ LeaseBanner appears                        Sources/VRApp/Control/LeaseBanner.swift
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
- **The listener dies mid-wait.** The next heartbeat can't be written; the task is cancelled; the waiter is removed; presence goes to `absent`. Nothing was taken.

**A refusal.** After the send, `video-review comment edit 7f3a9c21-c1 "new text"` reaches `Review.editComment`, which finds `c1` in the state `sent` and throws `notQueued(c1, .sent)`. `desk.change` saves nothing. The reply is `refused("7f3a9c21-c1 is sent; only a queued comment can be edited")`, exit 1.

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
| 3 | The timeline is the app's own, with a marker per comment: a circle for a comment at a time, a rounded square for one with a region. | AVKit's scrubber can't carry markers. The shape tells the two kinds apart before a click. |
| 4 | A marker's colour and symbol show its state: hollow grey queued, blue sent, blue with a tick acknowledged, orange pulsing working, green done, red failed, a purple question mark while a question is open. The sidebar cards use the same style. | Story 16: one look at the timeline tells which comments are done. One style table serves markers and cards, so they can't disagree. |
| 5 | Playback keys follow QuickTime and editors: Space plays and pauses, Left and Right move 5 s, `,` and `.` step one frame, J K L shuttle, a click on the frame plays or pauses. | Story 2: nothing to learn. Frame steps let the person land on the exact frame before commenting. |
| 6 | Return or C opens the comment box at the playhead and pauses. The box has the focus at once. | Story 3: one key from watching to typing. |
| 7 | Dragging on the frame draws a region, pauses, and opens the comment box next to the rectangle. The pointer is a crosshair over the frame. A drag under 8 points counts as a click. | Stories 6 and 7: the same gesture as Cmd+Shift+4, with no mode to enter first. |
| 8 | In the comment box, Return queues the comment, Shift+Return makes a new line, Escape cancels the box and its region. | The common act gets the plain key. Escape cancelling the region is the ticket's rule. |
| 9 | After a comment is queued, playback resumes if the video was playing when the box opened. | Pause, comment, carry on: the fastest loop for a run of small notes. |
| 10 | The comment box is a standard text field. | Story 8: Wispr Flow dictates into any standard field, so dictation needs no code. |
| 11 | Player keys act only while no text field has the focus, and no plain key is a menu shortcut. | The ticket's rule that typing must never trigger a player shortcut, held by the focus system, not by a list of exceptions. |
| 12 | Cmd+Return sends the queue from anywhere. Typed text in an open comment box is queued first, then sent. | Story 11: one keystroke, and nothing the person typed is left behind. |
| 13 | The sidebar is an inspector on the right: the queue on top with its count and the Send button, sent comments below, grouped by batch, in time order. It can be hidden. | The queue is what the person acts on next; the frame keeps the larger share. |
| 14 | A queued comment is edited in place in its card (double-click or the pencil) and deleted with the trash button or Delete. | Story 10, without a separate editor. |
| 15 | Clicking a marker or a card seeks to the comment's time, pauses, selects it in both places and draws its region on the frame. | Story 13: the marker, the card and the region are one selection. |
| 16 | A thread shows under its comment's card. The answer box appears only while a question is open. | Stories 18 and 20: the answer goes where the question is. A person's message with no question has no command to deliver it, so the box isn't offered. |
| 17 | Messages for a whole batch show in a card at the head of that batch's group. | Story 21: the overall result sits above the comments it is about. |
| 18 | An agent message shows as a notice at the bottom right of the frame for 5 s, with the comment's time. A click selects the comment. | Story 19: seen while watching, away from the centre of the frame, and gone by itself. |
| 19 | Presence is a pill in the toolbar: green Listening, orange Working, grey No listener. Hovering names the listener and its folder. | Story 14: the answer to "will my batch reach someone" is always in sight. |
| 20 | Sending with no listener works. The batch's card says "Waiting for a listener". | Story 15: the person isn't blocked, and knows why nothing answers yet. |
| 21 | While an agent holds the lease, a banner under the toolbar names it, its folder, the seconds left and how many agents wait, with a Stop button. Stop ends the lease and refuses that agent for 5 minutes; an agent in line gets the lease at once. The person's own clicks and keys always work. A screenshot shows the banner, since it is in the window. | Stories 29 and 30. The person never needs the lease. A screenshot is what the window shows, and the contract has no option to hide a part of it. |
| 22 | The context note is a popover from a toolbar button. It also names the sidecar file that was found. | Story 26: rarely used, so out of the way, and it shows what the agent will get. |
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
| The transcription research lands | One new `TranscriptSource` in `Sources/VRTranscript/Sources/`, and its place in the list `VideoReviewApp` gives `OrderedTranscriber`. Or a whole new `Transcriber`. Nothing else knows. |
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
| #4 Control: lease | `VRLease/ControlLease.swift` in full; `control take` and `release`; the take's wait, the settle timer, `stopLease` and `undelivered` in `ControlServer`; `ControlRequest.silence`; `LeaseBanner` with `LeaseIndicator`; `VRLeaseTests`, and `VRAppTests` with `ControlServerTests` |
| #5 Comment: timestamped | `VRReview`: `Identifiers`, `Comment`, `ThreadMessage`, `Review` (add, edit, delete), `ReviewError`; `VRStore`: `SupportLayout`, `ContentHash`; `Comments/ReviewDesk` (in memory), `FrameGrabber` (keyframe), `Sidebar`, `CommentCard`, `StatusStyle`; `Overlay/Composer`; markers in `Timeline`; `Shortcuts`; the `comment` rows |
| #6 Comment: region | `VRReview/Region.swift`; `Overlay/FrameGeometry`, `RegionOverlay`; the crop in `FrameGrabber`; `--region` |
| #7 Mate: send and wait | `Batch`, `Review.sendBatch`, `BatchPayload`, `ListenerLedger`, `Presence`; `Mate/ListenerQueue`, `PresencePill`; the heartbeat in `SocketListener`; `batch send`, `wait`; Cmd+Return |
| #8 Transcript | `VRTranscript` whole; `VRStore/TranscriptCache`; the lines captured in `AppModel.sendBatch` |
| #9 Mate: context | `ContextText`; `Mate/ContextSource`; `ledger.contextToSend`; `Comments/ContextNote`; `context set` |
| #10 Mate: answers | `acknowledge`, `setStatus`, `reply`, `ask`, `answer` in `Review`; the `ask` side of `ListenerQueue`; `ThreadView`, `BatchCard`, `NoticeToast`; `ack`, `status`, `reply`, `ask`, `thread answer` |
| #11 Comment: persist | `VRStore/ReviewStore`; saving in `ReviewDesk.change`; the ledger saved; `app.json` and reopening the last video; `VRStoreTests` |
| #12 Mate: the skill | `.agents/skills/video-review-mate/SKILL.md` |
| #13 Proto: acceptance | `scripts/acceptance.sh`, `make acceptance`, `assets/screenshots/` |

#4 and #5 can run side by side (lease files against review files; both add rows to `CommandTable` and routes to `ControlServer`, in separate lines). #8, #9 and #10 can run side by side after #7 (Transcript against context against threads; they meet only in `AppModel.sendBatch`, `ListenerQueue.deliverIfPossible` and the command table).
