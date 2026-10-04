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
| 2, 4, 6 comments, queue, markers | ReviewCore `VideoReview`, ReviewApp `ReviewDesk`, `FrameGrabber`, `Timeline/` | #5 |
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

Fields, not entities: `Region`, `ThreadMessage`, `Batch`, `CommentState`, `Holder`, `LeaseTerm`, `TranscriptLine`, `BatchPayload`. They are data on the entities above.

Relationships:

```text
AppModel ──owns──▶ PlayerEngine
AppModel ──owns──▶ ReviewDesk ──holds──▶ VideoReview ──contains──▶ Comment ──contains──▶ ThreadMessage
                        │                     └──contains──▶ Batch ──refers to──▶ Comment (by id)
                        └──saves through──▶ Library
AppModel ──owns──▶ ListenerQueue ──holds──▶ Outbox ──refers to──▶ Batch (by id and content hash)
                        ├──changes reviews through──▶ ReviewDesk
                        └──reads──▶ TranscriptSources, ContextReader, Library (image paths)
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
ReviewTranscript  ← Foundation, AVFoundation and Speech (the speech source only)
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
    ControlReply.swift             {ok, output, error, lease?}
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
    ControlCommands.swift          control take [--wait] | release
    PlayerCommands.swift           player open | play | pause | seek
    CommentCommands.swift          comment add | edit | delete, batch send, thread answer, context set
    ScreenshotCommand.swift        screenshot <abs.png> [--appearance]
    ListenerCommands.swift         wait, ack, status, reply, ask
    AppLauncher.swift              starts the app through Launch Services; the AppLaunching seam for tests
  ReviewCLI/
    main.swift                     exit(VideoReviewCLI.run(...))
  ReviewCore/
    Comment.swift                  Comment, Region (validation), ThreadMessage
    CommentState.swift             the seven states and the legal moves
    Batch.swift                    Batch: id, sentAt, comment ids, batch-level messages
    VideoReview.swift              one video's review: every rule about comments, batches and threads
    ReviewRefusal.swift            why a change is refused, as the line the CLI prints
    Outbox.swift                   the listener outbox: pending, taken, session, context sent, presence
    BatchPayload.swift             the JSON `wait` prints, and how it is assembled
    ItemID.swift                   short ids: c-xxxxxxxx, b-xxxxxxxx, m-xxxxxxxx
  ReviewTranscript/
    TranscriptLine.swift           start, end, text
    Transcriber.swift              the interface: a video and a window in, timed lines out
    TranscriptWindow.swift         the cut: lines that overlap time-15 … time+15
    TranscriptSources.swift        the source order; picks the first source that serves the video
    VoiceoverSource.swift          voiceover.json; scene times from scene lengths
    SubtitleSource.swift           .srt and .vtt sidecars, and their parser
    SpeechSource.swift             Apple SpeechAnalyzer in the background; lines arrive over time
  ReviewStore/
    Library.swift                  the support folder's layout; load and save reviews, the outbox, transcripts; the id index
    ContentHash.swift              SHA-256 of the file, streamed
    ImageFiles.swift               where keyframes and crops are, writing a PNG
  ReviewApp/
    VideoReviewApp.swift           @main; the one window; the menu commands
    AppModel.swift                 the orchestrator; every action a person or an operator can take
    ReviewDesk.swift               change a review, save it, publish it
    ListenerQueue.swift            open waits and asks; delivery; payload assembly; presence
    ContextReader.swift            the sidecar context file plus the note
    Player/
      PlayerEngine.swift           AVPlayer: open, play, pause, exact seek, time
      PlayerSurface.swift          AVPlayerView without controls, as a SwiftUI view
      FrameGrabber.swift           keyframe and crop PNGs from the asset, at the exact time
      Shortcuts.swift              the player's keys, off while a text field has the focus
    Control/
      ControlServer.swift          the socket, the lease, held requests, dispatch
      StateReport.swift            `state` and `app status` as JSON and as lines
      Screenshotter.swift          the app window through ScreenCaptureKit, in an appearance
    UI/
      RootView.swift               banner, stage, timeline, rail
      Theme.swift                  one place for the status colours and glyphs
      LeaseBanner.swift            who controls the app, and Stop
      EmptyState.swift             no video open
      ContextPopover.swift         the sidecar text and the editable note
      Stage/StageView.swift        the video with the overlay, the composer and the notices
      Stage/RegionOverlay.swift    draw a rectangle; show a comment's region
      Stage/VideoFrameGeometry.swift  view points to normalized frame coordinates and back (pure)
      Stage/Composer.swift         the comment box
      Stage/Toasts.swift           the brief notices
      Timeline/TimelineLane.swift  play button, time, scrubber, markers
      Timeline/Marker.swift        one marker: number, state, unread badge
      Rail/RailView.swift          the queue, then each batch
      Rail/CommentCard.swift       thumbnail, time, text, status, edit and delete
      Rail/ThreadView.swift        the messages and the answer box
      Rail/SendBar.swift           presence pill and the Send button

Tests/
  ReviewWireTests/                 version refusal, message round trips, time codes, the demo pointer, Holder.find
  ReviewLeaseTests/                time-driven tables
  ReviewCommandTests/              parsing, the request sent, output and exit codes, with a fake transport and launcher
  ReviewCoreTests/                 the state machine, batch assembly, the outbox
  ReviewTranscriptTests/           the window cut, the source order, voiceover timing, srt and vtt parsing (reads fixtures/sample)
  ReviewStoreTests/                round trips in a temp folder, the content hash of a renamed copy
  ReviewAppTests/                  ControlServer with a fake app, VideoFrameGeometry
```

