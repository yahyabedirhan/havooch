# Low-level design: Video Review v1 (proto-3)

This is the design of the `proto-3` build of the v1 spec (`Spec: Video Review v1`, issue #1). It says which modules exist, what each one owns, how they call each other and where each file sits. It was written before the first build ticket and accepted by the agent that wrote it; nobody reviewed it. Every later ticket updates it in the same change, so it matches the code.

Read `docs/adr/0001-agents-control-the-app-through-a-leased-cli.md` first. Agent control copies the patterns of Shipyard (`yahyabedirhan/shipyard`: its `Package.swift`, `Makefile`, `Sources/ShipyardControl/`, `Sources/ShipyardApp/Control/`, ADR 0006 and ADR 0007). No code is linked from it.

## Start here

| You want to | Open |
|---|---|
| see where the app starts | `Sources/VRApp/VideoReviewApp.swift`, then `AppServices.swift` |
| see where the CLI starts | `Sources/VRCLI/main.swift`, then `Sources/VRCommand/CommandTable.swift` |
| add a CLI command | [Adding a CLI command](#adding-a-cli-command) |
| change what a request looks like on the socket | `Sources/VRWire/ControlRequest.swift` |
| change who may drive the app | `Sources/VRLease/ControlLease.swift` |
| change a comment's states or the batch payload | `Sources/VRReview/` |
| change what is kept on disk | `Sources/VRStore/Library.swift` |
| change where the transcript comes from | `Sources/VRTranscript/TranscriptSources.swift` |
| change the look | `Sources/VRApp/UI/` and [UX choices](#ux-choices-of-this-prototype) |
| rename the build (drop `proto-3`) | `Sources/VRWire/AppIdentity.swift`, one constant |

The whole system in one picture:

```text
 agent's shell                                  the app (one process)
┌──────────────────────────┐   control.sock   ┌───────────────────────────────────────────┐
│ video-review  (VRCLI)    │   one JSON       │ ControlServer ── ControlLease (VRLease)   │
│  └ VRCommand             │ ──request per──▶ │   ├ OperatorDesk ─┐                       │
│      ├ VRWire  (client)  │   connection     │   └ ListenerDesk ─┤                       │
│      └ VRLease (Holder)  │ ◀──one reply──── │                   ▼                       │
└──────────────────────────┘                  │ ReviewModel ── ReviewSession, Outbox      │
                                              │   │                (VRReview, pure)       │
 person ── keyboard, mouse ─────────────────▶ │   ├ PlayerController, FrameGrabber        │
                                              │   ├ TranscriptService ── VRTranscript     │
                                              │   └ Library (VRStore) ── Application      │
                                              │                          Support folder   │
                                              └───────────────────────────────────────────┘
```

A person and an operator agent reach the same `ReviewModel` methods: the person through SwiftUI views, the agent through `OperatorDesk`. Nothing the UI can do skips the model, so every UI action has a CLI command (ADR 0001).

## Build identity

Three prototypes share one Mac. This build's identity is set in one place, `AppIdentity.variant` in `Sources/VRWire/AppIdentity.swift`:

```swift
public enum AppIdentity {
    /// The one build setting. "" for the real product.
    public static let variant = "proto-3"
    public static let version = "0.1.0"
}
```

Everything else is derived from it, in the same file and in the `Makefile` (which reads the constant with `sed`, as Shipyard's `Makefile` reads its version):

| Derived value | With `proto-3` | With `""` |
|---|---|---|
| `AppIdentity.name`, the bundle folder | `Video Review (proto-3)` / `/Applications/Video Review (proto-3).app` | `Video Review` |
| `AppIdentity.bundleID` | `com.yahyabedirhan.video-review.proto-3` | `com.yahyabedirhan.video-review` |
| `AppIdentity.supportFolder()` | `~/Library/Application Support/Video Review (proto-3)/` | `…/Video Review/` |
| the CLI | `<bundle>/Contents/Helpers/video-review` | the same |

The CLI's name and commands never change. Agents run it from this build's bundle, never from `PATH`. Because the constant is compiled into both binaries, the CLI finds its own app's socket wherever it is copied.

`AppIdentity` also names the two variables a demo run's app is launched with, `VIDEO_REVIEW_SUPPORT_DIR` and `VIDEO_REVIEW_DEMO_DIR`. `VIDEO_REVIEW_CONTROL_KEY` is named in `Holder` and `VIDEO_REVIEW_CONTROL_LEASE` in `ControlLease` (`VRLease`), which read them and cannot import `VRWire`.

`app open` launches the bundle the CLI sits in (`<bundle>/Contents/Helpers/video-review` → `<bundle>`), and looks the app up by bundle id only when the CLI runs from somewhere else. So a second copy with the same bundle id on the disk (a `build/` folder) is never launched instead of the installed one.

## 1. Requirements

### Capabilities

1. Open a local `mp4`, `mov` or `m4v` file and play it: play, pause, seek, scrub.
2. Add a comment at the current time. It keeps its time, its text and a PNG of the frame.
3. Draw a rectangle on the frame and comment on it. It keeps the region (normalized 0..1) and a PNG crop.
4. Edit or delete a comment that is not sent yet.
5. Send every queued comment of the open video as one batch (Cmd+Enter).
6. Deliver the batch to a listener's `wait` as the spec's JSON payload. A batch sent with no listener waits for the next one.
7. Show listener presence: `absent`, `listening` or `working`.
8. Let the listener acknowledge a batch, set a comment's status, send messages, and ask a question and wait for its answer.
9. Show every comment as a marker on the timeline with its status, and its thread beside the video. Show a brief notice when an agent message arrives.
10. Give each comment the transcript from 15 s before to 15 s after its time, from the best source available.
11. Give the listener the video's context (`context.md` sidecar plus the in-app note) once per listener session and again when it changes.
12. Keep comments, batches, threads and statuses on disk, keyed by the video's content hash.
13. Let an agent do everything a person can through the `video-review` CLI, one operator at a time under the lease.
14. Report what the app shows as JSON (`state --json`) and as a PNG of its window in light or dark.
15. Run on demo data in a separate support folder.

### Rules and completion

- A comment moves only forward: `draft → queued → sent → acknowledged → working → done | failed`. `done` and `failed` are final. The one move backward is a requeue (see rule below).
- A batch is finished when every comment in it is `done` or `failed`.
- A batch a listener took and did not finish goes back in the queue when another listener session arrives. Its unfinished comments go back to `sent`.
- The lease ends 60 s after the holder's last operator command, and 5 min after it was taken at most. The person's Stop ends it and bars that holder for 5 min.
- A thread message has an author (`person` or `agent`) and a kind (`message`, `question` or `answer`).
- The listener is present while a `wait` is open.

### Error handling

- Every refusal is a reply with `ok: false` and one line in `error`. The CLI prints it on standard error and exits 1. A command line that does not parse prints usage and exits 2. A `wait` or `ask` whose time ran out exits 3.
- A request of another protocol version is refused, naming both versions.
- An operator command from another holder than the lease's is refused, naming the holder, its place and when the lease ends.
- An operator command or a `control take` from a holder the person stopped is refused for 5 min, telling the agent to ask the person.
- An action in the wrong state is refused by the module that owns the state: editing a sent comment (`ReviewSession`), answering when no question is open (`ReviewSession`), seeking with no video (`ReviewModel`), a region outside 0..1 (`Region`).
- A file AVPlayer cannot play is refused by `player open` with the reason; the open video stays.

### Scope

In: everything above. Out, as in the spec: editing video, other containers, URLs, system-wide hotkeys, more than one listener, shapes other than rectangles, transcription research, Developer ID signing. Out by this design: more than one window or open video, person messages that are not answers, system notifications, undo.

### Requirement → module

| Requirement | Module |
|---|---|
| 1 | VRApp (`Player/`) |
| 2, 3, 4, 5, 8, 9 (rules) | VRReview |
| 2, 3 (images) | VRApp (`FrameGrabber`), VRStore (paths) |
| 6, 7, 11 (rules) | VRReview (`Outbox`) |
| 6, 7, 8 (connections) | VRApp (`ListenerDesk`) |
| 10 | VRTranscript, VRApp (`TranscriptService`, `SpeechSource`) |
| 12 | VRStore |
| 13 | VRLease, VRWire, VRCommand, VRApp (`ControlServer`) |
| 14 | VRApp (`StateReport`, `Screenshotter`) |
| 15 | VRWire (`DemoPointer`), VRCommand (`AppCommand`) |

## 2. Entities and relationships

Entities hold changing state or enforce rules. Everything else is a field.

| Entity | Module | Holds | Enforces |
|---|---|---|---|
| `ControlLease` | VRLease | the current term, the line of waiters, the bars | who may send operator commands, and until when |
| `ReviewSession` | VRReview | one video's comments, batches, threads and note | the comment state machine, what may be edited, sent, answered |
| `Outbox` | VRReview | sent batches not finished (`Parcel`s), the listener, the context already sent | which batch a `wait` gets, requeue, presence, context once |
| `Library` | VRStore | the support folder | where each file is, id counters, id → video lookup |
| `ReviewModel` | VRApp | the open video, its session, the outbox, the player | the order of work for each action: check, change, save, publish |
| `ControlServer` | VRApp | the socket, the one `ControlLease` | version check, lease gate, dispatch |
| `ListenerDesk` | VRApp | parked `wait` and `ask` connections | nothing: it asks `Outbox` and `ReviewSession` |
| `PlayerController` | VRApp | the `AVPlayer` | seek bounds |

Fields, not entities: `Comment`, `Region`, `Batch`, `ThreadMessage` (inside `ReviewSession`); `Parcel` (inside `Outbox`); `Holder`, `Term` (inside `ControlLease`); `TranscriptLine`; `VideoInfo`.

```text
ControlServer ─owns→ ControlLease
ControlServer ─calls→ OperatorDesk ─calls→ ReviewModel
ControlServer ─calls→ ListenerDesk ─calls→ ReviewModel
SwiftUI views ─read and call→ ReviewModel
ReviewModel ─owns→ ReviewSession (the open video's; others loaded on demand)
ReviewModel ─owns→ Outbox
ReviewModel ─uses→ Library, PlayerController, FrameGrabber, TranscriptService
ReviewSession ─contains→ Comment ─contains→ Region?, ThreadMessage[]
ReviewSession ─contains→ Batch ─contains→ ThreadMessage[]
Outbox ─contains→ Parcel (batch id + video hash + delivery)
Library ─reads and writes→ ReviewSession, Outbox, TranscriptLine[], PNG files
```

`ReviewModel` is the orchestrator. Lifecycle rules ("is a video open?", "is the frame saved yet?") live there. Data rules live with the data: "may this comment be edited?" is `ReviewSession`'s, "may this holder act?" is `ControlLease`'s.

## 3. Class design

### Targets

SwiftPM only, `swift-tools-version: 6.2`, `platforms: [.macOS(.v26)]`, Swift 6 language mode, no package dependencies. Module names carry the prefix `VR` so no type shares a name with its module (`Lease`, `Review` and `Transcript` would).

| Target | Kind | Spec module | Depends on | Owns |
|---|---|---|---|---|
| `VRLease` | library | Lease | nothing | `Holder` and how it is found, `ControlLease`, `LeaseStatus` |
| `VRWire` | library | Wire | `VRLease` | `AppIdentity`, requests, replies, the version, socket location, demo pointer, socket framing, the client |
| `VRCommand` | library | Command | `VRWire`, `VRLease` | the command table, argument parsing, exit codes, launching the app |
| `VRCLI` | executable, product `video-review` | Command | `VRCommand` | `main.swift` only |
| `VRReview` | library | Review | nothing | comments, regions, batches, threads, the state machine, the outbox, the payload |
| `VRTranscript` | library | Transcript | nothing | `Transcriber`, sidecar sources, the window cut, the source order |
| `VRStore` | library | Store | `VRReview`, `VRTranscript` | the support folder's layout, the content hash, JSON and PNG files |
| `VRApp` | executable, product `VideoReview` | App | `VRLease`, `VRWire`, `VRReview`, `VRTranscript`, `VRStore` | SwiftUI, AVKit, the control server, the listener desk, Speech |

```text
An arrow points at what a target depends on.

agent side:   VRCLI ──▶ VRCommand ──▶ VRWire ──▶ VRLease

app side:     VRApp ──▶ VRWire, VRLease          (the socket's server side and the one lease)
              VRApp ──▶ VRStore ──▶ VRReview
                           └──────▶ VRTranscript
              VRApp ──▶ VRReview, VRTranscript
```

`Package.swift` holds a target from the ticket that gives it its first file, and a dependency from the ticket whose code first needs it. After the region ticket it has `VRLease`, `VRWire`, `VRCommand`, `VRCLI`, `VRReview` (`VideoInfo`, `Comment`, `Region`, `ReviewSession`), `VRStore` (`ContentHash`, `Library`, `JSONFile`; no dependencies yet, since `Library` does not keep sessions before the persistence ticket) and `VRApp`; `VRTranscript` is not there yet.

Agent-side modules (`VRLease`, `VRWire`, `VRCommand`) never import an app-side module. `VRCommand` is a library and `VRCLI` is a thin executable so the command table tests without a process, as in Shipyard. `VRCommand` imports AppKit only for `NSWorkspace` (to launch the app); it has no UI code.

Test targets, all run by `make test` without the app:

| Target | Tests |
|---|---|
| `VRLeaseTests` | time-driven lease tables (take, renew, expire, cap, queue, stop, bar), holder discovery with a fake process table |
| `VRWireTests` | encode and decode of every request, version refusal, demo pointer, socket location |
| `VRCommandTests` | parsing, output and exit codes through `CommandTable.run` with a fake transport and launcher |
| `VRReviewTests` | the state machine, batch assembly, the outbox (delivery, requeue, presence, context once), the payload's JSON |
| `VRTranscriptTests` | the window cut, the source order, `voiceover.json` scene times, `.srt` and `.vtt` parsing, against `fixtures/sample/` |
| `VRStoreTests` | save and load in a temporary folder, the content hash of a renamed copy, id counters |
| `VRAppTests` | `ControlServer.reply(to:)` with a fake player, a fake frame grabber, a clock the test sets and a temporary library: lease gate, takes in line, Stop, the banner's words, dispatch, comments, a parked `wait`; the command against the server over a real socket; `FrameGrabber` (keyframes and crops) against `fixtures/sample/sample.mp4`; the key routing; the region's geometry without a window: `FrameFit` at several stage sizes, a drag to a region, which regions show (`RegionMark`), where the comment box goes (`ComposerPlacement`) |

### Folder tree

```text
Package.swift                       targets above
Makefile                            build, test, bundle, install, clean; reads the variant and version
Packaging/
  Info.plist                        template: __NAME__, __BUNDLE_ID__, __VERSION__; movie document types
scripts/
  acceptance.sh                     the v1 acceptance scenario through the installed CLI (ticket #13)
.agents/skills/video-review-mate/
  SKILL.md                          the listener skill (ticket #12)
Sources/
  VRLease/
    Holder.swift                    who sends a request; Holder.find from the environment and process table
    ProcessTable.swift              ProcessTable protocol, SystemProcessTable (sysctl)
    ControlLease.swift              the lease rules as a pure value; Term, Transition, Ending, Refusal, Decision; a relaunch's handover
    LeaseStatus.swift               the lease as status and state report it
  VRWire/
    AppIdentity.swift               variant, version, name, bundle id, support folder, environment variable names
    ControlRequest.swift            the request enum, its role (free, operator, listener), the version
    ControlMessage.swift            request + holder + json flag as one JSON object; decode refusals
    ControlReply.swift              {ok, output, error, lease?}
    ControlSocket.swift             control.sock's place; DemoPointer (demo.json)
    UnixSocket.swift                POSIX calls: address, connect, bind, read to end, write all
    ControlClient.swift             ControlTransport protocol, UnixSocketTransport, send one request
  VRCommand/
    CommandTable.swift              name → entry; the standard table; run(arguments) → CommandResult; top-level help
    CommandResult.swift             output, error, exit status (0, 1, 2, 3)
    CommandContext.swift            CommandEnvironment (what the command reads from outside); support folder, client, launcher for one invocation
    Arguments.swift                 shared parsing: time (seconds or mm:ss), region (x,y,w,h), --json, options
    AppCommand.swift                app status | open [--demo] | quit; launch, relaunch, demo pointer
    ControlCommand.swift            control take [--wait] | release
    StateCommand.swift              state
    PlayerCommand.swift             player open | play | pause | seek
    CommentCommand.swift            comment add | edit | delete
    BatchCommand.swift              batch send
    ThreadCommand.swift             thread answer
    ContextCommand.swift            context set
    ScreenshotCommand.swift         screenshot
    ListenerCommand.swift           wait | ack | status | reply | ask
    AppLauncher.swift               AppLaunching protocol, WorkspaceLauncher (NSWorkspace)
  VRCLI/
    main.swift                      runs CommandTable.standard, prints, exits
  VRReview/
    Comment.swift                   Comment, CommentState and its allowed moves
    Region.swift                    normalized rectangle, validation, pixel rectangle for a frame size, its x,y,w,h text
    ThreadMessage.swift             author, kind, text, time
    Batch.swift                     id, sentAt, comment ids, its own thread
    VideoInfo.swift                 content hash, path, title, duration
    ReviewSession.swift             one video's review: every change to comments, batches and threads
    Outbox.swift                    parcels, delivery, requeue, presence, context once
    BatchPayload.swift              the wait payload as a Codable contract, and how it is assembled
  VRTranscript/
    TranscriptLine.swift            start, end, text; the window cut
    Transcriber.swift               the interface: video + window → lines
    TranscriptSources.swift         the source order: which sidecar a video has
    VoiceoverSource.swift           voiceover.json: scene times from scene lengths
    SubtitleSource.swift            .srt and .vtt parsing
  VRStore/
    Library.swift                   the support folder: sessions, outbox, index, ids, image paths
    ContentHash.swift               a video file's hash
    TranscriptCache.swift           a video's speech transcript on disk
    JSONFile.swift                  atomic read and write of one Codable file
  VRApp/
    VideoReviewApp.swift            @main, the window scene with the lease banner over it, the menu commands
    AppServices.swift               composition root: reads the environment, builds and wires everything
    ReviewModel.swift               the orchestrator the views and the desks call
    Notice.swift                    a brief agent message shown over the stage
    TimeText.swift                  a time as text (0:10.000, 0:10) and rounded to the millisecond
    Player/
      PlayerController.swift        Playing protocol and its AVPlayer implementation
      PlayerSurface.swift           AVPlayerView without controls, as a SwiftUI view
      VideoFile.swift               opening a file: playable check, duration, frame rate, title, hash
      FrameGrabber.swift            FrameGrabbing protocol; keyframe and crop PNGs from the asset
    Transcript/
      TranscriptService.swift       resolves the source on open, runs speech in the background, answers windows
      SpeechSource.swift            Transcriber over Apple SpeechAnalyzer
    Context/
      ContextSidecar.swift          <base>.context.md, else context.md, beside the video
    Control/
      ControlServer.swift           decode, version, lease gate, dispatch; lease timers and waiters
      SocketListener.swift          the listening socket: accept, read, answer, heartbeat, close; a granted lease whose reply wasn't written goes back
      OperatorDesk.swift            operator requests → ReviewModel calls → reply text
      ListenerDesk.swift            listener requests; parked wait and ask connections
      StateReport.swift             app status and state as text and JSON
      LeaseIndicator.swift          the lease as the banner reads it, and the banner's words
      Screenshotter.swift           the window as a PNG through ScreenCaptureKit, in an appearance
    UI/
      MainWindow.swift              stage and sidebar laid out
      EmptyState.swift              no video open: drop, open, the demo folder's videos
      Stage.swift                   the video, the overlay, the composer, the notice
      RegionOverlay.swift           drawing and showing rectangles in frame coordinates: FrameFit (the frame inside the stage), RegionMark (which regions show), ComposerPlacement (the box beside a region), the overlay view
      Composer.swift                the comment box
      TransportBar.swift            play, time, the timeline
      Timeline.swift                the scrubber track and the marker pins
      Sidebar.swift                 batch cards and comment cards in time order
      CommentCard.swift             one comment: time, status, text, thumbnail, thread, answer box
      BatchCard.swift               one batch: its header and its thread
      SendBar.swift                 queued count, Send, the presence chip
      LeaseBanner.swift             who controls the app, time left, Stop
      ContextPopover.swift          the sidecar's text and the editable note
      Shortcuts.swift               the player's keys (PlayerKey, Escape among them) and where the focus is (KeyFocus): given up in a panel, under a sheet and while a text view has focus
      Theme.swift                   state colours and glyphs, spacing, fonts
Tests/
  VRLeaseTests/  VRWireTests/  VRCommandTests/  VRReviewTests/
  VRTranscriptTests/  VRStoreTests/  VRAppTests/
```

### Makefile and bundle

Copied from Shipyard's pattern.

- `VARIANT` and `VERSION` are read from `AppIdentity.swift` with `sed`. `APP_NAME` is `Video Review` plus ` ($(VARIANT))` when the variant is not empty. `BUNDLE_ID` is `com.yahyabedirhan.video-review` plus `.$(VARIANT)`.
- `make test`: `swift test`, with the Command Line Tools' Testing framework flags and a shared module cache when no Xcode is installed (this Mac has the Command Line Tools only).
- `make bundle`: release builds of `VideoReview` and `video-review`; `build/$(APP_NAME).app` with `Contents/MacOS/VideoReview`, `Contents/Helpers/video-review` and `Info.plist` filled from the template; ad-hoc `codesign`, the helper first.
- `make install`: quits only this variant's running copy, replaces the bundle in `/Applications`, and does not open it. Agents open it with `app open`. The copy is found by this bundle's `Contents/MacOS/` path as a fixed string (`ps` piped to `grep -F`), never by process name, since the three prototypes share the name `VideoReview`, and not with `pkill -f`, whose pattern would read the name's parentheses as a group.
- `Info.plist`: `NSSpeechRecognitionUsageDescription`, `LSMinimumSystemVersion` 26.0, document types for `public.mpeg-4`, `com.apple.quicktime-movie` and `com.apple.m4v-video`. The app is a normal windowed app, not `LSUIElement`.

### Key types

Signatures are the contract between tickets. Bodies are sketched in section 4.

**VRLease** (rules copied from Shipyard's `ControlLease`)

The first build ticket shipped `ControlLease` as a pass-through behind `use(by:at:)`, `current(at:)` and `status(at:)`; the lease ticket filled in the rules below without moving the gate in `ControlServer`. Shipyard's Allow (the person lifting a bar early) and its list of barred holders are left out: this app has no place that shows them, and a bar ends by itself.

```swift
public struct Holder: Codable, Hashable, Sendable {
    public var key: String      // VIDEO_REVIEW_CONTROL_KEY, else "CLAUDE_CODE_SESSION_ID=<id>", else "process:<pid>@<start>"
    public var name: String     // "Claude Code", or the process's name
    public var place: String    // "Herdr pane <id>", else the working folder
    public static func find(variables: [String: String], workingDirectory: URL, processes: any ProcessTable) -> Holder
}

public struct ControlLease: Equatable, Sendable {
    public static let renewal: TimeInterval = 60, cap: TimeInterval = 300, bar: TimeInterval = 300
    public struct Term: Codable, Equatable, Sendable { var holder: Holder; var taken: Date; var ends: Date   // coded as seconds since 1970
        public func secondsLeft(at: Date) -> Int; public func held(timeZone: TimeZone) -> String }           // "you hold video-review until 12:05:00"
    public enum Transition { case started(Holder), renewed(Holder), ended(Holder, Ending) }
    public enum Ending { case expired, capped, released, stopped }
    public enum Refusal: Error { case inUse(Term), queued(Term), waitedOut(seconds: Int, Term), stopped
        public func message(at: Date, timeZone: TimeZone) -> String }
    public struct Decision { var answer: Result<Term, Refusal>; var transitions: [Transition] }

    public init()
    public init(environment: [String: String], at now: Date)          // a relaunch's handover, from VIDEO_REVIEW_CONTROL_LEASE
    public static func handover(_ term: Term) -> [String: String]     // what a relaunch adds to the launch environment
    public mutating func use(by: Holder, at: Date) -> Decision         // an operator command
    public mutating func take(by: Holder, at: Date, waitingUntil: Date?) -> Decision
    public mutating func giveUp(by: Holder, waited: Int, at: Date) -> Decision
    public mutating func release(by: Holder, at: Date) -> [Transition]
    public mutating func stop(at: Date) -> [Transition]                // the person's Stop
    public mutating func settle(at: Date) -> [Transition]              // ends what ran out, serves the line, lifts ended bars
    public func current(at: Date) -> Term?
    public func waiting(at: Date) -> Int
    public func nextEnd(after: Date) -> Date?                          // the held lease's end
    public func status(at: Date) -> LeaseStatus?
}
```

A holder is the same across commands by its `key` alone; its name and place are as its latest command gave them. The transitions are returned for tests and for a later notice; the app reads the lease's value, not the transitions.

**VRWire**

```swift
public enum ControlRequest: Equatable, Sendable {
    // free
    case appStatus, state, controlTake(waitSeconds: Int?), controlRelease
    // operator (leased)
    case appOpen, appQuit
    case playerOpen(path: String), playerPlay, playerPause, playerSeek(seconds: Double)
    case commentAdd(text: String, at: Double?, region: WireRegion?)
    case commentEdit(id: String, text: String), commentDelete(id: String)
    case batchSend
    case threadAnswer(commentID: String, text: String)
    case contextSet(text: String)
    case screenshot(path: String, appearance: Appearance?)
    // listener (no lease)
    case wait(timeoutSeconds: Int?)
    case ack(batchID: String, text: String?)
    case status(commentID: String, state: String)
    case reply(id: String, text: String)
    case ask(commentID: String, question: String, waitSeconds: Int?)

    public static let version = 1
    public enum Role { case free, operator, listener }
    public var role: Role
    public static let longestWait = 3600   // a take's wait in line, in seconds, at most
    public var wait: TimeInterval      // how long the app may hold the connection: a take's wait in line, else 0
    public var isLongPoll: Bool        // wait and ask: the app holds the connection and sends a heartbeat
    public struct WireRegion: Codable, Equatable { var x, y, w, h: Double }   // four numbers as --region gave them, not yet checked
}

public struct ControlMessage { var request: ControlRequest; var holder: Holder; var json: Bool
    public func encoded() -> Data
    public static func decode(_ data: Data) throws(ControlProtocolError) -> ControlMessage }

public struct ControlReply: Codable { var ok: Bool; var output: String; var error: String; var lease: ControlLease.Term? }

public struct ControlClient { var socket: URL; var holder: Holder; var transport: any ControlTransport
    public func send(_ request: ControlRequest, json: Bool) -> Result<ControlReply, Failure> }
```

Each ticket adds its own cases to `ControlRequest`. The first build ticket has `appStatus`, `state`, `appOpen`, `appQuit`, the four `player` cases and `screenshot`; the lease ticket adds `controlTake`, `controlRelease` and `wait`; the comment ticket adds the three `comment` cases, and the region ticket gives `commentAdd` its `region`; `isLongPoll` arrives with the listener's `wait`. `ControlClient.send` waits for a reply for its timeout (15 s) plus the request's `wait`. On the wire, `comment.add` carries `text`, for `--at` its `time`, and for `--region` a `region` object `{x, y, w, h}`; `comment.edit` carries `id` and `text`; `comment.delete` carries `id`.

`ControlMessage.decode` checks the version before it reads the holder or the command, so a request of another version is refused by its version whatever else it holds. A path on the wire (`player.open`, `screenshot`) must be absolute.

`WireRegion` is four numbers and no rule: `VRWire` cannot import `VRReview`, and the rule belongs to `Region`. `OperatorDesk` makes the `Region` from it, so a rectangle outside the frame is refused by the app in `Region`'s words, with exit 1.

On the socket a message is one flat JSON object, keys sorted: `{"command":"player.seek","holder":{…},"json":false,"time":10,"version":1}`. Command names are the CLI words joined by a dot (`comment.add`, `control.take`, `wait`).

`output` is always the exact text the CLI prints. The app formats it, as lines or as JSON when the message's `json` is true. So the CLI never needs the app's types, and `VRCommand` links only `VRWire` and `VRLease`.

**VRCommand**

```swift
public struct CommandResult { var output: String; var error: String; var status: Int32 }   // 0 ok, 1 refused, 2 usage, 3 timed out
public struct CommandTable { public static var standard: CommandTable; public mutating func add(_ entries: [Entry]); public func run(_ arguments: [String], environment: CommandEnvironment) -> CommandResult }
public struct CommandEnvironment { var variables; var workingDirectory; var transport; var launcher; var processes; var pause; public static func system() -> CommandEnvironment }
public protocol AppLaunching: Sendable { func launch(bundleID: String, environment: [String: String]) throws(AppLaunchFailure) }
```

Each `…Command.swift` has its `entry` for the table, `parse(_ arguments:) -> Result<ControlRequest, CommandResult>` and its usage text. All but `AppCommand` then go through one function, `CommandContext.send(_:)`, which maps a reply to a `CommandResult`. `CommandTable.run` takes `--json` out of the arguments wherever it stands, and answers `--help` and `--version` itself.

**VRReview**

```swift
public enum CommentState: String, Codable { case draft, queued, sent, acknowledged, working, done, failed }

public struct Region: Codable, Equatable { let x, y, w, h: Double      // 0..1, origin top left of the video frame
    public init(x:y:w:h:) throws(ReviewRefusal)                          // inside the frame, w and h above 0
    public var text: String                                              // "0.5,0,0.5,0.5", as --region takes it
    public func pixelRect(in size: CGSize) -> CGRect }                   // whole pixels, rounded outward, inside the frame

public struct ThreadMessage: Codable { var author: Author; var kind: Kind; var text: String; var at: Date
    public enum Author: String, Codable { case person, agent }
    public enum Kind: String, Codable { case message, question, answer } }

public struct Comment: Codable, Identifiable { var id: String; var time: Double; var text: String
    var region: Region?; var state: CommentState; var batchID: String?; var thread: [ThreadMessage] }

public struct Batch: Codable, Identifiable { var id: String; var sentAt: Date; var commentIDs: [String]; var thread: [ThreadMessage] }

public struct ReviewSession: Codable, Equatable {
    public var video: VideoInfo; public var note: String
    public private(set) var comments: [Comment]      // kept in time order
    public private(set) var batches: [Batch]

    public mutating func draft(id: String, time: Double, region: Region?) -> Comment
    public mutating func commit(_ id: String, text: String) throws(ReviewRefusal)         // draft → queued
    public mutating func discard(_ id: String) throws(ReviewRefusal)                      // a draft
    public mutating func edit(_ id: String, text: String) throws(ReviewRefusal)           // queued only
    public mutating func delete(_ id: String) throws(ReviewRefusal)                       // queued only
    public mutating func send(batchID: String, at: Date) throws(ReviewRefusal) -> Batch   // every queued → sent
    public mutating func acknowledge(_ batchID: String, text: String?, at: Date) throws(ReviewRefusal)
    public mutating func setStatus(_ id: String, to: CommentState) throws(ReviewRefusal)  // working, done, failed
    public mutating func reply(to id: String, text: String, at: Date) throws(ReviewRefusal)       // a comment or a batch
    public mutating func ask(_ id: String, question: String, at: Date) throws(ReviewRefusal)
    public mutating func answer(_ id: String, text: String, at: Date) throws(ReviewRefusal)       // needs an open question
    public mutating func requeue(_ batchID: String)                                        // unfinished → sent
    public func openQuestion(on id: String) -> ThreadMessage?
    public func isFinished(_ batchID: String) -> Bool
    public var queue: [Comment]
}

public struct Outbox: Codable, Equatable {
    public struct Parcel: Codable { var batchID: String; var videoHash: String; var delivery: Delivery }
    public enum Delivery: Codable { case pending, taken(by: String, at: Date) }
    public enum Presence: String, Codable { case absent, listening, working }

    public mutating func post(batchID: String, videoHash: String)                       // a batch was sent
    public mutating func arrive(_ listener: Holder, at: Date) -> [Parcel]               // a wait opened; returns the requeued
    public mutating func take(at: Date) -> Parcel?                                      // the next pending, for the open wait
    public mutating func undelivered(_ batchID: String)                                 // the reply could not be written
    public mutating func leave(at: Date, delivered: Bool)                               // the wait closed
    public mutating func finish(_ batchID: String)                                      // every comment done or failed
    public mutating func context(for videoHash: String, text: String?) -> String?       // the text, or nil when already sent
    public func presence(at: Date) -> Presence
}

public struct BatchPayload: Codable { … }     // exactly the spec's shape, see "The batch payload"
```

Each ticket adds its own fields and methods. After the region ticket, `Comment` is `id`, `time`, `text`, `region` and `state`, and `CommentState` has all seven states with `canMove(to:)`, the whole table of allowed moves. `ReviewSession` has `video`, `comments`, `queue`, `comment(_:)`, `draft(id:time:region:)`, `commit`, `discard`, `edit`, `delete` and `written(_:)`, the rule for a comment's text: trimmed, and not empty. `ReviewRefusal` is one line, `reason`. The batches, the threads and the note arrive with their tickets.

A region's parts are constants (`let`), so a `Region` that exists passed its rule; one read back from disk is trusted as it was kept. A part may reach past the frame's edge by rounding alone (a slack of 1e-9), and `pixelRect` snaps an edge that is whole but for rounding, so `0.3 × 1920` is 576 and not a pixel more.

**VRTranscript**

```swift
public struct TranscriptLine: Codable, Equatable, Sendable { var start: Double; var end: Double; var text: String }
public protocol Transcriber: Sendable {
    func lines(for video: URL, in window: ClosedRange<Double>) async throws -> [TranscriptLine]
}
public enum TranscriptWindow { static func around(_ time: Double, duration: Double) -> ClosedRange<Double>
                               static func cut(_ lines: [TranscriptLine], to: ClosedRange<Double>) -> [TranscriptLine] }
public enum TranscriptSources { case voiceover(URL), subtitles(URL), speech
    static func best(for video: URL) -> TranscriptSources          // the spec's order
    func transcriber(frameRate: Double, speech: any Transcriber) -> any Transcriber }
public struct VoiceoverSource: Transcriber { … }   // one line per scene; a scene lasts ceil((duration + padding) × fps) frames
public struct SubtitleSource: Transcriber { … }    // .srt and .vtt
```

**VRStore**

```swift
public struct Library: Sendable {
    public init(root: URL)
    public func session(for hash: String) throws -> ReviewSession?
    public func save(_ session: ReviewSession) throws
    public func outbox() throws -> Outbox;  public func save(_ outbox: Outbox) throws
    public func nextCommentID() throws -> String      // "c1", "c2", … across every video of this library
    public func nextBatchID() throws -> String        // "b1", "b2", …
    public func videoHash(forComment id: String) -> String?;  public func videoHash(forBatch id: String) -> String?
    public func keyframeURL(_ hash: String, comment: String) -> URL
    public func cropURL(_ hash: String, comment: String) -> URL
}
public enum ContentHash { static func of(_ file: URL) throws -> String }
public struct TranscriptCache { func load(_ hash: String) -> [TranscriptLine]?; func save(_ lines: [TranscriptLine], for hash: String) throws }
```

After the region ticket, `Library` has `init(root:)`, `nextCommentID()`, `keyframeURL(_:comment:)` and `cropURL(_:comment:)`, and `index.json` holds the next comment number only. An id that was given out is never given again, also when its draft was cancelled or its comment deleted, so ids may have gaps.

**VRApp**

```swift
@MainActor protocol Playing: AnyObject {            // AVPlayer in the app, a fake in VRAppTests
    var time: Double { get }; var isPlaying: Bool { get }
    func load(_ url: URL) async throws; func play(); func pause(); func seek(to: Double) async
}
protocol FrameGrabbing: Sendable {                  // AVAssetImageGenerator in the app, a fake in VRAppTests
    func writeKeyframe(of video: URL, at: Double, to: URL) async throws -> CGSize
    func writeCrop(of keyframe: URL, region: Region, to: URL) async throws
}

@MainActor @Observable final class ReviewModel {
    private(set) var video: VideoFile?              // the open video: its VideoInfo, frame rate and size
    private(set) var session: ReviewSession?        // the open video's
    private(set) var outbox: Outbox
    private(set) var selection: String?             // the selected comment
    private(set) var composing: String?             // the draft the comment box is open on
    private(set) var keyframes: Set<String>         // the comments whose keyframe is on disk
    private(set) var crops: Set<String>             // the comments whose region's crop is on disk
    private(set) var notices: [Notice]

    // what a person and an operator can do
    func open(_ url: URL) async throws(ModelRefusal)
    func play() async throws(ModelRefusal); func pause() throws(ModelRefusal); func seek(to: Double) async throws(ModelRefusal)
    func beginComment(at: Double?, region: Region?) throws(ModelRefusal) -> String
    func commitComment(_ id: String, text: String) throws(ModelRefusal)
    func discardComment(_ id: String) throws(ModelRefusal)
    func addComment(text: String, at: Double?, region: Region?) async throws(ModelRefusal) -> Comment
    func editComment(_ id: String, text: String) throws(ModelRefusal); func deleteComment(_ id: String) throws(ModelRefusal)
    func showComment(_ id: String) async throws(ModelRefusal)     // a click on a marker or a card: pause, seek, select
    func sendBatch() async throws(ModelRefusal) -> Batch
    func answer(_ commentID: String, text: String) throws(ModelRefusal)
    func setNote(_ text: String) throws(ModelRefusal)

    // what the listener can do (any video of the library, open or not)
    func payload(for parcel: Outbox.Parcel) async throws(ModelRefusal) -> BatchPayload
    func acknowledge(_ batchID: String, text: String?) throws(ModelRefusal)
    func setStatus(_ commentID: String, to: CommentState) throws(ModelRefusal)
    func reply(to id: String, text: String) throws(ModelRefusal)
    func ask(_ commentID: String, question: String) throws(ModelRefusal)
}
```

`Playing` and `FrameGrabbing` are the only interfaces in the app with a second implementation (the test fakes). `Screenshotter` is concrete; tests do not capture windows, so `OperatorDesk` takes the capture as a closure and the tests pass their own. `OperatorDesk` and `ListenerDesk` are concrete and tested through `ControlServer.reply(to:)`.

The video's length has one source, `VideoFile.info.duration` (the asset's, rounded to the millisecond), so `Playing` has no `duration`. `play` is `async` because playing at the end first seeks to the start. Beside the calls above, `ReviewModel` has a person's gestures (`openByPerson`, `togglePlay`, `scrub`, `skip`, `step`, `compose`, `commitComposer`, `cancelComposer`, `showByPerson`): the same calls with a time kept inside the video instead of refused, and a failed open kept in `openFailure` for the window's alert.

`beginComment` is not `async`: it makes the draft and starts one task that writes the keyframe and then, for a region, cuts the crop from it; `addComment` waits for that task. `writeCrop` is `async` so that reading, cutting and writing a full frame stays off the main actor. `comments` is what the views show: the open video's comments without the drafts. `keyframeURL(for:)` and `cropURL(for:)` are a comment's image files, or nil while they are not on disk. `marks` is the rectangles the stage draws now (`RegionMark.shown`).

The region's gestures are `beginDrawing()` (a drag started: pause; false while the comment box is open or no video is) and `compose(region:)` (the drag ended: the comment box on the rectangle). The geometry between the stage's points and a `Region` is not the model's: `FrameFit`, in `RegionOverlay.swift`, is a value the tests use without a window.

Until the persistence ticket, `ReviewModel` keeps the reviews of the videos opened in this run in memory, by content hash, so a video opened again in the same run has its comments. `Library` takes that over.

### The CLI contract as this build answers it

The commands are the spec's, unchanged. This table fixes what the spec left open: the text printed and the exit codes. With `--json`, every command prints one JSON object on one line.

| Command | Role | Prints (text) | Prints (`--json`) |
|---|---|---|---|
| `app status` | free | version, demo, lease, video, listener, one per line | `{running, version, variant, demo, lease, video, listener}` |
| `state` | free | the state as lines | the state object below |
| `control take [--wait <s>]` | free | `you hold video-review until 12:05:00` (the app's local time) | `{held: true, until}`, `until` in ISO 8601, UTC |
| `control release` | free | `released video-review` | `{released}`: `false` when the sender held nothing |
| `app open [--demo <folder>]` | operator | the status lines | the status object |
| `app quit` | operator | `video-review quit` | `{quit: true}` |
| `player open <path>` | operator | `opened <title> (0:21.233)` | `{video}` |
| `player play`, `player pause` | operator | `playing at 0:10.000`, `paused at 0:10.000` | `{playing, time}` |
| `player seek <t>` | operator | `at 0:10.000` | `{time}` |
| `comment add …` | operator | `c1 at 0:10.000` | the comment object |
| `comment edit`, `comment delete` | operator | `edited c1`, `deleted c1` | `{id}` |
| `batch send` | operator | `sent b1 with 2 comments` | `{id, sentAt, commentIds}` |
| `thread answer <id> <text>` | operator | `answered c1` | `{id}` |
| `context set <text>` | operator | `context note set` | `{note}` |
| `screenshot <abs.png> […]` | operator | the path | `{path}` |
| `wait [--timeout <s>]` | listener | the payload (always JSON) | the same |
| `ack <batch-id> [<text>]` | listener | `acknowledged b1` | `{id}` |
| `status <id> <state>` | listener | `c1 is working` | `{id, state}` |
| `reply <id> <text>` | listener | `replied on c1` | `{id}` |
| `ask <id> <question> [--wait <s>]` | listener | the answer's text | `{commentId, question, answer, answeredAt}` |

Exit codes: 0 done; 1 refused, app not running, or no reply; 2 usage; 3 a `wait` or `ask` whose time ran out (nothing on standard output). The reply shape stays `{ok, output, error, lease?}`: a long poll that ran out comes back `ok: true` with empty `output` and a note in `error`, and `ListenerCommand` turns exactly that into exit 3.

`control take --wait` takes whole seconds from 0 to 3600. A take refused or waited out exits 1, like every refusal. `control release` exits 0 whoever sends it. The holder key has no flag: `VIDEO_REVIEW_CONTROL_KEY` is the one way to name it (Shipyard's `--key` is not in the contract).

The comment object of `comment add --json` is the one in `state --json`'s `comments`. A comment's text is one argument; a second word is refused with exit 2 and the advice to quote it. An option starts with two dashes, so a text may start with one (`"-3 dB would be better"`). `--region` takes `x,y,w,h` as one argument: four numbers of digits and a dot, with spaces allowed around them. Anything else is refused with exit 2. Four numbers that are not a rectangle inside the frame are refused by the app with exit 1, and no comment is left. The text printed for a comment with a region is the same `c1 at 0:10.000`; the region and the crop's path are in `--json`.

Times are accepted as seconds (`10`, `10.5`) or `mm:ss` (`0:10`, `1:02.5`), also `h:mm:ss`. A time outside the video is refused. `screenshot` needs an absolute `.png` path whose folder exists. `player open` takes a relative path against the folder the command runs in.

`app status --json` gains its `listener` key with presence; until then it is `{running, version, variant, demo, lease, video}`.

`screenshot` captures the window from this process's own shareable content, which needs no Screen Recording permission. When the capture fails, the app draws the window's views itself, writes that, and says `captured by rendering: <why>` on standard error with exit 0; the video's frame is missing from such a file. One screenshot runs at a time, since each sets the app's appearance.

NOTE: ADR 0001 lists the listener commands as `done` and `fail`. The spec's contract has `status <comment-id> working|done|failed` instead. This build follows the spec.

### `state --json`

```json
{
  "app": {"version": "0.1.0", "variant": "proto-3", "demo": "/abs/demo/folder"},
  "lease": {"holder": "Claude Code", "place": "/abs/folder", "secondsLeft": 48, "waiting": 0},
  "listener": {"presence": "listening", "name": "Claude Code"},
  "video": {"path": "/abs/sample.mp4", "contentHash": "…", "duration": 21.233, "title": "sample"},
  "player": {"time": 10, "playing": false},
  "time": 10,
  "context": {"sidecarPath": "/abs/sample.context.md", "note": ""},
  "transcript": {"source": "voiceover", "ready": true, "lines": 3},
  "queue": ["c3"],
  "comments": [
    {"id": "c1", "time": 10, "text": "…", "state": "done", "batchId": "b1",
     "region": null, "keyframePath": "/abs/…/frames/c1.png", "cropPath": null,
     "thread": [{"author": "agent", "kind": "question", "text": "…", "at": "2026-10-04T12:00:00Z"}]}
  ],
  "batches": [{"id": "b1", "sentAt": "…", "commentIds": ["c1", "c2"], "delivery": "taken", "finished": true, "thread": []}]
}
```

The player's time is in two places with the same value: `player.time`, and a top-level `time` for a script that reads one field. Both are rounded to the millisecond.

Each key arrives with the ticket that builds what it reports. The first build ticket gives `app`, `lease`, `video`, `player` and `time`. The comment ticket gives `queue` and `comments`, each comment as `{id, time, text, state, keyframePath}`; the region ticket adds `region` and `cropPath`; `batchId` and `thread` arrive with their tickets.

`lease`, `video`, `demo`, `region`, `keyframePath` and `cropPath` are `null` when there is none, never left out. `cropPath` is `null` for a comment without a region, and until the PNG is on disk. `comments` is in time order and holds every comment of the open video, a draft included (state `draft`, empty text) while the comment box is open; `queue` holds the ids still `queued`, in time order. Both are `[]` with no video. `keyframePath` is `null` until the PNG is on disk. `state` as lines lists the comments only when there are some: `comments: 2, 1 queued`, then one line per comment, `  c1 queued at 0:10.000: <text>`. `StateReport` builds it from `ReviewModel`, `ControlLease` and `Outbox`.

### The batch payload

`BatchPayload` in `VRReview` is the spec's object and nothing more:

```json
{
  "batch": {"id": "b1", "sentAt": "2026-10-04T12:00:00Z"},
  "video": {"path": "/abs/sample.mp4", "contentHash": "…", "duration": 21.233, "title": "sample"},
  "context": "…or null",
  "comments": [
    {"id": "c1", "time": 10, "text": "…", "keyframePath": "/abs/…/frames/c1.png",
     "region": {"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.2}, "cropPath": "/abs/…/crops/c1.png",
     "transcript": [{"start": 6.067, "end": 14.333, "text": "…"}]}
  ]
}
```

### On disk

```text
~/Library/Application Support/Video Review (proto-3)/     AppIdentity.supportFolder(), or VIDEO_REVIEW_SUPPORT_DIR
  control.sock                 there only while the app runs, mode 0600
  demo.json                    the demo pointer: {version, support, folder}
  index.json                   next comment and batch numbers; comment id → hash; batch id → hash
  outbox.json                  the Outbox's parcels
  videos/<contentHash>/
    review.json                the ReviewSession
    transcript.json            the cached speech transcript
    frames/<comment-id>.png    the keyframe, at the video's natural size
    crops/<comment-id>.png     the region's crop
  d-<8 hex>/                   one demo run's support folder, the same layout inside
```

A demo run's support folder is inside the normal one, named by a hash of the demo folder's absolute path. So the demo folder itself (the tracked `fixtures/sample/`) is never written to, two demo folders never share data, and the socket path stays under the 103 bytes a Unix socket allows.

## 4. Implementation

### One CLI command, end to end: `video-review player seek 0:10`

```text
VRCLI/main.swift                         CommandTable.standard.run(["player","seek","0:10"])
└ VRCommand/CommandTable.run             finds the entry "player"
  └ PlayerCommand.parse                  Arguments.time("0:10") → 10.0 → .playerSeek(seconds: 10)
  └ CommandContext                       support = AppIdentity.supportFolder()
    ├ VRWire/ControlSocket.locate        demo.json names a demo and its socket exists → that socket
    ├ VRLease/Holder.find                CLAUDE_CODE_SESSION_ID set → key "CLAUDE_CODE_SESSION_ID=…"
    └ VRWire/ControlClient.send          {"command":"player.seek","holder":{…},"json":false,"time":10,"version":1}
      └ UnixSocketTransport.exchange     connect, write, shut down the write side, read to the end
        ┆ control.sock
VRApp/Control/SocketListener.serve       reads the request to its end
└ ControlServer.reply(to:)
  ├ ControlMessage.decode                version 1 = 1, holder present
  ├ request.role == .operator
  │ └ lease.use(by: holder, at: now)     free → Term(ends: now + 60) + [.started]
  │   └ LeaseIndicator                   the banner appears
  └ OperatorDesk.seek(10)
    └ ReviewModel.seek(to: 10)           video open? 0 ≤ 10 ≤ duration?
      └ PlayerController.seek(to: 10)    AVPlayer.seek, zero tolerance, awaited
  ← ControlReply(ok: true, output: "at 0:10.000\n")
SocketListener                           writes the reply, closes
VRCommand                                prints "at 0:10.000", exit 0
```

State after each step:

| Step | Lease | Player |
|---|---|---|
| before | free | time 0, paused |
| after `lease.use` | held by the caller, 60 s left | time 0 |
| after `PlayerController.seek` | the same | time 10 |
| `state --json` from any holder | reports the lease | `"player": {"time": 10, "playing": false}` |

`app open` is the one command that does not start at the socket: `AppCommand` launches the bundle `AppIdentity.bundleID` through `AppLaunching`, with `VIDEO_REVIEW_SUPPORT_DIR` and `VIDEO_REVIEW_DEMO_DIR` set for a demo, writes or removes `demo.json`, and polls `app.status` until the app answers. When an app of the other mode runs (the normal one, or a demo on another folder), it quits it first. `app open --demo` on the folder the running demo already uses sends `app.open` and launches nothing, so the open video stays.

When `app open` quits one app to launch another, the lease moves with it, as in Shipyard: the quit's reply carries the opener's term in `lease`, `AppCommand` puts it in the launched app's environment as `VIDEO_REVIEW_CONTROL_LEASE` (`ControlLease.handover`), and `AppServices` starts the server with `ControlLease(environment:at:)`. The term keeps when it was taken, so the 5 min cap is not started again.

### One rejection: a second holder

```text
holder B: video-review player play
└ ControlServer.reply(to:)
  └ lease.use(by: B, at: now)            term.holder.key ≠ B.key → .failure(.inUse(term))
  ← ControlReply(ok: false, error: "video-review is in use by Claude Code in /abs/folder until 12:05:00 (48s left);
                                    `video-review control take --wait <seconds>` to queue")
VRCommand                                prints the line on standard error, exit 1
```

Nothing reached `OperatorDesk`: the gate is before the dispatch, so a refused command changes nothing.

### One batch, from Cmd+Enter to `wait`

The listener is already waiting: `video-review wait` is parked in `ListenerDesk`.

```text
person presses Cmd+Enter                 (or: video-review batch send → OperatorDesk.sendBatch)
UI/SendBar                               ReviewModel.sendBatch()
└ ReviewModel.sendBatch
  ├ await pending frames                 every queued comment's keyframe and crop are on disk
  ├ Library.nextBatchID()                "b1"; index.json saved
  ├ session.send(batchID: "b1", at: now) c1, c2: queued → sent; Batch b1
  ├ outbox.post("b1", videoHash)         Parcel(b1, pending)
  ├ Library.save(session), save(outbox)
  └ ListenerDesk.outboxChanged()
    ├ a wait is parked → outbox.take(at: now)      Parcel(b1, taken(by: listener key))
    ├ ReviewModel.payload(for: parcel)
    │ ├ Library paths                    keyframePath, cropPath (absolute)
    │ ├ TranscriptService.lines(around:) TranscriptWindow.cut(known lines, to: time ± 15 s)
    │ ├ ContextSidecar.text + note
    │ │ └ outbox.context(for: hash, text)          first batch of this listener → the text; later → nil
    │ └ BatchPayload(…)                  the spec's object
    └ resume the parked connection       ControlReply(ok: true, output: <payload JSON>)
SocketListener                           writes the reply
├ written → outbox.leave(at: now, delivered: true); Library.save(outbox)
└ not written (the client is gone) → outbox.undelivered("b1"): the parcel is pending again
VRCommand/ListenerCommand                prints the payload, exit 0
```

State after each step:

| Step | c1, c2 | Parcel b1 | Presence |
|---|---|---|---|
| before | `queued` | none | `listening` |
| after `session.send` | `sent` | none | `listening` |
| after `outbox.post` | `sent` | `pending` | `listening` |
| after `outbox.take` | `sent` | `taken` | `working` |
| after `ack b1` | `acknowledged` | `taken` | `working` |
| after `status … done` on both | `done` | removed (`finish`) | `listening` when a `wait` is open, else `absent` |

When no `wait` is open, the trace stops after `outbox.post`: the parcel stays `pending` on disk. The next `wait` runs `ListenerDesk.wait`, which calls `outbox.arrive(listener, at:)` and then `outbox.take`, and answers at once.

### How a long poll is held

`wait`, `ask` and a queued `control take` keep their connection open. One request per connection still holds.

A queued `control take` is held the way Shipyard holds it, without the heartbeat below: `ControlServer` parks it as a continuation with a timer for its wait, and the client reads for its usual 15 s plus the wait. A client that went away shows when the reply granting it the lease can't be written; `SocketListener` then tells the server (`undelivered`), which releases that lease so the next in line gets it. The rest of this section is the listener's long polls.

- `ListenerDesk` parks the request as a continuation with a deadline, and `ControlServer` goes on answering other requests.
- While a connection is parked, `SocketListener` writes one space byte to it every 2 s. JSON ignores leading whitespace, so the reply still reads. A write that fails means the client is gone: the desk drops the parked request, and for a `wait` calls `outbox.leave(at:delivered: false)`, so presence turns `absent` within 2 s of a killed `wait`.
- The client's read gives up after 10 s without a byte, so a `wait` never outlives an app that died.
- `wait` without `--timeout` waits until a batch comes. `ask` without `--wait` waits until the answer comes.

### The rules that carry the logic

**The comment state machine** (`Comment.swift`)

```text
rank: draft 0, queued 1, sent 2, acknowledged 3, working 4, done 5, failed 5

commit:        draft → queued
send:          queued → sent                       (every queued comment of the video, one batch)
acknowledge:   sent → acknowledged                 (every comment of the batch still sent)
setStatus(s):  s ∈ {working, done, failed}; from sent, acknowledged or working; rank must not go down
               done and failed are final
requeue:       acknowledged, working → sent        (the only move backward)
edit, delete:  queued only                         refused: "c1 was sent; it can't be edited"
                                                   a draft: "c1 is still being written; it can't be edited"
commit, edit:  the text is trimmed                 refused when empty: "a comment needs its text"
discard:       a draft only                        removes it; its id is not used again
any of them:   an id the video doesn't have        refused: "there's no comment c9"
```

`CommentState.canMove(to:)` is the table of these moves, and `ReviewSession` asks it before it changes a comment's state.

A status may skip forward (`acknowledged → done`), because the acceptance scenario sets comments to `done` straight after `ack`.

**Questions and answers** (`ReviewSession.swift`)

```text
ask(id, question):   appends agent/question. Refused when a question on that comment is still open.
answer(id, text):    appends person/answer. Refused when no question is open.
ListenerDesk.ask:    session.ask → park the connection → on answer: reply with the answer's text.
                     Time ran out → ok with empty output (exit 3); the question stays open.
                     ask again on a comment whose question was answered after the time ran out
                     → the answer comes back at once, and is given once.
```

The person and `thread answer` both end in `ReviewModel.answer`, which resumes the parked `ask`.

**The outbox** (`Outbox.swift`)

```text
arrive(listener, at):
    if listener.key ≠ the last listener's key:            // a new listener session
        every parcel taken by another key → pending       // and ReviewSession.requeue for its batch
        forget the context already sent
    remember the listener; a wait is open
take(at):       the oldest pending parcel → taken(by: listener key, at)
undelivered:    that parcel → pending; forget its video's context if this delivery carried it
leave(at, delivered):  no wait is open; remember when, and whether a batch was delivered
finish(batch):  remove the parcel
context(hash, text):   digest(text) ≠ the digest remembered for hash → remember it, return text; else nil

presence(at):
    a wait is open, or one closed with a delivery less than 30 s ago:
        any parcel taken by this listener → working, else listening
    else absent
```

The same listener running `wait` again while its batch is in work gets no second copy: only a different key requeues. The 30 s after a delivered batch cover the moment between the listener reading a batch and starting `wait` again. Parcels persist in `outbox.json`; the listener and the context memory do not, so a restarted app sends the context again.

A requeued batch is delivered again with the comments that are not `done` or `failed`.

**The lease gate** (`ControlServer.swift`), as Shipyard's:

```text
reply(to data):
    message = decode(data)                 → refused: unreadable, other version, unknown command
    if message.request.role == .operator:
        decision = lease.use(by: holder, at: now)
        refused → reply(refusal.message); nothing else runs
    switch message.request: free → self; operator → OperatorDesk; listener → ListenerDesk

control.take:    lease.take(by: holder, at: now, waitingUntil: now + wait)
                 held → reply at once; in use and no wait → refused; queued → park the connection
control.release: lease.release(by: holder, at: now)

every change of the lease (leaseChanged):
    LeaseIndicator.lease = lease                          // the banner redraws
    a parked take whose holder now has the lease → answered "you hold video-review until …"
    a timer for lease.nextEnd(after: now) → lease.settle(at: now)
```

The banner's Stop calls `ControlServer.stopLease`, which calls `lease.stop(at:)`: the lease ends, its holder is barred for 5 min, and the first waiter gets it. Stop is the person's only way into the lease and has no CLI command, since it is the person's override of agents. The timer's `settle` makes the banner go and hands the lease to the next waiter with no request. `LeaseBanner` also redraws each second from the lease's value and the time, so the countdown ticks and the strip goes at the end by itself.

`app status` and `state` are free: any holder gets them, they renew nothing, and they report `lease.status(at: now)`.

**Keyframe and crop** (`FrameGrabber.swift`)

```text
writeKeyframe(video, at t, to url):  AVAssetImageGenerator, zero tolerance before and after, the track's
                                     natural size with its transform applied → PNG
writeCrop(keyframe, region, to url): read the keyframe's PNG, cut region.pixelRect(in: its size) → PNG
```

The keyframe comes from the asset, never from the screen, and the crop is cut from the keyframe's file. So a comment from the UI and one from the CLI at the same time and region give the same pixels, at any window size: both end in `beginComment(at:region:)`, and a test compares the two crops' pixels. The tests compare decoded pixels, not file bytes: two PNGs written from one frame sometimes differ in their bytes (seen in about one test run in three on this Mac) and never in what they show. `beginComment` starts the grab when the composer opens; `sendBatch` and `comment add` wait for it.

- A comment's time is the player's time (or `--at`) rounded to the millisecond, and the keyframe is the frame the video shows at that time: the last frame that starts at or before it.
- At the video's very end no frame starts exactly there, and the zero-tolerance read fails. The grabber then reads again with one second of tolerance before the time, which gives the last frame.
- A draft that is cancelled, and a comment that is deleted, lose their PNGs, the crop too. A write still running when its comment is dropped removes its files when it lands.
- `comment add` whose keyframe or crop cannot be written is refused and leaves no comment and no file. A comment from the window whose crop cannot be written stays, with `cropPath: null`.
- A comment from the window whose keyframe cannot be written stays queued with `keyframePath: null`; the batch ticket decides what `sendBatch` does with it.

**The region in the view** (`RegionOverlay.swift`)

```text
FrameFit(video size, stage size):   frame = the video's rectangle in the stage, fitted whole and centred
                                    (what AVPlayerView's resizeAspect shows)
rect(for region):                   frame.origin + region × frame.size
selection(from a, to b):            the rectangle between the two points, each kept inside frame
region(from a, to b):               selection under 8 points on a side → nil (a click)
                                    else (selection − frame.origin) ÷ frame.size, each part kept to 1/10000

RegionMark.shown(comments, selection, composing, time):
    a draft's region   → only the draft the comment box is open on
    a comment's region → when its card is selected, or the player is within 0.5 s of its time

ComposerPlacement.centre(box, beside rect, in stage), with a 12 point gap:
    right of rect when the box fits there, else left, else below, else the stage's bottom centre
    beside: level with rect's top; below: centred under it; always kept inside the stage
```

`Stage` makes one `FrameFit` from its own size on every layout and hands it to `RegionOverlay`, which draws every mark through `rect(for:)`. So a stored region is redrawn from its normalized values whenever the window changes, and stays on the same part of the picture. A drag draws through the same `FrameFit`: the first movement calls `ReviewModel.beginDrawing` (pause), the frame around the rectangle dims while it is drawn, and the release calls `compose(region:)`. The drag in progress is the view's own state; everything it computes is `FrameFit`'s. The comment box measures itself (`onGeometryChange`) and is placed by `ComposerPlacement`.

**The transcript** (`TranscriptService.swift`, `VRTranscript`)

```text
on open:   source = TranscriptSources.best(for: video)
               1. voiceover.json in the video's folder
               2. <base>.srt, else <base>.vtt
               3. speech
           sidecar → parse now, all lines known
           speech  → TranscriptCache.load(hash), else SpeechSource in a background task,
                     lines added as they come, saved to the cache at the end
window:    TranscriptWindow.around(t, duration) = max(0, t − 15) … min(duration, t + 15)
           TranscriptWindow.cut = every known line that overlaps the window, whole, in order
```

A comment made before speech finished gets the lines that exist at send time. `VoiceoverSource` gives one line per scene: a scene lasts `ceil((durationSeconds + paddingSeconds) × fps)` frames and starts where the previous one ends; `fps` is the video track's nominal frame rate.

**The context** (`ContextSidecar.swift`): `<base>.context.md` beside the video, else `context.md` in the same folder. The payload's text is the sidecar's text, then the note under the heading `## Reviewer's note` when the note is not empty. `null` when both are empty or `Outbox.context` says it was sent.

**The content hash** (`ContentHash.swift`): SHA-256 over the file's byte count, its first 4 MiB and its last 4 MiB, as lowercase hex. A file of 8 MiB or less is hashed whole. A renamed or moved copy has the same hash; `review.json` keeps the last path seen.

**Opening a video** (`ReviewModel.open`)

```text
VideoFile.read(url)          playable? duration, frame rate, title (the file's base name), ContentHash
Library.session(for: hash)   the history, or a new ReviewSession
player.load(url), paused at 0
TranscriptService.start      in the background
```

### Adding a CLI command

1. Add the case to `ControlRequest`, its role, and its wire name and fields in `ControlMessage` (`VRWire`).
2. Add its parsing and usage to the matching `…Command.swift` and, for a new first word, one entry in `CommandTable.standard` (`VRCommand`).
3. Add the method to `ReviewModel` and call it from `OperatorDesk` or `ListenerDesk`, with one more `case` in `ControlServer`'s dispatch (`VRApp`).
4. Call the same `ReviewModel` method from the view.

## 5. Extensibility

| Change | What you touch |
|---|---|
| Drop the `proto-3` suffix | `AppIdentity.variant = ""`. Nothing else. |
| A better transcriber (the transcription research) | A new `Transcriber` in `VRApp/Transcript/` or `VRTranscript`, chosen in `TranscriptSources.transcriber`. |
| A new transcript sidecar format | A new source file in `VRTranscript` and one line in `TranscriptSources.best`. |
| A new CLI command | The four steps above. |
| A new comment state | `CommentState` and its rank; `Theme` for its colour and glyph. |
| A new field in the payload | `BatchPayload` and its assembly in `ReviewModel.payload`. |
| Shapes other than rectangles | `Region` becomes an enum; `RegionOverlay` and `FrameGrabber.writeCrop` follow. The wire's `--region` stays. |
| More than one listener | `Outbox` keeps a set of listeners instead of one; `take` picks per listener. `ListenerDesk` already parks any number of connections. |
| Person messages that are not answers | A new kind of delivery to the listener. The payload has no place for it, so it needs a contract change first. |
| A system notification for an agent message | `Notice` is already one value per message; post it from `ReviewModel` where the toast is raised. |
| Undo of an edit or delete | Every change goes through `ReviewSession`'s methods, so keeping the previous value there is enough. |

Refused for now, because no requirement needs them: a plugin interface for sources, a database instead of JSON files, a protocol for the store, more than one window.

## UX choices of this prototype

The CLI contract, the payload and the item states are the spec's. Everything below is this prototype's own choice.

| Choice | Reason |
|---|---|
| One window, one video at a time. | The task is one review at a time, and the CLI's `state` then has one obvious subject. |
| Two columns: the stage on the left, a 340 pt review sidebar on the right. | The video keeps its size while threads grow. Answers stay beside the feedback without covering the frame. |
| The stage is black in light and dark; only the chrome follows the appearance. | Video is judged against black, as in QuickTime. Light mode should not change how the frame looks. |
| `AVPlayerView` with its controls off, and our own transport bar. | The built-in scrubber cannot show markers. Playback itself stays AVKit's. |
| Keys: Space or K play and pause, ← and → 5 s, `,` and `.` one frame, C comment, Cmd+O open. | The keys QuickTime and editors use, so nothing is new to learn. |
| C pauses and opens the comment box in one keystroke, already focused. | "Pause and type at once" is the main action, so it costs one key. Wispr Flow dictates into the focused box. |
| A drag on the frame draws a rectangle with a dimmed surround, like Cmd+Shift+4. It pauses the video when the drag starts (after 4 points of movement), not when it ends. | The gesture the person already knows. No tool to pick first. The rectangle lands on the frame the person points at, not on one a moment later. |
| A click, or a rectangle under 8 points on a side, opens nothing. The video stays paused when the pointer moved. | A slip of the hand is not a region. |
| While the comment box is open, a drag on the frame draws nothing. Escape first, then draw again. | One draft at a time, and what was typed is never thrown away by a stray drag. |
| The rectangle being drawn, and the one the comment box is open on, are white with the frame dimmed around them. A saved region is an outline in the accent colour with nothing dimmed. Both have a dark edge under them. | The dim says "you are choosing"; a saved region must not hide the frame. The dark edge keeps the line readable on a light frame. |
| A region comment's card shows the crop as its thumbnail and a small dashed-rectangle glyph beside its state. | The card shows what was pointed at, and region comments stand out in the list. |
| The comment box opens beside the rectangle (right, else left, else below), 320 points wide, and at the bottom centre of the stage for a comment without a region. A rectangle that leaves no room on any side gets the box at the bottom centre too, over it. | Writing happens where the person points, and the box never covers the region while a side has room. |
| In the comment box, Enter queues the comment, Shift+Enter adds a line, Escape cancels. | Fast for one-line notes. Escape also removes the rectangle. |
| Escape also cancels the open comment box when the focus is on the player, not in the box. With no box open, Escape is left to the window. | A click on the stage takes the focus out of the box; Escape must still cancel the region. |
| Cmd+Enter sends from anywhere, also from inside the comment box (it queues the open comment first). | One keystroke delivers the feedback, as the spec asks, with no need to leave the box. |
| Player keys are ignored while a text view has focus. | Typing "k" in a comment must not pause the video. |
| The transport bar has a comment button beside the video's length. | The same action as C, for the mouse. |
| Markers are pins above the scrubber track. A click seeks, pauses and selects the comment's card. | Pins do not hide the played part of the track. The card and the frame show together. |
| A click on a card does what a click on its marker does. | One way to see a comment's moment, from either place. |
| A draft has no marker and no card; the open comment box stands for it. | A marker is feedback that exists. The draft still shows in `state --json`, so an operator sees the box is open. |
| A queued card has an edit and a delete button. Edit turns the card's text into a text box with Save and Cancel. Delete asks nothing. | The fix happens where the mistake shows. A queued comment is cheap to write again. |
| Each state has a colour and a glyph: queued (grey ring), sent (blue arrow), acknowledged (blue check), working (orange dots, pulsing), done (green check), failed (red cross). | Status reads at a glance and does not depend on colour alone. |
| A region comment's rectangle shows on the frame only while its card is selected or the playhead is within 0.5 s of it. | The frame stays clean while watching. |
| The sidebar lists comments in time order, with the keyframe (or crop) as a thumbnail. | Time order matches the timeline. The thumbnail shows what the comment is about. |
| A thread shows inside its comment's card. An open question turns the card's edge orange and shows an answer box in it. | Answers stay next to the feedback, and a waiting agent is hard to miss. |
| A batch shows as a header card above its comments' first one, with its own thread. | The spec's message for the full batch needs a place that is not one comment. |
| An agent message raises a toast at the top right of the stage for 5 s. A click selects its comment. | Seen while watching, gone without a click, and it never pauses the video. |
| The send bar at the bottom of the sidebar shows the queued count, the Send button and the presence chip (`No listener`, `Listening`, `Working`). | The person sees whether the batch will reach someone at the moment of sending. |
| Sending with no listener is allowed; the bar then says the batch waits for the next listener. | The spec's story 15. No dialog in the way. |
| The lease banner is a one-line strip under the title bar, over whatever the window shows (the empty state too): "Claude Code controls this app", the place (a folder's last component), the time left, how many wait, Stop. It is tinted orange. | Always visible while an agent drives, and it takes one line. |
| Stop is a button in the banner only: no menu item, no key, no CLI command. A stopped agent is told to ask the person; nothing in the window lists it. | Stop is the person's override, so an agent can't reach it. A bar ends by itself after 5 min. |
| Screenshots show the window as it is, banner included. | A screenshot is evidence of what the person sees. The contract has no flag to hide it. |
| The context note is a popover from a toolbar button, with the sidecar's text above it, read-only. | Context is set once per video, so it should not take sidebar space. |
| With no video: a drop target, an Open button, and in a demo run the demo folder's videos as a list. | An operator still uses `player open`; a person in a demo gets one click. |
| System colours, materials and SF Symbols only. | Light and dark both work without a second palette. |
| `comment add` from the CLI pauses the video, and seeks first when `--at` is given. Its comment is selected, so a region given with it shows on the stage. | The window then shows what the operator did, as if a person had done it. |
| A region drawn in the window is kept to four decimals per part. One from `--region` is kept as given. | A ten-thousandth of the frame is finer than a pixel of any video, and the numbers stay short in `state --json` and the payload. |

## Which ticket builds what

| Ticket | Builds |
|---|---|
| #3 | `Package.swift`, `Makefile`, `Packaging/`, `VRWire`, `VRCommand` (app, state, player, screenshot), `VRLease/Holder` and `ProcessTable`, a pass-through `ControlLease` and `LeaseStatus`, `VRReview/VideoInfo`, `VRStore/ContentHash`, `VRApp` shell: `AppServices`, `ReviewModel` (the player's part), `ControlServer`, `SocketListener`, `OperatorDesk`, `StateReport`, `Screenshotter`, `Player/` without `FrameGrabber`, `TimeText`, `MainWindow`, `EmptyState`, `Stage`, `TransportBar`, `Timeline` (the scrubber), `Shortcuts` (the player's keys), `Theme` |
| #4 | `ControlLease`, `control take` and `release` (`ControlCommand`), the gate with its timer and line of takes, the lease's handover on a relaunch, `LeaseIndicator`, `LeaseBanner` |
| #5 | `VRReview` (`Comment`, `CommentState`, `ReviewSession`), `FrameGrabber` (keyframes), `Composer`, `Timeline` markers, `Sidebar`, `CommentCard`, the C key and `KeyFocus`, `comment` commands, `queue` and `comments` in `state`; `Library` (comment ids, frame paths) and `JSONFile` |
| #6 | `Region`, `WireRegion`, `RegionOverlay` (`FrameFit`, `RegionMark`, `ComposerPlacement`), crops (`writeCrop`, `Library.cropURL`), `--region`, `region` and `cropPath` in `state`, the Escape key on the player |
| #7 | `Batch`, `Outbox`, `BatchPayload`, `ListenerDesk`, long polls, `wait`, `batch send`, `SendBar`, presence |
| #8 | `VRTranscript`, `TranscriptService`, `SpeechSource`, `TranscriptCache` |
| #9 | `ContextSidecar`, the note, `ContextPopover`, `context set`, `Outbox.context` |
| #10 | `ack`, `status`, `reply`, `ask`, `thread answer`, threads in cards, `BatchCard`, the toast |
| #11 | The rest of `VRStore`: `review.json`, `outbox.json`, `index.json`, `ContentHash`, reload on open |
| #12 | `.agents/skills/video-review-mate/SKILL.md` |
| #13 | `scripts/acceptance.sh`, `assets/screenshots/` |

Before #11, `Library` already exists (#5 needs image paths and ids): it keeps the comment counter and the keyframes on disk, and `ReviewModel` keeps the sessions in memory for the run. #11 moves the sessions into `Library` and adds reload on launch. Tickets may move a file's first appearance earlier, never its owner.
