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
| 2, 4, 6 comments, queue, markers | ReviewCore `VideoReview`, ReviewStore `ContentHash`, `ImageFiles`, ReviewApp `ReviewDesk`, `FrameGrabber`, `Stage/Composer`, `Timeline/Marker`, `Rail/CommentCard` | #5 |
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
ReviewCommand     ← ReviewWire, ReviewLease, AppKit for the launcher only
ReviewCLI         ← ReviewCommand

ReviewCore        ← Foundation only
ReviewTranscript  ← Foundation, Synchronization; AVFoundation and Speech in `AppleSpeechRecognizer` only
ReviewStore       ← ReviewCore, ReviewTranscript, CryptoKit
ReviewApp         ← all of the above, SwiftUI, AVKit, ScreenCaptureKit
```

`ReviewCore` does not import `ReviewWire`: the server turns a request into a call and a result into a line. `ReviewCommand` does not import `ReviewCore`: the payload and the state report cross the socket as text in `output`.

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
Package.swift                      targets below; platforms: macOS 26; no dependencies
Makefile                           test, build, bundle, install, clean; reads VARIANT and VERSION from ReviewWire
Packaging/Info.plist               the bundle's template; speech recognition usage text
scripts/acceptance.sh              the v1 acceptance scenario, CLI only (#13)
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
    UnixSocket.swift               POSIX calls: the address (through a short link for a long path), connect, bind, write all, half-close, read to end
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
    AppLauncher.swift              starts the app through Launch Services; the AppLaunching seam for tests
  ReviewCLI/
    main.swift                     exit(VideoReviewCLI.run(...))
  ReviewCore/
    Comment.swift                  Comment, Region (validation), ThreadMessage
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
    Library.swift                  the support folder's layout; load and save reviews, the outbox, transcripts; the id index
    ContentHash.swift              SHA-256 of the file, streamed
    ImageFiles.swift               where keyframes and crops are, writing and removing a PNG, a small copy for a card
    TranscriptFiles.swift          where a video's finished speech transcript is kept: load and save
  ReviewApp/
    VideoReviewApp.swift           @main; the one window; the menu commands
    AppModel.swift                 the orchestrator; every action a person or an operator can take
    ReviewDesk.swift               change a review, save it, publish it
    ListenerQueue.swift            open waits and asks; delivery; payload assembly; presence
    ContextReader.swift            the sidecar context file plus the note
    TranscriptDesk.swift           the videos opened in this run; a comment's lines and the transcript's report, asked of the sources
    Player/
      PlayerEngine.swift           AVPlayer: open, play, pause, exact seek, time
      PlayerSurface.swift          AVPlayerView without controls, as a SwiftUI view
      FrameGrabber.swift           keyframe and crop PNGs from the asset, at the exact time
      Shortcuts.swift              the player's keys, off while a text field has the focus
    Control/
      ControlServer.swift          the socket, the lease, held requests, dispatch
      LeaseIndicator.swift         the lease as the banner draws it; hidden while a screenshot leaves it out
      StateReport.swift            `state` and `app status` as JSON and as lines
      Screenshotter.swift          the app window through ScreenCaptureKit, in an appearance
    UI/
      RootView.swift               banner, stage, timeline, rail
      Theme.swift                  one place for the status colours and glyphs
      LeaseBanner.swift            who controls the app, and Stop: the banner's words (pure) and its view
      EmptyState.swift             no video open
      ContextPopover.swift         the sidecar text and the editable note
      TranscriptChip.swift         the toolbar chip: the transcript's source and progress; its words (pure) and its view
      CommentEditor.swift          the text view a comment is written in (the composer and a card being edited), and its keys
      Stage/StageView.swift        the video with the overlay, the composer and the notices
      Stage/RegionOverlay.swift    draw a rectangle; show a comment's region
      Stage/VideoFrameGeometry.swift  view points to normalized frame coordinates and back (pure)
      Stage/Composer.swift         the comment box, and where it sits on the stage (pure)
      Stage/Toasts.swift           the brief notices
      Timeline/TimelineLane.swift  play button, time, scrubber, the Comment button
      Timeline/Marker.swift        one marker's pin (number, state, unread badge), and the layer of pins above the track
      Rail/RailView.swift          the queue, then each batch
      Rail/CommentCard.swift       thumbnail, time, text, status, edit and delete
      Rail/ThreadView.swift        the messages and the answer box
      Rail/SendBar.swift           presence pill and the Send button

Tests/
  ReviewWireTests/                 version refusal, message round trips, time codes, the demo pointer, Holder.find
  ReviewLeaseTests/                time-driven tables
  ReviewCommandTests/              parsing, the request sent, output and exit codes, with a fake transport and launcher
  ReviewCoreTests/                 the state machine, batch assembly, the outbox
  ReviewTranscriptTests/           the window cut, the source order, voiceover timing, srt and vtt parsing (reads fixtures/sample), speech with a recognizer the test drives
  ReviewStoreTests/                round trips in a temp folder, the content hash of a renamed copy, the kept transcript
  ReviewAppTests/                  ControlServer with a fake app, the lease gate and the line of takes over the real socket, the keys, comments and batches through AppModel on the fixture video, the listener queue behind the server, VideoFrameGeometry, the transcript window in the payload (voiceover, srt only, slow speech)
```

A module and a type never share a name, so a type can always be qualified by its module.

### ReviewWire

`ControlRequest` is one enum, one case per command of the spec's contract:

| Role | Cases | Lease |
|---|---|---|
| free | `appStatus`, `state`, `controlTake(waitSeconds?)`, `controlRelease` | none |
| operator | `appOpen`, `appQuit`, `playerOpen(path)`, `playerPlay`, `playerPause`, `playerSeek(seconds)`, `commentAdd(text, at?, region?)`, `commentEdit(id, text)`, `commentDelete(id)`, `batchSend`, `threadAnswer(commentID, text)`, `contextSet(text)`, `screenshot(path, appearance?, withBanner)` | takes or renews |
| listener | `wait(timeout?)`, `ack(batchID, text?)`, `status(commentID, state)`, `reply(id, text)`, `ask(commentID, question, waitSeconds?)` | none |