A module and a type never share a name, so a type can always be qualified by its module.

### ReviewWire

`ControlRequest` is one enum, one case per command of the spec's contract:

| Role | Cases | Lease |
|---|---|---|
| free | `appStatus`, `state`, `controlTake(waitSeconds?)`, `controlRelease` | none |
| operator | `appOpen`, `appQuit`, `playerOpen(path)`, `playerPlay`, `playerPause`, `playerSeek(seconds)`, `commentAdd(text, at?, region?)`, `commentEdit(id, text)`, `commentDelete(id)`, `batchSend`, `threadAnswer(commentID, text)`, `contextSet(text)`, `screenshot(path, appearance?)` | takes or renews |
| listener | `wait(timeout?)`, `ack(batchID, text?)`, `status(commentID, state)`, `reply(id, text)`, `ask(commentID, question, waitSeconds?)` | none |

- `role` and `holdSeconds` (how long the app may keep the connection: a `take`'s wait, a `wait`'s timeout, an `ask`'s wait, or no limit) are computed properties on the request, so the server and the client agree without a table.
- On the wire a message is one JSON object: `version`, `command` (`player.seek`), `holder` (`key`, `name`, `place`), `json` (the caller passed `--json`) and the command's own fields. Protocol version 1.
- `ControlMessage.decode` refuses in this order: not JSON, another version (naming both), no holder, unknown command, a missing or invalid field.
- `Holder.find(variables, workingDirectory, processes)`: the key is `VIDEO_REVIEW_CONTROL_KEY` when set, else `CLAUDE_CODE_SESSION_ID`, else the nearest ancestor process that is not a shell, as `process:<pid>@<start>`. The name is `Claude Code` or the process name. The place is the Herdr pane when there is one, else the working folder. The process table is a protocol with the system's `sysctl` reader and a fake.
- `ControlClient.send(request)` writes the message, half-closes, reads to the end. Its read timeout is 15 s plus `holdSeconds`, or none when the request has no limit. A connection that closes with no reply reads as an app that is not running.
- `UnixSocket.address(path)`: a socket address holds 103 bytes. A longer path (a demo folder deep in a worktree) is reached through a symbolic link to its folder, in the user's temporary folder (`confstr(_CS_DARWIN_USER_TEMP_DIR)`), named after a hash of the folder's path. The app and the CLI each make the same link, so neither tells the other.
- `SupportFolder.app(environment)`: `VIDEO_REVIEW_SUPPORT_DIR` when it is an absolute path, else `~/Library/Application Support/<AppIdentity.supportFolderName>/`.
- `ControlSocket.locate(support)`: the demo's socket while `demo.json` names a demo folder whose socket exists, else the folder's own.

### ReviewLease

`ControlLease` copies the rules of Shipyard's `ControlLease`: a struct with `renewal` 60 s, `cap` 5 min and `bar` 5 min, and the time passed into every call.

| Call | Does | Returns |
|---|---|---|
| `use(by:at:)` | an operator request: takes a free lease to `now + renewal`, renews the holder's, never past the cap | `Decision`: the `LeaseTerm` or a `Refusal`, plus transitions |
| `take(by:at:waitingUntil:)` | `control take`: holds to the cap; behind another holder it queues until the deadline, one place per key | `Decision` (`queued` means no answer yet) |
| `release(by:at:)` | ends the holder's lease; the first waiter gets it | transitions |
| `stop(at:)` | the person's Stop: ends the lease, bars the holder for `bar` | transitions |
| `settle(at:)` | ends a lease that ran out, lifts ended bars, hands a free lease to the first waiter | transitions |
| `giveUp(by:waited:at:)` | a waiter's wait ran out | `Decision` |
| `current(at:)`, `status(at:)`, `nextEnd(after:)` | read-only | the term, the status for `app status`, when to settle next |

`Refusal` is `inUse(term)`, `queued(term)`, `waitedOut(seconds, term)` or `stopped`, and writes its own line, naming the holder, its place and the end time. `handover(term)` and `init(environment:at:)` carry a lease across `app quit` and a relaunch in `VIDEO_REVIEW_CONTROL_LEASE`, so `app open --demo` on a running app keeps the operator's lease.

### ReviewCommand

- `CommandTable` maps `app status`, `player seek` and the rest to a parser that returns a `ControlRequest` or a usage error. `--json` is accepted on every command.
- `VideoReviewCLI.run(arguments, environment)` returns `CommandResult(output, error, exitCode)`. `environment` holds the variables, the working folder, the process table, the transport and the launcher, so tests replace all of them.
- The CLI makes paths absolute against its own working folder before it sends them (`player open`, `app open --demo`); `screenshot` requires an absolute path, as the contract says.
- `app status` answers without the app: `not running`, exit 0. Every other command but `app open` and `wait` exits 1 with `Video Review isn't running; run video-review app open` when nothing listens.
- `app open [--demo <folder>]`: when the app does not run, it launches the bundle the command ships in without activating it, with `VIDEO_REVIEW_SUPPORT_DIR` for a demo, waits for the socket, then sends `app.open`. When the app already runs on the data asked for, it only sends `app.open`. When the app runs on other data, it sends `app.quit`, takes the lease from the reply and relaunches with the handover. `--demo` records the pointer; plain `app open` removes it. A demo that does not come to run leaves no pointer.
- The launcher waits for a quitting copy of the app to end. For a demo launch, a copy that is still there (one that `make install` has just opened and that does not answer yet) is asked to quit first: Launch Services would hand that copy back on its own data.
- `--json` is taken from anywhere on the command line. An action then prints the parts of the state it changed (`player seek` prints `{"player": {…}}`, `player open` adds `video`, `screenshot` prints `{"path": …}`). `app status --json` prints `{"running": false}` when the app is not running.
- `wait` connects again while the app is not running or quits, once a second, until its timeout. A listener can start before the app.

### ReviewCore

```swift
public struct VideoReview: Codable, Equatable {       // one video's review
    public var video: VideoInfo                        // contentHash, title, duration, path (last seen)
    public var note: String                            // the in-app context note
    public private(set) var comments: [Comment]        // kept in time order
    public private(set) var batches: [Batch]           // in the order sent

    // the person and the operator
    mutating func addComment(id:, time:, text:, region:, at now:) throws(ReviewRefusal) -> Comment   // state queued
    mutating func editComment(_ id:, text:) throws(ReviewRefusal)                // queued only
    mutating func deleteComment(_ id:) throws(ReviewRefusal)                     // queued only
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
- `Region` holds `x, y, w, h` from the top-left corner of the displayed frame. `Region.init` refuses values outside 0..1, a rectangle that leaves the frame, and a width or height of 0.
- Ids and the time come in as arguments, so tests are deterministic. `ItemID` makes `c-`, `b-` and `m-` ids with 8 random hex digits; the prefix tells `reply` whether its target is a comment or a batch.

`Outbox` is the listener's side as a pure value, given the time on each call, like the lease:

```swift
public struct Outbox: Codable, Equatable {
    var pending: [BatchRef]                 // sent, not yet delivered; first in, first out. BatchRef = batch id + content hash
    var taken: [BatchRef]                   // delivered, not finished
    var session: ListenerSession?           // holder key, name, place of the last `wait`
    var contextSent: [String: String]       // content hash → digest of the context text this session got

    mutating func enqueue(_ ref:)
    mutating func waitOpened(by holder:, at now:) -> [BatchRef]     // a new key is a new session: taken → front of pending, contextSent cleared; returns the requeued
    mutating func deliverNext() -> BatchRef?                         // only while a wait is open: pending.first → taken
    mutating func undelivered(_ ref:)                                // the reply could not be written: back to the front
    mutating func finished(_ ref:)
    mutating func context(for hash:, text:) -> String?               // the text when it is due, else nil; records the digest
    mutating func heard(at now:), connectionOpened(), connectionClosed(at now:)
    func presence(at now:) -> Presence                               // listening | working | absent
}
```

Presence: `working` when the session has a taken batch and is alive; `listening` when a `wait` is open and nothing is taken; `absent` otherwise. Alive means a `wait` or `ask` connection is open, or the last listener command was less than 120 s ago while a batch is taken, or less than 5 s ago otherwise (so a listener that runs `wait` in a loop does not flicker).

`BatchPayload` is the Codable shape of the spec, and `BatchPayload.assemble(review, batch, context, transcript:, images:)` builds it. The two closures give each comment its transcript lines and its image paths, so `ReviewCore` needs neither `ReviewTranscript` nor `ReviewStore`.

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
    func lines(for video: VideoFile, in window: ClosedRange<TimeInterval>) async -> [TranscriptLine]
}
```

- `VideoFile` is the file URL, the frame rate and the duration.
- `TranscriptSources.pick(for:cached:)` returns the first source that serves the video, in the spec's order: `VoiceoverSource` (`<base>.voiceover.json`, else `voiceover.json`, in the video's folder), `SubtitleSource` (`<base>.srt`, else `<base>.vtt`), `SpeechSource`. The interface has three implementations today, which is why it is an interface; the transcription research replaces or adds a source behind it.
- `VoiceoverSource`: a scene lasts `ceil((durationSeconds + paddingSeconds) × fps)` frames and starts where the previous one ends. One line per scene.
- `TranscriptWindow.cut(lines, around: time, duration:)` keeps every line that overlaps `time − 15 … time + 15`, clamped to the video. Lines are kept whole.
- `SpeechSource` starts when the video opens and no sidecar serves it. It feeds the audio track to `SpeechAnalyzer` off the main actor, publishes lines as they arrive and answers `lines(for:in:)` with what it has. It starts from the lines the `Library` cached, and the app saves new lines to the `Library`. When the model or the permission is missing it stays empty and says why in the state report.

