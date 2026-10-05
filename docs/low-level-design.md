# Video Review: low-level design (proto-2)

Written 2026-10-04, before the first build ticket, from the v1 spec (#1), ADR 0001 and the `effort:v1` tickets (#3 to #13). It is documentation for the maintainer, not a review gate. When the code and this document disagree, fix one of them in the same change.

Sources: the spec decides the modules, the CLI contract, the batch payload and the item states. ADR 0001 decides the wire, the roles and the lease. Shipyard (`yahyabedirhan/shipyard`, ADR 0006 and ADR 0007, `Sources/ShipyardControl/`, `Sources/ShipyardApp/Control/`) is the working example whose patterns this design copies; no code is linked from it. Everything the spec left open is decided here and listed under [Decisions](#6-decisions-the-spec-left-open).

NOTE: ADR 0001 names the listener commands `done` and `fail`. The spec's CLI contract names one command, `status <comment-id> working|done|failed`. The spec's contract is the one built.

NOTE: This document describes the whole build. [What is built so far](#7-what-is-built-so-far) lists the parts that exist in the code today.

## For a newcomer, in one screen

Video Review is one Swift package. It builds two executables: the macOS app and the `video-review` command, which ships inside the app bundle at `Contents/Helpers/video-review`. The code is seven modules, split by concern. The agent's side never links the app's rules.

```text
agent side (no app rules, no UI)
  ReviewWire        the control protocol: request, reply, holder, socket framing, socket and support folder locations, the app identity
  ReviewLease       the lease rules as a pure value (ControlLease), given the time on each call
  ReviewCommand     the command table of `video-review`: parse arguments, send one request, print the reply, pick the exit code
  ReviewCLI         main.swift only: runs ReviewCommand with the real environment

app side
  ReviewCore        the spec's "Review" module: comments, regions, batches, threads, the item state machine, the batch payload, the listener outbox. Pure logic.
  ReviewTranscript  the Transcriber interface, its three sources and the window cut
  ReviewStore       persistence under Application Support, keyed by the content hash of the video
  ReviewApp         the SwiftUI app: player, overlay, timeline, rail, control server, listener queue. The only UI code.

video-review (CLI)   → ReviewWire + ReviewLease + ReviewCommand
Video Review.app     → everything
```

```text
person ──keys, mouse──▶ ReviewApp UI ─┐
                                      ├─▶ AppModel ──▶ PlayerEngine      (AVPlayer)
operator agent ──▶ video-review ──▶ ControlServer ─┘      ├─▶ ReviewDesk ──▶ VideoReview (ReviewCore) ──▶ Library (ReviewStore)
                   (lease)          (control.sock)        └─▶ ListenerQueue ──▶ Outbox (ReviewCore)
listener agent ──▶ video-review wait / ack / status / reply / ask ──▶ ControlServer ──▶ ListenerQueue, ReviewDesk
                   (no lease)
```

The person and the operator agent reach the same `AppModel` methods, so a UI action and its CLI command are one code path. Where to look:

| You want to | Open |
|---|---|
| see where the app starts | `Sources/ReviewApp/VideoReviewApp.swift`, then `AppModel.swift` |
| see where the CLI starts | `Sources/ReviewCLI/main.swift`, then `Sources/ReviewCommand/CommandTable.swift` |
| add a CLI command | [Extensibility](#5-extensibility), first row |
| change a comment rule or a state | `Sources/ReviewCore/VideoReview.swift` and `CommentState.swift` |
| change what `wait` prints | `Sources/ReviewCore/BatchPayload.swift` |
| change the lease | `Sources/ReviewLease/ControlLease.swift` |
| change where data is kept | `Sources/ReviewStore/Library.swift` |
| change the app name of this prototype | `Sources/ReviewWire/AppIdentity.swift`, one line |

## 1. Requirements

### Capabilities

1. Open a local mp4, mov or m4v file and play it with QuickTime-like controls and shortcuts.
2. Add a comment at the current time. The comment keeps its timestamp and a PNG of the frame at that time.
3. Draw a rectangle on the frame and comment on it. The comment keeps the region (normalized 0..1) and a PNG crop.
4. Keep comments in a queue. Edit or delete a queued comment.
5. Send the full queue as one batch with Cmd+Enter or `batch send`.
6. Show each comment as a marker on the timeline, with its status. A click on a marker seeks to it.
7. Give a listener the next batch through a long-poll `wait`, as the payload JSON of the spec. Show listener presence.
8. Let the listener acknowledge a batch, set a comment's status, send a message on a comment or a batch, and ask a question and wait for the answer.
9. Show agent messages as a thread on each comment and as a brief notice. Let the person answer a question in the thread.
10. Give each comment the transcript from 15 s before to 15 s after its time, from the best source available.
11. Give the listener the video context (sidecar plus in-app note) once per listener session, and again when it changes.
12. Persist comments, threads, batches and statuses per video, keyed by content, across restarts, renames and moves.
13. Let agents drive every action through the `video-review` CLI over a Unix socket, one agent at a time through a lease.
14. Report the app's state as JSON, capture the app window in light and dark, and run on separate demo data.
15. Ship the listener skill `video-review-mate` in the repo.

### Rules and completion

- A comment moves `draft → queued → sent → acknowledged → working → done | failed`. It never moves back, with one exception: a batch that goes back to the queue after a listener restart returns its unfinished comments to `sent`.
- Only a `queued` comment can be edited or deleted. A sent comment is a record.
- A batch is all queued comments of the open video, in time order. A batch is finished when every comment in it is `done` or `failed`.
- A batch sent with no listener waits. The next `wait` gets it. Batches go out first in, first out, one per `wait`.
- A thread message has an author (`person` or `agent`) and a kind (`message`, `question` or `answer`). A comment has at most one open question.
- The listener is present while a `wait` is open. One listener at a time.
- The lease: the first operator command takes it, each later one renews it. It ends 60 s after the holder's last command and 5 min after it was taken at most. `control take --wait` queues holders first come, first served. The person's Stop ends it and bars the holder for 5 min. The person never needs the lease.
- A request of another protocol version is refused, naming both versions.

### Error handling

- Every refusal is a reply: `ok` false and one line in `error`. The CLI prints it on standard error.
- Exit codes: 0 done. 1 refused or failed (lease in use, unknown id, illegal state move, app not running, file not playable). 2 timed out with no result (`wait --timeout`, `ask --wait`). 64 wrong usage.
- Invalid input is refused before any state changes: a time outside the video, a region outside 0..1 or with no area, an empty comment text, a relative screenshot path, an unknown id.
- A file AVPlayer cannot play is refused with the reason. The open video stays open.
- A transcript source that fails gives no lines. It never blocks a comment or a batch.
- A store file from a newer schema version is left untouched and the app refuses to open that video's history, saying why.
- A reply that cannot be written (the client has gone) undoes what only the client would know: a granted `take` is released, a delivered batch goes back to the front of the queue.

### Scope

In: all of the above.

Out, as the spec says: video editing, formats AVPlayer cannot play, URLs, system-wide hotkeys, more than one listener, shapes other than rectangles, transcription research, a developer ID and notarization, any reuse of ReviewMate code. Also out by this design's choice: more than one window, system notifications, an Allow button that lifts a Stop early, undo.

### Requirement to module

| Requirement | Module | Ticket |
|---|---|---|
| 1 play a video | ReviewApp `Player/` | #3 |
| 2, 4, 6 comments, queue, markers | ReviewCore `VideoReview`, ReviewStore `ContentHash`, `ImageFiles`, ReviewApp `ReviewDesk`, `FrameGrabber`, `Stage/Composer`, `Timeline/Marker`, `Rail/CommentRow` | #5 |
| 3 regions | ReviewCore `Region`, ReviewApp `Stage/RegionOverlay`, `VideoFrameGeometry` | #6 |
| 5, 7 batches, `wait`, presence | ReviewCore `Outbox`, `BatchPayload`, ReviewApp `ListenerQueue` | #7 |
| 8, 9 answers and questions | ReviewCore `VideoReview` (threads), ReviewApp `ListenerQueue` (asks), `Rail/`, `Stage/Toasts` | #10 |
| 10 transcript | ReviewTranscript | #8 |
| 11 context | ReviewCore `Outbox.context`, ReviewApp `ContextReader` | #9 |
| 12 persistence | ReviewStore | #11 |
| 13 CLI, socket | ReviewWire, ReviewCommand, ReviewApp `Control/ControlServer` | #3 |
| 13 lease | ReviewLease, ReviewApp `Control/ControlServer`, `UI/LeaseBanner` | #4 |
| 14 state, screenshot, demo | ReviewApp `Control/StateReport`, `Control/Screenshotter`, ReviewWire `DemoPointer` | #3 |
| 15 skill | `.agents/skills/video-review-mate/` | #12 |
| acceptance scenario | `scripts/acceptance.sh` | #13 |

## 2. Entities and relationships

Terms, one word for one thing:

- **Video**: a local file the person opens. Its identity is its **content hash**.
- **Review**: everything kept about one video: its comments, batches and context note.
- **Comment**: text at a time, with an optional **region**, a **keyframe**, an optional **crop**, a state and a **thread**.
- **Queue**: the comments of the open video in state `queued`.
- **Batch**: the comments sent together by one Cmd+Enter, with batch-level messages.
- **Outbox**: the line of sent batches waiting for the listener, across all videos.
- **Listener session**: one agent listening, named by the holder key of its `wait`.
- **Holder**: who sends a control request. **Lease**: the holder's right to drive the app.
- **Operator**: an agent that drives the UI under the lease. **Listener**: an agent that receives batches, without a lease.

Entities (hold changing state or enforce rules):

| Entity | Owns | Lives in |
|---|---|---|
| `AppModel` (orchestrator) | which video is open, the draft, the selection, the notices | ReviewApp |
| `PlayerEngine` | the AVPlayer, the time, playing or paused | ReviewApp |
| `VideoReview` | the comments, threads and batches of one video, and every rule about them | ReviewCore |
| `ReviewDesk` | the one path for changing a `VideoReview`: change, save, publish | ReviewApp |
| `Outbox` | pending and taken batches, the listener session, the context already sent, presence | ReviewCore |
| `ListenerQueue` | the open `wait` and `ask` connections, payload assembly | ReviewApp |
| `Library` | the files under the support folder | ReviewStore |
| `ControlLease` | who holds the lease, the line of waiters, the bars | ReviewLease |
| `ControlServer` | the socket, the one lease instance, dispatch of requests | ReviewApp |
| `TranscriptSources` | which transcript source serves a video | ReviewTranscript |
| `SpeechSource` | the speech lines of each video so far, and whether its transcription runs, is done or gave up | ReviewTranscript |
| `TranscriptDesk` | the videos opened in this run, and the app's one way to their transcripts | ReviewApp |

Fields, not entities: `Region`, `ThreadMessage`, `Batch`, `CommentState`, `Holder`, `LeaseTerm`, `TranscriptLine`, `Transcript`, `VideoFile`, `BatchPayload`. They are data on the entities above.

Relationships:

```text
AppModel ──owns──▶ PlayerEngine
AppModel ──owns──▶ ReviewDesk ──holds──▶ VideoReview ──contains──▶ Comment ──contains──▶ ThreadMessage
                        │                     └──contains──▶ Batch ──refers to──▶ Comment (by id)
                        └──saves through──▶ Library
AppModel ──owns──▶ ListenerQueue ──holds──▶ Outbox ──refers to──▶ Batch (by id and content hash)
                        ├──changes reviews through──▶ ReviewDesk
                        └──reads──▶ TranscriptDesk ──asks──▶ TranscriptSources; ContextReader, Library (image paths)
AppModel ──owns──▶ TranscriptDesk                         (a video that opens is told to it)
ControlServer ──holds──▶ ControlLease
ControlServer ──calls──▶ AppModel (operator and free requests), ListenerQueue (listener requests)
UI views ──read──▶ AppModel, ReviewDesk, ListenerQueue, PlayerEngine   ──call──▶ AppModel
```

Where each rule lives:

- "Can this comment change state, be edited, be answered?" lives in `VideoReview`, which holds the comments.
- "Which batch does this `wait` get, is this a new listener, is the context due?" lives in `Outbox`.
- "May this holder drive the app now?" lives in `ControlLease`.
- "Is this time inside the video, is a video open?" lives in `AppModel`, which owns the lifecycle.

Module dependencies run one way:

```text
ReviewWire        ← Foundation only
ReviewLease       ← ReviewWire          (Holder, LeaseTerm)
ReviewCommand     ← ReviewWire, ReviewLease, Synchronization; AppKit for the launcher only, on macOS
ReviewCLI         ← ReviewCommand

ReviewCore        ← Foundation only
ReviewTranscript  ← Foundation, Synchronization; AVFoundation and Speech in `AppleSpeechRecognizer` only, on macOS
ReviewStore       ← ReviewCore, ReviewTranscript; CryptoKit in `ContentHash` and ImageIO in `ImageFiles`, on Apple platforms
ReviewApp         ← all of the above, SwiftUI, AVKit, ScreenCaptureKit; macOS only
```

`ReviewCore` does not import `ReviewWire`: the server turns a request into a call and a result into a line. `ReviewCommand` does not import `ReviewCore`: the payload and the state report cross the socket as text in `output`.

Off the Mac (a Linux machine) the package is the six modules without `ReviewApp` (D214). A file that needs an Apple framework is behind `#if canImport(…)`, and `ReviewWire` imports `Glibc` in place of `Darwin`.

## 3. Class design

### The app identity: one line

Three prototypes run on one Mac. Each needs its own app name, bundle id and support folder. The one setting is a Swift constant; the `Makefile` reads it, as Shipyard's `Makefile` reads its version.

```swift
// Sources/ReviewWire/AppIdentity.swift
public enum AppIdentity {
    public static let variant = "proto-2"      // the real product: ""
    public static var appName: String          // "Video Review (proto-2)"  or "Video Review"
    public static var bundleID: String         // "com.yahyabedirhan.video-review.proto-2"  or without the suffix
    public static var supportFolderName: String { appName }
}
```

```make
VARIANT   := $(shell sed -n 's/.*static let variant = "\(.*\)".*/\1/p' Sources/ReviewWire/AppIdentity.swift)
APP_NAME  := Video Review$(if $(VARIANT), ($(VARIANT)))
BUNDLE_ID := com.yahyabedirhan.video-review$(if $(VARIANT),.$(VARIANT))
```

`make bundle` writes `APP_NAME`, `BUNDLE_ID` and the version into `Packaging/Info.plist` (placeholders `__APP_NAME__`, `__BUNDLE_ID__`, `__VERSION__`). The executable inside the bundle is always `Contents/MacOS/VideoReview`, and the CLI is always `Contents/Helpers/video-review`. The constant is the source and not a `Makefile` variable, so `swift test` sees the same identity with no generated file. `make install` quits only this bundle (`pkill -f` on the installed bundle's full executable path), never another prototype's app. The app quits cleanly on that `SIGTERM`, so it removes its socket.

The CLI starts the app whose bundle it ships in (`<app>/Contents/Helpers/video-review`), so each prototype's command starts its own app. Outside a bundle it falls back to the installed app with this build's bundle id.

### Folder tree

```text
Package.swift                      targets below; platforms: macOS 26; no dependencies; ReviewApp and ReviewAppTests on macOS only
Makefile                           test, build, bundle, install, acceptance, clean; reads VARIANT and VERSION from ReviewWire
Packaging/Info.plist               the bundle's template; speech recognition usage text
scripts/acceptance.sh              the v1 acceptance scenario, CLI only (#13)
scripts/screenshots.sh             the scene of the pictures in assets/screenshots/v1-acceptance/, CLI only
assets/screenshots/v1-acceptance/  the app in light and dark: a thread and a region, an open question and the queue, the lease banner (older than the toolbar sign; to make again)
.agents/skills/video-review-mate/  the listener skill (#12)
fixtures/sample/                   the fixture video and its sidecars

Sources/
  ReviewWire/
    AppIdentity.swift              the variant, the app name, the bundle id (one line to change)
    Version.swift                  the app version and the protocol version
    Holder.swift                   who sends a request; Holder.find from the environment and the process table
    LeaseTerm.swift                a lease held: holder, taken, ends (data in the reply and the handover)
    ControlRequest.swift           every request as an enum case; its role (free, operator, listener); how long the app may hold it
    ControlMessage.swift           request plus holder as one JSON object; decode refuses another version
    ControlReply.swift             {ok, output, error, lease?, timedOut?}
    ControlProtocolError.swift     unreadable, otherVersion, unknownCommand, each with its line
    TimeCode.swift                 "90", "1:30", "0:01:30.5" to seconds and back
    UnixSocket.swift               POSIX calls (Darwin, or Glibc off the Mac): the address (through a short link for a long path), connect, bind, write all, half-close, read to end
    ControlClient.swift            one exchange over the socket; the ControlTransport seam for tests
    ControlSocket.swift            where control.sock is; follows the demo pointer
    DemoPointer.swift              demo.json in the normal support folder
    SupportFolder.swift            the support folder; VIDEO_REVIEW_SUPPORT_DIR moves it
  ReviewLease/
    ControlLease.swift             the lease rules as a pure value: use, take, release, stop, settle, giveUp, status
  ReviewCommand/
    CommandTable.swift             the commands by name, usage text, global --json
    VideoReviewCLI.swift           run(arguments, environment) → output, error, exit code; CommandResult and CommandEnvironment
    AppCommands.swift              app status | open [--demo] | quit, and state
    ControlCommands.swift          control take [--wait <s>] | release
    PlayerCommands.swift           player open | play | pause | seek
    CommentCommands.swift          comment add | edit | delete, batch send, thread answer, context set
    ScreenshotCommand.swift        screenshot <abs.png> [--appearance] [--with-banner]
    ListenerCommands.swift         wait, ack, status, reply, ask
    AppLauncher.swift              starts the app through Launch Services (off the Mac: refuses); the AppLaunching seam for tests
  ReviewCLI/
    main.swift                     exit(VideoReviewCLI.run(...))
  ReviewCore/
    Comment.swift                  Comment, Region (validation)
    ThreadMessage.swift            ThreadMessage: author, kind, text, time; the open question of a thread
    CommentState.swift             the seven states, the legal moves, and which state can still be edited
    Batch.swift                    Batch: id, sentAt, comment ids, batch-level messages; BatchRef: a batch id and its content hash
    VideoReview.swift              one video's review: every rule about comments, batches and threads
    ReviewRefusal.swift            why a change is refused, as the line the CLI prints
    Outbox.swift                   the listener outbox: pending, taken, session, context sent, presence
    BatchPayload.swift             the JSON `wait` prints, and how it is assembled
    ItemID.swift                   short ids: c-xxxxxxxx, b-xxxxxxxx, m-xxxxxxxx
  ReviewTranscript/
    TranscriptLine.swift           start, end, text
    Transcriber.swift              the interface: a video and a window in, timed lines out; VideoFile, Transcript, TranscriptSource
    TranscriptWindow.swift         the cut: lines that overlap time-15 … time+15
    TranscriptSources.swift        the source order; picks the first source that serves the video
    VoiceoverSource.swift          voiceover.json; scene times from scene lengths
    SubtitleSource.swift           .srt and .vtt sidecars, and their parser
    SpeechSource.swift             speech in the background: the lines so far, once per video, kept in a cache; the SpeechRecognizing seam
    AppleSpeechRecognizer.swift    Apple SpeechAnalyzer on the video file's sound, one line per finalized result
  ReviewStore/
    Library.swift                  reviews, the outbox and the last video on disk: load, save, the schema version; the id index
    ContentHash.swift              SHA-256 of the file, streamed
    ImageFiles.swift               where keyframes and crops are, writing and removing a PNG, a small copy for a row
    TranscriptFiles.swift          where a video's finished speech transcript is kept: load and save
  ReviewApp/
    VideoReviewApp.swift           @main; the one window; the menu commands
    AppModel.swift                 the orchestrator; every action a person or an operator can take
    ReviewDesk.swift               change a review, save it, publish it
    ListenerQueue.swift            open waits and asks; delivery; payload assembly; presence; the listener's answers
    Notice.swift                   one notice of what the agent said: its subject, kind, words and when it goes
    ContextReader.swift            the sidecar context file plus the note
    TranscriptDesk.swift           the videos opened in this run; a comment's lines and the transcript's report, asked of the sources
    Player/
      PlayerEngine.swift           AVPlayer: open, play, pause, exact seek, time
      PlayerSurface.swift          AVPlayerView without controls, as a SwiftUI view
      FrameGrabber.swift           keyframe and crop PNGs from the asset, at the exact time
      Shortcuts.swift              the player's keys, off while a text field has the focus
    Control/
      ControlServer.swift          the socket, the lease, held requests, dispatch
      LeaseIndicator.swift         the lease as the banner (the toolbar's agent-control sign) draws it; hidden while a screenshot leaves it out
      StateReport.swift            `state` and `app status` as JSON and as lines
      Screenshotter.swift          the app window through ScreenCaptureKit, in an appearance
    UI/
      RootView.swift               the toolbar (agent-control sign, Context, Comments), the subtitle, stage, timeline, rail; the app's tint
      Theme.swift                  one place for the measures, the pastel palette, the fills, and the status colours and glyphs
      LeaseBanner.swift            who controls the app, and Stop: the banner's words (pure), the toolbar sign and its popover
      QuietButtonStyle.swift       the lane's and a row's symbol buttons: hover and press feedback
      EmptyState.swift             no video open
      ContextPopover.swift         the toolbar's Context button; the sidecar text, the editable note and the transcript part
      TranscriptChip.swift         the transcript's source and progress as words (pure), shown in the Context popover
      CommentEditor.swift          the text view a comment is written in (the composer and a row being edited), and its keys
      Stage/StageView.swift        the video with the overlay, the composer and the notices
      Stage/RegionOverlay.swift    draw a rectangle; show a comment's region
      Stage/VideoFrameGeometry.swift  view points to normalized frame coordinates and back (pure)
      Stage/Composer.swift         the comment box, and where it sits on the stage (pure)
      Stage/Toasts.swift           the brief notices
      Timeline/TimelineLane.swift  play button, time, scrubber, the Comment button; as tall as the rail's foot
      Timeline/Marker.swift        one marker's pin (number, state, unread badge), and the layer of pins above the track
      Rail/RailView.swift          the queue, then each batch, as sections with a header band
      Rail/CommentRow.swift        one full-width row: thumbnail, time, text, status, edit and delete, the thread or its last message
      Rail/ThreadView.swift        the messages as chat bubbles and the answer box; a batch's messages too
      Rail/SendBar.swift           presence (dot and words) and the Send button; as tall as the timeline lane

Tests/
  ReviewWireTests/                 version refusal, message round trips, time codes, the demo pointer, Holder.find
  ReviewLeaseTests/                time-driven tables
  ReviewCommandTests/              parsing, the request sent, output and exit codes, with a fake transport and launcher
  ReviewCoreTests/                 the state machine, batch assembly, the outbox
  ReviewTranscriptTests/           the window cut, the source order, voiceover timing, srt and vtt parsing (reads fixtures/sample), speech with a recognizer the test drives
  ReviewStoreTests/                round trips in a temp folder, the content hash of a renamed copy, the kept transcript, the library (the id index, files that do not read, a newer schema, a save that fails, the outbox rebuilt)
  ReviewAppTests/                  macOS only. ControlServer with a fake app, the lease gate and the line of takes over the real socket, the keys, comments and batches through AppModel on the fixture video, the listener queue behind the server, VideoFrameGeometry, the transcript window in the payload (voiceover, srt only, slow speech), restarts (a second model on the same support folder)
```

A module and a type never share a name, so a type can always be qualified by its module.

### ReviewWire

`ControlRequest` is one enum, one case per command of the spec's contract:

| Role | Cases | Lease |
|---|---|---|
| free | `appStatus`, `state`, `controlTake(waitSeconds?)`, `controlRelease` | none |
| operator | `appOpen`, `appQuit`, `playerOpen(path)`, `playerPlay`, `playerPause`, `playerSeek(seconds)`, `commentAdd(text, at?, region?)`, `commentEdit(id, text)`, `commentDelete(id)`, `batchSend`, `threadAnswer(commentID, text)`, `contextSet(text)`, `screenshot(path, appearance?, withBanner)` | takes or renews |
| listener | `wait(timeout?)`, `ack(batchID, text?)`, `status(commentID, state)`, `reply(id, text)`, `ask(commentID, question, waitSeconds?)` | none |

- `status`'s state is a `ControlRequest.Status` (`working`, `done`, `failed`): the agent side does not link `ReviewCore`, so the wire has its own three names, and the server turns one into the `CommentState` of the same name. `ask --wait` is 0 to 86400 s, as `wait --timeout`; without the option it has no limit. On the wire `ack`, `status`, `reply`, `ask` and `thread.answer` carry `id` and `text` (`ack`'s text is optional), `status` its `state`, and `ask` its `waitSeconds`.
- `role` and `holdSeconds` (how long the app may keep the connection: a `take`'s wait, a `wait`'s timeout, an `ask`'s wait, or no limit) are computed properties on the request, so the server and the client agree without a table. A `take` waits 3600 s at most (`ControlRequest.longestWait`); the command and `decode` both refuse more. A `wait --timeout` is 0 to 86400 s (`ControlRequest.longestListen`); without the option it has no limit.
- `ControlReply` is `{ok, output, error, lease?, timedOut?}`. `timedOut` is true only in the reply to a held request whose time ran out with nothing to say (`ControlReply.ranOut`); the command exits 2 on it and prints nothing.
- `UnixSocket.peerClosed(descriptor)` says whether the peer closed its socket, by `poll` for writing: a hang-up shows there only once the peer is gone, not when it half-closed after its request.
- `commentAdd`'s region is a `ControlRequest.Rectangle`: the four numbers of `--region x,y,w,h` as they were written, as the object `{"x", "y", "w", "h"}` on the wire. `Rectangle(text)` reads four numbers with commas between them and nothing else; the command refuses any other text as wrong usage (exit 64). Whether the numbers are a region of the frame is the app's rule (`Region.init` in `ReviewCore`, which `ReviewWire` does not link): the server makes the `Region` before it calls the app, and refuses with exit 1.
- On the wire a message is one JSON object: `version`, `command` (`player.seek`), `holder` (`key`, `name`, `place`), `json` (the caller passed `--json`) and the command's own fields. Protocol version 1.
- `ControlMessage.decode` refuses in this order: not JSON, another version (naming both), no holder, unknown command, a missing or invalid field.
- `Holder.find(variables, workingDirectory, processes)`: the key is `VIDEO_REVIEW_CONTROL_KEY` when set, else `CLAUDE_CODE_SESSION_ID`, else the nearest ancestor process that is not a shell, as `process:<pid>@<start>`. The name is `Claude Code` or the process name. The place is the Herdr pane when there is one, else the working folder. The process table is a protocol with the system's reader (`sysctl` on macOS, `/proc/<pid>/stat` on Linux) and a fake.
- `ControlClient.send(request)` writes the message, half-closes, reads to the end. Its read timeout is 15 s plus `holdSeconds`, or none when the request has no limit. A connection that closes with no reply reads as an app that is not running.
- `UnixSocket.address(path)`: a socket address holds 103 bytes. A longer path (a demo folder deep in a worktree) is reached through a symbolic link to its folder, in the user's temporary folder (`confstr(_CS_DARWIN_USER_TEMP_DIR)` on macOS, `NSTemporaryDirectory()` elsewhere), named after a hash of the folder's path. The app and the CLI each make the same link, so neither tells the other.
- `SupportFolder.app(environment)`: `VIDEO_REVIEW_SUPPORT_DIR` when it is an absolute path, else `~/Library/Application Support/<AppIdentity.supportFolderName>/`.
- `ControlSocket.locate(support)`: the demo's socket while `demo.json` names a demo folder whose socket exists, else the folder's own.

### ReviewLease

`ControlLease` copies the rules of Shipyard's `ControlLease`: a struct with `renewal` 60 s, `cap` 5 min and `bar` 5 min, and the time passed into every call. A holder is the same across requests by its key; its name and place are as its latest request says. The lease it holds is a `LeaseTerm` (the data in `ReviewWire`), which this module extends with `capped`, `secondsLeft(at:)` and the line `control take` prints.

| Call | Does | Returns |
|---|---|---|
| `use(by:at:)` | an operator request: takes a free lease to `now + renewal`, renews the holder's, never past the cap | `Decision`: the `LeaseTerm` or a `Refusal`, plus transitions |
| `take(by:at:waitingUntil:)` | `control take`: holds to the cap; behind another holder it queues until the deadline, one place per key | `Decision` (`queued` means no answer yet) |
| `release(by:at:)` | ends the holder's lease; the first waiter gets it | transitions |
| `stop(at:)` | the person's Stop: ends the lease, bars the holder for `bar` | transitions |
| `settle(at:)` | ends a lease that ran out, lifts ended bars, hands a free lease to the first waiter | transitions |
| `giveUp(by:waited:at:)` | a waiter's wait ran out | `Decision` |
| `current(at:)`, `waiting(at:)`, `status(at:)`, `nextEnd(after:)` | read-only | the term, how many takes wait, the `Status` for `app status` and `state`, when to settle next (the lease's end or a bar's) |

`Status` is the held lease as it is reported: `holder` (`key`, `name`, `place`), `taken`, `ends`, `secondsLeft` (whole, rounded up) and `waiting`. `Decision` is the answer (the `LeaseTerm` or a `Refusal`) plus the transitions (`started`, `renewed`, `ended` with why: `expired`, `capped`, `released`, `stopped`), which the tests read and the server ignores.

`Refusal` is `inUse(term)`, `queued(term)`, `waitedOut(seconds, term)` or `stopped`, and writes its own line, naming the holder, its place and the end time. A stopped holder reads `the person took <app> back; ask them before using it again`. `handover(term)` and `init(environment:at:)` carry a lease across `app quit` and a relaunch in `VIDEO_REVIEW_CONTROL_LEASE`, so `app open --demo` on a running app keeps the operator's lease.

### ReviewCommand

- `CommandTable` maps `app status`, `player seek` and the rest to a parser that returns a `ControlRequest` or a usage error. `--json` is accepted on every command.
- `VideoReviewCLI.run(arguments, environment)` returns `CommandResult(output, error, exitCode)`. `environment` holds the variables, the working folder, the process table, the transport and the launcher, so tests replace all of them.
- The CLI makes paths absolute against its own working folder before it sends them (`player open`, `app open --demo`); `screenshot` requires an absolute path, as the contract says.
- `control take [--wait <seconds>]` prints `you hold <app> until <HH:mm:ss>`. Behind another holder it is refused at once, or with `--wait` (0 to 3600) waits in line; a wait that runs out is a refusal, exit 1, saying how long it waited and who still holds the app. `control release` prints `released <app>`, also when the caller holds nothing. The contract gives them no `--key`: a holder names itself with `VIDEO_REVIEW_CONTROL_KEY`.
- `app status` answers without the app: `not running`, exit 0. Every other command but `app open` and `wait` exits 1 with `Video Review isn't running; run video-review app open` when nothing listens.
- `app open [--demo <folder>]`: when the app does not run, it launches the bundle the command ships in without activating it, with `VIDEO_REVIEW_SUPPORT_DIR` for a demo, waits for the socket, then sends `app.open`. When the app already runs on the data asked for, it only sends `app.open`. When the app runs on other data, it sends `app.quit`, takes the lease from the reply and relaunches with the handover (`ControlLease.handover`, in the launch environment). Plain `app open` from a demo does the same. `--demo` records the pointer; plain `app open` removes it. A demo that does not come to run leaves no pointer.
- The launcher waits for a quitting copy of the app to end. For a demo launch, a copy that is still there (one that `make install` has just opened and that does not answer yet) is asked to quit first: Launch Services would hand that copy back on its own data.
- A text may look like an option (D201). An argument that starts with `--` is an option, except when it has a space in it or comes after a `--` argument: then it is a word (`Arguments.isOption`, `Arguments.optionsEnd`). `--` itself ends the options and is dropped. `--help` and `-h` print the usage only before the command's name; after it, `-h` is a word and `--help` an unknown option. A time that would read as infinity is no time (`TimeCode.seconds`, D202).
- `--json` is taken from anywhere on the command line before a `--`. An action then prints the parts of the state it changed (`player seek` prints `{"player": {…}}`, `player open` adds `video`, `screenshot` prints `{"path": …}`). `app status --json` prints `{"running": false}` when the app is not running.
- `wait [--timeout <seconds>]` (`ListenerCommands.wait`) prints the payload as JSON with or without `--json`. It connects again while the app is not running or quits, once a second, until its timeout, and looks for the socket again each time (the app may come back on a demo's data). A listener can start before the app. Each request asks only for the time that is left, counted by the environment's clock (`CommandEnvironment.now`, which tests replace). Exit 0 with the batch, 2 when the time ran out (nothing printed), 1 when the app refuses (a newer `wait` took its place).
- `batch send` prints `b-5d0c2a91 sent with 2 comments, taken by the listener`, or `…, waiting for a listener`. With `--json` it prints `{"batch": {"id", "sentAt", "commentIds"}}`.
- `context set <text>` takes one word of text and prints `context note set (14 characters)`. An empty text clears the note and prints `context note cleared`. With `--json` it prints `{"video": {…}}` with the new `contextNote`.
- The listener's answers are plain requests (`Invocation.send`). `ack <batch-id> [<text>]` prints `b-5d0c2a91 acknowledged, 2 comments` (`--json`: `{"batch": {…}}`). `status <comment-id> working|done|failed` prints `c-7f3a9c2e working` (`--json`: `{"comment": {…}}`); another word for the state is wrong usage (exit 64). `reply <comment-id|batch-id> <text>` prints `m-524fd296 on c-7f3a9c2e` (`--json`: `{"message": {"id", "author", "kind", "text", "at"}}`). `ask <comment-id> <question> [--wait <seconds>]` prints the answer's text and exits 0 (`--json`: `{"answer": {…}}`, the answer as a message). When its wait runs out it prints nothing and exits 2: `VideoReviewCLI.result` exits 2 on any reply with `timedOut`. `thread answer <comment-id> <text>` is an operator command and prints `c-7f3a9c2e answered` (`--json`: `{"comment": {…}}`).

### ReviewCore

```swift
public struct VideoReview: Codable, Equatable {       // one video's review
    public var video: VideoInfo                        // contentHash, title, duration, path and frameRate (as last opened)
    public var note: String                            // the in-app context note
    public private(set) var comments: [Comment]        // kept in time order
    public private(set) var batches: [Batch]           // in the order sent

    // the person and the operator
    mutating func addComment(id:, time:, text:, region:) throws(ReviewRefusal) -> Comment   // state queued; the text is trimmed
    mutating func editComment(_ id:, text:) throws(ReviewRefusal) -> Comment     // queued only
    mutating func deleteComment(_ id:) throws(ReviewRefusal) -> Comment          // queued only; returns what it removed
    mutating func send(batchID:, at now:) throws(ReviewRefusal) -> Batch         // all queued → sent; refused when the queue is empty
    mutating func answer(_ commentID:, text:, messageID:, at now:) throws(ReviewRefusal) -> ThreadMessage   // needs an open question

    // the listener
    mutating func acknowledge(_ batchID:, text:, messageID:, at now:) throws(ReviewRefusal) -> Batch   // sent → acknowledged; text is a batch message
    mutating func setStatus(_ commentID:, _ state:) throws(ReviewRefusal) -> Comment   // working | done | failed, forward only
    mutating func reply(to id:, text:, messageID:, at now:) throws(ReviewRefusal) -> ThreadMessage   // a comment's thread or a batch's messages
    mutating func ask(_ commentID:, question:, messageID:, at now:) throws(ReviewRefusal) -> ThreadMessage   // refused while a question is open
    mutating func requeue(_ batchID:) -> [ItemID]                                // unfinished comments back to sent

    var queue: [Comment] { get }                       // state queued, time order
    func isFinished(_ batchID:) -> Bool
}
```

- `CommentState.canMove(to:)` is the state machine: forward only, skips allowed (`sent → working`, `acknowledged → done`), `done` and `failed` final. `draft` is a comment still in the composer; it lives in `AppModel` and enters a `VideoReview` as `queued`.
- `Region` holds `x, y, w, h` from the top-left corner of the displayed frame. `Region.init` refuses values outside 0..1, a rectangle that leaves the frame, and a width or height of 0 (`ReviewRefusal.badRegion`), so a `Region` that exists is always valid; reading one from JSON goes through the same check. `x + w` and `y + h` may pass 1 by 1e-9, since 0.7 + 0.3 is not exactly 1 in binary. `Region.pixels(width:height:)` gives the region's whole pixels in a picture: each edge rounded to the nearest pixel, at least one pixel each way, inside the picture. `Region.text` is `0.25,0.2,0.3,0.25`, as `--region` takes it.
- Ids and the time come in as arguments, so tests are deterministic. `ItemID` makes `c-`, `b-` and `m-` ids with 8 random hex digits; the prefix tells `reply` whether its target is a comment or a batch. An `ItemID` reads only from text of that shape, and is one string in JSON.
- A `Comment` holds `id`, `time`, `text`, `state`, `region` (nil for the whole frame) and `batchID` (nil while it is queued). It holds no image path: the keyframe and the crop are files named after the id (`ImageFiles`).
- Comments at the same time stay in the order they were added. `CommentState.isEditable` is true for `queued` only.
- A `Batch` is `id`, `sentAt` and `commentIDs` in time order. `send(batchID:at:)` moves every queued comment to `sent` and gives it the batch's id. `comments(of:)` gives a batch's comments. `isFinished` is true when each of them is `done` or `failed`. `requeue` returns the unfinished ones to `sent`, which is the one move back, and leaves the finished ones.
- A `ThreadMessage` is `id`, `author` (`person` or `agent`), `kind` (`message`, `question` or `answer`), `text` and `at`. A comment's `thread` and a batch's `messages` are arrays of them, in the order written. A review file written before threads existed reads with empty ones. A time that enters a review (`sentAt`, a message's `at`) is cut to the millisecond, which is what the file holds, so a review reads back equal to the one that was saved. `[ThreadMessage].openQuestion` is the last question while no answer follows it; `Comment.openQuestion` is its thread's.
- `acknowledge` moves each comment of the batch that is still `sent` to `acknowledged`, and leaves one further on where it is. Words that come with it are an agent `message` on the batch.
- `setStatus` takes `working`, `done` or `failed` (`CommentState.isStatus`), and moves forward only (`canMove`). The state the comment already has is accepted and changes nothing. Any other move is `illegalMove`.
- `reply` adds an agent `message` to a comment's thread, or to a batch's messages when the id is a batch's. `ask` adds an agent `question`, refused while one is open (`questionOpen`). `answer` adds a person's `answer`, refused with no open question (`noQuestion`). A reply does not close a question.
- The listener answers only a comment that was sent: `setStatus`, `reply` and `ask` on a queued comment are refused (`notSent`). A message with no words is refused (`emptyMessage`).
- `ReviewRefusal` is `emptyText`, `unknownComment(id)`, `notQueued(id, state)`, `badRegion(x, y, w, h)`, `nothingQueued`, `unknownBatch(id)`, `emptyMessage`, `notSent(id)`, `illegalMove(id, from, to)`, `questionOpen(id)` or `noQuestion(id)`, each with its `line`.

`Outbox` is the listener's side as a pure value, given the time on each call, like the lease:

```swift
public struct Outbox: Codable, Equatable {
    private(set) var pending: [BatchRef]    // sent, not yet delivered; first in, first out. BatchRef = batch id + content hash
    private(set) var taken: [BatchRef]      // delivered, not finished
    private(set) var session: ListenerSession?   // holder key, name, place of the last `wait`
    private(set) var isWaitOpen: Bool       // one run only, not on disk
    private(set) var openAsks: Int          // how many asks are held open; one run only, not on disk
    private(set) var lastHeard: Date?       // one run only, not on disk
    private(set) var contextSent: [String: String]   // content hash → digest of the context text this session last got

    mutating func enqueue(_ ref:)                                    // a batch is in line once
    mutating func waitOpened(by listener:, at now:) -> [BatchRef]    // a new key is a new session: taken → front of pending, contextSent emptied; returns the requeued
    mutating func waitClosed(at now:)                                // the open wait ended with no batch
    mutating func deliverNext(at now:) -> BatchRef?                  // only while a wait is open: pending.first → taken; the wait is answered, so no longer open
    mutating func undelivered(_ ref:)                                // the reply could not be written: back to the front; its video's digest is forgotten
    mutating func discard(_ ref:)                                    // nothing of it is left to deliver: out of the line
    mutating func finished(_ ref:)
    mutating func context(for hash:, text:) -> String?               // the text when it is due, else nil; records the digest
    func isContextDue(for hash:, text:) -> Bool                      // there is a text, and its digest is not the one this session has
    mutating func heard(at now:)                                     // any listener command
    mutating func askOpened(at now:)                                 // an ask is held for its answer
    mutating func askClosed(at now:)                                 // answered, out of time, or its client gone
    func presence(at now:) -> Presence                               // listening | working | absent
    mutating func reconcile(unfinished: [BatchRef])                  // at launch: agree with the reviews on disk
    func isKeptAs(_ other:) -> Bool                                  // the same on disk: pending, taken, session, contextSent
}
```

`ListenerSession` is the holder's `key`, `name` and `place` as `ReviewCore`'s own type, since `ReviewCore` does not link `ReviewWire`. `Codable` keeps `pending`, `taken`, `session` and `contextSent`; an outbox read from disk has no open `wait`, and a key that is missing reads as empty. `reconcile(unfinished:)` is given every batch on disk with an unfinished comment, in the order sent: a batch that is no longer one of them leaves `pending` and `taken`, and one that is in neither joins the end of the line, in one pass with a set of what is in line already. So a run that ended between the save of a review and the save of the outbox, and an outbox file that was lost, cost no feedback.

The context rule: `context(for:text:)` gives the text on a session's first batch of a video and whenever the text's digest differs from the one the session last got, and `nil` otherwise. With no text it gives `nil` and keeps the digest, so a sidecar that goes and comes back unchanged is not sent again. The digest (`Outbox.digest`) is the text's length in bytes and its 64-bit FNV-1a hash, the same in every run of the app. `VideoReview` reads a review with no `note` key as an empty note.

Presence: `working` when the session has a taken batch and is alive; `listening` when it is alive and nothing is taken; `absent` otherwise. Alive means a `wait` or an `ask` is open, or the last listener command or the close of its `wait` was less than 120 s ago while a batch is taken (`Outbox.workingGrace`), or less than 5 s ago otherwise (`Outbox.listeningGrace`, so a listener that runs `wait` in a loop does not flicker).

`BatchPayload` is the Codable shape of the spec, and `BatchPayload.assemble(review, batch, context, transcript:, images:)` builds it. The two closures give each comment its transcript lines (`BatchPayload.Line`: `start`, `end`, `text`) and its image paths (`BatchPayload.Images`), so `ReviewCore` needs neither `ReviewTranscript` nor `ReviewStore`. The payload carries the batch's comments that are not finished, so a batch delivered again holds only what is left. `video.duration` is rounded to the millisecond, as in `state`. `json` prints it with sorted keys, `null` for every key with no value and the time as ISO 8601.

```json
{
  "batch":   { "id": "b-5d0c2a91", "sentAt": "2026-10-04T19:02:11Z" },
  "video":   { "path": "/abs/sample.mp4", "contentHash": "<64 hex>", "duration": 21.233, "title": "sample" },
  "context": "…the sidecar text…\n\n## Note from the reviewer\n\n…the note…",
  "comments": [
    { "id": "c-7f3a9c2e", "time": 10.0, "text": "…", "keyframePath": "/abs/…/frames/c-7f3a9c2e.png",
      "region": null, "cropPath": null,
      "transcript": [ { "start": 0, "end": 6.067, "text": "This is Video Review. …" },
                      { "start": 6.067, "end": 14.333, "text": "Your comments queue up. …" },
                      { "start": 14.333, "end": 21.233, "text": "The agent reads your notes …" } ] },
    { "id": "c-1b44e0d7", "time": 12.5, "text": "…", "keyframePath": "/abs/…/frames/c-1b44e0d7.png",
      "region": { "x": 0.25, "y": 0.2, "w": 0.3, "h": 0.25 }, "cropPath": "/abs/…/crops/c-1b44e0d7.png",
      "transcript": [ … ] }
  ]
}
```

### ReviewTranscript

```swift
public protocol Transcriber: Sendable {
    func transcript(of video: VideoFile) -> Transcript?        // what the source has now; nil: it has nothing for this video
    func prepare(_ video: VideoFile)                           // the video opened: a source that needs time starts (default: nothing)
    func lines(for video: VideoFile, in window: ClosedRange<TimeInterval>) -> [TranscriptLine]   // default: the cut of transcript(of:)
}
```

- `VideoInfo.frameRate` is the frame rate the player read when the video was last opened; a review kept before it existed has none. It lets a `voiceover.json` be read for a batch that is delivered in a run that did not open the video.
- `VideoFile` is the file URL, the content hash (the key a source keeps its work under), the frame rate and the duration. `Transcript` is what is known of a video's transcript now: `source` (`voiceover`, `subtitles` or `speech`), `lines` in time order, `complete`, and `problem` (why the source gave up, else nil). `TranscriptLine` is `start`, `end`, `text`, with the times to the millisecond in every source.
- A source answers at once with what it has and never makes its caller wait. This is how a comment sent before the transcript is ready gets the lines that exist then.
- `TranscriptSources` holds the sources in order and is a `Transcriber` itself: `pick(for:)` is the first source whose `transcript(of:)` is not nil, and `prepare` starts only that one. `TranscriptSources.standard(speech:)` is the spec's order: `VoiceoverSource`, `SubtitleSource`, then the speech source, which serves every video. The interface has three implementations today, which is why it is an interface; the transcription research replaces or adds a source behind it.
- `VoiceoverSource`: `<base>.voiceover.json`, else `voiceover.json`, in the video's folder. A scene lasts `ceil((durationSeconds + paddingSeconds) × fps)` frames and starts where the previous one ends. One line per scene; a scene with no text takes its time and gives no line. The file is read each time it is asked. A file that does not read as a voiceover leaves the video to the next source.
- `SubtitleSource`: `<base>.srt`, else `<base>.vtt`. `parse` reads both formats the same way: blocks with a blank line between them, and a cue is the block with a `start --> end` line; what is above that line is dropped, the rows under it are joined with a space, and markup (`<i>`, `<v Name>`, `{\an8}`) is removed. Times are `HH:MM:SS,mmm`, `HH:MM:SS.mmm` or `MM:SS.mmm`. A cue whose time is not a finite number (`inf`, `1e999`) is skipped (D202). A file with no cue leaves the video to the next source.
- `TranscriptWindow.range(around: time, duration:)` is `time − 15 … time + 15`, kept inside the video. `cut(lines, to: window)` keeps every line that overlaps the window, whole; a line that only touches the window's edge is out.
- `SpeechSource` holds each video's speech transcript by content hash, behind a lock. `transcript(of:)` for a video that was not prepared in this run gives the finished transcript in the `Cache`, when there is one. `prepare` starts a task once per video, which runs `transcribe`, a `@concurrent` function, off the caller's actor: it takes the finished transcript from its `Cache` when there is one, else it reads lines from its `SpeechRecognizing` one at a time, appends each, then marks the transcript complete and saves it to the cache. A recognizer that throws leaves the lines it gave and sets `problem`; the video's next opening starts over. Its `Cache` is two closures, load and save, so `ReviewTranscript` does not link `ReviewStore`.
- `SpeechRecognizing` is the seam under the speech source: `lines(of: file)` is a stream of lines that ends when the file is done. `AppleSpeechRecognizer` is the real one, built on macOS only; its `transcribe` is `@concurrent`. It is a `SpeechTranscriber` for the Mac's language (the nearest supported locale, else `en-US`) with audio time ranges, its model installed through `AssetInventory` when it is missing, and a `SpeechAnalyzer` that reads the video file with `AVAudioFile`. Each finalized result is one line with that result's time range. A video with no sound track is done with no lines. The tests give a recognizer they drive.

### ReviewStore

```text
<support>/                               ~/Library/Application Support/Video Review (proto-2)/, or the demo folder
  control.sock                           while the app runs
  demo.json                              the demo pointer; only in the normal folder
  outbox.json                            the Outbox: schemaVersion, pending, taken, session, contextSent
  recent.json                            schemaVersion and the path of the last open video
  videos/<contentHash>/
    review.json                          one VideoReview (video, note, comments, batches), with schemaVersion
    transcript.json                      the finished speech transcript: source, lines, complete
    frames/<comment-id>.png              the keyframe, at the video's own size
    crops/<comment-id>.png               the region's crop
```

- `Library(support:)` is one object per support folder, used on the main actor. Its `init` reads every `review.json` once into an index from comment and batch ids to content hashes, so `status c-…` finds its video without the video being open, and into the list of unfinished batches for `loadOutbox`. It writes nothing: a launch that changes nothing leaves the folder as it was, and a folder that does not exist is not made.
- Reviews: `load(hash)` gives the review, or nil when the video has none yet; `save(review)` writes it and brings the index up to date (a deleted comment's id leaves it). `contentHash(of: id)` reads the index. `reviewFile(of:)`, `outboxFile` and `recentFile` are the files' places.
- The outbox: `loadOutbox()` reads `outbox.json` and passes it through `Outbox.reconcile` with the unfinished batches of the reviews; with no file, or one that does not read, that puts every unfinished batch in line again. `save(outbox)` writes it.
- The last video: `recent()` and `saveRecent(url)`. A file that does not read is no video, and one that cannot be written is not an error.
- Every save encodes the whole file, writes it to a temporary file and renames that over the old one (`Data.write(options: .atomic)`). A reader, a quit and a crash during a save see the old file or the new one, never a part. Saves happen on the main actor, one after the other, so two never race. Files are pretty-printed JSON with sorted keys, and times are ISO 8601 with milliseconds.
- Each file carries `schemaVersion` (1) beside its own keys; a file without it reads as version 1. A file from a higher version is not read and never written over: `load` throws `Library.Failure` with a line that names the file and both versions, `save(outbox)` throws, and `saveRecent` does nothing.
- A `review.json` that does not read (half a file, not JSON, a missing key, the review of another content hash) is treated the same way: `load` throws with the file's path and why, and nothing writes over it. `Library.init` leaves such a review out of the index.
- `Library.Failure` is one line, `reason`, for the person or the CLI.
- `TranscriptFiles(support:)` stays beside the library, as `ImageFiles` does: the speech source reads and writes it from a background task, and `Library` is for the main actor. It keeps a video's speech transcript: `file(of: hash)`, `load(hash)` and `save(transcript, contentHash:)`, written atomically. Only a complete transcript is written, so a video is transcribed once. A file that does not read is no transcript.
- `ContentHash.of(url)` is the SHA-256 of the whole file, read in 4 MiB chunks off the main actor (`AppModel.contentHash(of:)`, a `@concurrent` function). A renamed or moved copy has the same hash, so it opens the same folder; `review.json` then records the new path.
- Demo and real data never mix: the `Library`, `ImageFiles` and `TranscriptFiles` only ever see the support folder they were given, and the only file a demo run has outside its folder is the pointer `demo.json`, which the command writes.

### ReviewApp

`AppModel` (`@MainActor @Observable`) is the orchestrator. Its methods are the product's actions; the UI and the `ControlServer` call the same ones:

| Method | Rules it owns | Refuses |
|---|---|---|
| `open(url)` | hash, load the review (before the player changes), load the video, take the review again as it is after the load (D200), record where the video is now and its frame rate, pick the transcript source, read the context, remember as recent. `openRecent()` is the launch's call: it opens `Library.recent()` when that file is still there, and shows why when it does not open | a file AVPlayer cannot play; a review that does not read or is from a newer version (the video that was open stays open) |
| `play()`, `pause()`, `seek(seconds)` | seek is exact and keeps play or pause | no video; a time outside the video |
| `startDraft(region?)`, `commitDraft()`, `cancelDraft()` | starting a draft pauses and fixes the comment's time; commit writes the keyframe and crop, then queues the comment and selects it. A commit that fails opens the box again with its words. With a region while the box is open, the box takes the new region and the time of the frame on screen, and keeps its words | empty text (the box stays open) |
| `clickFrame()`, `beginRegion()`, `endRegion(region?)`, `escape()` | the mouse on the frame. A click plays or pauses, and does nothing while the box is open. A drag's start pauses and sets `isDrawingRegion`. Its end opens the box on the region; a nil region (too small) and a drag that Escape cancelled open nothing. Escape drops the rectangle being drawn, else the open box with its region | |
| `addComment(text, at?, region?)` | the CLI's path: pause, seek to `at`, then the same as commit. It answers once the keyframe and the crop are on disk | no video; empty text; bad time or region |
| `editComment`, `deleteComment` | through `ReviewDesk`; delete removes the keyframe file, the crop file and the selection | not queued; unknown id |
| `shownRegion` (read) | the region to draw on the frame: the draft's, else the selected comment's while the player is paused within half a frame of that comment's time | |
| `select(id)`, `jumpToMarker(forward)` | a click on a marker or a row, and Up and Down: select, pause, seek to the comment's time | |
| `sendBatch()` | waits for a comment the box is still queueing, queues a draft with text, sends, hands the batch to `ListenerQueue`. `batch send` calls it; Cmd+Return, the Send button and the menu item call `send()`, which calls it and does nothing when `canSend` is false or a send is under way | empty queue |
| `answer(commentID, text)` | the answer box and `thread answer`: through `ReviewDesk` on the comment's video, open or not, then tells `ListenerQueue` (the waiting `ask` exits with it), marks the thread read and takes the question's notice down. `answerQuestion(id, text)` is the answer box's call: the same, with the refusal shown to the person | no open question; no words; unknown id |
| `raise(notice)`, `dismiss(id)`, `openNotice(id)` | the notices on the stage. `raise` adds one and marks its comment unread, unless that comment is selected with the rail showing; a notice with an end time takes itself down. `openNotice` is a click: the notice goes, the rail shows, the comment is selected. Opening a video clears the notices and the unread marks | |
| `setContextNote(text)` | the note is kept on the review without the space around it; an empty text clears it. `context set` calls it, and the popover's Save calls `saveContextNote`, which calls it and closes the popover | no video |

- `AppModel.unread` is the set of comments with an agent message the person has not looked at. Selecting a comment, or answering its question, reads it. It lives in memory only. `AppModel.agentName` is the listener session's name, or "Agent" before anyone listened.
- `Notice` is a value: `subject` (a comment or a batch), `kind` (`acknowledgement`, `message` or `question`), the agent's name, the words and `expires` (5 s after it was raised, `Notice.life`; nil for a question). `title(number:)` and `hint` are its words, pure.
- `ReviewDesk(library:)` owns the `Library`. `contentHash(of: id)` finds the video whose review has a comment or a batch, from the library's index.
- `ReviewDesk.change(hash) { review in … }` is the one path for every change to a `VideoReview`: it takes the review from memory, or loads it from the `Library` the first time and keeps it, runs the change, saves, and publishes when the review is the open one. A thrown `ReviewRefusal` changes nothing. A save that fails is refused too (`nothing changed: couldn't write …`), and memory keeps the review as it is on disk, so the person and the listener see the failure when it happens. A change that leaves the review equal writes nothing. `change { … }` with no hash changes the open review. `review(of: hash)` reads a review, open or not; `review(for: video)` is the review a video opens on (the kept one or a new one), refused when the kept one does not read; `open(review)` makes it the open one and saves it only when it is on disk already and its video moved, was renamed or got its frame rate. A new review is first written with its first change.
- `PlayerEngine` wraps `AVPlayer`. `seek` uses zero tolerance and returns when the seek has finished, so `state` reports the time that was asked for. `PlayerEngine.exact(seconds)` is the time both `seek` and `FrameGrabber` ask for, at the one timescale `PlayerEngine.timescale` (60000, which holds a millisecond exactly), so the player and the keyframe show the same frame (D203). The duration is the video track's own length (21.233 s for the fixture), not the container's, whose sound track can run a few milliseconds longer. A file that does not play is refused, and the video that was open stays open.
- `PlayerSurface` is an `AVPlayerView` with no controls that takes no click and no key (`hitTest` gives nil). The stage's own layer above it takes the mouse.
- `Shortcuts` is one local key monitor. It maps a key to an action in a pure function, `action(keyCode:modifiers:isTyping:)`, which gives no action while a text view has the focus (`isTyping`), but for Cmd+Return (and Cmd+Enter on the keypad), which is `send` from anywhere. The Playback menu has the same actions with no key equivalents, since a menu key with no modifier would take the key from a text field; its Send Comments item shows Cmd+Return. The monitor sees the key first, and both call `AppModel.send`.
- `CommentEditor` is the one text view comments are written in: a standard `NSTextView` that takes the focus when it appears, from a main-actor task once the view is in its window. Its pure function `keyAction(for:shift:)` maps the text view's commands: `insertNewline` commits, with Shift it makes a new line, `cancelOperation` cancels, and every other command stays the text view's.
- A comment's time is the player's time raised to the next millisecond (`AppModel.commentTime`), never rounded down: a frame rarely starts on a whole millisecond, and a time before the frame's start names the frame before it. `comment add --at` keeps the time it was given.
- `FrameGrabber` makes the keyframe with `AVAssetImageGenerator` at the exact time, from the asset and not from the window. The crop is the keyframe cut by the region. The UI and the CLI therefore produce the same pixels at any window size. A time at the video's very end is asked inside the last frame. The keyframe and the crop are written before the comment enters the review (`FrameGrabber.writeImages`, a `@concurrent` function, off the main actor), so a comment never exists without its pictures; when either cannot be written, neither file is left and the comment is refused. The crop is `Region.pixels` of the keyframe image in memory, so it is exactly that part of the keyframe PNG.
- `VideoFrameGeometry(stage:video:)` is the pure way between the stage's points and a region: `frame` is the picture fitted whole and centred in the stage (the size comes from `PlayerEngine.videoSize`, the track's size after its transform), `rect(of: region)` is where a region is on the stage, and `region(from:to:)` is the region a drag draws, in any direction, clamped to the picture, with four decimals, or nil under 8 pt either way. `isDrag(from:to:)` tells a drag from a click at 4 pt. A region is kept as fractions of the frame, so nothing is stored that depends on the window's size.
- `RegionOverlay` is the layer above the picture that takes the mouse: one drag gesture with no minimum distance, which calls `clickFrame`, `beginRegion` and `endRegion`. It draws the rectangle being drawn, the draft's region, and the selected comment's region with the comment's pin on its corner: the rest of the picture is dimmed and the rectangle is outlined in the accent colour. The rectangle being drawn and the region shown are one frame, so letting go hands the rectangle to the comment box in place; only a change of the shown region animates.
- `Composer.placement(beside:box:stage:)` is where the comment box sits for a region, as a pure function: right of the rectangle, else left, else below, else above, else the stage's lower right corner, always 12 pt inside the stage. `StageView` measures the box and passes its size. `StageView` brings the box in 8 pt from what it is about (from the rectangle's side, or up from the playhead) and sends it back the same way; with reduce motion it only fades.
- `ListenerQueue` (`@Observable`, owned by `AppModel`) holds the `Outbox`, the one open `wait` (a continuation, with its timeout and the id of its connection) and the open `ask`s by comment id. `wait(by:timeout:connection:)` ends as an `Outcome`: `batch(ref, payload)`, `ranOut`, `replaced` or `gone`. It assembles the payload when a `wait` takes a batch; a batch in line with nothing left to deliver (no review that reads, or every comment finished) is discarded. It starts from `Library.loadOutbox()` and saves the outbox in its `didSet` whenever what is kept of it changed (`Outbox.isKeptAs`), so `enqueue`, a `wait` from a new listener, a delivery, `undelivered`, `finished` and a context that was sent are each on disk at once. An outbox that cannot be written is a line on standard error, and is written again with the next change. `connectionClosed(id)` ends the `wait` held on that connection, `undelivered(ref)` puts a batch back, `stop()` ends the open `wait` with no reply. `report(at:)` is the `listener` of `state`. `ack`, `status`, `reply` and `ask` find their video with `ReviewDesk.contentHash(of:)`, change the review through `ReviewDesk.change`, and call `Outbox.heard` first, refused or not. `ack`, `reply` and `ask` hand a `Notice` to `announce`, a closure `AppModel` sets to `raise`; `status` raises none, since the marker shows it. `status` calls `Outbox.finished` when `VideoReview.isFinished` turns true for the comment's batch. `ask` ends as an `Asked`: `answered(message)`, `ranOut` or `gone`. The open `ask`s are held by comment id, each with its continuation, its timeout and its connection; `answered(id, with:)` resumes one, `connectionClosed` and `stop` end them as `gone`.
- `ContextReader` is the context as the listener is told it. `sidecar(beside: video)` is the first of `<video base name>.context.md` and `context.md` in the video's folder that is a file and reads as UTF-8, with its text trimmed; a blank file of the video's own name still serves, so a video can opt out of its folder's `context.md`. `text(sidecar:note:)` joins the sidecar's text and the note under the heading `## Note from the reviewer` (pure), and is `nil` when both are empty. `text(for: review)` reads the sidecar beside the path the video was last opened at. `ListenerQueue.payload` calls it when a `wait` takes a batch and passes the result through `Outbox.context(for:text:)`, so nothing watches the file. `AppModel` keeps the open video's `sidecar` for the popover (read when the video opens and when the popover opens), and `contextText` and `isContextDue` for its words.
- `ContextPopover` (`UI/ContextPopover.swift`) holds the toolbar's `ContextButton`, the popover and its words as a pure struct, `ContextWords` (where the sidecar's text comes from, and when the agent gets the context). The popover's transcript part shows the `TranscriptChip` words (the source, its progress, and what it gives the agent or why it gives nothing), read again each second. `ContextButton` reads them each second too, and its glyph pulses while speech is transcribed, unless reduce motion is on. The note is written in `CommentField`, the comment box's text view. While the popover is open (`AppModel.isContextShown`) the player's keys are off, Cmd+Return too.
- `TranscriptDesk` (owned by `AppModel`, given to the `ListenerQueue`) is the app's way to the transcripts. `opened(video)` remembers the `VideoFile` by content hash (the frame rate comes from the player) and calls `prepare` on the sources. `lines(around: time, of: info)` is the window's lines as `BatchPayload.Line`, read when it is asked: for a video that was not opened in this run it makes the `VideoFile` from the review's `VideoInfo` (the last path and the kept frame rate), so the voiceover or subtitles beside that path, or the speech transcript kept on disk, serve it. `report(of: hash)` is the `transcript` of `state`. `AppModel.init(environment:speech:)` takes the recognizer, so the tests give a slow one.
- `ControlServer` listens on `control.sock` (mode 0600), reads each request off the main actor and answers on it. It owns the one `ControlLease`, takes the time from a closure the tests replace, and starts from the lease a relaunch handed over. It asks `ControlLease.use` before any operator request, holds a queued `take`, a `wait` and an `ask` as suspended continuations while it answers other requests (an `ask` that is `gone` gets a `silent` answer, as a `wait`), and settles the lease on a timer at `nextEnd`. `ready` is a task the app sets at launch (opening the last video again); every request waits for it, so `app open` and the `state` after it see the app with its video open. Every change to the lease goes through one place (`leaseChanged`): it copies the lease to the `LeaseIndicator`, answers the waiting takes of the holder that got it, and sets the timer again. A `take`'s reply that grants the lease and cannot be written releases it (`undelivered`). `stopLease()` is the banner's Stop, in the agent-control popover. `app status` and `state` get their `lease` from the server, not from `AppModel`, and `state` gets its `listener` from the `ListenerQueue` the server is given. It depends on a small protocol, `AppControlling`, which `AppModel` implements and the server's tests fake. An `Answer` is the reply plus what only the client would know: the lease a `take` granted (`granted`) and the batch a `wait` carried (`delivered`). When the reply cannot be written, `undelivered` releases the one and puts the other back in line. A `silent` answer writes nothing and closes the connection, which is how an open `wait` ends when the app quits. Each connection has an id. While its answer is awaited, the socket's side looks at it every 0.5 s (`HangUpWatch`, `UnixSocket.peerClosed`) and tells the server once when the client closed its socket (`connectionClosed`), so a `wait` whose command was stopped is no listener. `Listener` and `HangUpWatch` are `@unchecked Sendable`: neither has mutable state, but each holds a dispatch source that is not declared `Sendable`. Their reads block, so they run on a dispatch queue, not on the concurrency pool.
- `LeaseIndicator` (`@Observable`) is the lease as the banner draws it. "Banner" is the domain word for what the person sees of the lease; today it is a sign in the toolbar. `shown(at:)` is the lease's `Status`, or nil while it is free or while a screenshot leaves the banner out. `LeaseBanner` makes the banner's words from that status in a pure struct. `AgentControlButton` is the sign: `cursorarrow.rays` in `Theme.control`, at the head of the toolbar's buttons while `shown(at:)` has a lease, with one bounce when it arrives unless reduce motion is on. A click opens `AgentControlPopover`: who controls the app, where, the time left ticking each second, how many wait, and Stop.
- `StateReport` builds `state --json`:

```json
{
  "app":      { "version": "0.1.0", "variant": "proto-2", "demo": true, "support": "/abs/demo" },
  "lease":    { "holder": { "key": "CLAUDE_CODE_SESSION_ID=…", "name": "Claude Code", "place": "/abs/repo" },
                "taken": "2026-10-04T19:00:00Z", "ends": "2026-10-04T19:01:00Z", "secondsLeft": 48, "waiting": 0 },
  "listener": { "presence": "listening", "waitOpen": true, "session": "Claude Code", "pendingBatches": 0, "takenBatches": 0 },
  "video":    { "path": "/abs/sample.mp4", "contentHash": "<64 hex>", "duration": 21.233, "title": "sample", "contextNote": "" },
  "player":   { "time": 10.0, "playing": false },
  "transcript": { "source": "voiceover", "complete": true, "lines": 3, "problem": null },
  "draft":    null,
  "comments": [ { "id": "c-7f3a9c2e", "time": 10.0, "text": "…", "state": "queued", "region": null,
                  "keyframePath": "/abs/…png", "cropPath": null, "batchId": null,
                  "thread": [ { "id": "m-…", "author": "agent", "kind": "question", "text": "…", "at": "…" } ] } ],
  "queue":    [ "c-7f3a9c2e" ],
  "batches":  [ { "id": "b-…", "sentAt": "…", "commentIds": [ "c-…" ], "messages": [ … ] } ]
}
```

  `comments` and `queue` are in time order. `video` is `null` with no video open. `lease` is `null` while the lease is free. `app status --json` has the same `lease`; as lines, both commands print `lease: held by Claude Code in /abs/repo, 48s left, 0 waiting` or `lease: free`. A thread message and a batch message are `{ "id", "author", "kind", "text", "at" }`; `thread` and `messages` are `[]` when there are none. `StateReport.Comment(comment, contentHash:, images:)` makes a comment's report for any video, so a listener's command answers for a video that is not open. As a line, a comment with a thread reads `c-… 0:10 working (2 messages, question open): …`. An open comment box is `"draft": { "time": 8.0, "text": "…", "region": null }`, with the region when the person drew one. A comment's `region` is `{ "x", "y", "w", "h" }` or `null`, and its `cropPath` is the crop's absolute path or `null`. `listener.session` is the name of the agent of the last `wait`, or `null` before the first one; `pendingBatches` counts the batches no `wait` took yet and `takenBatches` those a `wait` took that are not finished. As a line, `state` prints `listener: working (Claude Code), 0 batches waiting, 1 taken`. `transcript` is `null` with no video open. Its `source` is `voiceover`, `subtitles` or `speech`; `lines` counts the lines there are now; `complete` is false while speech is being transcribed and when that gave up, and `problem` then says why. As a line, `state` prints `transcript: voiceover, 3 lines, complete`, `transcript: speech, 2 lines, transcribing`, `transcript: speech, 0 lines, stopped: <why>` or `transcript: none`.
- What the comment commands print: `comment add` prints `c-7f3a9c2e queued at 0:10`, and with a region `c-1b44e0d7 queued at 0:12.5 on the region 0.25,0.2,0.3,0.25`, `comment edit` prints `c-7f3a9c2e edited`, `comment delete` prints `c-7f3a9c2e deleted`. With `--json`, add and edit print `{"comment": {…}}` in the shape above, and delete prints `{"deleted": "c-7f3a9c2e"}`. `state` without `--json` lists each comment on a line: id, time, `region x,y,w,h` when it has one, state, text.
- `Screenshotter` captures the app's own window with ScreenCaptureKit, from this process's shareable content only, which needs no Screen Recording permission. For `--appearance` it sets the app's appearance, waits for the window to redraw, captures and restores. Captures take turns, so two of them never mix their appearances. It makes the PNG's folder when it is missing. The banner (the toolbar's agent-control sign) is hidden for the capture, since the holder would be in every picture; `--with-banner` keeps it in, which is how an agent proves the sign shows. Every capture first gives the window 400 ms to redraw, since the sign has just gone, or has just come when the capture's own request took the lease.
- `Theme` holds the window's measures and its colours. Each colour is a muted pastel with a light and a dark variant (`pastel(light:dark:)`, a dynamic `NSColor`). `Theme.accent` is a soft slate blue, set as the app's tint at `RootView`; `agent` is the accent, `question` a soft teal, `control` the amber of the agent-control sign, and `onTint` the colour of a number or glyph on a filled colour. The faint fills (`selectedRow`, `sectionBand`, `personBubble`, `agentBubble`, `questionBubble`) take the `ColorSchemeContrast` and deepen when the person asks for more contrast. `footerHeight` (116 pt) is the height of the timeline lane and of the rail's foot, and `railPadding` (16 pt) the side padding of a row and a header in the rail.
- `QuietButtonStyle` is the look of the lane's and a row's symbol buttons: no chrome at rest, a soft fill under the pointer, a deeper fill and a small press while held (no press with reduce motion).
- The app has one `Window` scene. Closing the window quits the app. A second copy started on the same support folder finds the socket taken and quits; only the copy that has the socket opens the last video, so a second copy writes nothing.

### The UX of this prototype

The idea: **the video is the stage, the timeline carries the markers, and a rail at the side carries the conversation.** The person watches on the left and reads answers on the right, and never leaves the window. Each choice and its reason:

| # | Choice | Reason |
|---|---|---|
| 1 | One window, one video at a time. Opening another video replaces the open one. | The CLI commands name no window, and there is one queue and one listener. |
| 2 | Three parts: the stage (video) on the left, the timeline lane under it, the rail (340 pt, can collapse) on the right. The rail is the system's inspector column, with a toolbar button that hides it. The stage is a black card with round corners. The lane has a ruler of times under the track. The lane and the rail's foot (the send bar) have one height, so the stage's lower edge and the line over the rail's foot are one line across the window. The default window (1360 by 730 pt) shows a 16:9 video with no letterbox. | Answers stay next to the feedback and stay visible while the video plays. One screenshot shows markers, a region and a thread. The inspector resizes and collapses as the Mac's other apps do. One line across the window reads as one layout, not two panels. |
| 3 | The app's own player surface (`AVPlayerView` with no built-in controls) and its own timeline lane, always visible. | The stock controls cannot carry markers, and they take the mouse drags the region overlay needs. Markers are the core of the app, so the lane never hides. |
| 4 | QuickTime keys: Space or K plays and pauses, Left and Right move 5 s, Shift+Left and Shift+Right move one frame, Up and Down jump to the previous and next marker. A click on the frame plays or pauses. | Playback should feel like QuickTime. Frame steps matter for pointing at an exact frame. |
| 5 | C or Return starts a comment at the current time and pauses. A Comment button at the right of the lane does the same. No automatic focus on pause. | One key from watching to typing, and Space still resumes. The button makes the key discoverable. Typing never reaches the player: the shortcuts are off while a text field has the focus. |
| 6 | Dragging on the frame draws a rectangle at any time, with no drawing mode. The drag pauses the video. The picture outside the rectangle is dimmed. Releasing opens the comment box. Escape cancels, during the drag and in the box. A press that moves under 4 pt is a click; a rectangle under 8 pt either way opens nothing. A drag while the box is open moves the region and keeps the words. The empty rail says that a drag comments on a part of the frame. | It works like Cmd+Shift+4: point first, no tool to pick. A slip of the hand must not open a box. Pointing again is a correction, not a new comment. |
| 7 | The comment box floats on the stage: beside the rectangle for a region comment (right, else left, else below, else above, always inside the stage, with no notch and the heading "Comment on this region at"), above the playhead for a time comment, at the foot of the stage, with a notch that points at the playhead. The box comes in from what it is about (from the rectangle's side, or up from the playhead) and leaves the same way; with reduce motion it only fades. The rectangle drawn stays in place as the box opens. The box is a solid surface, not a material. While it is open, a click on the frame does not play. | The person writes where they point, and the motion shows what the box belongs to. A material over a video takes the picture's colours and its words stop being readable. The comment is about the frame on screen, so the frame stays. |
| 8 | In the comment box, Return queues the comment, Shift+Return makes a new line, Escape cancels, Cmd+Return queues and sends everything. The box is a standard text view that takes the focus when it opens. The hints under the box name Return, Cmd+Return and Escape. | Fast entry with one hand on the keyboard. A standard focused text view is all Wispr Flow needs to dictate into. The row has room for three hints, and Shift+Return is a habit. |
| 9 | Cmd+Return anywhere sends the queue, also while a text view has the focus. A draft with text is queued first, and so is a comment whose keyframe is still being written. With nothing to send the key does nothing. The Playback menu has Send Comments with the same key. | One keystroke delivers all feedback, with nothing left behind in the box. A key that has nothing to do must not raise an alert. |
| 10 | Markers are numbered pins on the timeline, numbered in time order. Colour and glyph show the state: hollow for queued, grey for sent, and for a state the agent set a small glyph at the pin's foot in the state's colour: a check for acknowledged (the slate accent) and done (sage green), three dots for working (amber), a cross for failed (terracotta). Each colour is a muted pastel with a light and a dark variant, and the number and glyphs on a filled pin are in `Theme.onTint`. At the pin's head a teal question mark marks an open question, else an accent dot marks an unread agent message. A pin stands above the track on a stem. The selected pin has a ring and a halo in the accent colour. The same pin heads the comment's row in the rail. The band the pins stand in is always there. | The state reads at a glance, and never by colour alone. The number ties a pin to its row. The selection never changes a state's colour. The first comment does not move the lane. |
| 11 | A click on a marker or a row seeks to its time, pauses, selects it and shows its region on the frame, with the comment's pin on the rectangle's corner. The region goes when the video plays or moves to another frame. | One gesture gives the full context back. A rectangle over another frame would point at the wrong thing. |
| 12 | The rail groups by batch, as sections of a list: "Queue" on top, then each batch, newest first. Each section starts with a full-width header band ("Queue" and "2 comments"; for a batch "Sent at 00:13" with a two-digit hour, then "2 comments", or progress such as "2 of 3 done" once a comment is finished, and "waiting for an agent" with a clock while no `wait` took the batch). The batch's own messages sit under its header as chat bubbles. Comments are full-width rows in time order inside a section, numbered as their markers are, with a hairline between two rows. The Queue section stays when it is empty, with one line that says how to comment. | The batch is the unit that is sent and answered, so the batch message has a natural home and the progress of a batch is visible. A sent time must not read as a time in the video. Bands and hairlines tell the parts apart with no bordered boxes. |
| 13 | A row shows a thumbnail (the crop, else the keyframe), the time, a small dashed rectangle when the comment is on a region, the text and the state as its glyph and name in its colour, with no capsule. The selected row is told by its fill, a hovered row by a fainter one; no row has a border. Its thread is inline under it, open for the selected row and for any row with an open question; any other row shows its last message on one line, with the count, in bold while it is unread. A message is a soft bubble with no stroke (the agent's tinted, a question's teal, the person's grey), headed by who said it ("Claude Code", "Claude Code asked", "You answered") and its time. An open question says "waiting for you", and the answer box sits under it: Return or the Answer button sends, Escape clears. The answer box takes the focus only on a click. | The thread is part of the comment, not a second screen. A question must not hide. A question arrives while the person watches or types, so its box must not take the keys. |
| 14 | Edit and delete show on queued rows only. Edit turns the row's text into the same text view as the comment box, with Save and Cancel (Return and Escape). Delete acts at once. A new comment is selected, and the rail scrolls to the selected row, smoothly, or at once with reduce motion. | Only a queued comment can change, so the controls do not appear where they would be refused. A queued comment is cheap to write again, so delete asks nothing. |
| 15 | The send bar at the foot of the rail, as tall as the timeline lane, holds the presence and, under it, the Send button across the rail's width with the count and the shortcut ("Send 2 comments ⌘↩"). The presence is a dot and words, with no capsule: a filled green dot and "Agent listening", a half amber dot and "Agent working", a hollow grey dot and "No agent listening". After it come the agent's name and how many batches wait ("· Claude Code · 1 batch waiting"), or "a batch will wait" with no agent. The pill's words are a pure struct, `PresencePill`. It is drawn again each second. | The person sees before sending whether someone will receive the batch, and that sending is safe either way. The dot's shape tells the state without its colour. An agent that stops answering turns absent with no event. |
| 16 | An agent message shows as a notice in the top-right corner of the stage for 5 s: who said it and about which comment ("Claude Code replied on comment 2", "Claude Code on the whole batch", "Claude Code has your batch" for an acknowledgement), then up to three lines of its words. A question stays until it is clicked or answered, with a teal outline and "Click to answer". A click takes the notice down, shows the rail and selects the comment. The three newest show. A notice slides in from the right, or only fades in with reduce motion. A status change raises none. No system notifications. | Brief while watching; a question blocks the agent, so it does not fade. The app is in front when notices matter. |
| 17 | The lease banner is a sign in the toolbar while an agent holds the lease: an amber `cursorarrow.rays` glyph at the head of the toolbar's buttons, which bounces once when it arrives (not with reduce motion). Its tooltip and VoiceOver label say who controls the app. A click opens a popover: who controls the app ("Claude Code controls Video Review"), where (the working folder's name or the Herdr pane), the time left ticking each second, how many agents wait, and Stop. It shows with no video open too. Stop ends the lease and bars that agent for 5 min; nothing lifts the bar early. | The person must see at once why things move, and one click and Stop take the app back. A sign in the toolbar does not move the stage or letterbox the video, as the strip across the window did (D208). |
| 18 | The window follows the system's light and dark appearance, with system materials and a muted pastel palette: each colour has a light and a dark variant, and a soft slate blue is the app's tint in place of the system's bright blue. Surfaces are told apart by a fill, not a border, and each faint fill deepens with the system's increased contrast. The letterbox around the video is black in both. | It matches the Mac, and the video stays the loudest thing in the window. Black bars are what a player shows. |
| 19 | With no video: a drop target and "Open a video" (Cmd+O). On launch the app opens the last video again, paused at the start. | Coming back to a review should not need a file dialog. It also makes the history visible after a restart with no extra step. |
| 20 | A Context button in the toolbar opens a popover with the sidecar's text (read-only, in a box that scrolls, under the file's name; its path is the tooltip) and the editable note under it. With no sidecar the popover names the two files it looked for. Return or Save keeps the note and closes the popover, Shift+Return makes a new line, Escape or Cancel closes it with no change. The popover's foot says when the agent gets the context: "Goes to the agent with your next batch", "The agent has this. It goes again when it changes" or "Nothing to tell the agent yet". The button's glyph is filled while the video has a context, and pulses while speech is being transcribed (not with reduce motion). Above the popover's foot, a transcript part names the transcript source and its progress: "Voiceover transcript", "Subtitle transcript", "Transcribing… 2 lines" with a spinner, "Speech transcript", "No speech", or "No transcript" with a warning sign when the transcription gave up, and under it where the lines come from, or why there are none. Its words are a pure struct, `TranscriptChip`. They are read again each second. The toolbar is one group of icon buttons: the agent-control sign while an agent holds the lease, Context, and the Comments button that hides the rail. | The person can check what the agent will be told without leaving the player, and sees that a change will reach the agent. The transcript around each comment is part of what the agent is told. The keys are the comment box's keys. |
| 21 | During a demo run the window's subtitle says "Demo · <folder>", where the folder is the open video's. | The person can tell a demo from their own data, with no chip of words in the toolbar. |
| 22 | Motion answers the hand and gives way to reduce motion: the scrubber's knob and track grow while held; the lane's and a row's symbol buttons answer hover and press (`QuietButtonStyle`); every slide and bounce becomes a fade, or nothing, with reduce motion. VoiceOver can step the scrubber by 5 s, as Left and Right do. | Feedback on the press tells the person the click took. Motion must never be the only way to read a change. |

### The listener skill

`.agents/skills/video-review-mate/SKILL.md` is the whole skill: one file, no code. A Claude Code session in the repo the feedback is about reads it and becomes the listener. It uses only the listener commands, `state --json` and `app status` of the spec's contract, so the same file drives each prototype.

```text
start        find the CLI once: $VIDEO_REVIEW_CLI, else /Applications/Video Review.app/Contents/Helpers/video-review,
             else the one /Applications/Video Review*.app/Contents/Helpers/video-review
listen       `wait` as a background command; exit 0 wakes the session with the payload, exit 2 → `wait` again
on a batch   `ack <batch-id> "<line>"`, then a new background `wait`, both before the batch is studied
per comment  open the crop and the keyframe, read the text, the transcript and the context
             `status working` → decide the intent (research, design change, issues, spec, implementation) → the work
             → one commit when files changed → `reply <comment-id>` with the short SHA → `status done`
             cannot be done: `reply <comment-id>` with the reason → `status failed`
unclear      `ask` as a background command; the next comment goes on; exit 0 wakes the session with the answer
             exit 2: the late answer is read from `state --json` (the comment's thread), else `failed` with a reply
close        `reply <batch-id>` with one line for the whole batch
```

- The skill's facts about the app come from the contract, and its advice holds in a build that behaves otherwise: it runs `wait` again on exit 2 although this build's `wait` has no limit, and it tells the user when `wait` says the app is not running although this build's `wait` connects again by itself.
- The session is the listener session of D5: every `video-review` command runs in the session itself, so the holder key stays the same. A batch that comes again after a new session started (D6) is checked against `git log` before its work is done twice.
- The skill is found by a session through its harness, not through this repo: it is linked or copied into the target repo's skills folder, or into the user's own. This repo has no `.claude/skills` link (D163).

## 4. Implementation

### The methods that carry the logic

Dispatch in the server:

```text
ControlServer.reply(to data)
  message = ControlMessage.decode(data)            else refused(error.message)
  switch message.request.role
    operator: decision = lease.use(by: holder, at: now)        // its transitions are ignored (D45)
              refused(decision.refusal.message) when another holds it or the holder is barred
    free, listener: no lease
  switch message.request
    controlTake / controlRelease   → the lease's own calls; a queued take suspends
    appStatus / state              → StateReport
    operator requests              → app.<method>(…); done(line) or refused(refusal.line)
    wait / ack / status / reply / ask → listenerQueue.<method>(…)
```

Sending and delivering a batch:

```text
AppModel.sendBatch()
  await the comment the box is still queueing (its keyframe write)
  queue the draft when it has text
  batch = desk.change { try $0.send(batchID: ItemID.make(.batch), at: now) }             // queued → sent
  listeners.enqueue(BatchRef(batch.id, openHash))

ListenerQueue.enqueue(ref)        outbox.enqueue(ref); deliver()                          // outbox.json is written as the outbox changes

ListenerQueue.wait(holder, timeout, connection) async -> Outcome
  requeued = outbox.waitOpened(by: holder, at: now)
  for ref in requeued: desk.change(ref.hash) { $0.requeue(ref.batchID) }                 // unfinished → sent
  resume an older open wait with .replaced
  if let outcome = takeNext(): return outcome                                            // a batch was in line
  if timeout == 0: outbox.waitClosed; return .ranOut
  suspend with a continuation; start the timeout when there is one

ListenerQueue.deliver()           when a wait is suspended and takeNext() gives a batch: resume it

ListenerQueue.takeNext()
  while a wait is open and a batch is first in line
    no review of it that reads, or nothing unfinished in it: outbox.discard; next
    ref     = outbox.deliverNext(at: now)                                                 // pending → taken; the wait is answered
    context = outbox.context(for: ref.hash, text: ContextReader.text(for: review))        // nil when already sent unchanged, and with no text
    payload = BatchPayload.assemble(review, batch, context,
                transcript: { transcripts.lines(around: $0.time, of: review.video) },     // the lines the source has now
                images: { ImageFiles paths of $0.id under ref.hash })
    return .batch(ref, payload as JSON)

ControlServer   .batch → Answer(done(payload), delivered: ref)    .ranOut → ControlReply.ranOut (exit 2)
                .replaced → refused                               .gone → a silent answer
ControlServer, when that reply cannot be written:  listeners.undelivered(ref)             // back to the front
ControlServer, when the wait's client closed its socket:  listeners.connectionClosed(id)  // outbox.waitClosed
```

Asking and answering:

```text
ListenerQueue.ask(commentID, question, waitSeconds, connection) async -> Asked
  outbox.heard(at: now)
  hash = desk.contentHash(of: commentID)                         else refused: no such comment
  desk.change(hash) { try $0.ask(commentID, question, …) }      // refused while a question is open
  announce a question notice
  if waitSeconds == 0: return .ranOut                            // the question is left; nothing is held
  outbox.askOpened; suspend with a continuation under commentID; start the timeout when there is one
AppModel.answer(commentID, text)                                 // from the answer box or `thread answer`
  message = desk.change(hash) { try $0.answer(commentID, text, …) }
  listeners.answered(commentID, message)                         // resumes the ask with .answered(message); outbox.askClosed
  the comment is read; its question's notice goes
timeout: resume with .ranOut (exit 2); the question stays open in the thread
client gone, or the app quits: resume with .gone (no reply); the question stays open

ListenerQueue.status(commentID, state)
  outbox.heard(at: now)
  comment = desk.change(hash) { try $0.setStatus(commentID, state) }
  if the review's batch of the comment is finished: outbox.finished(ref)     // working → listening
```

An answer that arrives after its `ask` stopped waiting is kept in the thread. The listener reads it from `state --json`.

Edge cases:

- `comment add --at 0:40` on a 21 s video: `AppModel` refuses before any change.
- `status c-… working` on a `done` comment: `CommentState.canMove` is false; `ReviewRefusal.illegalMove(from: done, to: working)`.
- `ack` with an unknown batch id: the `Library` index has no such id; refused.
- `status c-… done` twice: the second changes nothing and answers as the first.
- `ask` on a comment whose question is open (its first `ask` ran out): refused. The listener reads the answer from `state --json`.
- `thread answer` after the `ask` ran out: the answer is added, no `ask` waits, the command answers `answered`.
- A listener's command on a comment of a video that is no longer open: it works, and its notice says "a comment" with no number.
- `batch send` with an empty queue: refused, exit 1, no batch.
- A `wait` when the app quits: the connection closes with no reply; the CLI connects again until its timeout.
- Two `wait`s: the newer one replaces the older, which exits 1 saying so. A `wait` from another holder key is a new listener session.
- A `wait` whose command is stopped (its process ends): the server sees the closed socket within about 0.5 s and closes the `wait`. Presence falls to `absent` 5 s later, or stays `working` for 120 s while a batch is taken.
- A `wait` from the same holder while it has a taken batch: it gets the next batch in line, never the taken one again.
- Cmd+Return while a row's text is being edited: the queue is sent with the text as it was saved; the edit stays open and its Save is then refused, since the comment is sent.
- The person presses Stop while a `take` waits in line: the holder is barred and the first waiter gets the lease.
- A batch is sent while speech is still being transcribed: each comment gets the lines of its window that exist when a `wait` takes the batch. Nothing waits for the transcript.
- The Mac has no speech model for the language, or the transcription fails: the transcript stays incomplete with its `problem` in `state`, the Context popover's transcript part says "No transcript", and comments go out with the lines that arrived, or none.
- The app quits, or is killed, in the middle of a change: each file is replaced whole, so `review.json` is the review before the change or after it. When the review was saved and the outbox was not, the next launch's `Outbox.reconcile` puts the batch in line.
- `review.json` does not read, or a newer version wrote it: `player open` is refused with the file's path and the reason, the open video stays open, and the file is left as it is. A listener's command on one of its comments is refused as an unknown id. At launch the person is shown "The last video didn't open".
- The disk is full or the folder is read-only: the change is refused (`nothing changed: couldn't write …`), nothing changes in memory, and a new comment's keyframe and crop are removed again.
- A keyframe or crop file was removed by hand: the row shows an empty thumbnail, and `state` and the payload still name the path. Nothing writes the picture again.
- The last video's file is gone at launch: the app starts with no video and says nothing.
- A `wait` after a restart, from the listener that had a batch: the batch is still its own (`taken`), and it gets the next one in line. From a new holder key: the taken batches are first in line again, their unfinished comments `sent`.
- An `ask` that was open when the app quit: its question is open in the thread after the restart, with no `ask` waiting; the answer lands in the thread.
- A comment is added before the hash of a large file is ready: `player open` answers only after the hash and the review are loaded, and the UI's comment key is off until then.

### Trace 1: a CLI command, `video-review player seek 0:10`

Start: the app runs on demo data with the fixture open at 0 s, paused. The lease is free. The caller is a Claude Code session.

```text
ReviewCLI/main.swift               VideoReviewCLI.run(["player","seek","0:10"], environment)
ReviewCommand/CommandTable.swift     finds `player seek` → PlayerCommands.seek
ReviewWire/TimeCode.swift            "0:10" → 10.0                       (a bad time: usage error, exit 64, nothing sent)
ReviewWire/Holder.swift              Holder.find → key "CLAUDE_CODE_SESSION_ID=…", name "Claude Code", place the working folder
ReviewWire/ControlSocket.swift       locate: demo.json names the demo folder, its control.sock exists → that socket
ReviewWire/ControlClient.swift       writes {"command":"player.seek","holder":{…},"json":false,"seconds":10,"version":1}, half-closes
ReviewApp/Control/ControlServer.swift  reads to the end, on the main actor: reply(to:)
ReviewWire/ControlMessage.swift        decode: version 1 = 1, holder present → .playerSeek(seconds: 10)
ReviewLease/ControlLease.swift         use(by: holder, at: 12:00:00) → started; term ends 12:01:00
                                       state: lease = Claude Code until 12:01:00; the toolbar's sign shows
ReviewApp/AppModel.swift               seek(10): a video is open, 0 ≤ 10 ≤ 21.233
ReviewApp/Player/PlayerEngine.swift    AVPlayer.seek(to: 10, tolerance 0), awaited
                                       state: player.time = 10.0, playing = false
ReviewApp/Control/ControlServer.swift  writes {"ok":true,"output":"0:10\n","error":""} and closes
ReviewCommand/VideoReviewCLI.swift   prints "0:10", exit 0
```

`video-review state --json` now shows `"player": {"time": 10.0, "playing": false}` and the lease with its holder.

The rejection: five seconds later another agent (another holder key) runs `video-review player pause`.

```text
ControlLease.use(by: other, at: 12:00:05) → failure(.inUse(term))          no transition, nothing reaches AppModel
reply {"ok":false,"error":"Video Review is in use by Claude Code in /…/video-review until 12:01:00 (55s left); `video-review control take --wait <seconds>` to queue"}
CLI: the line on standard error, exit 1
```

A CLI of another build sends `"version": 2`: `decode` throws `otherVersion(2)` before the lease is asked, and the reply names both versions and says to reinstall.

### Trace 2: a batch, from Cmd+Enter to `wait`

Start: the fixture is open. The queue holds `c-7f3a9c2e` (10.0 s, no region) and `c-1b44e0d7` (12.5 s, region 0.25,0.2,0.3,0.25). A listener session L1 has `video-review wait` open: the outbox has `session = L1`, nothing pending, nothing taken; the pill says "Agent listening". L1 has not had this video's context yet.

```text
ReviewApp/Player/Shortcuts.swift       Cmd+Return → AppModel.send() → sendBatch()
ReviewApp/AppModel.swift               no draft; FrameGrabber has written both keyframes and the crop
ReviewApp/ReviewDesk.swift             change(hash) { $0.send(batchID: "b-5d0c2a91", at: 19:02:11Z) }
ReviewCore/VideoReview.swift             both comments queued → sent, batchId set; batches += b-5d0c2a91
ReviewStore/Library.swift                review.json written
                                       state: queue = []; both markers grey "sent"
ReviewApp/ListenerQueue.swift          enqueue(b-5d0c2a91): outbox.pending = [b-5d0c2a91]; outbox.json written; deliver()
ReviewCore/Outbox.swift                  deliverNext(at:): a wait is open → pending = [], taken = [b-5d0c2a91]; the wait is no longer open
ReviewCore/Outbox.swift                  context(for: hash, text): no digest for this video in this session → the text; digest recorded
ReviewApp/ContextReader.swift            sample.context.md, plus the note when there is one
ReviewTranscript/TranscriptSources.swift voiceover.json serves the fixture
ReviewTranscript/TranscriptWindow.swift  10.0 → 0 … 21.233 clamps to all three scenes; 12.5 → the same
ReviewCore/BatchPayload.swift            assemble → the JSON object of the spec, with absolute PNG paths
ReviewApp/Control/ControlServer.swift  the suspended wait resumes: {"ok":true,"output":"{…payload…}\n"}; the connection closes
                                       state: presence = working (a batch is taken); pill "Agent working"
ReviewCommand/ListenerCommands.swift   prints the payload, exit 0
```

Then, in order: `ack b-5d0c2a91 "On it"` moves both comments to `acknowledged` and adds a batch message; `ask c-1b44e0d7 "Which box?"` adds a question and waits; `thread answer c-1b44e0d7 "The left one"` (or the answer box) adds the answer and `ask` exits 0 with it; `reply` and `status … done` on each comment finish the batch, `Outbox.finished` removes it from `taken`, and presence returns to `listening` while a `wait` is open. A second batch on the same video gets `"context": null`.

The rejections:

```text
comment edit c-7f3a9c2e "new text" after the send
  VideoReview.editComment → the comment is sent, not queued → ReviewRefusal.notQueued → exit 1, nothing saved

no listener at Cmd+Return
  deliver() finds no open wait → the batch stays in pending; the pill says "No agent listening · 1 batch waiting"
  the next `wait` → waitOpened → takeNext() → the same payload, at once

the listener restarts as session L2 while b-5d0c2a91 is taken and unfinished
  Outbox.waitOpened(by: L2): the key differs → taken → front of pending; contextSent cleared
  VideoReview.requeue: acknowledged and working comments → sent; done and failed stay
  takeNext(): L2 gets b-5d0c2a91 with its unfinished comments and with the context again
```

### Build and tests

- `Package.swift`: tools version 6.2, `platforms: [.macOS(.v26)]`, no package dependencies. Library targets for the six modules, executable targets `ReviewCLI` (product `video-review`) and `ReviewApp` (product `VideoReview`), one test target per module. `ReviewApp`, `ReviewAppTests` and the `VideoReview` product are added under `#if os(macOS)`, after the rest (D214).
- Off the Mac (Linux), `swift test` builds the six modules and runs their tests: 181 tests in 6 targets, 1 skipped (the Application Support path, a macOS folder). `AppleSpeechRecognizer`, `ContentHash` and `ImageFiles` are left out there, `Holder` reads `/proc`, and `WorkspaceLauncher` refuses with `<app> runs only on macOS`. The app, its tests and every visual check stay on the Mac.
- Tests run a list of inputs with `@Test(arguments:)`, not a loop, so each input is its own case. The command's test doubles keep their state in a `Mutex`. The payload tests compare JSON numbers by type (`as? Double`), since `AnyHashable` compares them differently on Linux's Foundation.
- `Makefile`, after Shipyard's: `make test` (`swift test`, with the Command Line Tools flags for Swift Testing and a shared module cache), `make bundle` (builds both products, lays out the `.app`, stamps `Info.plist`, signs the CLI then the bundle ad hoc), `make install` (quits this bundle's app, replaces `/Applications/<APP_NAME>.app`, opens it in the background with `open -g`), `make acceptance` (runs `scripts/acceptance.sh` against the installed app; it is not part of `make test`).
- `make test` never drives the Mac. Each contract has one owner test at its strongest boundary:

| Contract | Owner test |
|---|---|
| version refusal, wire round trips | `ReviewWireTests` |
| the lease rules | `ReviewLeaseTests`, time-driven tables |
| CLI parsing, output, exit codes | `ReviewCommandTests`, fake transport and launcher |
| the state machine, batch assembly, requeue, context once per session, presence | `ReviewCoreTests` |
| the window cut, the source order | `ReviewTranscriptTests`, against `fixtures/sample` |
| what is on disk, the hash of a renamed copy, files that do not read | `ReviewStoreTests` |
| what a restart keeps | `ReviewAppTests` `PersistenceTests`: a second `AppModel` on the same support folder |
| the server enforcing the lease, held requests | `ReviewAppTests`, fake `AppControlling` |
| everything end to end | `scripts/acceptance.sh` against the installed app in demo mode |

- `app open --demo <folder>`: the folder is the demo run's own support folder, made when missing (the scenario uses a folder under `.scratch/`). The fixture video is opened with `player open`.

### The acceptance scenario

`scripts/acceptance.sh` is the spec's v1 acceptance scenario as one bash script. It drives the installed app through the `video-review` command only, in demo mode, and checks what the commands print and write. Run it after an install:

```text
make install && make acceptance
VIDEO_REVIEW_CLI="/Applications/Video Review.app/Contents/Helpers/video-review" scripts/acceptance.sh     another build of the spec
```

- The command is named in one place: `VIDEO_REVIEW_CLI`, else the installed app of this checkout's `AppIdentity.variant`, read as the `Makefile` reads it. The script needs `jq`, `sips` and `xxd`, which macOS ships.
- Each run has its own folder, `.scratch/acceptance/<date>-<time>-<pid>/` (`ACCEPTANCE_DIR` moves it): `demo/` is the demo's support folder, `payload.json` is what `wait` printed, `logs/` holds each command's output, `state-before-quit.json` and `state-after-open.json` are the two sides of step 7, and `screenshots/` holds `light.png` and `dark.png`. The fixture folder is only read.
- Two holder keys, set with `VIDEO_REVIEW_CONTROL_KEY`: the operator's for every leased command, and the listener's for `wait`, `ack`, `status`, `reply` and `ask`, which stands for the scenario's second shell. The operator takes the lease in step 1 (`control take`) and releases it at the end of step 8.
- The demo rule: after each `app open --demo` the script reads `app status --json`, and when that does not say `"demo": true` it prints the answer and exits 3 at once. Nothing more is sent, the clean-up's `app quit` included.
- A step prints one line per check (`ok` or `FAIL`), then `PASS  step N: …` or `FAIL  step N: …`. The first failed step ends the run with exit 1, since each step builds on the one before. Exit 0 means all eight passed; 69 means a tool, the command or the fixture is missing. On every exit the script ends its held `ask` and quits the demo app.

| Step | Commands | Checks |
|---|---|---|
| 1 | `app open --demo`, `app status --json`, `control take` | the exit codes; `"demo": true` |
| 2 | `player open`, `play`, `pause`, `seek 0:10`, `comment add` | the fixture is open and paused; one queued comment at 10 s with its text |
| 3 | `comment add --at 0:12.5 --region 0.47,0.27,0.29,0.15` | two queued comments; the second at 12.5 s with a region |
| 4 | `batch send` | both comments are `sent` |
| 5 | `wait --timeout 20`, as the listener | `batch.id` and `sentAt`; `video` (the fixture's path, a content hash, 21.233 s, a title); `context` is the text of `sample.context.md`; two comments in time order with their texts, the region as sent and `null` for the first; both keyframes are PNG files of 1920 by 1080; the crop is a PNG of the region's size in the frame (557 by 162, within a pixel); the paths are absolute; each transcript line lies inside 15 s before to 15 s after its comment, and the line spoken at the comment's time holds "Press command enter" |
| 6 | `ack`, `ask --wait 60` held in the background, `thread answer`, then `status working`, `reply` and `status done` on each comment, and `reply` on the batch | `acknowledged` after the `ack`; the question is in the thread before the answer is sent; `ask` exits 0 and prints the answer's text; both comments `done`; the second thread is question, answer (by the person), reply, in that order; the batch has the acknowledgement and its reply |
| 7 | `app quit`, `app status --json`, `app open --demo` (the same folder), `state --json` | not running after the quit; `"demo": true` again; `comments`, `queue`, `batches` and `video` of `state --json` are the same bytes as before the quit (`jq -S`); both comments `done`, threads of 1 and 3 messages |
| 8 | `screenshot --appearance light`, `--appearance dark`, `control release` | two PNG files with a size, not the same picture; the lease is free |

What the script reads beyond the spec's contract is the shape of this build's `state --json` and `app status --json` (`demo`, `comments[].state`, `thread`, `batches[].messages`, `lease`), which the contract leaves to each build (D29). The commands, their arguments, the exit codes and the payload are the contract's.

`scripts/screenshots.sh [<folder>]` builds a fuller scene the same way and writes the pictures of `assets/screenshots/v1-acceptance/`: two batches with comments that are done, failed, working and acknowledged, a question with its answer, an open question, a queued comment and two region comments. It makes three views, each in light and dark: `review` (a selected region comment with its rectangle on the frame and its thread open), `queue-and-question` (a queued region comment, an open question with its notice and its answer box) and `lease-banner` (the second view with `--with-banner`). It has the same demo rule. The replies and the commit ids in it are scene text.

NOTE: The pictures in `assets/screenshots/v1-acceptance/` are older than the pastel palette, the rail of rows, the toolbar's agent-control sign and the Context popover's transcript part. They show the cards, the strip banner and the transcript chip. Make them again on the Mac with `scripts/screenshots.sh`.

## 5. Extensibility

| Change | What you touch |
|---|---|
| A new CLI command | a case in `ControlRequest` with its wire fields, a parser in `ReviewCommand`, a branch in `ControlServer`, a method on `AppModel` or `ListenerQueue`. Four known places; the compiler finds the two `switch`es. |
| A new UI action | a method on `AppModel`, then the CLI command above. ADR 0001: it is not done until the command exists. |
| A better transcription source | one new `Transcriber` in `ReviewTranscript`, one line in `TranscriptSources.standard`. Another speech engine behind the same background source: one new `SpeechRecognizing`, passed to `AppModel.init`. |
| A new field in the payload | `BatchPayload` and its `assemble`. |
| A new comment state | `CommentState` and `canMove`, `Theme` for its colour and glyph. Old files still read. |
| Dropping the prototype suffix | `AppIdentity.variant = ""`. |
| A shape other than a rectangle | `Region` becomes one case of a shape type; `RegionOverlay`, `FrameGrabber` and the payload's `region` follow. Not designed for now. |
| A database in place of JSON files | `Library` only; its callers use its methods, not its files. |
| A listener over the network | a second transport beside `UnixSocket`; `ControlServer.reply(to:)` already takes bytes and returns bytes. |

Refused for now, because v1 does not need them: more than one listener or window, an Allow button for a barred holder, a cache of content hashes by path, persisted drafts, undo, system notifications, a plug-in registry of commands.

## 6. Decisions the spec left open

Each UX choice is in [the UX table](#the-ux-of-this-prototype). The other choices:

| # | Decision | Reason |
|---|---|---|
| D1 | The prototype identity is one Swift constant, `AppIdentity.variant`, which the `Makefile` reads. | One line to change, and `swift test` sees it with no generated file. Shipyard keeps its version the same way. |
| D2 | Target names are `ReviewWire`, `ReviewLease`, `ReviewCommand`, `ReviewCLI`, `ReviewCore` (the spec's Review), `ReviewTranscript`, `ReviewStore`, `ReviewApp`. | Bare names such as `Transcript` can clash with system types. The command table is a library so it tests without a process. |
| D3 | `ReviewWire` is the lowest module and holds `Holder` and `LeaseTerm`; `ReviewLease` builds on it. | The first build ticket ships the wire with no lease rules yet. |
| D4 | The pure listener rules are a value, `Outbox`, in `ReviewCore`; the app's `ListenerQueue` holds only the connections. | The same split as `ControlLease` and `ControlServer`: the rules test without the app. |
| D5 | A listener session is the holder key of its `wait`. A `wait` from another key is a new session: unfinished taken batches go back to the queue and the context is sent again. This holds across an app restart, since the outbox is on disk. | Every request already carries the holder, so the listener passes nothing, and a test names a session with `VIDEO_REVIEW_CONTROL_KEY`. |
| D6 | A redelivered batch keeps its id and carries only its unfinished comments, which return to `sent`. | Finished work is not done twice. |
| D7 | One open `wait`. A newer `wait` replaces the older one. | A restarted listener must not wait behind a dead connection. |
| D8 | `wait` and `ask` are held connections in the app, like a queued `take`. | One mechanism for every long wait, already proven in Shipyard. |
| D9 | `wait` without `--timeout` and `ask` without `--wait` wait with no limit. A timeout exits 2 with nothing on standard output. | The listener wakes only for work. Exit 2 tells a timeout from a refusal. |
| D10 | `wait` connects again while the app is not running. | The listener can start first and survive an app restart. |
| D11 | A late answer stays in the thread and is read from `state --json`. | The contract has no command for it, and `state` is free. |
| D12 | Presence is `listening`, `working` or `absent`, from the open `wait`, the taken batches and the time of the last listener command (120 s while working, 5 s otherwise). | It changes the moment a `wait` opens or closes, without a flicker between two `wait`s. |
| D13 | Listener state moves are forward only and may skip a state. | A listener that forgets `ack` is not stuck. |
| D14 | One open question per comment. | `thread answer` names a comment, so the answer must have one question to go to. |
| D15 | Storage is JSON files, one folder per content hash, each save atomic. | Small data, readable by the maintainer and by agents, no dependency. |
| D16 | The content hash is the SHA-256 of the whole file. | It is exact for renamed and moved files. A partial hash could confuse two renders of one video. |
| D17 | Ids are short and random with a type prefix (`c-`, `b-`, `m-`), unique across videos. | Listener commands name no video, and `reply` takes either kind of id. |
| D18 | Keyframes and crops come from the asset with `AVAssetImageGenerator` at zero tolerance, at the video's own size. | The exact frame, the same pixels from the UI and the CLI, at any window size, with no screen permission. |
| D19 | A region's origin is the top-left corner of the displayed frame. | It matches the screen and image coordinates an agent reads. |
| D20 | The payload is assembled when a `wait` takes the batch. The transcript window and the context are read then. | With a listener waiting it is the moment of sending. Otherwise the agent gets a fuller transcript and the current context. |
| D21 | Transcript lines are `{start, end, text}`. A line that overlaps the window is kept whole. | A cut sentence reads badly. |
| D22 | The context is the sidecar text, then the note under the heading "Note from the reviewer". It is `null` when there is no text. "Changed" means its digest differs from the one this session last got for this video. | One text for the agent, and a rule that needs no file watching. |
| D23 | `video.title` is the file name without its extension. | Predictable, and it follows a rename. |
| D24 | `comment add` pauses and seeks to `--at`, as a person would. `player seek` keeps play or pause. | An operator does what a person does, and the person sees where the comment went. |
| D25 | A draft is in memory only and is not saved. | Sent and queued work persists; half a sentence does not need a file format. |
| D26 | `--demo <folder>` is the demo run's support folder, as in Shipyard. | The fixture folder stays read-only, and demo and real data cannot mix. |
| D27 | Exit codes: 0, 1 refused, 2 timed out, 64 usage. `app status` exits 0 when the app is not running. | Scripts can tell the cases apart. |
| D28 | The lease banner (today the toolbar's agent-control sign, D208) is left out of screenshots, unless the agent passes `--with-banner`. | The agent that takes the screenshot always holds the lease, so the banner would be in every picture. The flag is an addition to the contract's `screenshot`, after Shipyard's `--with-indicator`: the only way an agent can prove the banner's pixels. |
| D29 | `state --json` has the shape shown under `StateReport`. | The contract names the command, not its fields. |
| D30 | The lease keeps Shipyard's handover across a relaunch, and leaves out Allow. | `app open --demo` on a running app must keep the operator's lease. Nothing in v1 lifts a bar early. |
| D31 | A socket path longer than an address holds is reached through a short symbolic link in the user's temporary folder. | A demo folder under `.scratch/` in a worktree is longer than 103 bytes. Shipyard refuses such a folder; here the tests need it. |
| D32 | The CLI launches the bundle it ships in, and falls back to the bundle id. | Three prototypes are installed side by side, and a build folder holds a second copy with the same bundle id. |
| D33 | `app open --demo` on the demo that already runs keeps it running. | A test script can call it again without losing the open video. |
| D34 | For a demo launch, the launcher asks a copy of the app that does not answer yet to quit. | `make install` opens the app; a demo launch right after it would get that copy back, on the person's data. |
| D35 | With `--json`, an action prints the parts of the state it changed. | An agent reads the result of its command without a second `state` call. |
| D36 | `video.duration` is the video track's length. | A comment points at a frame, and the last frame ends there. The sound track of the fixture runs 15 ms longer. |
| D37 | Closing the window quits the app. | There is one window and nothing to do without it. `screenshot` and `state` always have a window to show. |
| D38 | The app quits cleanly on `SIGTERM`. | `make install` ends the app with it, and a socket file left behind would hide a normal app from the CLI while a demo pointer exists. |
| D39 | `state --json` and `app status --json` report the lease as `holder` (`key`, `name`, `place`), `taken`, `ends`, `secondsLeft` and `waiting`. | An agent sees who holds the app, tells two holders with one name apart by the key, and knows how long to wait. |
| D40 | A `control take --wait` whose wait runs out exits 1, not 2. | It is a refusal with a reason (who still holds the app), as in Shipyard. Exit 2 stays for `wait` and `ask`, which time out with nothing to say. |
| D41 | `control take` and `control release` have no `--key` option. | The contract names none. `VIDEO_REVIEW_CONTROL_KEY` names the holder for every command of a run. |
| D42 | `control release` from an agent that holds nothing answers `released`, exit 0. | A script can always release at its end. Shipyard does the same. |
| D43 | `app open` on a running app is an operator command, so it takes or renews the lease, and another holder's is refused. | The contract lists `app open` under the operator commands. |
| D44 | After Stop the popover closes, the sign leaves the toolbar, and nothing more shows for the barred agent. | There is no Allow (D30), so a line about the bar would have no action. The agent's refusal tells it to ask the person. |
| D45 | The server ignores the lease's transitions. | They exist for notifications in Shipyard; this app has none (UX 16). The banner (the toolbar's sign) follows the lease itself. |
| D46 | A comment made at the player's time gets that time raised to the next millisecond. `--at` keeps the time given. | Rounding down would name the frame before the one on screen, and the keyframe would be the wrong frame. |
| D47 | The keyframe is written first, then the comment is queued. `comment add` answers after both. | A comment never exists without its keyframe, and an agent can read the PNG as soon as the command returns. |
| D48 | A comment holds no image path. `ImageFiles` derives it from the content hash and the comment id. | A support folder that moves (a demo folder, a restored backup) keeps working. |
| D49 | Deleting a comment deletes its keyframe file. | Nothing else refers to the file, and no undo exists. |
| D50 | `comment edit` and `comment delete` on an id that is not a comment id answer the same line as an unknown id. | The caller needs one thing to do: read the ids from `state --json`. |
| D51 | A comment has no creation date. | Nothing shows it or orders by it. The batch has `sentAt`. |
| D52 | `comment add` selects the new comment, like a comment from the box. | The person sees which row an operator just added. |
| D53 | `--region` text that is not four numbers is wrong usage (exit 64). Four numbers that are not a rectangle inside the frame are refused by the app (exit 1), before it pauses or seeks. | The command knows the shape of its arguments; the rule of what a region is has one home, `Region.init`, which the agent side does not link. |
| D54 | On the wire a region is the object `{x, y, w, h}`, the same shape as in `state --json` and the payload. | One shape for a region everywhere an agent reads or writes JSON. |
| D55 | A region's edges may pass 1 by 1e-9. | `0.7,0,0.3,1` is a valid region as written, and its sum is not exactly 1 in binary. |
| D56 | The crop's pixels are the region's edges rounded to the nearest pixel of the keyframe, at least one pixel each way. The crop is cut from the keyframe image in memory. | The crop is exactly a part of the keyframe PNG, and a sliver still gives a picture. |
| D57 | A region drawn in the UI is kept to four decimals. | Finer than a pixel of a 4K frame, and `state --json` and the payload stay readable. |
| D58 | A drag is clamped to the picture. A drag that starts in the letterbox counts from the picture's edge. | The person need not aim at the edge to take a region that reaches it. |
| D59 | A press that moves under 4 pt is a click (play or pause). A rectangle under 8 pt either way is not a region and opens nothing; the video stays paused. | A slip of the hand is not a comment. The pause already happened when the drag began, and resuming by itself would surprise. |
| D60 | Escape during a drag drops the rectangle; the pointer's release then opens nothing. Escape with the box open drops the comment and its region, also when the text view lost the focus. With neither, Escape is left to the window. | Escape always means "not this region". |
| D61 | A drag while the comment box is open replaces the draft's region, takes the time of the frame on screen and keeps the words. | Pointing again is a correction. A second box would lose what was typed. |
| D62 | A selected comment's region shows only while the player is paused within half a frame of the comment's time. | The rectangle belongs to one frame. |
| D63 | `comment add` with a region answers `… queued at 0:12.5 on the region 0.25,0.2,0.3,0.25`; without one the line is as before. `state` lines name the region too. | The operator sees the region it sent was kept. |
| D64 | The frame geometry is computed from the video's size and the stage's size, not read from `AVPlayerView.videoBounds`. | It is a pure function, so "the region stays correct at any window size" is a unit test. |
| D65 | Deleting a comment deletes its crop file with its keyframe. | As D49. |
| D66 | A held request whose time ran out answers `{"ok": false, "timedOut": true}`, and the command exits 2 on that field. | The app owns the timeout, so it closes the `wait` and the presence at the right moment. Exit 2 must not depend on the words of an error line. The field is left out of every other reply, as `lease` is. |
| D67 | `wait --timeout` takes 0 to 86400 whole seconds. `--timeout 0` answers at once: the batch in line, or exit 2. | A listener may wait for hours. Zero is a way to ask "is there a batch now". |
| D68 | The app looks at each held connection every 0.5 s and closes a `wait` whose client closed its socket. | "Present while a `wait` is open" must end when the listener's command is stopped, not only when a reply fails to write, which may be hours later. |
| D69 | After a `wait` closes with no batch the listener still counts as listening for 5 s, also when its client hung up. | One rule for every way a `wait` ends (D12). A harness that restarts a background `wait` does not make the pill flicker. |
| D70 | A new listener session is told only by a new holder key. A `wait` from the same key keeps what it took and gets the next batch in line. | The listener skill runs `wait` again before it starts work on a batch; that must not hand it the same batch twice. |
| D71 | A batch in line whose review is not there or does not read, or whose comments are all finished, is discarded when a `wait` reaches it. | A `wait` must never get stuck behind a batch that cannot be delivered. |
| D72 | Replaced by D143: the outbox is on disk. Before the persistence ticket the outbox stayed in memory. `Outbox` is `Codable` already, without its open `wait` and last-heard time. | The reviews are in memory too, so an outbox on disk would name batches that are gone after a restart. |
| D73 | `batch send` answers `b-… sent with 2 comments, taken by the listener` or `…, waiting for a listener`. | The operator sees at once whether someone has the batch. |
| D74 | `state --json` has `listener.takenBatches` beside `pendingBatches`. | An agent can tell "delivered and unfinished" from "still in line" without the payload. |
| D75 | `wait` looks for the app's socket again on every try. | A listener started before `app open --demo` must find the demo's app. |
| D76 | When the app quits, an open `wait` is closed with no reply. | The command reads that as "not running" and connects again (D10). A refusal would end the listener. |
| D77 | Cmd+Return is handled by the key monitor, before the text view, and the menu item shows the same key. Both call `AppModel.send`. | One place decides the key for the stage, the comment box and a row being edited. The menu makes it discoverable. |
| D78 | `send()` does nothing when there is nothing to send, or while a send is under way. `batch send` with an empty queue is a refusal. | A person's stray key press is not an error. An agent's command needs an answer. |
| D79 | The rail's rows are in a plain stack, not a lazy one, so the section headers are not pinned and scroll with their rows. | A lazy stack kept drawing a sent row as queued after it moved to its batch's section. A review has tens of comments. |
| D80 | A batch's header says "Sent at 00:13", with a two-digit hour. | "Sent 0:13" reads as a time in the video. |
| D81 | The comment box's hint row names Return, Cmd+Return and Escape, and no longer Shift+Return. | The row has room for three hints. |
| D82 | `Transcriber.lines(for:in:)` is synchronous and answers at once with what the source has. | The payload is assembled in one step when a `wait` takes the batch (D20), and a comment sent before the transcript is ready must get the lines that exist then. A call that could wait would hold the batch back. |
| D83 | The interface also has `transcript(of:)` (the source, the lines so far, complete, problem; nil when the source has nothing for the video) and `prepare`. `TranscriptSources` is a `Transcriber` too. | The source order, the state report and the Context popover's transcript part need more than a window's lines, and the app then holds one thing. |
| D84 | A sidecar is read each time it is asked, not when the video opens. | The files are small, and a sidecar that is added or fixed while the video is open is used by the next batch (D20). |
| D85 | A sidecar that does not read (a `voiceover.json` of another shape, a subtitle file with no cue) leaves the video to the next source. | A broken file must not cost the agent the transcript. |
| D86 | `voiceover.json` is looked for as `<base>.voiceover.json`, then `voiceover.json`, in the video's folder. Subtitles are `<base>.srt`, then `<base>.vtt`. | The context file is beside the video too, so "beside the video or in its `context.md` folder" is one folder. A folder with several videos needs the named form. |
| D87 | Every source gives its times to the millisecond. A scene's frames are counted at the video's own frame rate, read from the player. | The scene times then equal the `.srt` cue times, so the two sources give the same lines for the fixture. |
| D88 | A line that only touches the window's edge is outside the window. | A scene that ended exactly 15 s before the comment was not heard within 15 s of it. |
| D89 | A speech line is one finalized result of `SpeechTranscriber`, with that result's audio time range. No volatile results are used. | A line never changes after a batch carried it. The results are about a sentence long. |
| D90 | `Outbox.contextSent` is kept on disk with the session. | A listener session is its holder key, which outlives an app restart. What the session has must outlive it too, or every restart sends the context again. |
| D91 | The digest of a context text is its length in bytes and its 64-bit FNV-1a hash. | `ReviewCore` links Foundation only, and Swift's own hash differs in each run. The digest tells a change; it keeps no secret. |
| D92 | With no context text the payload has `null` and the session keeps its digest. | `null` already means "nothing new". A sidecar that is gone for one batch and comes back unchanged is not read twice. |
| D93 | A payload that could not be written forgets its video's digest, whether it carried the context or not. | The outbox does not know which payload carried the text. A context sent twice costs little; one that is lost costs the agent its topic. |
| D94 | The sidecar is the first of `<base>.context.md` and `context.md` that is a file and reads as UTF-8. Its text is trimmed. A blank file of the video's own name serves, with no text. | The spec's order. A file that does not read must not hide the fallback. A blank file is a way for one video to opt out of its folder's `context.md`. |
| D95 | A note with no sidecar keeps its heading: the context is `## Note from the reviewer`, then the note. | The agent always knows which words are the person's. |
| D96 | The note is kept trimmed. `context set ""` clears it. | The contract has no command to clear a note, and a note of spaces is no note. |
| D97 | The sidecar is read when a `wait` takes the batch (D20), from the folder of the path the video was last opened at, and when the popover opens. Nothing watches the file. | A change to the file reaches the next batch with no watcher, also for a video that is no longer open. |
| D98 | `state --json` has `video.contextNote`, and nothing about the sidecar. | The note is the app's state. The sidecar is a file the agent can read, and the payload carries its text. |
| D99 | The popover's Save and `context set` are one method, `AppModel.setContextNote`. In the popover Return saves, as in the comment box. While it is open the player's keys are off, Cmd+Return too. | One code path for the person and the operator (ADR 0001). Cmd+Return in the note must not send the queue with a note that is not saved yet. |
| D100 | The popover says whether the agent has the context, from `Outbox.isContextDue`. | "Once per session" is invisible otherwise, and the person would wonder whether a new note went out. |
| D101 | A review with no `note` key reads as an empty note. | Reviews written before this ticket, and the tests' own JSON, still read. |
| D102 | The context popover is not in a `screenshot`. | A popover is a window of its own, and `Screenshotter` captures the player's window only. The toolbar button, with its filled glyph, is in the picture. |
| D110 | Speech is transcribed in the Mac's language (the nearest locale `SpeechTranscriber` supports), else in `en-US`. | The spec names no language setting. The research task can choose better. |
| D111 | Only a complete speech transcript is kept on disk, in `videos/<hash>/transcript.json`. A transcription that stopped half way starts from the beginning the next time the video opens. | The fixture takes about a second. Resuming would need the recognizer to start at a time, for little gain. |
| D112 | `TranscriptFiles` in `ReviewStore` keeps the transcript, beside `Library` (D148). | The speech source reads and writes it from a background task; `Library` is for the main actor. |
| D113 | The speech engine is behind `SpeechRecognizing`, and `AppModel.init` takes one. | "A comment before the transcript is ready" is tested with a recognizer the test drives, with no real speech recognition in `make test`. |
| D114 | `state --json` has `transcript`: `source`, `complete`, `lines` and `problem`. `state` as lines has a `transcript:` line. | An agent can wait for `complete`, and reads why there is no transcript. |
| D115 | The transcript's words (the Context popover's transcript part, and the Context glyph's pulse) are read again each second, and observe nothing. | Speech lines arrive on a background task. The presence pill does the same. |
| D116 | The app installs the language's speech model through `AssetInventory` without asking, and asks for no speech recognition authorization. `Info.plist` has `NSSpeechRecognitionUsageDescription`. | `SpeechAnalyzer` ran on this Mac from a command-line tool with no prompt. The usage text is there in case macOS asks for the bundled app. |
| D117 | Replaced by D146: a batch of a video that was not opened in this run gets its transcript lines from the frame rate and the path kept with the review. | |
| D118 | A video with no sound track has a complete speech transcript with no lines; the Context popover's transcript part says "No speech". | Nothing failed, and there is nothing to wait for. |

Decisions of the ticket "Mate: Show agent answers and questions in the player":

| # | Decision | Reason |
|---|---|---|
| D120 | `ack` moves only the comments still `sent`. A comment further on stays, and the `ack` is not refused. | A listener that says `working` first and acknowledges after must not be refused or moved back. |
| D121 | `ack` with no text adds no message. Its notice says "It got your 2 comments." | The acknowledgement must show in the player, and a thread must hold only what the agent wrote. |
| D122 | A `status` that names the state the comment already has is accepted and changes nothing. Any move back, and any move from `done` or `failed`, is refused. | A listener that repeats itself after a retry is not in error. |
| D123 | `status`, `reply` and `ask` on a queued comment are refused. | The listener never got that comment; an id it guessed must not start a thread. |
| D124 | A reply does not close an open question, and an answer needs an open question. | Only the person's answer is what the `ask` waits for. |
| D125 | `thread answer` writes an answer by the `person`, also when an operator sends it. | The operator does what a person does, and the contract has two authors. |
| D126 | `ask --wait 0` leaves the question and answers at once with exit 2. `--wait` takes 0 to 86400 whole seconds. | The same rule as `wait --timeout 0`; a listener can ask and go on working. |
| D127 | `ask` prints the answer's text alone, and with `--json` `{"answer": {id, author, kind, text, at}}`. | "Exit with the person's answer": a script reads standard output as the answer. |
| D128 | The command exits 2 on any reply with `timedOut`, not only on `wait`'s. | One rule for every held request (D66). |
| D129 | An `ask` whose client goes away, or that is open when the app quits, ends with no reply, and its question stays open. | Nobody reads the reply. The question is a record in the thread, and the person can still answer it. |
| D130 | An open `ask` counts as alive for presence (`Outbox.openAsks`). | The listener is there for as long as it waits for the person. |
| D131 | The wire has its own `ControlRequest.Status` with three names. | `ReviewCommand` does not link `ReviewCore`, and `status acknowledged` must be wrong usage. |
| D132 | A listener's command finds its video in the `Library`'s index of comment and batch ids, read from every `review.json` at launch and kept current by each save. | Listener commands name no video, and the video need not be open or opened in this run. |
| D133 | The refusals for an id that names nothing are the app's own lines for the listener (`no comment … ; the batch video-review wait printed names each comment's id`). | `state --json` lists only the open video's comments. |
| D134 | Unread marks and notices are kept in memory only, and opening a video clears them. | They say what happened while the person watched; after a restart every thread is simply there. |
| D135 | A status change raises no notice. `ack`, `reply` and `ask` do. | The marker shows a status at once; three notices for three statuses would cover the video. |
| D136 | The answer box takes the focus only on a click. Cmd+Return in it still sends the queue. | A question arrives at any time and must not take the player's keys. Cmd+Return means "send the queue" everywhere (D77). |
| D137 | The working marker does not pulse. | A pulse caught at its dim point made the glyph vanish in a screenshot; the three dots tell the state by shape. |
| D138 | An open question has a colour no state has: a soft teal. The agent's colour is the app's slate accent (D204), which an acknowledged comment shares. | A question must not read as a state. The agent's messages and notices are told apart by their place and heading, not by a colour of their own. |
| D139 | A notice for a comment whose video is not open says "a comment", and a click on it only takes it down. | The comment has no marker to number it by or to select. |

Decisions of the ticket "Comment: Keep comments and threads across restarts":

| # | Decision | Reason |
|---|---|---|
| D140 | A `review.json` that does not read is treated like one from a newer schema: the video's history is not opened, the reason names the file, and the file is never written over. Nothing sets it aside and starts a new review. | Data loss is the risk. A file that half reads may still hold the person's comments, and a new review saved over it would end them. The maintainer can read and repair a JSON file. |
| D141 | A change whose save fails is refused, and memory keeps what is on disk. | The person and the listener learn of a full disk when it happens, not after a restart that lost the work. Memory and disk never disagree. |
| D142 | Each file carries `schemaVersion` beside its own keys, in one flat object. A file without it is version 1. | "One VideoReview, with schemaVersion" (D15), and files of earlier tickets' tests still read. |
| D143 | `outbox.json` is written whenever the kept part of the outbox changes, from one place (`ListenerQueue.outbox`'s `didSet`). | No call site can forget the save. Presence, the open `wait` and the last word are not kept, so a `heard` writes nothing. |
| D144 | At launch the outbox is reconciled with the reviews: every unfinished batch is in `pending` or `taken`. A missing or unreadable `outbox.json` is rebuilt the same way, in the order sent. | The review and the outbox are two files, so a crash can fall between their saves. "No feedback is lost" must not depend on that moment, or on one small file. |
| D145 | A taken, unfinished batch stays with its listener across an app restart when the next `wait` has the same holder key, and goes back in line for another key. | The listener session is its key (D5), which outlives the app. A listener whose `wait` connects again after a restart (D10) is the same session and must not get its batch twice. |
| D146 | The frame rate is kept on the review's `VideoInfo` with the last path. A batch delivered in a run that did not open its video reads its transcript and its context sidecar from there. | A pending batch can be taken after a restart with another video open, or none. Its payload must be as full as it would have been. |
| D147 | Times in a review are cut to the millisecond when they enter it, and files hold ISO 8601 with milliseconds. | A person can read the file, and a review reads back equal to the one saved, so `state` is the same before and after a restart. |
| D148 | `TranscriptFiles` and `ImageFiles` stay beside `Library`. | They are used off the main actor, and each is the one owner of its files. `Library` is the owner of the JSON records and the index. |
| D149 | A video that was opened and has no comment, batch or note yet has no `review.json`. `recent.json` alone makes it open again. | Opening a video is not a change to keep, and the real support folder stays empty until the person writes something. |
| D150 | `Library.init` writes nothing, and the folder is made by the first save. | A demo run, a test and a second copy of the app can look at a support folder without changing it. |
| D151 | At launch the app opens the last video only after it has the socket, and every request waits for that opening. | A second copy must not write. `app open` followed by `state --json` must show the video and its history, with no sleep in a script. |
| D152 | A last video whose file is gone is not an error at launch. One that does not open for another reason is shown to the person. | A moved file is ordinary. A history that does not read is something the person must know about. |
| D153 | A missing keyframe or crop is not made again. | The picture is written before its comment exists (D47), so it is missing only when someone removed it. The path is still the one a comment has (D48). |
| D154 | The listener's name is kept with the session, so threads keep "Claude Code" after a restart. Unread marks, notices, the draft and the open `ask`s are not kept. | The session is on disk for D145. The rest is by D25, D129 and D134. |
| D155 | `recent.json` is written on every open, also when an operator opens the video. | The operator does what a person does, and the acceptance scenario needs the video back after `app quit` and `app open`. |

Decisions of the ticket "Mate: Ship the video-review-mate skill":

| # | Decision | Reason |
|---|---|---|
| D160 | The skill is one `SKILL.md` with no reference file and no script. | Every branch of the loop needs nearly all of it, and it is short. A script would be a second thing to keep in step with the CLI. |
| D161 | The skill finds the CLI in one place: `$VIDEO_REVIEW_CLI`, else the real product's path, else the one `/Applications/Video Review*.app`. With several, it asks the user. | The path is all that differs between the builds. The glob finds a prototype's app without the skill naming one. |
| D162 | The skill has a description, so a session can start it from the user's words as well as by its name. | It costs context only in a repo where it is installed, and a headless session is started with a plain sentence. |
| D163 | This repo has no `.claude/skills` link to the skill. | `AGENTS.md` names no such folder. The skill is for sessions in other repos; a session working on this repo is not a listener. |
| D164 | On a batch the skill sends `ack` first, then starts the new `wait`. | The acknowledgement is what the person waits for. Both are one command each, so the new `wait` is open a moment later. |
| D165 | The skill never runs an operator command, `app open` included. | An operator command takes the lease and shows the banner. The person opens the app and the video. |
| D166 | The reason for a `failed` comment is a `reply` sent before `status failed`. | `status` carries no text in the contract. |
| D167 | `ask` runs as a background command with no `--wait`, and the other comments go on. | A foreground command of a harness ends after minutes, and a cut-off `ask` leaves an open question that refuses the next `ask`. |
| D168 | A question with no answer (exit 2, or the app quit) is looked up once in `state --json` when the rest of the batch is finished. With no answer there, the comment is `failed` with a reply. | Every comment must end, and D11 gives the late answer no other way out. |
| D169 | The batch-level `reply` comes last, after every comment is `done` or `failed`. | It reports the result of all of them. This build takes a message on a finished batch. |
| D170 | Comments are worked one at a time, in the payload's order. | One working tree and one commit per comment. |
| D171 | When the app is not running, the skill tells the user and keeps the results; it does not wait in a loop of its own. | This build's `wait` connects again by itself. A build whose `wait` exits must not make the session spin. |
| D200 | `AppModel.open` reads the review twice: before the load, to refuse a history that does not read, and after it, to open on the review as it is then. | The load takes time and gives the main actor away. A listener's `status` or `reply` in that time is saved by `ReviewDesk.change`, and the review taken before the load would be written over it. |
| D201 | An argument with a space in it is a word, every argument after `--` is a word, and help is asked for only before the command's name. A known option is an option anywhere else. | A reply or a comment may start with `--` or be `-h`. The contract's lines (`comment add "text" --at 5 --json`) read as before. The skill says only that a text must not start with `--`, since another build may not take `--`. |
| D202 | A time that is not a finite number is refused where it is read: `TimeCode.seconds` and `SubtitleSource.seconds`. | JSON has no infinity, and the request's and the payload's encoders do not fail softly. A long digit string is wrong usage (exit 64), and a cue with `inf` is a bad cue. |
| D203 | The player's seek and the keyframe use one timescale, 60000. | A comment's time is in milliseconds (D46). In 600ths, a millisecond time can round down to before its frame's start on 29.97 and 59.94 frames a second, and the player would show the frame before the keyframe's. |

Decisions of the ticket "Proto: Run the v1 acceptance scenario and open the draft pull request":

| # | Decision | Reason |
|---|---|---|
| D180 | The acceptance scenario is a bash script with `jq`, `sips` and `xxd`, not a Swift test. | Its seam is the installed command, so it must run outside the package and against another build of the spec. Shipyard's `Harness` scenarios run inside `swift test`, which never drives the Mac. The three tools ship with macOS. |
| D181 | The script names the command in one place: `VIDEO_REVIEW_CLI`, else the installed app of `AppIdentity.variant`. | The path is all that differs between the builds, and it is the variable the listener skill reads (D161). |
| D182 | When `app status --json` does not say `"demo": true` after `app open --demo`, the script exits 3 and sends nothing more, not even `app quit`. | The script must never touch the person's data. A quit is a command to an app that may be on that data. |
| D183 | Each run has a new folder under `.scratch/acceptance/`, with its demo data, payload, logs and screenshots. The fixture is opened where it is. | A run never sees another run's comments, and a failed run can be read afterwards. The fixture folder stays read-only (D26). |
| D184 | The operator and the listener are two holder keys in one script. The batch is sent with no listener, then `wait` takes it. | The scenario's order: `batch send`, then `wait` in a second shell. A second key is a second agent to the app (D5), with no second terminal to start. |
| D185 | `ask` is held in the background. The script sends `thread answer` once the question is in `state --json`. | The answer needs an open question (D124). A fixed sleep would be slow or flaky. |
| D186 | The first failed step ends the run. Inside a step every check still runs and prints. | Each step builds on the one before, so later failures would be noise. One step's checks are independent, and all of them help to find the fault. |
| D187 | The crop is checked by its size: the region's width and height in the frame's pixels, within a pixel. | The rounding to pixels is each build's choice (D56). That the crop's pixels are the keyframe's is tested in `ReviewAppTests`. |
| D188 | Step 2 comments at the player's time, after `play`, `pause` and `seek 0:10`. Step 3 uses `--at`. | Both ways to give a comment its time are run, and each of the four player commands is run once. |
| D189 | Step 7 compares `comments`, `queue`, `batches` and `video` of `state --json` before the quit and after the open, as sorted JSON. | "Comments, threads and statuses" are those keys. The lease, the listener's presence and the player's time belong to one run of the app. |
| D190 | The script reads this build's `state --json` and `app status --json` shapes. | The contract names the commands and leaves their fields to each build (D29). A run against another build changes these filters and nothing else. |
| D191 | The script releases the lease as its last check, then quits the demo app on exit. | A test leaves nothing running. `app quit` is an operator command, so the quit takes the lease once more and the lease ends with the app. |
| D192 | `make acceptance` does not build or install. | The script tests what is installed. `make install` replaces the app and opens it, which the caller should choose. |
| D193 | The pictures in `assets/screenshots/v1-acceptance/` come from a second script, `scripts/screenshots.sh`, and are kept as the app wrote them (2720 by 1460 pixels). | The acceptance scenario's two comments are a thin picture, and `--with-banner` is not in the contract (D28). A script makes the pictures repeatable after a UI change. |
| D194 | In the scene, the comment that is selected is the last one added before its batch is sent. | No command selects a comment; `comment add` selects the new one (D52), and the selection stays when the comment is sent. So one picture cannot hold a selected sent comment and a queued comment, and the scene has two views. |

Decisions of the design and Swift reviews after v1 (the apple-design and write-swift skills, and a build on Linux):

| # | Decision | Reason |
|---|---|---|
| D204 | The app's colours are muted pastels with a light and a dark variant each, all in `Theme`. A soft slate blue, `Theme.accent`, is the app's tint, set once at `RootView`. The agent's colour is the accent, a question's a soft teal, and the agent-control sign's the amber of a working comment. Words and glyphs on a filled colour use `Theme.onTint`. | The video is the loudest thing in the window, and the system's saturated colours competed with it. One place for the palette keeps a state the same colour on a marker, a row and a notice. |
| D205 | The rail has no bordered card. Comments are full-width rows split by hairlines; the selected row is told by its fill. Each section (the queue, each batch) starts with a header band. Only thread messages and batch messages sit in shapes, as chat bubbles with no stroke. A state is its glyph and name, and presence a dot and words, with no capsule. | Boxes inside boxes made the rail busy, and a border said nothing a fill did not. The pin beside a state already carries its colour. |
| D206 | Each faint fill takes the system's contrast setting and deepens when it is increased (`selectedRow`, `sectionBand` and the bubbles). | With no borders, a fill is the only edge between two surfaces, so it must stay visible to a person who asks for more contrast. |
| D207 | The timeline lane and the rail's foot have one height, `Theme.footerHeight` (116 pt). | The stage's lower edge and the line over the send bar meet as one line across the window. |
| D208 | The banner is a sign in the toolbar (`AgentControlButton`) that opens a popover with the details and Stop, not a strip across the window. "Banner" stays the domain word: `LeaseIndicator`, `LeaseBanner` and `screenshot --with-banner` keep their names, and the flag keeps the sign in a picture. | The strip moved the stage down while an agent drove the app, so the video got bars at its sides, and its tint ran into the rail (seen in the v1 pictures). A sign in the toolbar keeps the layout still and is still in view, and its one bounce draws the eye when control starts. |
| D209 | The toolbar is one group of icon buttons: the agent-control sign, Context, Comments. The demo shows in the window's subtitle ("Demo · <folder>"), and the transcript's source and progress move into the Context popover; the Context glyph pulses while speech is transcribed. | Chips of words beside icon buttons read as a second kind of control. The transcript around each comment is part of what the agent is told, which is the popover's subject. |
| D210 | Motion follows the apple-design review: one region frame from the drag to the comment box; the box comes in from what it is about and leaves the same way; a notice slides in; the scrubber grows while held; the rail scrolls to a selection with `.smooth`. With reduce motion each becomes a fade or nothing. | Motion shows where a thing comes from and that a press took. It must never be the only way to read a change. |
| D211 | The lane's and a row's symbol buttons share `QuietButtonStyle`: hover and press feedback with no chrome at rest. VoiceOver steps the scrubber by `Shortcuts.skip` (5 s). | A plain button gave no sign that a press took. Left and Right move 5 s, so VoiceOver moves the same. |
| D212 | Work that must leave the caller's actor is a `@concurrent` function, not a `Task.detached`: `SpeechSource.transcribe`, `AppleSpeechRecognizer.transcribe`, `AppModel.contentHash(of:)`, `FrameGrabber.writeImages` and a row's thumbnail. A plain `Task` starts it. | The declaration says where the work runs, for every caller. A detached task said it at one call site, and dropped the caller's priority and task-local values. |
| D213 | State shared across threads is kept in a `Mutex` (`WorkspaceLauncher`'s `LaunchOutcome`, the command's test doubles), not in an `@unchecked Sendable` class. `ControlServer`'s `Listener` and `HangUpWatch` keep `@unchecked Sendable`, with the reason in their comments: no mutable state, and a dispatch source that is not declared `Sendable`. | The compiler then checks the data-race safety of the shared state. The two kept exceptions hold nothing that changes. |
| D214 | On a machine that is not a Mac the package is the six modules without the app: `ReviewApp`, `ReviewAppTests` and the `VideoReview` product are added `#if os(macOS)`. `AppleSpeechRecognizer`, `ContentHash` and `ImageFiles` are behind `#if canImport(…)`; `ReviewWire` imports `Glibc` in place of `Darwin`, and `Holder` reads `/proc`. `WorkspaceLauncher` there refuses with "runs only on macOS". The Application Support path test runs on macOS only. | Agents on the Linux machines can build and test the modules: 181 tests in 6 targets, 1 skipped. The app is a macOS app, so nothing tries to launch it. |
| D215 | Tests run a list of inputs with `@Test(arguments:)`, not a loop. The payload tests compare JSON numbers field by field, by type. | Each input is its own case in the report, and a failure names it. `AnyHashable` compares a number read back from JSON differently on Linux's Foundation. |
| D216 | `ReviewApp` and `ReviewAppTests` build with the default main-actor isolation of Swift 6.2 (`.defaultIsolation(MainActor.self)`). `AppRefusal`, `ControlServer.Answer`, `ControlServer.Failure`, `Listener`, `HangUpWatch` and `StateReport` are `nonisolated`. The older explicit `@MainActor` marks stay; they are now redundant. | Without the setting a type that forgets `@MainActor` is silently off the main actor. With it, the socket's code is the only code that leaves the main actor, and it says so. Its first Mac build found the listener's queue calling a main-actor `serve`. The tests share the setting, so they use the app's values as the app does. |

## 7. What is built so far

The sections above describe the whole build. This list says what the code holds today. Each ticket moves its line.

Built (the first build ticket, "Control: Play a video and drive the player through the CLI"):

- `Package.swift`, `Makefile`, `Packaging/Info.plist`.
- `ReviewWire`: every file in the tree. `ControlRequest` has the cases `appStatus`, `state`, `appOpen`, `appQuit`, `playerOpen`, `playerPlay`, `playerPause`, `playerSeek` and `screenshot`.
- `ReviewCommand`: `CommandTable`, `VideoReviewCLI`, `AppCommands`, `PlayerCommands`, `ScreenshotCommand`, `AppLauncher`. `ReviewCLI/main.swift`.
- `ReviewApp`: `VideoReviewApp`, `AppModel` (open, play, pause, seek), `Player/PlayerEngine`, `Player/PlayerSurface`, `Player/Shortcuts` (play and pause, 5 s, one frame), `Control/ControlServer`, `Control/StateReport`, `Control/Screenshotter`, `UI/RootView`, `UI/Theme`, `UI/EmptyState`, `UI/Stage/StageView`, `UI/Timeline/TimelineLane`, `UI/Rail/RailView`, `UI/Rail/SendBar`.
- Tests: `ReviewWireTests`, `ReviewCommandTests`, `ReviewAppTests` (the control server with a fake app and over the real socket, the player's keys).

Built (the lease ticket, "Control: Lease app control to one agent at a time"):

- `ReviewLease` with `ControlLease`, and `ReviewLeaseTests`.
- `ReviewWire`: the cases `controlTake` and `controlRelease`, and `withBanner` on `screenshot`.
- `ReviewCommand`: `ControlCommands`, `screenshot --with-banner`, the handover of the lease when `app open` relaunches the app.
- `ReviewApp`: the lease in `ControlServer` (the gate before every operator request, the line of waiting takes, the timer, Stop), `Control/LeaseIndicator`, `UI/LeaseBanner`, the `lease` in `state` and `app status`.
- Tests: the lease gate with the fake app and a clock, and the line of takes over the real socket, in `ReviewAppTests`; the commands and the handover in `ReviewCommandTests`.

Built (the ticket "Comment: Add a timestamped comment with its keyframe"):

- `ReviewWire`: the `ControlRequest` cases `commentAdd(text, at?)`, `commentEdit(id, text)` and `commentDelete(id)`. `ReviewCommand`: `CommentCommands` with `comment add | edit | delete`.
- `ReviewCore`: `ItemID`, `CommentState`, `Comment` (`id`, `time`, `text`, `state`), `ReviewRefusal`, `VideoReview` (`video`, `comments`, `queue`, `addComment`, `editComment`, `deleteComment`).
- `ReviewStore`: `ContentHash` and `ImageFiles` (the keyframe's place, writing, removing, a small copy). It depended on `ReviewCore` only when this ticket was built; since the transcript ticket it links `ReviewTranscript` too.
- `ReviewApp`: `ReviewDesk`, `Player/FrameGrabber` (keyframes), `AppModel` (the draft, the selection, add, edit, delete, select, marker jumps), `UI/CommentEditor`, `Stage/Composer`, `Timeline/Marker`, `Rail/CommentRow` (then `CommentCard`), the state colours and glyphs in `Theme`. `Shortcuts` has Up, Down, C and Return.
- `state --json` has `video.contentHash`, `draft`, `comments` (`id`, `time`, `text`, `state`, `keyframePath`) and `queue`.
- Tests: `ReviewCoreTests`, `ReviewStoreTests`, and in `ReviewAppTests` comments through `AppModel` on the fixture video, the keys while typing and the comment box's keys.

Built (the ticket "Comment: Comment on a drawn region of the frame"):

- `ReviewWire`: `ControlRequest.Rectangle`, and `region` on `commentAdd`. `ReviewCommand`: `comment add --region x,y,w,h`.
- `ReviewCore`: `Region` (validation, `pixels`, `text`), `Comment.region`, `ReviewRefusal.badRegion`, `region` on `VideoReview.addComment`.
- `ReviewStore`: the crop's place in `ImageFiles`.
- `ReviewApp`: `FrameGrabber.writeImages` (keyframe and crop), `PlayerEngine.videoSize`, `Stage/VideoFrameGeometry`, `Stage/RegionOverlay`, the comment box beside a region in `Stage/Composer` and `Stage/StageView`, `AppModel` (the draft's region, `clickFrame`, `beginRegion`, `endRegion`, `escape`, `shownRegion`), Escape in `Shortcuts`, the crop as a row's thumbnail.
- `state --json` has `region` and `cropPath` on a comment and `region` on the draft.
- Tests: `Region` in `ReviewCoreTests`; the request and the option in `ReviewWireTests` and `ReviewCommandTests`; in `ReviewAppTests` the server's region path, `VideoFrameGeometry` at several stage sizes, the box's placement, and region comments through `AppModel` on the fixture video (the crop against its keyframe, the same crop from the box and from the CLI's path, the drag's pause, Escape).
- Not checked by an agent: the real drag, click and Escape key. An agent cannot press the mouse; the logic behind each is tested at `AppModel` and `VideoFrameGeometry`.

Built (the ticket "Mate: Send a batch to a waiting listener"):

- `ReviewWire`: the `ControlRequest` cases `batchSend` and `wait(timeoutSeconds)`, the role `listener`, `ControlReply.timedOut`, `UnixSocket.peerClosed`. `ReviewCommand`: `batch send` in `CommentCommands`, `ListenerCommands` with `wait`, `CommandEnvironment.now`.
- `ReviewCore`: `Batch`, `BatchRef`, `Comment.batchID`, `VideoReview` (`batches`, `send`, `comments(of:)`, `isFinished`, `requeue`), `ReviewRefusal.nothingQueued`, `Outbox` with `ListenerSession` and `Presence`, `BatchPayload`.
- `ReviewApp`: `ListenerQueue`, `ReviewDesk.change(hash)` and `review(of:)`, `AppModel` (`sendBatch`, `send`, `canSend`, `sendCount`, `batches`), the listener requests, `delivered`, `silent` and the hang-up watch in `ControlServer`, Cmd+Return in `Shortcuts` and the Send Comments menu item, `Rail/SendBar` (the presence pill and the Send button), the batch groups in `Rail/RailView`, the Cmd+Return hint in `Stage/Composer`.
- `state --json` has `listener`, `batches` (`id`, `sentAt`, `commentIds`) and `batchId` on a comment.
- Tests: `Batch`, `Outbox` and `BatchPayload` in `ReviewCoreTests`; the requests and the reply in `ReviewWireTests`; `batch send` and `wait` (exit codes, connecting again, the demo's socket) in `ReviewCommandTests`; in `ReviewAppTests` the key's mapping, the pill's words, the rail's groups, and batches through `AppModel` and `ControlServer` on the fixture video (a waiting listener, no listener, the payload against the files on disk, the timeout, a newer `wait`, a new listener session, an undelivered reply, and over the real socket a delivery and a client that goes away).
- Not checked by an agent: the real Cmd+Return key press, the Send button's click and the menu item. The key's mapping is tested at `Shortcuts.action`, and what it calls at `AppModel.send`. The comment box's new hint row was not seen in a screenshot, since no command opens the box.

Built (the ticket "Mate: Send the video context once per listener session"):

- `ReviewWire`: the `ControlRequest` case `contextSet(text)`, an operator request. `ReviewCommand`: `context set <text>` in `CommentCommands`.
- `ReviewCore`: `VideoReview.note`, and `Outbox` with `contextSent`, `context(for:text:)`, `isContextDue(for:text:)` and the digest. A new listener session empties `contextSent`, and an undelivered batch forgets its video's digest.
- `ReviewApp`: `ContextReader`, the context in `ListenerQueue.payload`, `AppModel` (`setContextNote`, `saveContextNote`, `contextNote`, `sidecar`, `readSidecar`, `contextText`, `isContextDue`, `isContextShown`), the `contextSet` branch in `ControlServer`, `UI/ContextPopover` with the toolbar's Context button, and the player's keys off while the popover is open.
- `state --json` has `video.contextNote`.
- Tests: the context rule in `ReviewCoreTests` (once per session, a changed text, per video, a new session, no text, an undelivered batch, the round trip); the request in `ReviewWireTests`; `context set` in `ReviewCommandTests`; in `ReviewAppTests` the server's `context set` with the fake app and under the lease, the sidecar lookup and the joined text in a temporary folder, the popover's words, and the real payload through `AppModel` and `ControlServer` on a copy of the fixture video (first batch, next batch, a new note, a changed sidecar, a cleared note, a new listener session, an undelivered reply, a note with no sidecar, the folder's `context.md`).
- Not checked by an agent: the context popover itself. No command opens it and a `screenshot` does not hold it (D102), so its look in light and dark, the click on the Context button, typing in the note, Return, Escape, Save and Cancel were not seen. What Save calls is tested at `AppModel.saveContextNote`.

Built (the ticket "Transcript: Add the transcript window to each comment"):

- `ReviewTranscript`: every file in the tree. `Package.swift` has the target and `ReviewTranscriptTests`; `ReviewStore` and `ReviewApp` link it.
- `ReviewStore`: `TranscriptFiles`.
- `ReviewApp`: `TranscriptDesk`, `AppModel.init(environment:speech:)`, `AppModel.transcript`, the transcript closure in `ListenerQueue.payload`, `UI/TranscriptChip` (a toolbar chip then; since the toolbar review, the Context popover's transcript part).
- `Packaging/Info.plist`: `NSSpeechRecognitionUsageDescription`.
- `state --json` has `transcript`, and `state` has its line.
- Tests: `ReviewTranscriptTests` (the window, `voiceover.json` timing, `.srt` and `.vtt` parsing, the source order in temporary folders, the speech source with a recognizer the test drives); `TranscriptFiles` in `ReviewStoreTests`; in `ReviewAppTests` the payload's transcript through `AppModel` and `ControlServer` (the fixture with `voiceover.json`, a copy with only the `.srt`, a copy with no sidecar and a slow recognizer, the kept transcript after a restart, a transcription that gives up), the state report and the transcript's words (`TranscriptChip`).
- Checked outside `make test`: `AppleSpeechRecognizer` on a copy of the fixture video with no sidecar, from a command-line tool. It gave five lines in about a second, with no permission prompt.
- Checked in the installed app at integration: the chip in the window (in the v1 screenshots; it has since moved into the Context popover), and a copy of the fixture with no sidecar, which the bundled app transcribed (five lines, complete in under 10 s) with no permission prompt on this Mac. A Mac without the speech model installed was not tried.

Built (the ticket "Mate: Show agent answers and questions in the player"):

- `ReviewWire`: the `ControlRequest` cases `ack`, `status`, `reply`, `ask` and `threadAnswer`, and `ControlRequest.Status`. `ReviewCommand`: `ack`, `status`, `reply` and `ask` in `ListenerCommands`, `thread answer` in `CommentCommands`, exit 2 on any timed-out reply in `VideoReviewCLI.result`.
- `ReviewCore`: `ThreadMessage`, `Comment.thread` and `openQuestion`, `Batch.messages`, `VideoReview` (`acknowledge`, `setStatus`, `reply`, `ask`, `answer`), `CommentState.isStatus`, six more `ReviewRefusal` cases, `Outbox.openAsks` with `askOpened` and `askClosed`.
- `ReviewApp`: the listener's answers and the open `ask`s in `ListenerQueue`, `ReviewDesk.contentHash(of:)`, `Notice`, `AppModel` (`answer`, `answerQuestion`, `notices`, `unread`, `raise`, `dismiss`, `openNotice`, `agentName`), the five requests in `ControlServer` and `answer` on `AppControlling`, `Rail/ThreadView`, `Stage/Toasts`, the thread and its one-line summary in `Rail/CommentRow` (then `CommentCard`), the batch's messages in `Rail/RailView`, the state glyph and the badge on `Timeline/Marker`, `takesFocus` on `CommentEditor`, the agent's and the question's colours and `pinGlyph` in `Theme`.
- `state --json` has `thread` on a comment and `messages` on a batch.
- Tests: threads, statuses and the outbox's asks in `ReviewCoreTests`; the requests in `ReviewWireTests`; the commands, their usage and `ask`'s exit codes in `ReviewCommandTests`; in `ReviewAppTests` the listener's answers through `AppModel` and `ControlServer` on the fixture video (`ack` with and without text, each status and the return to listening, replies to a comment and to a batch, notices and unread marks, `ask` answered by `thread answer` and by the answer box's call, an `ask` that runs out and its late answer, the refusals, a video that is no longer open, and over the real socket an `ask` held until its answer and one whose client goes away), and the words of a thread heading and a notice.
- Not checked by an agent: typing in the answer box, its Return, Escape and Answer button, and a click on a notice. The answer box calls `AppModel.answerQuestion`, which calls the same `AppModel.answer` as `thread answer`; a click on a notice calls `AppModel.openNotice`. Both are tested at `AppModel`.

Built (the ticket "Mate: Ship the video-review-mate skill"):

- `.agents/skills/video-review-mate/SKILL.md`. No code changed.
- Checked by reading: every command line in the skill against `ListenerCommands.swift`, the command table and the exit codes in `VideoReviewCLI`.
- Checked live by the acceptance ticket (2026-10-05): a headless Claude Code session (`claude -p`, Opus 5.5, tools Bash, Read, Edit, Write and Skill) in a throwaway repo with the skill linked into its `.claude/skills`, against the installed app on demo data. A batch of two comments waited for it: "Add a line to NOTES.md: the intro goes too fast." and a question on a region. The first `wait` took the batch; both comments were `acknowledged` 4 s later; a new background `wait` was open 1 s after that; the first comment ended `done` with one commit and its short SHA in the reply; the question ended `done` with the narration in the reply and no commit; the batch got its closing message; the session stopped its `wait` and ended, 30 s after it started, and presence fell to `absent`. `SKILL.md` needed no change.
- Not checked: a session that asks a question (`ask` in the background), a batch that arrives while another is worked, and a second listener session that gets a batch again.

Built (the ticket "Comment: Keep comments and threads across restarts"):

- `ReviewStore`: `Library` (reviews, the outbox, the last video, the id index, the schema version).
- `ReviewCore`: `VideoInfo.frameRate`, `Outbox.reconcile(unfinished:)`, `Outbox.isKeptAs`, an `Outbox` that reads with keys missing, times cut to the millisecond in `VideoReview`.
- `ReviewTranscript`: `SpeechSource.transcript(of:)` gives the kept transcript of a video that was not prepared in this run.
- `ReviewApp`: `ReviewDesk` on the `Library` (load on first use, save with every change, a failed save refused, the index for `contentHash(of:)`), the outbox loaded and saved in `ListenerQueue`, `TranscriptDesk.lines(around:of:)` for a video of an earlier run, `AppModel.open` (the review loaded before the player changes, the frame rate, `recent.json`) and `openRecent`, `ControlServer.ready`, the launch's reopening in `AppDelegate`.
- `state --json` and the payload are unchanged.
- Tests: `LibraryTests` in `ReviewStoreTests`; the outbox's missing keys, a taken batch across a restart, `reconcile` and what is kept in `ReviewCoreTests`; `PersistenceTests` in `ReviewAppTests`, each with a second `AppModel` on the same support folder (the state before and after, nothing to reopen, a renamed copy in another folder, two support folders, a pending batch delivered with no video open, a kept speech transcript, a taken batch for the same and for a new listener, a lost outbox file, a review that does not read, a change that cannot be saved).
- Checked in the installed app, in a demo folder, through the CLI: `state --json` before `app quit` and after `app open --demo` differs only in the lease, the listener's presence and the player's time; a batch sent with no listener is taken after the restart with its keyframes, crop, transcript and context; a new listener key gets the taken batches again; a renamed copy in another folder has the same comments and batches; the normal support folder holds only `demo.json` before and after.
- Not checked by an agent: a kill of the app in the middle of a save, and a full disk, in the installed app. Both are tested at `Library` and `ReviewDesk`.

Built (the ticket "Proto: Run the v1 acceptance scenario and open the draft pull request"):

- `scripts/acceptance.sh` and the `acceptance` target of the `Makefile`. `scripts/screenshots.sh` and the six pictures in `assets/screenshots/v1-acceptance/`. No Swift code changed.
- Checked in the installed app after `make install`: `make acceptance` passes all eight steps (62 checks). With a stand-in command that answers `"demo": false`, the script stops after `app open --demo` and `app status --json` with exit 3. A check that fails ends its step with `FAIL` and the run with exit 1.
- Seen in the pictures and left as it is: the first batch of the scene is below the rail's fold in every view, so its replies are not in a picture (its markers are). The window is not the key window while an agent drives it, so its three title bar buttons are grey, the toolbar's two buttons have a grey disc in light, and the transcript chip is dim in dark. With the lease banner the stage is lower, so the video has bars at its sides, and the bars are a deeper black than the video's own background. The banner's tint runs on into the top of the rail. The toolbar review replaced the strip with a sign in the toolbar (D208), so these pictures are out of date.
- Not checked by an agent, as before: every real key press, click and drag, and the context popover.

Built (the design and Swift reviews after v1):

- The palette, the fills and the measures in `UI/Theme` (D204, D206, D207). `Rail/CommentRow` in place of `Rail/CommentCard`, the sections in `Rail/RailView`, the bubbles in `Rail/ThreadView`, the dot and words in `Rail/SendBar` (D205).
- `AgentControlButton` and `AgentControlPopover` in `UI/LeaseBanner` in place of `LeaseBannerView`; one toolbar group and the demo subtitle in `UI/RootView`; the transcript part and the pulse in `UI/ContextPopover`; `TranscriptChip` keeps only its words (D208, D209).
- `UI/QuietButtonStyle`, the region frame in `Stage/RegionOverlay`, the box's arrival in `Stage/StageView`, the notices' fade in `Stage/Toasts`, the held scrubber and its VoiceOver steps in `Timeline/TimelineLane` (D210, D211).
- `@concurrent` functions in place of `Task.detached`, `Mutex` in place of `@unchecked Sendable`, `Outbox.reconcile` in one pass, `CommentEditor`'s focus from a main-actor task, `@Test(arguments:)` (D212, D213, D215). Default main-actor isolation for the app and its tests (D216).
- The package on Linux (D214). `AGENTS.md` says which tests run off the Mac.
- Checked: `swift test` on Linux, 181 tests in 6 targets, 1 skipped.
- Checked on the Mac: `make test`, 320 tests in 39 suites. The UI compiled as written.

Not built yet: nothing of the v1 tickets.