- `role` and `holdSeconds` (how long the app may keep the connection: a `take`'s wait, a `wait`'s timeout, an `ask`'s wait, or no limit) are computed properties on the request, so the server and the client agree without a table. A `take` waits 3600 s at most (`ControlRequest.longestWait`); the command and `decode` both refuse more. A `wait --timeout` is 0 to 86400 s (`ControlRequest.longestListen`); without the option it has no limit.
- `ControlReply` is `{ok, output, error, lease?, timedOut?}`. `timedOut` is true only in the reply to a held request whose time ran out with nothing to say (`ControlReply.ranOut`); the command exits 2 on it and prints nothing.
- `UnixSocket.peerClosed(descriptor)` says whether the peer closed its socket, by `poll` for writing: a hang-up shows there only once the peer is gone, not when it half-closed after its request.
- `commentAdd`'s region is a `ControlRequest.Rectangle`: the four numbers of `--region x,y,w,h` as they were written, as the object `{"x", "y", "w", "h"}` on the wire. `Rectangle(text)` reads four numbers with commas between them and nothing else; the command refuses any other text as wrong usage (exit 64). Whether the numbers are a region of the frame is the app's rule (`Region.init` in `ReviewCore`, which `ReviewWire` does not link): the server makes the `Region` before it calls the app, and refuses with exit 1.
- On the wire a message is one JSON object: `version`, `command` (`player.seek`), `holder` (`key`, `name`, `place`), `json` (the caller passed `--json`) and the command's own fields. Protocol version 1.
- `ControlMessage.decode` refuses in this order: not JSON, another version (naming both), no holder, unknown command, a missing or invalid field.
- `Holder.find(variables, workingDirectory, processes)`: the key is `VIDEO_REVIEW_CONTROL_KEY` when set, else `CLAUDE_CODE_SESSION_ID`, else the nearest ancestor process that is not a shell, as `process:<pid>@<start>`. The name is `Claude Code` or the process name. The place is the Herdr pane when there is one, else the working folder. The process table is a protocol with the system's `sysctl` reader and a fake.
- `ControlClient.send(request)` writes the message, half-closes, reads to the end. Its read timeout is 15 s plus `holdSeconds`, or none when the request has no limit. A connection that closes with no reply reads as an app that is not running.
- `UnixSocket.address(path)`: a socket address holds 103 bytes. A longer path (a demo folder deep in a worktree) is reached through a symbolic link to its folder, in the user's temporary folder (`confstr(_CS_DARWIN_USER_TEMP_DIR)`), named after a hash of the folder's path. The app and the CLI each make the same link, so neither tells the other.
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
- `--json` is taken from anywhere on the command line. An action then prints the parts of the state it changed (`player seek` prints `{"player": {…}}`, `player open` adds `video`, `screenshot` prints `{"path": …}`). `app status --json` prints `{"running": false}` when the app is not running.
- `wait [--timeout <seconds>]` (`ListenerCommands.wait`) prints the payload as JSON with or without `--json`. It connects again while the app is not running or quits, once a second, until its timeout, and looks for the socket again each time (the app may come back on a demo's data). A listener can start before the app. Each request asks only for the time that is left, counted by the environment's clock (`CommandEnvironment.now`, which tests replace). Exit 0 with the batch, 2 when the time ran out (nothing printed), 1 when the app refuses (a newer `wait` took its place).
- `batch send` prints `b-5d0c2a91 sent with 2 comments, taken by the listener`, or `…, waiting for a listener`. With `--json` it prints `{"batch": {"id", "sentAt", "commentIds"}}`.
- `context set <text>` takes one word of text and prints `context note set (14 characters)`. An empty text clears the note and prints `context note cleared`. With `--json` it prints `{"video": {…}}` with the new `contextNote`.

### ReviewCore

```swift
public struct VideoReview: Codable, Equatable {       // one video's review
    public var video: VideoInfo                        // contentHash, title, duration, path (last seen)
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
    mutating func acknowledge(_ batchID:, text:, messageID:, at now:) throws(ReviewRefusal)   // sent → acknowledged; text is a batch message
    mutating func setStatus(_ commentID:, _ state:) throws(ReviewRefusal)        // working | done | failed, forward only
    mutating func reply(to id:, text:, messageID:, at now:) throws(ReviewRefusal)   // a comment's thread or a batch's messages
    mutating func ask(_ commentID:, question:, messageID:, at now:) throws(ReviewRefusal)   // refused while a question is open
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
- `ReviewRefusal` is `emptyText`, `unknownComment(id)`, `notQueued(id, state)`, `badRegion(x, y, w, h)` or `nothingQueued` so far, each with its `line`.

`Outbox` is the listener's side as a pure value, given the time on each call, like the lease:

```swift
public struct Outbox: Codable, Equatable {
    private(set) var pending: [BatchRef]    // sent, not yet delivered; first in, first out. BatchRef = batch id + content hash
    private(set) var taken: [BatchRef]      // delivered, not finished
    private(set) var session: ListenerSession?   // holder key, name, place of the last `wait`
    private(set) var isWaitOpen: Bool       // one run only, not on disk
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
    func presence(at now:) -> Presence                               // listening | working | absent
}
```

`ListenerSession` is the holder's `key`, `name` and `place` as `ReviewCore`'s own type, since `ReviewCore` does not link `ReviewWire`. `Codable` keeps `pending`, `taken`, `session` and `contextSent`; an outbox read from disk has no open `wait`.

The context rule: `context(for:text:)` gives the text on a session's first batch of a video and whenever the text's digest differs from the one the session last got, and `nil` otherwise. With no text it gives `nil` and keeps the digest, so a sidecar that goes and comes back unchanged is not sent again. The digest (`Outbox.digest`) is the text's length in bytes and its 64-bit FNV-1a hash, the same in every run of the app. `VideoReview` reads a review with no `note` key as an empty note.

Presence: `working` when the session has a taken batch and is alive; `listening` when it is alive and nothing is taken; `absent` otherwise. Alive means a `wait` is open (or an `ask`, once there is one), or the last listener command or the close of its `wait` was less than 120 s ago while a batch is taken (`Outbox.workingGrace`), or less than 5 s ago otherwise (`Outbox.listeningGrace`, so a listener that runs `wait` in a loop does not flicker).

`BatchPayload` is the Codable shape of the spec, and `BatchPayload.assemble(review, batch, context, transcript:, images:)` builds it. The two closures give each comment its transcript lines (`BatchPayload.Line`: `start`, `end`, `text`) and its image paths (`BatchPayload.Images`), so `ReviewCore` needs neither `ReviewTranscript` nor `ReviewStore`. The payload carries the batch's comments that are not finished, so a batch delivered again holds only what is left. `video.duration` is rounded to the millisecond, as in `state`. `json` prints it with sorted keys, `null` for every key with no value and the time as ISO 8601.

```json
{
  "batch":   { "id": "b-5d0c2a91", "sentAt": "2026-10-04T19:02:11Z" },
  "video":   { "path": "/abs/sample.mp4", "contentHash": "<64 hex>", "duration": 21.233, "title": "sample" },
  "context": "…the sidecar text…\n\n## Note from the reviewer\n\n…the note…",
  "comments": [
    { "id": "c-7f3a9c2e", "time": 10.0, "text": "…", "keyframePath": "/abs/…/frames/c-7f3a9c2e.png",
      "region": null, "cropPath": null,
      "transcript": [ { "start": 6.067, "end": 14.333, "text": "Your comments queue up. …" } ] },
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

- `VideoFile` is the file URL, the content hash (the key a source keeps its work under), the frame rate and the duration. `Transcript` is what is known of a video's transcript now: `source` (`voiceover`, `subtitles` or `speech`), `lines` in time order, `complete`, and `problem` (why the source gave up, else nil). `TranscriptLine` is `start`, `end`, `text`, with the times to the millisecond in every source.
- A source answers at once with what it has and never makes its caller wait. This is how a comment sent before the transcript is ready gets the lines that exist then.
- `TranscriptSources` holds the sources in order and is a `Transcriber` itself: `pick(for:)` is the first source whose `transcript(of:)` is not nil, and `prepare` starts only that one. `TranscriptSources.standard(speech:)` is the spec's order: `VoiceoverSource`, `SubtitleSource`, then the speech source, which serves every video. The interface has three implementations today, which is why it is an interface; the transcription research replaces or adds a source behind it.
- `VoiceoverSource`: `<base>.voiceover.json`, else `voiceover.json`, in the video's folder. A scene lasts `ceil((durationSeconds + paddingSeconds) × fps)` frames and starts where the previous one ends. One line per scene; a scene with no text takes its time and gives no line. The file is read each time it is asked. A file that does not read as a voiceover leaves the video to the next source.
- `SubtitleSource`: `<base>.srt`, else `<base>.vtt`. `parse` reads both formats the same way: blocks with a blank line between them, and a cue is the block with a `start --> end` line; what is above that line is dropped, the rows under it are joined with a space, and markup (`<i>`, `<v Name>`, `{\an8}`) is removed. Times are `HH:MM:SS,mmm`, `HH:MM:SS.mmm` or `MM:SS.mmm`. A file with no cue leaves the video to the next source.
- `TranscriptWindow.range(around: time, duration:)` is `time − 15 … time + 15`, kept inside the video. `cut(lines, to: window)` keeps every line that overlaps the window, whole; a line that only touches the window's edge is out.
- `SpeechSource` holds each video's speech transcript by content hash, behind a lock. `prepare` starts a background task once per video: it takes the finished transcript from its `Cache` when there is one, else it reads lines from its `SpeechRecognizing` one at a time, appends each, then marks the transcript complete and saves it to the cache. A recognizer that throws leaves the lines it gave and sets `problem`; the video's next opening starts over. Its `Cache` is two closures, load and save, so `ReviewTranscript` does not link `ReviewStore`.
- `SpeechRecognizing` is the seam under the speech source: `lines(of: file)` is a stream of lines that ends when the file is done. `AppleSpeechRecognizer` is the real one: a `SpeechTranscriber` for the Mac's language (the nearest supported locale, else `en-US`) with audio time ranges, its model installed through `AssetInventory` when it is missing, and a `SpeechAnalyzer` that reads the video file with `AVAudioFile`. Each finalized result is one line with that result's time range. A video with no sound track is done with no lines. The tests give a recognizer they drive.

### ReviewStore

```text
<support>/                               ~/Library/Application Support/Video Review (proto-2)/, or the demo folder
  control.sock                           while the app runs
  demo.json                              the demo pointer; only in the normal folder
  outbox.json                            the Outbox
  recent.json                            the path of the last open video
  videos/<contentHash>/
    review.json                          one VideoReview, with schemaVersion
    transcript.json                      the finished speech transcript: source, lines, complete
    frames/<comment-id>.png              the keyframe, at the video's own size
    crops/<comment-id>.png               the region's crop
```

- `Library(support:)` reads every `review.json` once at launch into an index from comment and batch ids to content hashes, so `status c-…` finds its video without the video being open.
- `load(hash)`, `save(review)`, `loadOutbox()`, `save(outbox)`. Every save writes the whole file atomically. The files are small.
- `TranscriptFiles(support:)` keeps a video's speech transcript: `file(of: hash)`, `load(hash)` and `save(transcript, contentHash:)`, written atomically. Only a complete transcript is written, so a video is transcribed once. A file that does not read is no transcript.
- `ContentHash.of(url)` is the SHA-256 of the whole file, read in 4 MiB chunks off the main actor. A renamed or moved copy has the same hash, so it opens the same folder; `review.json` then records the new path.
- Demo and real data never mix: the `Library` only ever sees the support folder it was given.

### ReviewApp

`AppModel` (`@MainActor @Observable`) is the orchestrator. Its methods are the product's actions; the UI and the `ControlServer` call the same ones:

| Method | Rules it owns | Refuses |
|---|---|---|
| `open(url)` | hash, load the review, pick the transcript source, read the context, remember as recent | a file AVPlayer cannot play |
| `play()`, `pause()`, `seek(seconds)` | seek is exact and keeps play or pause | no video; a time outside the video |
| `startDraft(region?)`, `commitDraft()`, `cancelDraft()` | starting a draft pauses and fixes the comment's time; commit writes the keyframe and crop, then queues the comment and selects it. A commit that fails opens the box again with its words. With a region while the box is open, the box takes the new region and the time of the frame on screen, and keeps its words | empty text (the box stays open) |
| `clickFrame()`, `beginRegion()`, `endRegion(region?)`, `escape()` | the mouse on the frame. A click plays or pauses, and does nothing while the box is open. A drag's start pauses and sets `isDrawingRegion`. Its end opens the box on the region; a nil region (too small) and a drag that Escape cancelled open nothing. Escape drops the rectangle being drawn, else the open box with its region | |
| `addComment(text, at?, region?)` | the CLI's path: pause, seek to `at`, then the same as commit. It answers once the keyframe and the crop are on disk | no video; empty text; bad time or region |
| `editComment`, `deleteComment` | through `ReviewDesk`; delete removes the keyframe file, the crop file and the selection | not queued; unknown id |
| `shownRegion` (read) | the region to draw on the frame: the draft's, else the selected comment's while the player is paused within half a frame of that comment's time | |
| `select(id)`, `jumpToMarker(forward)` | a click on a marker or a card, and Up and Down: select, pause, seek to the comment's time | |
| `sendBatch()` | waits for a comment the box is still queueing, queues a draft with text, sends, hands the batch to `ListenerQueue`. `batch send` calls it; Cmd+Return, the Send button and the menu item call `send()`, which calls it and does nothing when `canSend` is false or a send is under way | empty queue |
| `answer(commentID, text)` | through `ReviewDesk`, then tells `ListenerQueue` | no open question |
| `setContextNote(text)` | the note is kept on the review without the space around it; an empty text clears it. `context set` calls it, and the popover's Save calls `saveContextNote`, which calls it and closes the popover | no video |

- `ReviewDesk.change(hash) { review in … }` is the one path for every change to a `VideoReview`: it takes the open review from memory or loads another video's from the `Library`, runs the change, saves, and publishes when the review is the open one. A thrown `ReviewRefusal` changes nothing. `change { … }` with no hash changes the open review. `review(of: hash)` reads a review, open or not.
- `PlayerEngine` wraps `AVPlayer`. `seek` uses zero tolerance and returns when the seek has finished, so `state` reports the time that was asked for. The duration is the video track's own length (21.233 s for the fixture), not the container's, whose sound track can run a few milliseconds longer. A file that does not play is refused, and the video that was open stays open.
- `PlayerSurface` is an `AVPlayerView` with no controls that takes no click and no key (`hitTest` gives nil). The stage's own layer above it takes the mouse.
- `Shortcuts` is one local key monitor. It maps a key to an action in a pure function, `action(keyCode:modifiers:isTyping:)`, which gives no action while a text view has the focus (`isTyping`), but for Cmd+Return (and Cmd+Enter on the keypad), which is `send` from anywhere. The Playback menu has the same actions with no key equivalents, since a menu key with no modifier would take the key from a text field; its Send Comments item shows Cmd+Return. The monitor sees the key first, and both call `AppModel.send`.
- `CommentEditor` is the one text view comments are written in: a standard `NSTextView` that takes the focus when it appears. Its pure function `keyAction(for:shift:)` maps the text view's commands: `insertNewline` commits, with Shift it makes a new line, `cancelOperation` cancels, and every other command stays the text view's.
- A comment's time is the player's time raised to the next millisecond (`AppModel.commentTime`), never rounded down: a frame rarely starts on a whole millisecond, and a time before the frame's start names the frame before it. `comment add --at` keeps the time it was given.
- `FrameGrabber` makes the keyframe with `AVAssetImageGenerator` at the exact time, from the asset and not from the window. The crop is the keyframe cut by the region. The UI and the CLI therefore produce the same pixels at any window size. A time at the video's very end is asked inside the last frame. The keyframe and the crop are written before the comment enters the review (`FrameGrabber.writeImages`), so a comment never exists without its pictures; when either cannot be written, neither file is left and the comment is refused. The crop is `Region.pixels` of the keyframe image in memory, so it is exactly that part of the keyframe PNG.
- `VideoFrameGeometry(stage:video:)` is the pure way between the stage's points and a region: `frame` is the picture fitted whole and centred in the stage (the size comes from `PlayerEngine.videoSize`, the track's size after its transform), `rect(of: region)` is where a region is on the stage, and `region(from:to:)` is the region a drag draws, in any direction, clamped to the picture, with four decimals, or nil under 8 pt either way. `isDrag(from:to:)` tells a drag from a click at 4 pt. A region is kept as fractions of the frame, so nothing is stored that depends on the window's size.
- `RegionOverlay` is the layer above the picture that takes the mouse: one drag gesture with no minimum distance, which calls `clickFrame`, `beginRegion` and `endRegion`. It draws the rectangle being drawn, the draft's region, and the selected comment's region with the comment's pin on its corner: the rest of the picture is dimmed and the rectangle is outlined in the accent colour.
- `Composer.placement(beside:box:stage:)` is where the comment box sits for a region, as a pure function: right of the rectangle, else left, else below, else above, else the stage's lower right corner, always 12 pt inside the stage. `StageView` measures the box and passes its size.
- `ListenerQueue` (`@Observable`, owned by `AppModel`) holds the `Outbox`, the one open `wait` (a continuation, with its timeout and the id of its connection) and the open `ask`s by comment id. `wait(by:timeout:connection:)` ends as an `Outcome`: `batch(ref, payload)`, `ranOut`, `replaced` or `gone`. It assembles the payload when a `wait` takes a batch; a batch in line with nothing left to deliver (no review in this run, or every comment finished) is discarded. `connectionClosed(id)` ends the `wait` held on that connection, `undelivered(ref)` puts a batch back, `stop()` ends the open `wait` with no reply. `report(at:)` is the `listener` of `state`. `ack`, `status`, `reply` and `ask` go through `ReviewDesk.change` and raise a notice.
- `ContextReader` is the context as the listener is told it. `sidecar(beside: video)` is the first of `<video base name>.context.md` and `context.md` in the video's folder that is a file and reads as UTF-8, with its text trimmed; a blank file of the video's own name still serves, so a video can opt out of its folder's `context.md`. `text(sidecar:note:)` joins the sidecar's text and the note under the heading `## Note from the reviewer` (pure), and is `nil` when both are empty. `text(for: review)` reads the sidecar beside the path the video was last opened at. `ListenerQueue.payload` calls it when a `wait` takes a batch and passes the result through `Outbox.context(for:text:)`, so nothing watches the file. `AppModel` keeps the open video's `sidecar` for the popover (read when the video opens and when the popover opens), and `contextText` and `isContextDue` for its words.
- `ContextPopover` (`UI/ContextPopover.swift`) holds the toolbar's `ContextButton`, the popover and its words as a pure struct, `ContextWords` (where the sidecar's text comes from, and when the agent gets the context). The note is written in `CommentField`, the comment box's text view. While the popover is open (`AppModel.isContextShown`) the player's keys are off, Cmd+Return too.
- `TranscriptDesk` (owned by `AppModel`, given to the `ListenerQueue`) is the app's way to the transcripts. `opened(video)` remembers the `VideoFile` by content hash (the frame rate comes from the player) and calls `prepare` on the sources. `lines(around: time, of: hash)` is the window's lines as `BatchPayload.Line`, read when it is asked. `report(of: hash)` is the `transcript` of `state`. A video that was not opened in this run has no lines. `AppModel.init(environment:speech:)` takes the recognizer, so the tests give a slow one.
- `ControlServer` listens on `control.sock` (mode 0600), reads each request off the main actor and answers on it. It owns the one `ControlLease`, takes the time from a closure the tests replace, and starts from the lease a relaunch handed over. It asks `ControlLease.use` before any operator request, holds a queued `take`, a `wait` and an `ask` as suspended continuations while it answers other requests, and settles the lease on a timer at `nextEnd`. Every change to the lease goes through one place (`leaseChanged`): it copies the lease to the `LeaseIndicator`, answers the waiting takes of the holder that got it, and sets the timer again. A `take`'s reply that grants the lease and cannot be written releases it (`undelivered`). `stopLease()` is the banner's Stop. `app status` and `state` get their `lease` from the server, not from `AppModel`, and `state` gets its `listener` from the `ListenerQueue` the server is given. It depends on a small protocol, `AppControlling`, which `AppModel` implements and the server's tests fake. An `Answer` is the reply plus what only the client would know: the lease a `take` granted (`granted`) and the batch a `wait` carried (`delivered`). When the reply cannot be written, `undelivered` releases the one and puts the other back in line. A `silent` answer writes nothing and closes the connection, which is how an open `wait` ends when the app quits. Each connection has an id. While its answer is awaited, the socket's side looks at it every 0.5 s (`HangUpWatch`, `UnixSocket.peerClosed`) and tells the server once when the client closed its socket (`connectionClosed`), so a `wait` whose command was stopped is no listener.
- `LeaseIndicator` (`@Observable`) is the lease as the banner draws it. `shown(at:)` is the lease's `Status`, or nil while it is free or while a screenshot leaves the banner out. `LeaseBanner` makes the banner's words from that status in a pure struct, and `LeaseBannerView` draws them with Stop and redraws each second.
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

  `comments` and `queue` are in time order. `video` is `null` with no video open. `lease` is `null` while the lease is free. `app status --json` has the same `lease`; as lines, both commands print `lease: held by Claude Code in /abs/repo, 48s left, 0 waiting` or `lease: free`. An open comment box is `"draft": { "time": 8.0, "text": "…", "region": null }`, with the region when the person drew one. A comment's `region` is `{ "x", "y", "w", "h" }` or `null`, and its `cropPath` is the crop's absolute path or `null`. `listener.session` is the name of the agent of the last `wait`, or `null` before the first one; `pendingBatches` counts the batches no `wait` took yet and `takenBatches` those a `wait` took that are not finished. As a line, `state` prints `listener: working (Claude Code), 0 batches waiting, 1 taken`. `transcript` is `null` with no video open. Its `source` is `voiceover`, `subtitles` or `speech`; `lines` counts the lines there are now; `complete` is false while speech is being transcribed and when that gave up, and `problem` then says why. As a line, `state` prints `transcript: voiceover, 3 lines, complete`, `transcript: speech, 2 lines, transcribing`, `transcript: speech, 0 lines, stopped: <why>` or `transcript: none`.
- What the comment commands print: `comment add` prints `c-7f3a9c2e queued at 0:10`, and with a region `c-1b44e0d7 queued at 0:12.5 on the region 0.25,0.2,0.3,0.25`, `comment edit` prints `c-7f3a9c2e edited`, `comment delete` prints `c-7f3a9c2e deleted`. With `--json`, add and edit print `{"comment": {…}}` in the shape above, and delete prints `{"deleted": "c-7f3a9c2e"}`. `state` without `--json` lists each comment on a line: id, time, `region x,y,w,h` when it has one, state, text.
- `Screenshotter` captures the app's own window with ScreenCaptureKit, from this process's shareable content only, which needs no Screen Recording permission. For `--appearance` it sets the app's appearance, waits for the window to redraw, captures and restores. Captures take turns, so two of them never mix their appearances. It makes the PNG's folder when it is missing. The lease banner is hidden for the capture, since the holder would be in every picture; `--with-banner` keeps it in, which is how an agent proves the banner shows. Every capture first gives the window 400 ms to redraw, since the banner has just gone, or has just come when the capture's own request took the lease.
- The app has one `Window` scene. Closing the window quits the app. A second copy started on the same support folder finds the socket taken and quits.

### The UX of this prototype

The idea: **the video is the stage, the timeline carries the markers, and a rail at the side carries the conversation.** The person watches on the left and reads answers on the right, and never leaves the window. Each choice and its reason:

| # | Choice | Reason |
|---|---|---|
| 1 | One window, one video at a time. Opening another video replaces the open one. | The CLI commands name no window, and there is one queue and one listener. |
| 2 | Three parts: the stage (video) on the left, the timeline lane under it, the rail (340 pt, can collapse) on the right. The rail is the system's inspector column, with a toolbar button that hides it. The stage is a black card with round corners. The lane has a ruler of times under the track. The default window (1360 by 730 pt) shows a 16:9 video with no letterbox. | Answers stay next to the feedback and stay visible while the video plays. One screenshot shows markers, a region and a thread. The inspector resizes and collapses as the Mac's other apps do. |
| 3 | The app's own player surface (`AVPlayerView` with no built-in controls) and its own timeline lane, always visible. | The stock controls cannot carry markers, and they take the mouse drags the region overlay needs. Markers are the core of the app, so the lane never hides. |
| 4 | QuickTime keys: Space or K plays and pauses, Left and Right move 5 s, Shift+Left and Shift+Right move one frame, Up and Down jump to the previous and next marker. A click on the frame plays or pauses. | Playback should feel like QuickTime. Frame steps matter for pointing at an exact frame. |
| 5 | C or Return starts a comment at the current time and pauses. A Comment button at the right of the lane does the same. No automatic focus on pause. | One key from watching to typing, and Space still resumes. The button makes the key discoverable. Typing never reaches the player: the shortcuts are off while a text field has the focus. |
| 6 | Dragging on the frame draws a rectangle at any time, with no drawing mode. The drag pauses the video. The picture outside the rectangle is dimmed. Releasing opens the comment box. Escape cancels, during the drag and in the box. A press that moves under 4 pt is a click; a rectangle under 8 pt either way opens nothing. A drag while the box is open moves the region and keeps the words. The empty rail says that a drag comments on a part of the frame. | It works like Cmd+Shift+4: point first, no tool to pick. A slip of the hand must not open a box. Pointing again is a correction, not a new comment. |
| 7 | The comment box floats on the stage: beside the rectangle for a region comment (right, else left, else below, else above, always inside the stage, with no notch and the heading "Comment on this region at"), above the playhead for a time comment, at the foot of the stage, with a notch that points at the playhead. The box is a solid surface, not a material. While it is open, a click on the frame does not play. | The person writes where they point. A material over a video takes the picture's colours and its words stop being readable. The comment is about the frame on screen, so the frame stays. |
| 8 | In the comment box, Return queues the comment, Shift+Return makes a new line, Escape cancels, Cmd+Return queues and sends everything. The box is a standard text view that takes the focus when it opens. The hints under the box name Return, Cmd+Return and Escape. | Fast entry with one hand on the keyboard. A standard focused text view is all Wispr Flow needs to dictate into. The row has room for three hints, and Shift+Return is a habit. |
| 9 | Cmd+Return anywhere sends the queue, also while a text view has the focus. A draft with text is queued first, and so is a comment whose keyframe is still being written. With nothing to send the key does nothing. The Playback menu has Send Comments with the same key. | One keystroke delivers all feedback, with nothing left behind in the box. A key that has nothing to do must not raise an alert. |
| 10 | Markers are numbered pins on the timeline, numbered in time order. Colour and glyph show the state: hollow for queued, grey for sent, blue check for acknowledged, amber pulse for working, green check for done, red cross for failed. A dot marks an unread agent message; a question mark marks an open question. A pin stands above the track on a stem. The selected pin has a ring and a halo in the accent colour. The same pin heads the comment's card. The band the pins stand in is always there. | The state reads at a glance, and never by colour alone. The number ties a pin to its card. The selection never changes a state's colour. The first comment does not move the lane. |
| 11 | A click on a marker or a card seeks to its time, pauses, selects it and shows its region on the frame, with the comment's pin on the rectangle's corner. The region goes when the video plays or moves to another frame. | One gesture gives the full context back. A rectangle over another frame would point at the wrong thing. |
| 12 | The rail groups by batch: "Queue" on top, then each batch, newest first, with a header ("Sent at 00:13" with a two-digit hour, then "2 comments", or progress such as "2 of 3 done" once a comment is finished, and "waiting for an agent" with a clock while no `wait` took the batch) and the batch's own messages under the header. Comments are in time order inside a group, numbered as their markers are. The Queue group stays when it is empty, with one line that says how to comment. | The batch is the unit that is sent and answered, so the batch message has a natural home and the progress of a batch is visible. A sent time must not read as a time in the video. |
| 13 | A card shows a thumbnail (the crop, else the keyframe), the time, a small dashed rectangle when the comment is on a region, the text and a status chip. Its thread is inline under it, open for the selected card and for any card with an open question. The answer box sits under the question. | The thread is part of the comment, not a second screen. A question must not hide. |
| 14 | Edit and delete show on queued cards only. Edit turns the card's text into the same text view as the comment box, with Save and Cancel (Return and Escape). Delete acts at once. A new comment is selected, and the rail scrolls to the selected card. | Only a queued comment can change, so the controls do not appear where they would be refused. A queued comment is cheap to write again, so delete asks nothing. |
| 15 | The send bar at the foot of the rail holds the presence pill and, under it, the Send button across the rail's width with the count and the shortcut ("Send 2 comments ⌘↩"). The pill is a dot and a title: a filled green dot and "Agent listening", a half amber dot and "Agent working", a hollow grey dot and "No agent listening". Beside it are the agent's name and how many batches wait ("Claude Code · 1 batch waiting"), or "a batch will wait" with no agent. The pill's words are a pure struct, `PresencePill`. It is drawn again each second. | The person sees before sending whether someone will receive the batch, and that sending is safe either way. The dot's shape tells the state without its colour. An agent that stops answering turns absent with no event. |
| 16 | An agent message shows as a notice in the top-right corner of the stage for 5 s. A question stays until it is clicked or answered. A click selects the comment. No system notifications. | Brief while watching; a question blocks the agent, so it does not fade. The app is in front when notices matter. |
| 17 | The lease banner is a strip under the toolbar, across the top of the stage: who controls the app ("Claude Code controls Video Review"), where (the working folder's name or the Herdr pane), the time left, how many agents wait, and Stop. It shows with no video open too. Stop ends the lease and bars that agent for 5 min; nothing lifts the bar early. | The person must see at once why things move, and one click takes the app back. |
| 18 | The window follows the system's light and dark appearance, with system colours and materials. The letterbox around the video is black in both. | It matches the Mac. Black bars are what a player shows. |
| 19 | With no video: a drop target and "Open a video" (Cmd+O). On launch the app opens the last video again, paused at the start. | Coming back to a review should not need a file dialog. It also makes the history visible after a restart with no extra step. |
| 20 | A Context button in the toolbar opens a popover with the sidecar's text (read-only, in a box that scrolls, under the file's name; its path is the tooltip) and the editable note under it. With no sidecar the popover names the two files it looked for. Return or Save keeps the note and closes the popover, Shift+Return makes a new line, Escape or Cancel closes it with no change. The popover's foot says when the agent gets the context: "Goes to the agent with your next batch", "The agent has this. It goes again when it changes" or "Nothing to tell the agent yet". The button's glyph is filled while the video has a context. A small chip beside it names the transcript source and its progress. A small chip beside it names the transcript source and its progress: "Voiceover transcript", "Subtitle transcript", "Transcribing… 2 lines" with a moving waveform, "Speech transcript", "No speech", or "No transcript" with a warning sign when the transcription gave up. Its tooltip says where the lines come from, or why there are none. The chip's words are a pure struct, `TranscriptChip`. It is drawn again each second. | The person can check what the agent will be told without leaving the player, and sees that a change will reach the agent. The keys are the comment box's keys. |
| 21 | A "Demo data" chip shows in the toolbar during a demo run. | The person can tell a demo from their own data. |

## 4. Implementation

### The methods that carry the logic

Dispatch in the server:

```text
ControlServer.reply(to data)
  message = ControlMessage.decode(data)            else refused(error.message)
  switch message.request.role
    operator: decision = lease.use(by: holder, at: now); apply transitions
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

ListenerQueue.enqueue(ref)        outbox.enqueue(ref); deliver()                          // save, once the outbox is on disk

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
    no review of it in this run, or nothing unfinished in it: outbox.discard; next
    ref     = outbox.deliverNext(at: now)                                                 // pending → taken; the wait is answered
    context = outbox.context(for: ref.hash, text: ContextReader.text(for: review))        // nil when already sent unchanged, and with no text
    payload = BatchPayload.assemble(review, batch, context,
                transcript: { transcripts.lines(around: $0.time, of: ref.hash) },         // the lines the source has now
                images: { ImageFiles paths of $0.id under ref.hash })
    return .batch(ref, payload as JSON)

ControlServer   .batch → Answer(done(payload), delivered: ref)    .ranOut → ControlReply.ranOut (exit 2)
                .replaced → refused                               .gone → a silent answer
ControlServer, when that reply cannot be written:  listeners.undelivered(ref)             // back to the front
ControlServer, when the wait's client closed its socket:  listeners.connectionClosed(id)  // outbox.waitClosed
```

Asking and answering:

```text
ListenerQueue.ask(commentID, question, waitSeconds) async
  desk.change(hash) { try $0.ask(commentID, question, …) }      // refused while a question is open
  raise a notice; suspend with a continuation under commentID; start the timeout when there is one
AppModel.answer(commentID, text)                                 // from the answer box or `thread answer`
  message = desk.change(hash) { try $0.answer(commentID, text, …) }
  listenerQueue.answered(commentID, message)                     // resumes the ask with done(text)
timeout: resume with a timed-out reply (exit 2); the question stays open in the thread
```

An answer that arrives after its `ask` stopped waiting is kept in the thread. The listener reads it from `state --json`.

Edge cases:

- `comment add --at 0:40` on a 21 s video: `AppModel` refuses before any change.
- `status c-… working` on a `done` comment: `CommentState.canMove` is false; `ReviewRefusal.illegalMove(from: done, to: working)`.
- `ack` with an unknown batch id: the `Library` index has no such id; refused.
- `batch send` with an empty queue: refused, exit 1, no batch.
- A `wait` when the app quits: the connection closes with no reply; the CLI connects again until its timeout.
- Two `wait`s: the newer one replaces the older, which exits 1 saying so. A `wait` from another holder key is a new listener session.
- A `wait` whose command is stopped (its process ends): the server sees the closed socket within about 0.5 s and closes the `wait`. Presence falls to `absent` 5 s later, or stays `working` for 120 s while a batch is taken.
- A `wait` from the same holder while it has a taken batch: it gets the next batch in line, never the taken one again.
- Cmd+Return while a card's text is being edited: the queue is sent with the text as it was saved; the edit stays open and its Save is then refused, since the comment is sent.
- The person presses Stop while a `take` waits in line: the holder is barred and the first waiter gets the lease.
- A batch is sent while speech is still being transcribed: each comment gets the lines of its window that exist when a `wait` takes the batch. Nothing waits for the transcript.
- The Mac has no speech model for the language, or the transcription fails: the transcript stays incomplete with its `problem` in `state`, the chip says "No transcript", and comments go out with the lines that arrived, or none.
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
                                       state: lease = Claude Code until 12:01:00; the banner shows
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

- `Package.swift`: tools version 6.2, `platforms: [.macOS(.v26)]`, no package dependencies. Library targets for the six modules, executable targets `ReviewCLI` (product `video-review`) and `ReviewApp` (product `VideoReview`), one test target per module.
- `Makefile`, after Shipyard's: `make test` (`swift test`, with the Command Line Tools flags for Swift Testing and a shared module cache), `make bundle` (builds both products, lays out the `.app`, stamps `Info.plist`, signs the CLI then the bundle ad hoc), `make install` (quits this bundle's app, replaces `/Applications/<APP_NAME>.app`, opens it in the background with `open -g`).
- `make test` never drives the Mac. Each contract has one owner test at its strongest boundary:

| Contract | Owner test |
|---|---|
| version refusal, wire round trips | `ReviewWireTests` |
| the lease rules | `ReviewLeaseTests`, time-driven tables |
| CLI parsing, output, exit codes | `ReviewCommandTests`, fake transport and launcher |
| the state machine, batch assembly, requeue, context once per session, presence | `ReviewCoreTests` |
| the window cut, the source order | `ReviewTranscriptTests`, against `fixtures/sample` |
| what is on disk, the hash of a renamed copy | `ReviewStoreTests` |
| the server enforcing the lease, held requests | `ReviewAppTests`, fake `AppControlling` |
| everything end to end | `scripts/acceptance.sh` against the installed app in demo mode |

- `app open --demo <folder>`: the folder is the demo run's own support folder, made when missing (the scenario uses a folder under `.scratch/`). The fixture video is opened with `player open`.

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
| D5 | A listener session is the holder key of its `wait`. A `wait` from another key is a new session: unfinished taken batches go back to the queue and the context is sent again. | Every request already carries the holder, so the listener passes nothing, and a test names a session with `VIDEO_REVIEW_CONTROL_KEY`. |
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
| D28 | The lease banner is left out of screenshots, unless the agent passes `--with-banner`. | The agent that takes the screenshot always holds the lease, so the banner would be in every picture. The flag is an addition to the contract's `screenshot`, after Shipyard's `--with-indicator`: the only way an agent can prove the banner's pixels. |
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
| D44 | After Stop the banner goes and nothing more shows for the barred agent. | There is no Allow (D30), so a line about the bar would have no action. The agent's refusal tells it to ask the person. |
| D45 | The server ignores the lease's transitions. | They exist for notifications in Shipyard; this app has none (UX 16). The banner follows the lease itself. |
| D46 | A comment made at the player's time gets that time raised to the next millisecond. `--at` keeps the time given. | Rounding down would name the frame before the one on screen, and the keyframe would be the wrong frame. |
| D47 | The keyframe is written first, then the comment is queued. `comment add` answers after both. | A comment never exists without its keyframe, and an agent can read the PNG as soon as the command returns. |
| D48 | A comment holds no image path. `ImageFiles` derives it from the content hash and the comment id. | A support folder that moves (a demo folder, a restored backup) keeps working. |
| D49 | Deleting a comment deletes its keyframe file. | Nothing else refers to the file, and no undo exists. |
| D50 | `comment edit` and `comment delete` on an id that is not a comment id answer the same line as an unknown id. | The caller needs one thing to do: read the ids from `state --json`. |
| D51 | A comment has no creation date. | Nothing shows it or orders by it. The batch has `sentAt`. |
| D52 | `comment add` selects the new comment, like a comment from the box. | The person sees which card an operator just added. |
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
| D71 | A batch in line whose review is not in this run, or whose comments are all finished, is discarded when a `wait` reaches it. | A `wait` must never get stuck behind a batch that cannot be delivered. |
| D72 | The outbox stays in memory until the persistence ticket. `Outbox` is `Codable` already, without its open `wait` and last-heard time. | The reviews are in memory too, so an outbox on disk would name batches that are gone after a restart. |
| D73 | `batch send` answers `b-… sent with 2 comments, taken by the listener` or `…, waiting for a listener`. | The operator sees at once whether someone has the batch. |
| D74 | `state --json` has `listener.takenBatches` beside `pendingBatches`. | An agent can tell "delivered and unfinished" from "still in line" without the payload. |
| D75 | `wait` looks for the app's socket again on every try. | A listener started before `app open --demo` must find the demo's app. |
| D76 | When the app quits, an open `wait` is closed with no reply. | The command reads that as "not running" and connects again (D10). A refusal would end the listener. |
| D77 | Cmd+Return is handled by the key monitor, before the text view, and the menu item shows the same key. Both call `AppModel.send`. | One place decides the key for the stage, the comment box and a card being edited. The menu makes it discoverable. |
| D78 | `send()` does nothing when there is nothing to send, or while a send is under way. `batch send` with an empty queue is a refusal. | A person's stray key press is not an error. An agent's command needs an answer. |
| D79 | The rail's cards are in a plain stack, not a lazy one. | A lazy stack kept drawing a sent card as queued after it moved to its batch's group. A review has tens of comments. |
| D80 | A batch's header says "Sent at 00:13", with a two-digit hour. | "Sent 0:13" reads as a time in the video. |
| D81 | The comment box's hint row names Return, Cmd+Return and Escape, and no longer Shift+Return. | The row has room for three hints. |
| D82 | `Transcriber.lines(for:in:)` is synchronous and answers at once with what the source has. | The payload is assembled in one step when a `wait` takes the batch (D20), and a comment sent before the transcript is ready must get the lines that exist then. A call that could wait would hold the batch back. |
| D83 | The interface also has `transcript(of:)` (the source, the lines so far, complete, problem; nil when the source has nothing for the video) and `prepare`. `TranscriptSources` is a `Transcriber` too. | The source order, the state report and the chip need more than a window's lines, and the app then holds one thing. |
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
| D112 | `TranscriptFiles` in `ReviewStore` keeps the transcript until `Library` exists. | The persistence ticket builds `Library`; the file's place and shape are already the ones the layout names. |
| D113 | The speech engine is behind `SpeechRecognizing`, and `AppModel.init` takes one. | "A comment before the transcript is ready" is tested with a recognizer the test drives, with no real speech recognition in `make test`. |
| D114 | `state --json` has `transcript`: `source`, `complete`, `lines` and `problem`. `state` as lines has a `transcript:` line. | An agent can wait for `complete`, and reads why there is no transcript. |
| D115 | The chip is drawn again each second and observes nothing. | Speech lines arrive on a background task. The presence pill does the same. |
| D116 | The app installs the language's speech model through `AssetInventory` without asking, and asks for no speech recognition authorization. `Info.plist` has `NSSpeechRecognitionUsageDescription`. | `SpeechAnalyzer` ran on this Mac from a command-line tool with no prompt. The usage text is there in case macOS asks for the bundled app. |
| D117 | A batch of a video that was not opened in this run gets no transcript lines. | The frame rate a `voiceover.json` needs comes from the player. Until the persistence ticket, every batch in line belongs to a video opened in this run. |
| D118 | A video with no sound track has a complete speech transcript with no lines; the chip says "No speech". | Nothing failed, and there is nothing to wait for. |

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
- `ReviewStore`: `ContentHash` and `ImageFiles` (the keyframe's place, writing, removing, a small copy). It depends on `ReviewCore` only.
- `ReviewApp`: `ReviewDesk`, `Player/FrameGrabber` (keyframes), `AppModel` (the draft, the selection, add, edit, delete, select, marker jumps), `UI/CommentEditor`, `Stage/Composer`, `Timeline/Marker`, `Rail/CommentCard`, the state colours and glyphs in `Theme`. `Shortcuts` has Up, Down, C and Return.
- `state --json` has `video.contentHash`, `draft`, `comments` (`id`, `time`, `text`, `state`, `keyframePath`) and `queue`.
- Tests: `ReviewCoreTests`, `ReviewStoreTests`, and in `ReviewAppTests` comments through `AppModel` on the fixture video, the keys while typing and the comment box's keys.

Built (the ticket "Comment: Comment on a drawn region of the frame"):

- `ReviewWire`: `ControlRequest.Rectangle`, and `region` on `commentAdd`. `ReviewCommand`: `comment add --region x,y,w,h`.
- `ReviewCore`: `Region` (validation, `pixels`, `text`), `Comment.region`, `ReviewRefusal.badRegion`, `region` on `VideoReview.addComment`.
- `ReviewStore`: the crop's place in `ImageFiles`.
- `ReviewApp`: `FrameGrabber.writeImages` (keyframe and crop), `PlayerEngine.videoSize`, `Stage/VideoFrameGeometry`, `Stage/RegionOverlay`, the comment box beside a region in `Stage/Composer` and `Stage/StageView`, `AppModel` (the draft's region, `clickFrame`, `beginRegion`, `endRegion`, `escape`, `shownRegion`), Escape in `Shortcuts`, the crop as a card's thumbnail.
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
- `ReviewApp`: `TranscriptDesk`, `AppModel.init(environment:speech:)`, `AppModel.transcript`, the transcript closure in `ListenerQueue.payload`, `UI/TranscriptChip` in the toolbar.
- `Packaging/Info.plist`: `NSSpeechRecognitionUsageDescription`.
- `state --json` has `transcript`, and `state` has its line.
- Tests: `ReviewTranscriptTests` (the window, `voiceover.json` timing, `.srt` and `.vtt` parsing, the source order in temporary folders, the speech source with a recognizer the test drives); `TranscriptFiles` in `ReviewStoreTests`; in `ReviewAppTests` the payload's transcript through `AppModel` and `ControlServer` (the fixture with `voiceover.json`, a copy with only the `.srt`, a copy with no sidecar and a slow recognizer, the kept transcript after a restart, a transcription that gives up), the state report and the chip's words.
- Checked outside `make test`: `AppleSpeechRecognizer` on a copy of the fixture video with no sidecar, from a command-line tool. It gave five lines in about a second, with no permission prompt.
- Not checked by an agent: the chip in the window, and whether macOS asks the bundled app for speech recognition permission.

Not built yet, and what stands in its place:

- The rest of `ReviewCore`: `ThreadMessage`, the batch-level messages on `Batch`, and the `VideoReview` methods for threads and the listener (`acknowledge`, `setStatus`, `reply`, `ask`, `answer`). A comment has no `thread` yet. No comment passes `sent`, so no batch is finished: `Outbox.finished` and `Outbox.heard` have no caller yet. They are for the commands `ack`, `status`, `reply` and `ask`, which call `heard` each time and `finished` when `VideoReview.isFinished` turns true.
- The rest of `ReviewStore`: `Library`. Nothing but keyframes, crops and finished speech transcripts is written to disk. `ReviewDesk` keeps each review in memory for as long as the app runs, by content hash, so a video that opens again in the same run has its comments back; after a restart the comments and the outbox are gone and the keyframe files stay.
- `state --json` lacks the keys `messages` on a batch and `thread` on a comment. They come with their tickets.
- Threads, the commands `ack`, `status`, `reply`, `ask` and `thread answer`.
- The last video does not open again on launch. That comes with the store.