### ReviewStore

```text
<support>/                               ~/Library/Application Support/Video Review (proto-2)/, or the demo folder
  control.sock                           while the app runs
  demo.json                              the demo pointer; only in the normal folder
  outbox.json                            the Outbox
  recent.json                            the path of the last open video
  videos/<contentHash>/
    review.json                          one VideoReview, with schemaVersion
    transcript.json                      cached speech lines, source and whether complete
    frames/<comment-id>.png              the keyframe, at the video's own size
    crops/<comment-id>.png               the region's crop
```

- `Library(support:)` reads every `review.json` once at launch into an index from comment and batch ids to content hashes, so `status c-…` finds its video without the video being open.
- `load(hash)`, `save(review)`, `loadOutbox()`, `save(outbox)`, `transcript(hash)`, `saveTranscript(...)`. Every save writes the whole file atomically. The files are small.
- `ContentHash.of(url)` is the SHA-256 of the whole file, read in 4 MiB chunks off the main actor. A renamed or moved copy has the same hash, so it opens the same folder; `review.json` then records the new path.
- Demo and real data never mix: the `Library` only ever sees the support folder it was given.

### ReviewApp

`AppModel` (`@MainActor @Observable`) is the orchestrator. Its methods are the product's actions; the UI and the `ControlServer` call the same ones:

