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
| change what a listening agent does with a batch | `.agents/skills/video-review-mate/SKILL.md` and [The listener skill](#the-listener-skill) |
| change the look | `Sources/VRApp/UI/` and [UX choices](#ux-choices-of-this-prototype) |
| prove the build end to end | `scripts/acceptance.sh` and [The acceptance scenario](#the-acceptance-scenario) |
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
12. Keep comments, batches, threads and statuses on disk, keyed by the video's content hash. Open the video that was open last again at launch, so the history shows after a restart.
13. Let an agent do everything a person can through the `video-review` CLI, one operator at a time under the lease.
14. Report what the app shows as JSON (`state --json`) and as a PNG of its window in light or dark.
15. Run on demo data in a separate support folder.

### Rules and completion

- A comment moves only forward: `draft → queued → sent → acknowledged → working → done | failed`. `done` and `failed` are final. The one move backward is a requeue (see rule below).
- A batch is finished when every comment in it is `done` or `failed`.
- A batch a listener took and did not finish goes back in the queue when another listener session arrives, and when the app starts again. Its unfinished comments go back to `sent`.
- Every change to a review or to the outbox is on disk before its command answers. Nothing is saved at quit, so a crash loses nothing. A draft is not kept.
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
| `ReviewSession` | VRReview | one video's comments, batches, threads, note and the answers no `ask` heard yet | the comment state machine, what may be edited, sent, asked, answered |
| `Outbox` | VRReview | sent batches not finished (`Parcel`s), the listener, the context already sent | which batch a `wait` gets, requeue, presence, context once |
| `Library` | VRStore | the support folder | where each file is, id counters, id → video lookup, what is kept of a review (no drafts), which video was open last |
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
ReviewModel ─owns→ ReviewSession (the open video's; others read from Library on demand)
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

`Package.swift` has the eight targets of the table, with the dependencies the table names and no others. `VRStore` depends on `VRReview` because `Library` keeps the reviews and the outbox's parcels, and on `VRTranscript` because `TranscriptCache` keeps transcript lines. `VRReview` and `VRTranscript` depend on nothing, so neither knows the store, the wire or the app.

Agent-side modules (`VRLease`, `VRWire`, `VRCommand`) never import an app-side module. `VRCommand` is a library and `VRCLI` is a thin executable so the command table tests without a process, as in Shipyard. `VRCommand` imports AppKit only for `NSWorkspace` (to launch the app); it has no UI code.

Test targets, all run by `make test` without the app:

| Target | Tests |
|---|---|
| `VRLeaseTests` | time-driven lease tables (take, renew, expire, cap, queue, stop, bar), holder discovery with a fake process table |
| `VRWireTests` | encode and decode of every request, version refusal, a path that is relative or (for a screenshot) not a `.png` refused, demo pointer, socket location |
| `VRCommandTests` | parsing, output and exit codes through `CommandTable.run` with a fake transport and launcher |
| `VRReviewTests` | the state machine, batch assembly, the outbox (delivery, requeue, presence, context once, an app restart), the payload's JSON, the threads (ack, each status, replies, questions and answers, the answer no `ask` heard yet, owed to the same question and not to another) |
| `VRTranscriptTests` | the window cut, the source order, `voiceover.json` scene times, `.srt` and `.vtt` parsing, against `fixtures/sample/` |
| `VRStoreTests` | in a temporary folder: a review and the outbox's parcels saved and read back, a draft not kept, the index's id → video lookup, images of no comment removed, two libraries sharing nothing; the content hash of a renamed copy, id counters, the transcript cache, the last open video |
| `VRAppTests` | `ControlServer.reply(to:)` with a fake player, a fake frame grabber, a clock the test sets and moves (`FakeClock`, which is also the app's `Later`, so no test waits for real seconds) and a temporary library: lease gate, takes in line, a take's wait and the lease running out, Stop, the banner's words, dispatch, comments, a parked `wait` and its time running out, the listener's answers (`ack`, `status`, `reply`), a parked `ask` answered by `thread answer` and by the answer box's model call, a new question not answered by an old answer, notices and their going, the sidebar's rows; the context (`ContextTests`): the sidecar found beside the video and its fallback, the note set, cleared and kept per video, the context in the payload once per listener session and again when the sidecar or the note changed, `context` in `state`, the toolbar button's tooltip; the command against the server over a real socket; `FrameGrabber` (keyframes and crops) against `fixtures/sample/sample.mp4`; the key routing; the region's geometry without a window: `FrameFit` at several stage sizes, a drag to a region, which regions show (`RegionMark`), where the comment box goes (`ComposerPlacement`); the transcript in the payload and in `state` with a recognizer the test holds back (`TranscriptTests`): the fixture's voiceover, a copy with only the `.srt`, a copy with no sidecar sent before and after speech is ready, the cache, a failure; an app started again on the same library (`PersistenceTests`): the same `state` after a restart with no `player open` (the last open video is open again, paused at 0), a last video that is gone or changed (no video, no error), a renamed copy, each change on disk before its command answers, a pending and a taken batch delivered after a restart, an answer still owed, an open question, a parcel a crash left, a review that can't be read |

The tests that wait for work they can't await (a task a gesture started, a frame written off the main actor, a command on a real socket) share one helper, `settle(until:)` in `Tests/VRAppTests/Settle.swift`. It looks every millisecond and records an issue at the caller's line after 5 seconds, so a wait that timed out never passes as one that settled. Nothing else in the tests sleeps.

### Folder tree

```text
Package.swift                       targets above
Makefile                            build, test, bundle, install, acceptance, clean; reads the variant and version
Packaging/
  Info.plist                        template: __NAME__, __BUNDLE_ID__, __VERSION__; movie document types
scripts/
  acceptance.sh                     the v1 acceptance scenario through the installed CLI (ticket #13)
assets/screenshots/
  v1-acceptance/                    light.png and dark.png: the window at the scenario's end
.agents/skills/video-review-mate/
  SKILL.md                          the listener skill (ticket #12): the procedure
  mate.sh                           the CLI under one listener key; `listen` is wait, then ack
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
    Transcriber.swift               the interface: video + window → lines; TranscriptFailure; a line as every source gives it (tidy)
    TranscriptSources.swift         the source order: which sidecars a video has, and what reads each
    VoiceoverSource.swift           voiceover.json: scene times from scene lengths
    SubtitleSource.swift            .srt and .vtt parsing
  VRStore/
    Library.swift                   the support folder: sessions, outbox, index, ids, image paths, the last open video
    ContentHash.swift               a video file's hash
    TranscriptCache.swift           a video's speech transcript on disk
    JSONFile.swift                  atomic read and write of one Codable file
  VRApp/
    VideoReviewApp.swift            @main, the window scene with the lease banner over it, the menu commands
    AppServices.swift               composition root: reads the environment, builds and wires everything
    ReviewModel.swift               the orchestrator the views and the desks call
    Notice.swift                    a brief notice of one agent message, shown over the stage
    TimeText.swift                  a time as text (0:10.000, 0:10) and rounded to the millisecond
    Later.swift                     a call made once a time has passed: a sleeping task in the app, the test's clock in tests
    PNGFile.swift                   a picture written as a PNG file: keyframes, crops and screenshots
    Player/
      PlayerController.swift        Playing protocol and its AVPlayer implementation
      PlayerSurface.swift           AVPlayerView without controls, as a SwiftUI view
      VideoFile.swift               opening a file: playable check, duration, frame rate, title, hash
      FrameGrabber.swift            FrameGrabbing protocol; keyframe and crop PNGs (PNGFile) from the asset
    Transcript/
      TranscriptService.swift       resolves the source on open, runs speech in the background, answers windows
      SpeechSource.swift            Transcriber over Apple SpeechAnalyzer
    Context/
      ContextSidecar.swift          <base>.context.md, else context.md, beside the video, read fresh; the context's text (the sidecar, then the note under its heading)
    Control/
      ControlServer.swift           decode, version, lease gate, dispatch; lease timers and waiters
      SocketListener.swift          the listening socket: accept, read, answer, heartbeat (Pulse), close; says how writing a reply went that a lease or a batch hangs on
      OperatorDesk.swift            operator requests → ReviewModel calls → reply text
      ListenerDesk.swift            listener requests: ack, status, reply; parked wait and ask connections
      StateReport.swift             app status and state as text and JSON
      LeaseIndicator.swift          the lease as the banner reads it, and the banner's words
      Screenshotter.swift           the window as a PNG (PNGFile) through ScreenCaptureKit, in an appearance
    UI/
      MainWindow.swift              stage and sidebar laid out
      EmptyState.swift              no video open: drop, open, the demo folder's videos
      Stage.swift                   the video, the overlay, the composer, the notices
      RegionOverlay.swift           drawing and showing rectangles in frame coordinates: FrameFit (the frame inside the stage), RegionMark (which regions show), ComposerPlacement (the box beside a region), the overlay view
      Composer.swift                the comment box
      TransportBar.swift            play, time, the timeline
      Timeline.swift                the scrubber track and the marker pins
      Sidebar.swift                 batch cards and comment cards in time order (Sidebar.rows)
      CommentCard.swift             one comment: time, status, text, thumbnail, thread, answer box
      BatchCard.swift               one batch: its header, where it is (BatchCard.Progress) and its thread
      ThreadView.swift              a thread's messages inside a card; AnswerBox, the box under an open question
      NoticeToast.swift             the notices of agent messages at the stage's top right
      SendBar.swift                 queued count, Send, the presence chip
      LeaseBanner.swift             who controls the app, time left, Stop
      ContextPopover.swift          ContextButton (the toolbar's button and its tooltip) and the popover: the sidecar's text and the editable note
      Shortcuts.swift               the player's keys (PlayerKey, Escape among them), Cmd+Enter (SendKey) and where the focus is (KeyFocus): given up in a panel, under a sheet and while a text view has focus
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
- `make acceptance`: runs `scripts/acceptance.sh` against what is installed, so `make install` comes first. It does not depend on `install`: the script also runs against another build's CLI. See [The acceptance scenario](#the-acceptance-scenario).
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

A holder is the same across commands by its `key` alone; its name and place are as its latest command gave them. The app shows the lease from its value (`current`, `status`, `nextEnd`). It reads the transitions in one place: `control release` answers `released: true` only when `release`'s transitions hold `.ended(<the sender>, .released)`, so a sender that held nothing gets `false`. The other transitions are returned for the tests and for a later notice.

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
    public static let longestTimeout = 86_400   // a wait's --timeout and an ask's --wait, in seconds, at most
    public static let statuses = ["working", "done", "failed"]   // what status sets; the wire can't name CommentState
    public var hold: TimeInterval      // how long the app may hold the connection: a take's wait in line, else 0
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

Each ticket adds its own cases to `ControlRequest`. The first build ticket has `appStatus`, `state`, `appOpen`, `appQuit`, the four `player` cases and `screenshot`; the lease ticket adds `controlTake`, `controlRelease` and `hold`; the comment ticket adds the three `comment` cases, and the region ticket gives `commentAdd` its `region`; the batch ticket adds `batchSend`, `wait(timeoutSeconds:)` and `isLongPoll`; the answers ticket adds `ack`, `status`, `reply`, `ask` and `threadAnswer`, and makes `ask` a long poll. The property is `hold`, not `wait`, because an enum can't have a case and a property of one name. `ControlClient.send` waits for a reply for its timeout (15 s) plus the request's `hold`; for a long poll it waits as long as the connection isn't silent for 10 s (`ControlClient.longestSilence`). On the wire, `wait` carries `timeoutSeconds` when `--timeout` is given (0 to 86400); `batch.send` carries nothing; `comment.add` carries `text`, for `--at` its `time`, and for `--region` a `region` object `{x, y, w, h}`; `comment.edit` carries `id` and `text`; `comment.delete` carries `id`; `ack` carries `id` and, when a text is given, `text`; `status` carries `id` and `state` (one of `ControlRequest.statuses`, anything else is refused as unreadable); `reply` and `thread.answer` carry `id` and `text`; `ask` carries `id`, `text` (the question) and, for `--wait`, `waitSeconds` (0 to 86400).

`ControlMessage.decode` checks the version before it reads the holder or the command, so a request of another version is refused by its version whatever else it holds. A path on the wire (`player.open`, `screenshot`) must be absolute, and a `screenshot`'s must end in `.png` (in any case): the app answers whoever can write to its socket, not only the `video-review` command, and it writes a PNG whatever the name says. Both are refused as unreadable, before the lease is asked.

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
    var region: Region?; var state: CommentState; var batchID: String?; var thread: [ThreadMessage]
    public var openQuestion: ThreadMessage? }                            // the last question, while no answer follows it

public struct Batch: Codable, Identifiable { var id: String; var sentAt: Date; var commentIDs: [String]; var thread: [ThreadMessage] }

public struct ReviewSession: Codable, Equatable {
    public var video: VideoInfo; public private(set) var note: String    // "" with none
    public mutating func setNote(_ text: String)     // trimmed; an empty text takes the note away
    public private(set) var comments: [Comment]      // kept in time order
    public private(set) var batches: [Batch]
    public private(set) var unheard: Set<String>     // the comments whose last answer no ask was given yet
    public var kept: ReviewSession                   // the review as the store keeps it: without its drafts
    public struct Exchange { var question: ThreadMessage; var answer: ThreadMessage }
    public enum Place { case comment(String), batch(String) }

    public mutating func draft(id: String, time: Double, region: Region?) -> Comment
    public mutating func commit(_ id: String, text: String) throws(ReviewRefusal)         // draft → queued
    public mutating func discard(_ id: String) throws(ReviewRefusal)                      // a draft
    public mutating func edit(_ id: String, text: String) throws(ReviewRefusal)           // queued only
    public mutating func delete(_ id: String) throws(ReviewRefusal)                       // queued only
    public mutating func send(batchID: String, at: Date) throws(ReviewRefusal) -> Batch   // every queued → sent
    public mutating func acknowledge(_ batchID: String, text: String?, at: Date) throws(ReviewRefusal)
    public mutating func setStatus(_ id: String, to: CommentState) throws(ReviewRefusal)  // working, done, failed
    public mutating func reply(to id: String, text: String, at: Date) throws(ReviewRefusal) -> Place   // a comment or a batch
    public mutating func ask(_ id: String, question: String, at: Date) throws(ReviewRefusal) -> Exchange?   // the answer owed to this very question, else nil: asked
    public mutating func answer(_ id: String, text: String, at: Date) throws(ReviewRefusal)       // needs an open question
    public mutating func answerHeard(_ id: String)                                         // an ask got the answer
    public mutating func requeue(_ batchID: String)                                        // unfinished → sent
    public func openQuestion(on id: String) -> ThreadMessage?
    public func unheardAnswer(on id: String) -> Exchange?                                  // the answer an ask still has to get
    public func isFinished(_ batchID: String) -> Bool
    public var queue: [Comment]
    public static func trimmed(_ text: String) -> String; public static func isBlank(_ text: String) -> Bool
    public static func written(_ text: String) throws(ReviewRefusal) -> String   // a comment's text: trimmed, not blank
    public static func said(_ text: String) throws(ReviewRefusal) -> String      // a thread message's text: the same
}

public struct Outbox: Equatable {
    public struct Parcel: Codable { var batchID: String; var videoHash: String; var delivery: Delivery }
    public enum Delivery: Codable { case pending, taken(by: String, at: Date) }
    public enum Presence: String, Codable { case absent, listening, working }
    public struct Listener { var key: String; var name: String }                        // the holder its waits come from
    public static let grace: TimeInterval = 30

    public init(parcels: [Parcel] = [])                                                 // what the store keeps
    public private(set) var parcels: [Parcel]; public private(set) var listener: Listener?
    public mutating func post(batchID: String, videoHash: String)                       // a batch was sent
    public mutating func restart() -> [Parcel]                                          // the app started again: every taken parcel → pending; returns them
    public mutating func arrive(key: String, name: String, at: Date) -> [Parcel]        // a wait opened; returns the requeued
    public mutating func take(at: Date) -> Parcel?                                      // the next pending, for the open wait
    public mutating func undelivered(_ batchID: String)                                 // the reply could not be written
    public mutating func leave(key: String, at: Date, delivered: Bool)                  // a wait closed
    public mutating func finish(_ batchID: String)                                      // every comment done or failed
    public mutating func context(for videoHash: String, text: String?) -> String?       // the text, or nil when already sent
    public func presence(at: Date) -> Presence
}

public struct BatchPayload: Codable {          // exactly the spec's shape, see "The batch payload"
    public struct Header { var id: String; var sentAt: String }                         // ISO 8601, UTC
    public struct Line { var start, end: Double; var text: String }
    public struct Item { var id: String; var time: Double; var text: String; var keyframePath: String?
        var region: Region?; var cropPath: String?; var transcript: [Line] }
    public init(batch: Batch, session: ReviewSession, context: String?,
                keyframePath: (Comment) -> String?, cropPath: (Comment) -> String?, transcript: (Comment) -> [Line])
}
```

`written(_:)` and `said(_:)` are the rules for a comment's and a thread message's text: trimmed, and not blank. `isBlank(_:)` is the app side's one test for a text of white space only; the views (`Composer`, `AnswerBox`, `ContextPopover`) and `ReviewModel` ask it, so a button is off exactly when the review would refuse. The command line has its own, `Arguments.isBlank` in `VRCommand`, which cannot import `VRReview`. `CommentState` has all seven states with `canMove(to:)`, the whole table of allowed moves. `ReviewRefusal` is one line, `reason`.

`unheard` is part of the review, not of the desk that parks an `ask`, so that the store keeps it with the threads: an answer given while no `ask` waited is still owed to the listener after the app starts again. A review, a comment and a batch kept before they had these fields read with none.

`VRReview` depends on nothing, so `Outbox` takes a listener as its holder's `key` and `name`, not as a `Holder` (`VRLease`), and `BatchPayload` has its own `Line` instead of the transcript module's line. `Outbox` itself is not `Codable`: only its parcels are kept (`init(parcels:)`), while the listener, its open waits and the context it already has live for one run of the app. `leave` names the session's key, so a wait of a listener that was replaced closes without changing the new listener's presence. `BatchPayload` encodes every key always, `null` for what is missing; its `init` is the batch assembly, a pure function of the review that the tests run without the app.

A region's parts are constants (`let`), so a `Region` that exists passed its rule; one read back from disk is trusted as it was kept. A part may reach past the frame's edge by rounding alone (a slack of 1e-9), and `pixelRect` snaps an edge that is whole but for rounding, so `0.3 × 1920` is 576 and not a pixel more.

**VRTranscript**

```swift
public struct TranscriptLine: Codable, Equatable, Sendable { var start: Double; var end: Double; var text: String
    public static func tidy(start: Double, end: Double, text: String) -> TranscriptLine? }   // times to the millisecond, text on one line; nil without text
public protocol Transcriber: Sendable {
    func lines(for video: URL, in window: ClosedRange<Double>) async throws -> [TranscriptLine]
}
public struct TranscriptFailure: LocalizedError { var reason: String }
public enum TranscriptWindow { static let reach: Double = 15
                               static func around(_ time: Double, duration: Double) -> ClosedRange<Double>
                               static func cut(_ lines: [TranscriptLine], to: ClosedRange<Double>) -> [TranscriptLine] }
public enum TranscriptSources { case voiceover(URL), subtitles(URL), speech
    static func candidates(for video: URL) -> [TranscriptSources]  // the spec's order; speech is always last
    var name: String                                               // "voiceover", "subtitles", "speech"
    func transcriber(frameRate: Double, speech: any Transcriber) -> any Transcriber }
public struct VoiceoverSource: Transcriber { init(file: URL, frameRate: Double)     // one line per scene
    static func lines(of data: Data, frameRate: Double) throws(TranscriptFailure) -> [TranscriptLine] }
public struct SubtitleSource: Transcriber { init(file: URL)                         // .srt and .vtt
    static func lines(of text: String) -> [TranscriptLine] }
```

`Transcriber` is the one interface every source is behind, the recognizer too: `TranscriptSources.transcriber` hands back the sidecar's reader, or for `.speech` the `speech` it was given. `VRTranscript` is Foundation only; the recognizer over Apple's Speech framework (`SpeechSource`) lives in `VRApp` and is handed in by `AppServices`.

**VRStore**

```swift
public struct Library: Sendable {
    public init(root: URL)
    public func session(for hash: String) throws -> ReviewSession?   // nil when none was kept
    public func save(_ session: ReviewSession) throws                // session.kept, and its ids in the index
    public func outbox() throws -> Outbox;  public func save(_ outbox: Outbox) throws   // the parcels only
    public func nextCommentID() throws -> String      // "c1", "c2", … across every video of this library
    public func nextBatchID() throws -> String        // "b1", "b2", …
    public func videoHash(forComment id: String) -> String?;  public func videoHash(forBatch id: String) -> String?
    public func keyframeURL(_ hash: String, comment: String) -> URL
    public func cropURL(_ hash: String, comment: String) -> URL
    public func removeImages(of hash: String, keeping ids: Set<String>)   // the PNGs of no comment
    public struct LastVideo: Codable, Equatable { var path: String; var contentHash: String }
    public func lastVideo() -> LastVideo?             // nil when none was kept, or it can't be read
    public func keep(lastVideo: LastVideo) throws     // written only when it changed
}
public enum ContentHash { static func of(_ file: URL) throws -> String }
public struct TranscriptCache { init(root: URL); func load(_ hash: String) -> [TranscriptLine]?; func save(_ lines: [TranscriptLine], for hash: String) throws }
```

`TranscriptCache` is the part of the store the transcript ticket owns: `videos/<contentHash>/transcript.json`, the speech transcript's lines as a JSON array. It takes the support folder itself (`Library.root`), so it stands beside `Library`, and the persistence ticket did not touch it. Only speech is kept; a sidecar is read again each time its video opens.

`Library` is a value with no state of its own: every call reads or writes a file, so two values on one folder (the app started again) see the same. `index.json` holds the next comment and batch numbers and, since the persistence ticket, which video each kept comment and each batch belongs to. An index written before batches were numbered reads with the batch number at 1, and one written before reviews were kept names no ids. An id that was given out is never given again, also when its draft was cancelled or its comment deleted, so ids may have gaps.

`save(_ session:)` writes two files, the index first. It replaces the index's ids of that video by the review's (so a deleted comment leaves the index) and writes the index only when that changed it; then it writes `review.json`. An id the index names and the review doesn't have yet is found by nobody (`ReviewModel` checks the review), while a comment the index didn't name could not be answered by a listener. A draft is not written (`ReviewSession.kept`). `JSONFile` replaces a file in one step, so a crash leaves the last full version of each.

`keep(lastVideo:)` writes `last-video.json`, the path and the content hash of the open video, whenever another video is opened. It is one file per library, so a demo run and the normal run each have their own. A file that can't be read counts as none: the app then starts with no video.

`save(_ outbox:)` writes `outbox.json`, the parcels as a JSON array. A parcel keeps who took it and when, though a restart puts every taken parcel back (`Outbox.restart`).

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
    private(set) var notices: [Notice]             // one per agent message, each gone after Notice.lifetime (5 s)
    var posted: (() -> Void)?                      // a batch is in the outbox: ListenerDesk.outboxChanged
    var answered: ((String) -> Void)?              // a question was answered: ListenerDesk.answered

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
    func setNote(_ text: String) throws(ModelRefusal)             // the open video's note; refused with no video
    var note: String { get }                                      // the open video's note
    var sidecar: ContextSidecar? { get }                          // the open video's context file, read from disk now

    // what the listener can do (any video of the library, open or not)
    var presence: Outbox.Presence { get }
    func listenerArrived(key: String, name: String)               // a wait opened: outbox.arrive, and the requeue
    func takeParcel() -> Outbox.Parcel?
    func parcelUndelivered(_ batchID: String); func parcelDropped(_ batchID: String)
    func listenerLeft(key: String, delivered: Bool)               // a wait closed
    func payload(for parcel: Outbox.Parcel) throws(ModelRefusal) -> BatchPayload
    func acknowledge(_ batchID: String, text: String?) throws(ModelRefusal)
    func setStatus(_ commentID: String, to: CommentState) throws(ModelRefusal)
    func reply(to id: String, text: String) throws(ModelRefusal) -> ReviewSession.Place
    func ask(_ commentID: String, question: String) throws(ModelRefusal) -> ReviewSession.Exchange?   // the answer owed to this question, else nil
    func unheardAnswer(on commentID: String) -> ReviewSession.Exchange?
    func answerHeard(_ commentID: String)
    func dismissNotice(_ id: UUID)
    func restored() async                                         // the transcripts of the batches the last run left are read
    func launched() async                                         // the video the last run had open is open again, or won't be
}

@MainActor struct Later {                           // a call made once a time has passed
    typealias Cancel = @MainActor () -> Void
    var after: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Cancel
    static let sleeping: Later                      // the app's: a task that sleeps
}

enum PNGFile { static func write(_ image: CGImage, to file: URL) throws(Failure) }   // keyframes, crops, screenshots
```

`Playing` and `FrameGrabbing` are the only protocols in the app with a second implementation (the test fakes). `Later` is the third thing the tests replace, and it is a value holding one closure, not a protocol (see [Time in the app](#time-in-the-app)). `Screenshotter` is concrete; tests do not capture windows, so `OperatorDesk` takes the capture as a closure and the tests pass their own. `OperatorDesk` and `ListenerDesk` are concrete and tested through `ControlServer.reply(to:)`.

The video's length has one source, `VideoFile.info.duration` (the asset's, rounded to the millisecond), so `Playing` has no `duration`. `play` is `async` because playing at the end first seeks to the start. Beside the calls above, `ReviewModel` has a person's gestures: the same calls with a time kept inside the video instead of refused, and a refusal kept for the window to show instead of answered.

| Gesture | From | Ends in |
|---|---|---|
| `openByPerson` | Cmd+O, a drop, the Finder, the demo list | `open`; a refusal lands in `openFailure` for the window's alert |
| `togglePlay`, `scrub`, `skip`, `step` | the player's keys, the transport bar, the timeline | `play`, `pause`, `seek` |
| `beginDrawing` | a drag on the frame starts | `pause`; false while the comment box is open or no video is |
| `compose` | C, the comment button, a drag's end (with its region) | `beginComment`; the comment box opens |
| `commitComposer`, `cancelComposer` | Enter and Escape in the comment box | `commitComment`, `discardComment` |
| `sendByPerson` | Cmd+Enter, the send bar's button | `commitComposer` for what the box holds, then `sendBatch`; a refusal lands in `sendFailure` |
| `showByPerson` | a click on a marker or a card | `showComment` |
| `answerByPerson` | the answer box | `answer`; false when it is refused, and the box keeps its text |
| `noteByPerson` | the context popover closing | `setNote` |
| `openNotice` | a click on a notice | `dismissNotice`, then `showByPerson` for its comment |

`beginComment` is not `async`: it makes the draft and starts one task that writes the keyframe and then, for a region, cuts the crop from it; `addComment` waits for that task. `writeCrop` is `async` so that reading, cutting and writing a full frame stays off the main actor. `comments` is what the views show: the open video's comments without the drafts. `keyframeURL(for:)` and `cropURL(for:)` are a comment's image files, or nil while they are not on disk. `marks` is the rectangles the stage draws now (`RegionMark.shown`).

The region's gestures are `beginDrawing()` (a drag started: pause; false while the comment box is open or no video is) and `compose(region:)` (the drag ended: the comment box on the rectangle). The geometry between the stage's points and a `Region` is not the model's: `FrameFit`, in `RegionOverlay.swift`, is a value the tests use without a window.

`ReviewModel` holds one review in memory, the open video's (`session`). Every other review is read from `Library` when it is needed and written back when it changed. Three private functions carry this:

- `review(of: hash)`: the open review when the hash is its video's, else `Library.session(for:)`.
- `changeReview(of: hash, body)`: runs `body` on a copy, saves the copy (`Library.save`) when what is kept of it changed, and only then makes it the open review. A refusal by the review, and a save that failed, both leave the review as it was and refuse the command. A change to a draft alone writes nothing.
- `hash(ofComment:)` and `hash(ofBatch:)`: the open review when it has the id (a draft too), else `Library.videoHash(forComment:)` or `videoHash(forBatch:)`, checked against the review it names.

So the listener's answers and `thread answer`, which name a comment or a batch by its id alone, reach any video of the library, opened in this run or not.

`keyframes` and `crops` name the comments whose images are on disk. For a comment this run made, its grab task says so. For a review of an earlier run, `findImages(of:)` looks for the files, when its video opens and when a payload is made of it.

`setStatus` is where a batch finishes: when every comment of the batch is done or failed, the model calls `outbox.finish`, so the listener has no work of it left and presence goes from `working` to `listening`. `acknowledge` with a text, `reply` and `ask` raise a `Notice`; an `ack` without a text and a status raise none, since they show on the pins and cards. `answer` calls `answered`, which `ControlServer` sets to `ListenerDesk.answered`. The answer box ends in `answerByPerson`, and a click on a notice in `openNotice` (the notice goes, its comment shows). The outbox is `ReviewModel.outbox`, changed only through the model's own `deliver`, which writes `outbox.json` whenever the parcels changed. The model's `init` takes up what the last run kept (`restoreOutbox`, see [Starting again](#starting-again)).

The model takes the time as a closure (`now`) and what it does later as a `Later`, so the tests set when a batch was sent and when a wait closed, and move the time past a notice's 5 s. `payload(for:)` is not `async`: everything it reads is in memory or a small local file read at once (the review of a video that is not open, which images are on disk, the transcript lines known at that moment, the context), so a batch goes to a parked `wait` in the same step it is sent in, with nothing running between. Two private functions feed it: `contextText(of:)` (`ContextSidecar.find` beside the review's video path, read from disk on each call, plus the review's note; `Outbox.context` sends the text once per listener session and when it changed) and `transcript(around:of:)`, which asks `TranscriptService` for the lines it knows at that moment.

The model makes its `TranscriptService` (`transcripts`) from the recognizer it is given (`init(… speech: any Transcriber = SpeechSource() …)`) and a `TranscriptCache` on the library's folder. `open` ends in `await transcripts.start(file)`, which returns once a sidecar is read or speech has started. The tests hand in a recognizer they hold back, let it go, and await `settled(_:)` for the lines to be known. Only the tests call `settled`: the app never waits for speech.

```swift
@MainActor @Observable final class TranscriptService {
    struct Status { var source: String; var ready: Bool; var lines: Int; var failure: String? }
    init(speech: any Transcriber, cache: TranscriptCache)
    func start(_ video: VideoFile) async                          // find the source; read a sidecar, or start speech
    func lines(of hash: String, around time: Double, duration: Double) -> [TranscriptLine]   // from memory, never waits
    func status(of hash: String) -> Status?                       // what state reports
    func settled(_ hash: String) async                            // the tests' hook: the speech run of that video has ended
}
struct SpeechSource: Transcriber                                  // SpeechAnalyzer + SpeechTranscriber over the file's sound
```

`composerText` is what the comment box holds. The model keeps it, not the view, so that Cmd+Enter inside the box can queue it before sending. `sendByPerson()` is the person's send (Cmd+Enter and the send bar's button): it queues the box's text, then calls `sendBatch()`, the same call `batch send` ends in; a refusal lands in `sendFailure` for the send bar. A second press while a send is on its way does nothing. It returns the task of the send it started, or nil when it started none, so a test awaits the send and sees that the second press started nothing. `posted` is the closure the model calls after a batch is in the outbox; `ControlServer` sets it to `ListenerDesk.outboxChanged`.

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
| `context set <text>` | operator | `context note set`, or `context note cleared` for an empty text | `{note}`, the note as it was kept |
| `screenshot <abs.png> […]` | operator | the path | `{path}` |
| `wait [--timeout <s>]` | listener | the payload (always JSON) | the same |
| `ack <batch-id> [<text>]` | listener | `acknowledged b1` | `{id}` |
| `status <id> <state>` | listener | `c1 is working` | `{id, state}` |
| `reply <id> <text>` | listener | `replied on c1` | `{id}` |
| `ask <id> <question> [--wait <s>]` | listener | the answer's text | `{commentId, question, answer, answeredAt}` |

Exit codes: 0 done; 1 refused, app not running, or no reply; 2 usage; 3 a `wait` or `ask` whose time ran out (nothing on standard output). The reply shape stays `{ok, output, error, lease?}`: a long poll that ran out comes back `ok: true` with empty `output` and a note in `error`, and `ListenerCommand` turns exactly that into exit 3.

`control take --wait` takes whole seconds from 0 to 3600. A take refused or waited out exits 1, like every refusal. `control release` exits 0 whoever sends it. The holder key has no flag: `VIDEO_REVIEW_CONTROL_KEY` is the one way to name it (Shipyard's `--key` is not in the contract).

The comment object of `comment add --json` is the one in `state --json`'s `comments`. A comment's text is one argument; a second word is refused with exit 2 and the advice to quote it. An option starts with two dashes, so a text may start with one (`"-3 dB would be better"`). `--region` takes `x,y,w,h` as one argument: four numbers of digits and a dot, with spaces allowed around them. Anything else is refused with exit 2. Four numbers that are not a rectangle inside the frame are refused by the app with exit 1, and no comment is left. The text printed for a comment with a region is the same `c1 at 0:10.000`; the region and the crop's path are in `--json`.

Times are accepted as seconds (`10`, `10.5`) or `mm:ss` (`0:10`, `1:02.5`), also `h:mm:ss`. A time outside the video is refused. `screenshot` needs an absolute `.png` path whose folder exists. The command refuses another path with exit 2; the app refuses it too, with exit 1, when a request reaches the socket without the command (`ControlMessage.decode`). `player open` takes a relative path against the folder the command runs in.

`app status --json` has `listener` as `{presence, name}`, the same object as in `state --json`. As lines, `app status` and `state` say `listener: absent`, or `listener: listening (Claude Code)`.

`batch send` with nothing queued is refused with exit 1 (`there's nothing to send: no comment is queued`). It says `sent b1 with 1 comment` for one. `wait --timeout` takes whole seconds from 0 to 86400; `--timeout 0` answers at once. A `wait` whose time ran out prints `no batch came within 5 seconds` on standard error and exits 3. The payload is one JSON object on one line, keys sorted, with or without `--json`.

`ack`, `status`, `reply` and `ask` take ids as the payload gave them, and a text as one argument (a second word is refused with exit 2 and the advice to quote it). An empty text is refused with exit 2; `ack` takes no text at all instead. `status` takes exactly `working`, `done` or `failed`, anything else is exit 2. `reply` takes a comment's id or a batch's: ids don't collide (`c1`, `b1`), so the app finds which it is. `ask --wait` takes whole seconds from 0 to 86400; `--wait 0` asks and answers at once. An `ask` whose time ran out prints `no answer came within 5 seconds` on standard error and exits 3, and its question stays open. An answer that came after that is printed at once by the next `ask` of the same question in the same words, once; an `ask` of another question is asked and waits for its own answer. A refusal (`there's no comment c9`, `c1 is done; it can't be set to working`, `c3 wasn't sent yet; it can't be replied on`, `c1 has no question to answer`) is exit 1. `thread answer` reaches a comment of any video of the library, as the listener does.

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
  "context": {"sidecarPath": "/abs/sample.context.md", "note": ""},   // sidecarPath null with no file; context null with no video
  "transcript": {"source": "voiceover", "ready": true, "lines": 3, "failure": null},
  "queue": ["c3"],
  "comments": [
    {"id": "c1", "time": 10, "text": "…", "state": "done", "batchId": "b1",
     "region": null, "keyframePath": "/abs/…/frames/c1.png", "cropPath": null,
     "thread": [{"author": "agent", "kind": "question", "text": "…", "at": "2026-10-04T12:00:00Z"}]}
  ],
  "batches": [{"id": "b1", "sentAt": "…", "commentIds": ["c1", "c2"], "delivery": "taken", "finished": true, "thread": []}],
  "notices": [{"commentId": "c1", "batchId": "b1", "kind": "question", "text": "…"}]
}
```

The player's time is in two places with the same value: `player.time`, and a top-level `time` for a script that reads one field. Both are rounded to the millisecond.

Each key arrives with the ticket that builds what it reports. The first build ticket gives `app`, `lease`, `video`, `player` and `time`. The comment ticket gives `queue` and `comments`, each comment as `{id, time, text, state, keyframePath}`; the region ticket adds `region` and `cropPath`; the batch ticket adds `batchId` (`null` before the comment is sent), `listener` and `batches`, each batch as `{id, sentAt, commentIds, delivery, finished}`; the answers ticket adds `thread` to each comment and each batch, as `{author, kind, text, at}` oldest first (`at` in ISO 8601, UTC), and `notices`. `listener.name` is the last listener session's name, `null` before any `wait`. A batch's `delivery` is `pending` until a `wait` took it, then `taken`; a batch that went back in the queue is `pending` again, and so is one the app was quit with while a listener had it. `batches` holds the open video's batches, oldest first. As lines, `state` adds `batches: 1` and one line per batch (`  b1 pending: c2, c1`, `  b1 finished: c2, c1`) when there are some, and under each comment and each batch one line per thread message (`    agent question: which part?`). `notices` holds the notices the stage shows at that moment, oldest first, each as `{commentId, batchId, kind, text}` with `commentId` `null` for a message for a full batch: it's how an operator sees a toast, which is gone after 5 s, without a screenshot. `comment add --json` prints the comment with its (empty) `thread` too.

The transcript ticket gives `transcript`, the open video's: `source` is `voiceover`, `subtitles` or `speech`; `ready` is `false` only while speech is still being recognized; `lines` counts the lines known now, over the whole video; `failure` is why speech gave no transcript, else `null`. It is `null` with no video. As lines, `state` adds `transcript: voiceover, 3 lines`, `transcript: speech, transcribing` or `transcript: speech, failed: <why>` under the player's line.

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
  outbox.json                  the Outbox's parcels: the batches sent and not finished
  last-video.json              the video that was open last: {path, contentHash}
  videos/<contentHash>/
    review.json                the ReviewSession without its drafts: video, comments, batches, threads, note, unheard
    transcript.json            the cached speech transcript
    frames/<comment-id>.png    the keyframe, at the video's natural size
    crops/<comment-id>.png     the region's crop
  d-<8 hex>/                   one demo run's support folder, the same layout inside
```

A demo run's support folder is inside the normal one, named by a hash of the demo folder's absolute path. So the demo folder itself (the tracked `fixtures/sample/`) is never written to, two demo folders never share data, and the socket path stays under the 103 bytes a Unix socket allows. `AppServices` makes the one `Library` on the support folder it was launched with, so a demo run reads and writes only under its `d-<8 hex>/`, and the normal run never looks inside one: demo data and real data do not mix. A file is made when there is something to keep: opening a video writes `last-video.json` and nothing else, and no review until a comment is queued or a note is set.

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
UI/Shortcuts (SendKey), UI/SendBar       ReviewModel.sendByPerson(): the comment box's text is queued first
└ ReviewModel.sendBatch
  ├ await pending frames                 every queued comment's keyframe and crop are on disk;
  │                                      one that isn't is grabbed once more, and sent as it is
  ├ Library.nextBatchID()                "b1"; index.json saved
  ├ outbox.post("b1", videoHash)         Parcel(b1, pending); outbox.json saved
  ├ session.send(batchID: "b1", at: now) c1, c2: queued → sent; Batch b1; index.json and review.json saved
  └ posted → ListenerDesk.outboxChanged()
    ├ a wait is parked → outbox.take(at: now)      Parcel(b1, taken(by: listener key))
    ├ ReviewModel.payload(for: parcel)
    │ ├ Library paths                    keyframePath, cropPath (absolute); null for a file not on disk
    │ ├ transcript(around:of:)           TranscriptService.lines: TranscriptWindow.cut(known lines, to: time ± 15 s)
    │ ├ contextText(of:)                 ContextSidecar.find (read from disk now) + the review's note → ContextSidecar.text
    │ │ └ outbox.context(for: hash, text)          first batch of this listener → the text; later → nil
    │ └ BatchPayload(…)                  the spec's object
    └ resume the parked connection       Answer(reply: ok, output: <payload JSON>, batch: "b1", listener: key)
SocketListener                           writes the reply, then tells ControlServer.written(answer, delivered:)
├ written → ListenerDesk.written → outbox.leave(key, at: now, delivered: true)
└ not written (the client is gone) → outbox.undelivered("b1"): the parcel is pending again; then leave
VRCommand/ListenerCommand                prints the payload, exit 0
```

`sendBatch` is refused with no video open and with nothing queued. A comment queued while it waits for the frames of the others goes in the same batch. A frame that still can't be saved after the second grab never holds the batch back: its comment is sent with `keyframePath: null`. The parcel is kept before the review says the batch was sent: a crash between the two writes leaves a parcel of no batch, which the next launch drops while the comments are still queued, and never a sent batch that no listener gets. A parcel that can't be kept refuses the send.

State after each step:

| Step | c1, c2 | Parcel b1 | Presence |
|---|---|---|---|
| before | `queued` | none | `listening` |
| after `outbox.post` | `queued` | `pending` | `listening` |
| after `session.send` | `sent` | `pending` | `listening` |
| after `outbox.take` | `sent` | `taken` | `working` |
| after `ack b1` | `acknowledged` | `taken` | `working` |
| after `status … done` on both | `done` | removed (`finish`) | `listening` when a `wait` is open, else `absent` |

When no `wait` is open, the trace stops after `session.send`: the parcel stays `pending` on disk. The next `wait` runs `ListenerDesk.wait`, which calls `outbox.arrive(listener, at:)` and then `outbox.take`, and answers at once.

### How a long poll is held

`wait`, `ask` and a queued `control take` keep their connection open. One request per connection still holds.

A queued `control take` is held the way Shipyard holds it, without the heartbeat below: `ControlServer` parks it as a continuation with a timer for its wait, and the client reads for its usual 15 s plus the wait. A client that went away shows when the reply granting it the lease can't be written; `SocketListener` then tells the server (`undelivered`), which releases that lease so the next in line gets it. The rest of this section is the listener's long polls.

- `ListenerDesk` parks the request as a continuation, with a call through `Later` that ends it when its time ran out, and `ControlServer` goes on answering other requests.
- `SocketListener` gives every connection a ticket (a `UUID`) and hands it to `ControlServer.reply(to:ticket:)`, which hands it to the desk; a parked request is found again by it.
- While the server holds a long poll's connection (`ControlServer.isLongPoll` reads the request), `SocketListener` writes one space byte to it every 2 s (`Pulse`). JSON ignores leading whitespace, so the reply still reads. A write that fails means the client is gone: `ControlServer.dropped(ticket)` has the desk drop the parked request and call `outbox.leave(key:at:delivered: false)`, so presence turns `absent` within 2 s of a killed `wait` (or once the 30 s after its last delivered batch are over). The reply is written under the same lock as the beats, after the last one.
- `ControlServer.Answer` names what hangs on its reply being written: the lease a `take` grants, and the `batch` a `wait` delivers with the `listener` key it goes to. `SocketListener` reports how the write went for such an answer (`written(_:delivered:)`).
- The client's read gives up after 10 s without a byte, so a `wait` never outlives an app that died.
- `wait` without `--timeout` waits until a batch comes. `ask` without `--wait` waits until the answer comes.
- A parked `ask` is not the listener's presence: only a `wait` is. An `ask` whose client went away is dropped from the desk, and its question stays open.
- `ControlServer.Answer.heard` names the comment whose answer an `ask`'s reply carries. Once the reply is written, the answer counts as heard (`ReviewSession.answerHeard`); a reply that couldn't be written leaves it for the next `ask`.
- A `wait` from another listener session than the last one ends that one's parked waits (`another listener, <name>, took over`): one listener at a time.
- When the app quits, every parked `wait` and `ask` is refused with `video-review is quitting`.

### Time in the app

The app reads the time in one way and waits for it in one way, and the tests replace both.

- **What time it is**: a closure, `now`, handed to `ReviewModel` and `ControlServer`. The lease, the outbox's presence (the 30 s after a delivered batch) and every `sentAt` and `at` are computed from it. Nothing in them sleeps.
- **Doing something later**: `Later.after(seconds, then)`, handed to `ReviewModel`, `ControlServer` and, by the server, `ListenerDesk`. It is the one way they wait: a `wait`'s `--timeout`, an `ask`'s `--wait`, a queued `take`'s wait, the lease's end (`settleLease`) and a notice's 5 s. It returns a closure that takes the call back. In the app it is `Later.sleeping`, a task that sleeps. In `VRAppTests` it is `FakeClock.later`: `advance(by:)` moves the time on and makes each call that fell due, at once and on the test's own path, so a timeout test takes no real time and can't be early or late.

Left on real time, because no test waits on them: the heartbeat of a held connection (`SocketListener`'s `Pulse`, a dispatch timer whose interval `SocketListener.open(heartbeat:)` takes), the 350 ms a screenshot gives the window to redraw in a new appearance, and `PlayerController`'s look every 20 ms for a video to be ready.

### The rules that carry the logic

**The comment state machine** (`Comment.swift`)

```text
commit:        draft → queued
send:          queued → sent                       (every queued comment of the video, one batch)
acknowledge:   sent → acknowledged                 (every comment of the batch still sent; one that
                                                   moved on stays; a second ack changes no state)
setStatus(s):  s ∈ {working, done, failed}; from sent, acknowledged or working, to a state after it
               done and failed are final           refused: "c1 is done; it can't be set to working"
               the state it already has            done again, with no change (a listener's retry)
               a comment not sent yet              refused: "c3 wasn't sent yet; it can't be given a status"
requeue:       acknowledged, working → sent        (the only move backward)
edit, delete:  queued only                         refused: "c1 was sent; it can't be edited"
                                                   a draft: "c1 is still being written; it can't be edited"
commit, edit:  the text is trimmed                 refused when empty: "a comment needs its text"
discard:       a draft only                        removes it; its id is not used again
any of them:   an id the video doesn't have        refused: "there's no comment c9"
```

`CommentState.canMove(to:)` is the table of these moves, and the only place the rule lives: for each state, the states it may move to. `ReviewSession` asks it before it changes a comment's state. The states have no number and no order beyond that table.

A status may skip forward (`acknowledged → done`), because the acceptance scenario sets comments to `done` straight after `ack`.

**Questions and answers** (`ReviewSession.swift`)

```text
open question:       a comment's last question, while no answer follows it (messages between don't count).
reply(id, text):     appends agent/message to the thread of the comment, or of the batch when id is one.
                     Refused for a comment not sent yet. Allowed on a done or failed comment.
ask(id, question):   appends agent/question. Refused when another question on that comment is still open.
                     The open question asked again in the same words adds nothing: the same question.
                     The question whose answer is unheard, asked again in the same words: nothing is
                     asked, and that exchange is returned (the answer is owed to it).
                     Another question while an answer is unheard: it is appended, and the old answer
                     counts as heard. It stays in the thread.
answer(id, text):    appends person/answer, and marks the comment unheard. Refused when no question is open.
any of them:         the text is trimmed; refused when empty: "a message needs its text".
ListenerDesk.ask:    session.ask returned the owed exchange → reply with its answer at once.
                     else (the question is asked, or was open) → park the connection → on answer:
                     reply with the answer's text.
                     Time ran out → ok with empty output (exit 3); the question stays open.
                     The reply was written → answerHeard: the answer is given once.
```

The person and `thread answer` both end in `ReviewModel.answer`, which resumes every `ask` parked on that comment.

So a listener whose `ask` ran out has two ways on, both the same command again: while the question is still open, the same `ask` waits on it with no second question and no second notice; once the person answered, the next `ask` of that question in the same words (trimmed) gets the answer at once, with the question in its `--json`. An answer counts as given only when its reply was written, so a listener that was cut off while it waited gets it from the next such `ask`.

An `ask` of another question is never answered by the old answer: a listener that moved on would take "the intro" as the answer to "how long?". The new question is asked and the old answer is owed to no `ask` any more. It is not lost: it stays in the comment's thread, which `state --json` shows. The rule is in `ReviewSession.ask`, one change to the review, so a question that is refused (empty, or on a comment not sent) leaves the old answer owed.

**The outbox** (`Outbox.swift`)

```text
arrive(key, name, at):
    if key ≠ the last listener's key:                     // a new listener session
        every parcel taken by another key → pending       // and ReviewSession.requeue for its batch
        forget the context already sent, the open waits and the last delivery
    remember the listener; one more wait is open
take(at):       the oldest pending parcel → taken(by: listener key, at)
undelivered:    that parcel → pending; forget its video's context
leave(key, at, delivered):  ignored for a key that isn't the listener's;
                one wait fewer is open; a delivery is remembered with its time
finish(batch):  remove the parcel
context(hash, text):   text ≠ the text remembered for hash → remember it, return text; else nil
restart():      every taken parcel → pending, whoever took it  // and ReviewSession.requeue for its batch

presence(at):
    a wait is open, or one closed with a delivery less than 30 s ago:
        any parcel taken by this listener → working, else listening
    else absent
```

The same listener running `wait` again while its batch is in work gets no second copy: only a different key requeues. A listener session is its holder key: a Claude Code session's id, or `VIDEO_REVIEW_CONTROL_KEY`. The 30 s after a delivered batch cover the moment between the listener reading a batch and starting `wait` again. The outbox counts open waits, since one listener may hold more than one. `undelivered` forgets the video's context whether this delivery carried it or not; at worst the listener gets a context twice. The context is remembered as its text, not a digest: it lives in memory only. The parcels are kept in `outbox.json`; the listener, its open waits and the context memory are not, so a restarted app has no listener (`absent`) and sends the context again.

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
- A draft that is cancelled, and a comment that is deleted, lose their PNGs, the crop too. A write still running when its comment is dropped removes its files when it lands. A draft the app was quit with leaves its PNGs; they go when the video opens again (`Library.removeImages`).
- `comment add` whose keyframe or crop cannot be written is refused and leaves no comment and no file. A comment from the window whose crop cannot be written stays, with `cropPath: null`.
- A comment from the window whose keyframe cannot be written stays queued with `keyframePath: null`. `sendBatch` grabs it once more, and sends the comment with what it has.

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
on open:   TranscriptService.start(video), for each of TranscriptSources.candidates(for: video):
               1. voiceover.json in the video's folder
               2. <base>.srt, else <base>.vtt
               3. speech
           sidecar → read now, all lines known; one that can't be read, or has no line, gives way to the next
           speech  → the lines of this run, else TranscriptCache.load(hash), else SpeechSource in a
                     background task: ready is false until it ends, then the lines are known and
                     saved to the cache; a failure is kept as one line and tried again on the next open
window:    TranscriptWindow.around(t, duration) = max(0, t − 15) … min(duration, t + 15)
           TranscriptWindow.cut = every known line partly or wholly inside the window, whole, in time order;
                                  a line that only touches the window's edge is outside
```

`TranscriptService` keeps each video's lines in memory by content hash, so `payload(for:)` reads them without waiting, for a video that is open, was opened earlier in the run, or had a batch in the outbox when the app started ([Starting again](#starting-again)). A comment made before speech finished gets the lines that exist at send time: none, since the recognizer answers once, for the whole video. Speech is asked for the whole video in one call (`0…duration`), because the interface gives lines for a window and has no way to give them as they come; on the fixture that call takes under a second. A speech run goes on when another video is opened.

`VoiceoverSource` gives one line per scene: a scene lasts `ceil((durationSeconds + paddingSeconds) × fps)` frames and starts where the previous one ends; `fps` is the video track's nominal frame rate. A scene without narration has no line and still takes its time. `voiceover.json` is looked for in the video's folder, which is also where its `context.md` is.

`SubtitleSource` reads SubRip and WebVTT with one parser: a cue is a timing line (`hh:mm:ss,mmm --> hh:mm:ss,mmm`, a dot for the comma, hours optional) and the lines under it up to an empty one, joined by a space, with tags (`<i>`, `<v Name>`) taken out. Cue numbers and names, the `WEBVTT` header, notes and cue settings are skipped.

`SpeechSource` (`VRApp/Transcript/`) is the recognizer:

```text
no audio track                        → [] (a silent video has an empty transcript, ready)
locale = the first of the person's preferred languages that SpeechTranscriber.supportedLocale knows, else en-US
SpeechTranscriber(locale, attributeOptions: [.audioTimeRange])
locale not in SpeechTranscriber.installedLocales
    → AssetInventory.assetInstallationRequest(supporting:)?.downloadAndInstall()
SpeechAnalyzer(inputAudioFile: AVAudioFile(forReading: video), modules: [transcriber], finishAfterFile: true)
for each result of transcriber.results → one line: result.range's start and end, result.text
cut to the window
```

It reads the sound straight from the video file (`AVAudioFile` opens `mp4`, `mov` and `m4v`), and each result the recognizer ends is one line, a sentence or a phrase. On macOS 26.5 this needs no permission prompt: recognizing a file on the device with `SpeechAnalyzer` asks for no speech recognition authorization, and it ran from a command-line process with no `Info.plist`. The bundle still carries `NSSpeechRecognitionUsageDescription`, for a system that asks. The language's model is a system asset; when it isn't installed, the system downloads it on the first run, without a prompt.

**The context** (`ContextSidecar.swift`): `<base>.context.md` beside the video, else `context.md` in the same folder. The first of the two that is a readable file wins, even an empty one; a folder of that name is passed over. The payload's text is the sidecar's text, then the note under the heading `## Reviewer's note` when the note is not empty, each without the white space around it, two newlines between them and one at the end. `null` when both are empty or `Outbox.context` says it was sent. The sidecar is not cached: `ReviewModel.contextText(of:)` reads it when a `wait` takes a batch, so an edit on disk reaches the next batch, and `state` and the toolbar button read it when asked. The file is small and local, so the read stays on the main actor and `payload(for:)` stays synchronous. The video's path is the review's (`ReviewSession.video.path`), so a batch of a video that is not the open one finds its sidecar too.

The note is `ReviewSession.note`, one per video, kept with the review in `review.json`; a review kept without a note reads with none. `ReviewModel.setNote` is the one way in: `context set <text>` (an operator's, so it needs the lease; one argument, and `""` takes the note away) and the popover both end there. `ContextButton` is a toolbar item shown while a video is open: `doc.text`, filled once the video has a sidecar or a note, with a tooltip that names what the listener gets. Its popover shows the sidecar's file name and text read-only (as read when the popover opened), and the note in a text editor; the note is kept when the popover closes, whichever way (Done, Escape, a click outside). `state` shows the context in its JSON only (`context`); the lines of `state` and `app status` do not name it.

**The content hash** (`ContentHash.swift`): SHA-256 over the file's byte count, its first 4 MiB and its last 4 MiB, as lowercase hex. A file of 8 MiB or less is hashed whole. A renamed or moved copy has the same hash; `review.json` keeps the last path seen.

**Opening a video** (`ReviewModel.open`)

```text
VideoFile.read(url)          playable? duration, frame rate, title (the file's base name), ContentHash
Library.session(for: hash)   the history; a review.json that can't be read refuses the open and is left as it is
player.load(url), paused at 0
the review                   the open one when this video is open already, else the history, else a new ReviewSession
                             its video's path and title are the file's; a history whose file moved is saved again
Library.removeImages         the PNGs of no comment of the review: what a draft left at a quit
findImages                   the comments whose keyframe and crop are on disk
Library.keep(lastVideo:)     its path and content hash, for the next launch; a failure is one line on standard error
TranscriptService.start      in the background
```

The history is found by the content hash alone, so a renamed or moved copy of a video opens with the same comments, batches, threads, statuses and note. A new review is not written until it has something to keep.

### Starting again

Nothing is done at quit: every change was saved when it was made. At launch, `ReviewModel.init` runs `restoreOutbox`, then `reopenLastVideo`:

```text
outbox = Library.outbox()                      the parcels of the last run; no listener
outbox.restart()                               every taken parcel → pending
  └ for each: review.requeue(batch), saved     its acknowledged and working comments → sent
for each parcel: its batch is not in its review, or is finished → outbox.finish
outbox.json saved when any of this changed it
restoring = Task: for each video with a parcel, VideoFile.read(its last path) → TranscriptService.start; nil again at its end

last = Library.lastVideo()                     none → no video is open
reopening = Task: VideoFile.read(last.path)    no file, or one the player can't play → no video is open
                  its hash ≠ last.contentHash  → no video is open
                  else open it as `player open` does: paused at 0, with its review
                  nil again at its end
```

- The `wait` that took a batch ended with the app that held it, so the batch is given again to the next `wait`, also one of the same listener session. `arrive` alone would not do that: it requeues only what another session took.
- A parcel of a finished or a missing batch is what a crash between two writes left (a status and the outbox, or the outbox and a send).
- An outbox that can't be read starts empty, with a line on standard error. A review that can't be read keeps its parcel.
- The video that was open last is open again after a launch, so the window and `state` show its comments, threads and statuses with no `player open`. `ControlServer.reply(to:)` awaits the reopening (`ReviewModel.launched()`) before it answers any request, so the first `state` after `app open` already has the review. The player is paused at 0: where the playhead was is not kept, since a review is about its comments and each one seeks to its own moment.
- A last video whose file is gone, can't be played or has other content (its hash differs) is not opened. The app starts with no video and says nothing: no alert, nothing in `openFailure`. `last-video.json` stays as it is until another video is opened, so a file on a disk that comes back is opened at the next launch. The history is not lost either way: it is kept by content hash, and shows when the video is opened from wherever it is now.
- A video the person opens while the reopening still reads its file stays: the reopening gives way.
- A batch may go to a `wait` for a video that is not the open one, so the model reads the transcripts of the videos with a parcel in a background task, and `ListenerDesk.wait` awaits it (`ReviewModel.restored()`) before it takes a batch. A video whose file moved or changed gets no transcript until it is opened again. The images are found by `findImages` and the context is read from the review's last path, as for any video that is not the open one.
- What a restart keeps: comments, statuses, batches, threads, the note, an open question (its answer box shows again), an answer no `ask` heard (`unheard`, owed to the next `ask` on that comment), pending batches. Which video is open is kept too (`last-video.json`). What it does not keep: drafts, the listener and its presence, the context memory, notices, the lease (but for a relaunch's handover), the player's time (0 after a launch) and whether it was playing (paused), the selected comment.

### The listener skill

`.agents/skills/video-review-mate/` is what a Claude Code session in the target repo runs to be the listener. It is no Swift module and links nothing: it reaches the app through the CLI contract only (`wait`, `ack`, `status`, `reply`, `ask`, and `state --json` to read threads). `SKILL.md` is the procedure; `mate.sh` is the one way the skill runs the CLI.

```text
mate.sh <key> listen         wait (no timeout) → print the payload → ack <batch id>     one background command
mate.sh <key> <arguments>    video-review <arguments>, output and exit code unchanged

start:      key = mate-<8 hex>, one per run; `listen` in the background
a batch:    `listen` again in the background, first                  presence stays, the next batch is caught
            read context (when not null), each keyframe, crop and transcript
            state --json → the comments' threads                     a thread with messages: redelivered
            per comment: intent → status working → the work → one commit when files changed
                         → reply (with the SHA) → status done | reply (the reason) → status failed
            every comment final → reply <batch-id> (the summary)
a question: ask --wait 60 → exit 3 → the same ask in the background, --wait 86400; on to other comments
```

- **The key.** `mate.sh` exports its first argument as `VIDEO_REVIEW_CONTROL_KEY` for every command, so a run is one listener session whatever shell each command runs in, and a new run is a new one: `Outbox.arrive` gives it the batches the last session left and the context again.
- **The CLI's place.** `$VIDEO_REVIEW_CLI` when set, else `/Applications/Video Review.app/Contents/Helpers/video-review`; never `PATH`. This build's own CLI is in `Video Review (proto-3).app`, so here the variable (or a symlink it names) is set.
- **The acknowledgement is in `listen`.** The session hears of a batch only when its background command ends, and reading the output and writing an `ack` takes it some seconds each time. `listen` acknowledges in the same process as the `wait`, so the comments turn `acknowledged` within a second of the send. `mate.sh` reads the batch's id with `/usr/bin/plutil`, which every Mac that runs the app has; no `jq`, no Python.
- **`wait` without a timeout.** The background command ends only with a batch (exit 0) or with the app (exit 1), so exit 3 is an `ask`'s alone.
- **Threads after a requeue.** The payload carries no thread history, so the skill reads `state --json` once per batch and goes on from each comment's thread. `state` lists the open video's comments only; a comment it doesn't list is taken as new.
- **A redelivered comment the session finished** gets its status set again, which `setStatus` answers with no change, and no second piece of work.
- **An unanswered question never fails a comment.** The long `ask` in the background ends with the answer, whenever it comes; the same words wait on the same question (`ReviewSession.ask`).

### The acceptance scenario

`scripts/acceptance.sh` is the spec's v1 acceptance scenario, eight steps, through the CLI only against the installed app in demo mode. It is a shell script and links nothing, like the listener skill. Run it with `make acceptance` after `make install`; it drives the app's window, so it is not part of `make test`.

```text
make install
make acceptance                                   this build
VIDEO_REVIEW_CLI=<another build's CLI> scripts/acceptance.sh
ACCEPTANCE_SHOTS=<folder> scripts/acceptance.sh   where light.png and dark.png go (default .scratch/acceptance/)
```

| Step | Commands | Checked |
|---|---|---|
| 1 | `app open --demo`, `control take`, `app status` | the app names the demo folder; `state --json` has no comment |
| 2 | `player open`, `player seek 0:10`, `player pause`, `comment add` | the comment is `queued` at 10 s, the paused time |
| 3 | `comment add --at 16 --region …` | the comment is `queued` at 16 s with its region |
| 4 | `batch send` | it gives a batch id |
| 5 | `wait --timeout 30` under the listener's key | the batch id and send time; the video; both comments by id, time and text; each keyframe a PNG on disk; no region and no crop on the first comment; the region and a crop PNG in the region's shape on the second; transcript lines inside 15 s around each comment, and the line spoken at 10 s; `context` holding every line of the sidecar |
| 6 | `ack`, `ask` in the background, `thread answer`, then `reply` and `status … done` on both | `ask` exits 0 with the answer; `state --json` has both comments `done`, the question, the answer, the replies and the acknowledgement |
| 7 | `app quit`, `app status`, `app open --demo`, `control take` | the app is gone, then the same `state --json` checks pass again with no `player open`, and the video is open again, paused at 0 |
| 8 | `player seek 16`, `screenshot --appearance light` and `dark` | two PNG files that differ |

- **Failing.** Each check prints `  ok    <what it proves>`. The first one that fails prints `FAIL  step <n> (<title>): <why>` on standard error, with the command's own error or the JSON it judged, and the script exits 1. The last line of a good run is `PASS  all 8 steps of the v1 acceptance scenario`.
- **The CLI's place.** `$VIDEO_REVIEW_CLI` when set, else the helper in this build's installed bundle. The script reads `AppIdentity.variant` with the `sed` line the `Makefile` uses, so dropping the variant renames both. The path is always quoted: it has spaces and parentheses.
- **The demo folder** is a temporary copy of `fixtures/sample`, made with `mktemp`. A demo's support folder is named by its folder's path, so every run starts from an empty store, and the tracked fixture is never the demo folder. Paths the app gives back are compared by their end, since the app names `/var/…` what the shell may name `/private/var/…`.
- **The two shells** are two holder keys: every operator command runs with `VIDEO_REVIEW_CONTROL_KEY=acceptance-operator` and every listener command with `acceptance-listener`. The operator takes the lease after each `app open`, since a quit app's lease is gone.
- **Ids** come from `comment add --json` and `batch send --json` (`.id`), never from a count. In `state --json` a comment is found by its id wherever the state keeps it, and its state is read from `state` or `status`: the spec fixes the commands and the payload, not the state's shape, and the same script has to judge the other prototypes.
- **The question.** `ask --wait 60` runs in the background; `thread answer` is sent every quarter second until the app takes it (10 s at most), since a comment has no question to answer until the `ask` arrived.
- **The screenshots** are taken after the restart, with the player paused at the region comment's time: its rectangle shows on the frame (the playhead is on it), both pins are on the timeline, and its card holds the question, the answer and the reply. A `captured by rendering` line of the app is printed as a note.
- **The end,** also after a failure or Ctrl+C (a trap on `EXIT`): a background `ask` is ended, the app is quit, the lease is released if the quit was refused, and the temporary folder is removed. The demo's support folder (`d-<8 hex>/`) stays, with the images the payload named.
- **Tools.** `/bin/bash`, `/usr/bin/jq` (part of macOS since 15, and the app needs 26) and `/usr/bin/sips` for the images' sizes.

The two files in `assets/screenshots/v1-acceptance/` are copies of a run's `light.png` and `dark.png`. A run does not write there, so a run never changes a tracked file.

### Adding a CLI command

1. Add the case to `ControlRequest`, its role, and its wire name and fields in `ControlMessage` (`VRWire`).
2. Add its parsing and usage to the matching `…Command.swift` and, for a new first word, one entry in `CommandTable.standard` (`VRCommand`).
3. Add the method to `ReviewModel` and call it from `OperatorDesk` or `ListenerDesk`, with one more `case` in `ControlServer`'s dispatch (`VRApp`).
4. Call the same `ReviewModel` method from the view.

## 5. Extensibility

| Change | What you touch |
|---|---|
| Drop the `proto-3` suffix | `AppIdentity.variant = ""`. Nothing else. |
| A better transcriber (the transcription research) | A new `Transcriber` in `VRApp/Transcript/` or `VRTranscript`, handed to `ReviewModel` as `speech` in `AppServices`. A cached `transcript.json` of the old one stays until it is removed. |
| A new transcript sidecar format | A new source file in `VRTranscript`, and a case in `TranscriptSources` with its place in `candidates`. |
| A new CLI command | The four steps above. |
| A new comment state | `CommentState` and its row and column in `canMove(to:)`; `Theme` for its colour and glyph. |
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
| A pin is its comment's state glyph in the state's colour, the one on its card: a grey ring while queued, a blue arrow once sent. The selected pin is larger, with an accent ring. | A marker shows its status without a hover, and not by colour alone. |
| While the agent's question on a comment is open, its pin is an orange question mark instead of its state. | The one pin the person has to act on stands out on the timeline; the state is still on the card. |
| The comment box and its text field are opaque, in the window's and the text field's own colours, with a hairline edge. | Over the black stage a material goes grey in light appearance, and the text and the hint on it go faint. |
| A click on a card does what a click on its marker does. | One way to see a comment's moment, from either place. |
| A draft has no marker and no card; the open comment box stands for it. | A marker is feedback that exists. The draft still shows in `state --json`, so an operator sees the box is open. |
| A queued card has an edit and a delete button. Edit turns the card's text into a text box with Save and Cancel. Delete asks nothing. | The fix happens where the mistake shows. A queued comment is cheap to write again. |
| Each state has a colour and a glyph: queued (grey ring), sent (blue arrow), acknowledged (blue check), working (orange dots, pulsing), done (green check), failed (red cross). | Status reads at a glance and does not depend on colour alone. |
| A region comment's rectangle shows on the frame only while its card is selected or the playhead is within 0.5 s of it. | The frame stays clean while watching. |
| The sidebar lists comments in time order, with the keyframe (or crop) as a thumbnail. | Time order matches the timeline. The thumbnail shows what the comment is about. |
| A thread shows inside its comment's card, under a divider: each message with a glyph and a word for who wrote it and what it is (`Agent`, `Agent asks`, `You answered`). | Answers stay next to the feedback. Author and kind read without colour. |
| An open question turns the card's edge orange and shows an answer box in it: one text field and an Answer button. Return answers, and the field grows to four lines. | A waiting agent is hard to miss, and the answer is one line and a key away. |
| A batch shows as a header card above its comments' first one: its id, its comment count, where it is (`Waiting for a listener`, `With the agent`, `Finished`) and its own thread. It is outlined, not filled, and can't be selected. | The spec's message for the full batch needs a place that is not one comment, and the header must not read as one more comment. |
| An agent message raises a toast at the top right of the stage for 5 s: `Agent · 0:10`, `Agent asks · 0:10` or `Agent · batch b1` over up to three lines of the text. At most three show, the newest. A click shows its comment (pause, seek, select) and dismisses it. | Seen while watching, gone without a click, and it never pauses the video. |
| An `ack` without a text and a status change raise no toast. | They are not messages: the pins and cards show them. A toast per status would be noise while watching. |
| The toast is opaque, in the window's background colour with a hairline edge and a shadow. | Over the black stage a material goes grey, as for the comment box. |
| The send bar at the bottom of the sidebar shows the queued count, the Send button and the presence chip (`No listener`, `Listening`, `Working`). | The person sees whether the batch will reach someone at the moment of sending. |
| Sending with no listener is allowed; the bar then says the batch waits for the next listener. | The spec's story 15. No dialog in the way. |
| The presence chip is a word with a glyph in a tinted capsule: grey `No listener`, green `Listening`, orange `Working`. | Read at a glance beside the Send button, and not by colour alone. |
| A send that is refused (nothing queued) says why in red under the send bar, until a comment is queued or a send works. | The reason shows where the person pressed, with no dialog. |
| Cmd+Enter has no menu item; it is watched for beside the player's keys, and ignored in a panel or under a sheet. | It must work while the comment box has the focus, which a player's key never does. |
| The sidebar's header counts the comments; the queued count is in the send bar. | The number beside Send is the number Send sends. |
| The lease banner is a one-line strip under the title bar, over whatever the window shows (the empty state too): "Claude Code controls this app", the place (a folder's last component), the time left, how many wait, Stop. It is tinted orange. | Always visible while an agent drives, and it takes one line. |
| Stop is a button in the banner only: no menu item, no key, no CLI command. A stopped agent is told to ask the person; nothing in the window lists it. | Stop is the person's override, so an agent can't reach it. A bar ends by itself after 5 min. |
| Screenshots show the window as it is, banner included. | A screenshot is evidence of what the person sees. The contract has no flag to hide it. |
| The context note is a popover from a toolbar button, with the sidecar's text above it, read-only. | Context is set once per video, so it should not take sidebar space. |
| The context button's glyph is filled when the video has a sidecar or a note, and its tooltip names them. | Whether the agent gets a context shows without opening the popover. |
| The popover keeps the note when it closes, not on every key. | The note is trimmed when kept, which would fight typing; and the listener gets a note once it is written, not half of it. |
| `context set ""` clears the note and says `context note cleared`. | The CLI needs a way to take a note away, and the contract has no other command for it. |
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
| #7 | `Batch`, `Outbox` (in memory), `BatchPayload`, `ListenerDesk`, long polls with the heartbeat, `wait` (`ListenerCommand`), `batch send` (`BatchCommand`), `Library.nextBatchID`, `SendBar`, Cmd+Enter (`SendKey`), presence, `listener`, `batches` and `batchId` in `state`, the requeue for a listener that started again |
| #8 | `VRTranscript`, `TranscriptService`, `SpeechSource`, `TranscriptCache` |
| #9 | `ContextSidecar`, the note, `ContextPopover`, `context set`, `Outbox.context` |
| #10 | `ThreadMessage`, the threads and their rules in `ReviewSession`, `ack`, `status`, `reply`, `ask` (`ListenerCommand`), `thread answer` (`ThreadCommand`), the parked `ask` in `ListenerDesk`, a batch finishing (`Outbox.finish`), `thread` and `notices` in `state`, `Notice`, `ThreadView` and `AnswerBox` in `CommentCard`, `BatchCard`, `NoticeToast`, the question on a pin |
| #11 | The rest of `Library`: `review.json`, `outbox.json`, the ids in `index.json`, `removeImages`; `ReviewSession.kept`, `Outbox.restart`; in `ReviewModel`: reviews read and saved through `Library`, the outbox saved on each change, reload on open and at launch (`restoreOutbox`, `restored`, `findImages`) |
| #12 | `.agents/skills/video-review-mate/`: `SKILL.md` and `mate.sh` |
| #13 | `scripts/acceptance.sh`, `make acceptance`, `assets/screenshots/v1-acceptance/` |
| the final review's fixes | the last open video (`Library.lastVideo`, `ReviewModel.reopenLastVideo` and `launched`), a new question not answered by an old answer (`ReviewSession.ask`), a screenshot's `.png` checked on the wire, `Later` and the tests' `FakeClock.advance` and `settle(until:)`, `PNGFile`, one `isBlank` per side |

Before #11, `Library` already existed (#5 needs image paths and ids): it kept the comment and batch counters and the keyframes on disk, and `ReviewModel` kept the sessions and the outbox in memory for the run. #11 moved the sessions and the outbox's parcels into `Library` and added reload on open and at launch. Tickets may move a file's first appearance earlier, never its owner.