| Method | Rules it owns | Refuses |
|---|---|---|
| `open(url)` | hash, load the review, pick the transcript source, read the context, remember as recent | a file AVPlayer cannot play |
| `play()`, `pause()`, `seek(seconds)` | seek is exact and keeps play or pause | no video; a time outside the video |
| `startDraft(region?)`, `commitDraft()`, `cancelDraft()` | starting a draft pauses; commit captures the keyframe and crop and queues the comment | empty text |
| `addComment(text, at?, region?)` | the CLI's path: pause, seek to `at`, then the same as commit | no video; bad time or region |
| `editComment`, `deleteComment` | through `ReviewDesk` | not queued; unknown id |
| `sendBatch()` | commits a draft with text first, waits for image writes, sends, hands the batch to `ListenerQueue` | empty queue |
| `answer(commentID, text)` | through `ReviewDesk`, then tells `ListenerQueue` | no open question |
| `setContextNote(text)` | saved on the review | no video |

- `ReviewDesk.change(hash) { review in … }` is the one path for every change to a `VideoReview`: it takes the open review from memory or loads another video's from the `Library`, runs the change, saves, and publishes when the review is the open one. A thrown `ReviewRefusal` changes nothing.
- `PlayerEngine` wraps `AVPlayer`. `seek` uses zero tolerance and returns when the seek has finished, so `state` reports the time that was asked for. The duration is the video track's own length (21.233 s for the fixture), not the container's, whose sound track can run a few milliseconds longer. A file that does not play is refused, and the video that was open stays open.
- `PlayerSurface` is an `AVPlayerView` with no controls that takes no click and no key (`hitTest` gives nil). The stage's own layer above it takes the mouse.
- `Shortcuts` is one local key monitor. It maps a key to an action in a pure function and stands back while a text view has the focus. The Playback menu has the same actions with no key equivalents, since a menu key with no modifier would take the key from a text field.
- `FrameGrabber` makes the keyframe with `AVAssetImageGenerator` at the exact time, from the asset and not from the window. The crop is the keyframe cut by the region. The UI and the CLI therefore produce the same pixels at any window size.
- `ListenerQueue` holds the `Outbox`, the one open `wait` (a continuation) and the open `ask`s by comment id. It assembles the payload when a `wait` takes a batch. `ack`, `status`, `reply` and `ask` go through `ReviewDesk.change` and raise a notice.
- `ControlServer` listens on `control.sock` (mode 0600), reads each request off the main actor and answers on it. It asks `ControlLease.use` before any operator request, holds a queued `take`, a `wait` and an `ask` as suspended continuations while it answers other requests, and settles the lease on a timer at `nextEnd`. It depends on a small protocol, `AppControlling`, which `AppModel` implements and the server's tests fake.
- `StateReport` builds `state --json`:

```json
{
  "app":      { "version": "0.1.0", "variant": "proto-2", "demo": true, "support": "/abs/demo" },
  "lease":    null,
  "listener": { "presence": "listening", "waitOpen": true, "session": "Claude Code", "pendingBatches": 0 },
  "video":    { "path": "/abs/sample.mp4", "contentHash": "<64 hex>", "duration": 21.233, "title": "sample", "contextNote": "" },
  "player":   { "time": 10.0, "playing": false },
  "transcript": { "source": "voiceover", "complete": true, "lines": 3 },
  "draft":    null,
  "comments": [ { "id": "c-7f3a9c2e", "time": 10.0, "text": "…", "state": "queued", "region": null,
                  "keyframePath": "/abs/…png", "cropPath": null, "batchId": null,
                  "thread": [ { "id": "m-…", "author": "agent", "kind": "question", "text": "…", "at": "…" } ] } ],
  "queue":    [ "c-7f3a9c2e" ],
  "batches":  [ { "id": "b-…", "sentAt": "…", "commentIds": [ "c-…" ], "messages": [ … ] } ]
}
```

  `comments` and `queue` are in time order. `video` is `null` with no video open.
- `Screenshotter` captures the app's own window with ScreenCaptureKit, from this process's shareable content only, which needs no Screen Recording permission. For `--appearance` it sets the app's appearance, waits for the window to redraw, captures and restores. Captures take turns, so two of them never mix their appearances. It makes the PNG's folder when it is missing. The lease banner is hidden for the capture, since the holder would be in every picture.
- The app has one `Window` scene. Closing the window quits the app. A second copy started on the same support folder finds the socket taken and quits.

### The UX of this prototype

The idea: **the video is the stage, the timeline carries the markers, and a rail at the side carries the conversation.** The person watches on the left and reads answers on the right, and never leaves the window. Each choice and its reason:

| # | Choice | Reason |
|---|---|---|
| 1 | One window, one video at a time. Opening another video replaces the open one. | The CLI commands name no window, and there is one queue and one listener. |
| 2 | Three parts: the stage (video) on the left, the timeline lane under it, the rail (340 pt, can collapse) on the right. The rail is the system's inspector column, with a toolbar button that hides it. The stage is a black card with round corners. The lane has a ruler of times under the track. The default window (1360 by 730 pt) shows a 16:9 video with no letterbox. | Answers stay next to the feedback and stay visible while the video plays. One screenshot shows markers, a region and a thread. The inspector resizes and collapses as the Mac's other apps do. |
| 3 | The app's own player surface (`AVPlayerView` with no built-in controls) and its own timeline lane, always visible. | The stock controls cannot carry markers, and they take the mouse drags the region overlay needs. Markers are the core of the app, so the lane never hides. |
| 4 | QuickTime keys: Space or K plays and pauses, Left and Right move 5 s, Shift+Left and Shift+Right move one frame, Up and Down jump to the previous and next marker. A click on the frame plays or pauses. | Playback should feel like QuickTime. Frame steps matter for pointing at an exact frame. |
| 5 | C or Return starts a comment at the current time and pauses. No automatic focus on pause. | One key from watching to typing, and Space still resumes. Typing never reaches the player: the shortcuts are off while a text field has the focus. |
| 6 | Dragging on the frame draws a rectangle at any time, with no drawing mode. The drag pauses the video. Releasing opens the comment box. Escape cancels. | It works like Cmd+Shift+4: point first, no tool to pick. |
| 7 | The comment box floats on the stage: beside the rectangle for a region comment (right, else left, else below, always inside the stage), above the playhead for a time comment. | The person writes where they point. |
| 8 | In the comment box, Return queues the comment, Shift+Return makes a new line, Escape cancels, Cmd+Return queues and sends everything. The box is a standard text view that takes the focus when it opens. | Fast entry with one hand on the keyboard. A standard focused text view is all Wispr Flow needs to dictate into. |
| 9 | Cmd+Return anywhere sends the queue. A draft with text is queued first. | One keystroke delivers all feedback, with nothing left behind in the box. |
| 10 | Markers are numbered pins on the timeline, numbered in time order. Colour and glyph show the state: hollow for queued, grey for sent, blue check for acknowledged, amber pulse for working, green check for done, red cross for failed. A dot marks an unread agent message; a question mark marks an open question. | The state reads at a glance, and never by colour alone. The number ties a pin to its card. |
| 11 | A click on a marker or a card seeks to its time, pauses, selects it and shows its region on the frame. | One gesture gives the full context back. |
| 12 | The rail groups by batch: "Queue" on top, then each batch, newest first, with a header (sent time, progress such as 2 of 3 done) and the batch's own messages under the header. Comments are in time order inside a group. | The batch is the unit that is sent and answered, so the batch message has a natural home and the progress of a batch is visible. |
| 13 | A card shows a thumbnail (the crop, else the keyframe), the time, the text and a status chip. Its thread is inline under it, open for the selected card and for any card with an open question. The answer box sits under the question. | The thread is part of the comment, not a second screen. A question must not hide. |
| 14 | Edit and delete show on queued cards only. | Only a queued comment can change, so the controls do not appear where they would be refused. |
| 15 | The send bar at the foot of the rail holds the presence pill ("Agent listening", "Agent working", "No agent: the batch will wait") and the Send button with the count and the shortcut. | The person sees before sending whether someone will receive the batch, and that sending is safe either way. |
| 16 | An agent message shows as a notice in the top-right corner of the stage for 5 s. A question stays until it is clicked or answered. A click selects the comment. No system notifications. | Brief while watching; a question blocks the agent, so it does not fade. The app is in front when notices matter. |
| 17 | The lease banner is a strip across the top of the window: who controls the app, when the lease ends, and Stop. | The person must see at once why things move, and one click takes the app back. |
| 18 | The window follows the system's light and dark appearance, with system colours and materials. The letterbox around the video is black in both. | It matches the Mac. Black bars are what a player shows. |
| 19 | With no video: a drop target and "Open a video" (Cmd+O). On launch the app opens the last video again, paused at the start. | Coming back to a review should not need a file dialog. It also makes the history visible after a restart with no extra step. |
| 20 | A Context button in the toolbar opens a popover with the sidecar's text (read-only, with its path) and the editable note. A small chip beside it names the transcript source and its progress. | The person can check what the agent will be told without leaving the player. |
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
  commit the draft when it has text
  await FrameGrabber's pending writes
  batch = desk.change(openHash) { try $0.send(batchID: ItemID.batch(), at: now) }      // queued → sent
  listenerQueue.enqueue(BatchRef(batch.id, openHash))

ListenerQueue.enqueue(ref)        outbox.enqueue(ref); save; deliver()

ListenerQueue.wait(holder, timeout) async -> ControlReply
  requeued = outbox.waitOpened(by: holder, at: now)
  for ref in requeued: desk.change(ref.hash) { $0.requeue(ref.batchID) }                 // unfinished → sent
  answer an older open wait with refused("replaced by a newer wait")
  suspend with a continuation; start the timeout; deliver()

ListenerQueue.deliver()
  guard a wait is open, let ref = outbox.deliverNext()
  review  = desk.review(ref.hash)
  context = outbox.context(for: ref.hash, text: ContextReader.text(review))               // nil when already sent unchanged
  payload = BatchPayload.assemble(review, batch, context,
              transcript: { TranscriptWindow.cut(source.lines(…), around: $0.time) },
              images: { library.imagePaths(ref.hash, $0.id) })
  resume the wait with done(payload as JSON); save the outbox

ControlServer, when that reply cannot be written:  listenerQueue.undelivered(ref)         // back to the front
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
- Two `wait`s: the newer one replaces the older. A `wait` from another holder key is a new listener session.
- The person presses Stop while a `take` waits in line: the holder is barred and the first waiter gets the lease.
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
ReviewApp/UI/Rail/SendBar.swift        Cmd+Return → AppModel.sendBatch()
ReviewApp/AppModel.swift               no draft; FrameGrabber has written both keyframes and the crop
ReviewApp/ReviewDesk.swift             change(hash) { $0.send(batchID: "b-5d0c2a91", at: 19:02:11Z) }
ReviewCore/VideoReview.swift             both comments queued → sent, batchId set; batches += b-5d0c2a91
ReviewStore/Library.swift                review.json written
                                       state: queue = []; both markers grey "sent"
ReviewApp/ListenerQueue.swift          enqueue(b-5d0c2a91): outbox.pending = [b-5d0c2a91]; outbox.json written; deliver()
ReviewCore/Outbox.swift                  deliverNext(): a wait is open → pending = [], taken = [b-5d0c2a91]
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
  deliver() finds no open wait → the batch stays in pending; the pill says "No agent: the batch will wait"
  the next `wait` → waitOpened → deliver() → the same payload

the listener restarts as session L2 while b-5d0c2a91 is taken and unfinished
  Outbox.waitOpened(by: L2): the key differs → taken → front of pending; contextSent cleared
  VideoReview.requeue: acknowledged and working comments → sent; done and failed stay
  deliver(): L2 gets b-5d0c2a91 with its unfinished comments and with the context again
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
| A better transcription source | one new `Transcriber` in `ReviewTranscript`, one line in `TranscriptSources`. |
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
| D28 | The lease banner is left out of screenshots. | The agent that takes the screenshot always holds the lease. |
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

## 7. What is built so far

The sections above describe the whole build. This list says what the code holds today. Each ticket moves its line.

Built (the first build ticket, "Control: Play a video and drive the player through the CLI"):

- `Package.swift`, `Makefile`, `Packaging/Info.plist`.
- `ReviewWire`: every file in the tree. `ControlRequest` has the cases `appStatus`, `state`, `appOpen`, `appQuit`, `playerOpen`, `playerPlay`, `playerPause`, `playerSeek` and `screenshot`. `LeaseTerm` is data only.
- `ReviewCommand`: `CommandTable`, `VideoReviewCLI`, `AppCommands`, `PlayerCommands`, `ScreenshotCommand`, `AppLauncher`. `ReviewCLI/main.swift`.
- `ReviewApp`: `VideoReviewApp`, `AppModel` (open, play, pause, seek), `Player/PlayerEngine`, `Player/PlayerSurface`, `Player/Shortcuts` (play and pause, 5 s, one frame), `Control/ControlServer`, `Control/StateReport`, `Control/Screenshotter`, `UI/RootView`, `UI/Theme`, `UI/EmptyState`, `UI/Stage/StageView`, `UI/Timeline/TimelineLane`, `UI/Rail/RailView`, `UI/Rail/SendBar`.
- Tests: `ReviewWireTests`, `ReviewCommandTests`, `ReviewAppTests` (the control server with a fake app and over the real socket, the player's keys).

Not built yet, and what stands in its place:

- The lease. `ControlServer.reply(to:)` admits every holder. Each request already carries its `holder` and has a `role`; the lease check goes before the dispatch. The reply's `lease` is always absent, and `state` reports `"lease": null`.
- `ReviewLease`, `ReviewCore`, `ReviewTranscript`, `ReviewStore` and their test targets. `Package.swift` gets each target with its ticket.
- `state --json` has the keys `app`, `lease`, `video` (`path`, `title`, `duration`) and `player`. The keys `listener`, `transcript`, `draft`, `comments`, `queue` and `batches`, and `video.contentHash` and `video.contextNote`, come with their tickets.
- Comments, regions, markers, batches, threads, the listener commands, the context popover and the transcript chip. The rail shows an empty queue and a Send button that is off. The presence pill says "No agent listening". The timeline lane has no markers.
- The last video does not open again on launch. That comes with the store.
- The keys Up, Down, C and Return, and Cmd+Return.
