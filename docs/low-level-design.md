# Havooch 0.2.0: low-level design

Written 2026-10-05, before the first build ticket of `effort:0.1.0`, from `Spec: Havooch 0.1.0` (#20), the prototype decisions in `docs/prototypes/2026-10-05-decisions.md` (cited as D x.y), ADR 0001 and the tickets #22 to #33. It is documentation for the maintainer, not a review gate. When the code and this document disagree, fix one of them in the same change. `Spec: Havooch 0.2.0` (#36) and its tickets #37 to #44 changed it since; their decisions are L36 to L44.

It starts from proto-2's low-level design (`proto-2:docs/low-level-design.md`, PR #18), since proto-2's code is the base (D A.1). It keeps what proto-2 got right and changes four things: the **thread model** replaces comments and batches, the **send** cuts the transcript at send time, every colour comes from a **theme**, and the module changes A.2 to A.10 come from proto-1 (`proto-1:docs/low-level-design.md`, PR #17). proto-2's own decisions (D1 to D216 in its document) still hold where this document does not replace them; the decisions this design takes on its own are numbered L1, L2… under [Decisions](#6-decisions-the-spec-left-open).

NOTE: Domain words follow `GLOSSARY.md`. In particular, a **message** is what the person or the agent writes, a **thread** holds the messages about one keyframe, and a **send** is what Cmd+Enter delivers. "Comment" survives only as the CLI's `comment` commands and the UI's Comment button; "batch" is gone.

## For a newcomer, in one screen

Havooch is one Swift package. It builds two executables: the macOS app (`/Applications/Havooch.app`) and the `havooch` command, which ships inside the bundle at `Contents/Helpers/havooch`. The code is eight modules, split by concern. The agent side never links the app's rules.

```text
agent side (no app rules, no UI; builds and tests on Linux)
  ReviewLease       Holder and how it is found; the lease rules as a pure value. Depends on nothing.
  ReviewWire        the control protocol: request, reply, socket framing, socket and support folder locations, the app identity and version
  ReviewCommand     the command table of `havooch`: parse, send one request, print the reply, pick the exit code
  ReviewCLI         main.swift only

app side
  ReviewCore        threads, messages, regions, states, the send, the send payload, the outbox, theme resolution. Pure logic, given the time.
  ReviewTranscript  the Transcriber interface, its three sources and the window cut
  ReviewStore       SupportLayout (every path), Library (load and save), images, the speech cache, theme files
  ReviewApp         the SwiftUI app: player, stage, popovers, sidebar, header, control server, listener queue. macOS only.

havooch (CLI)   → ReviewLease + ReviewWire + ReviewCommand
Havooch.app     → everything
```

```text
person ──keys, mouse──▶ ReviewApp UI ──────────┐
                                               ├─▶ AppModel ──▶ PlayerEngine (AVPlayer)
operator ──▶ havooch ──▶ SocketListener ──▶ ControlServer      ├─▶ ReviewDesk ──▶ VideoReview (Core) ──▶ Library (Store)
             (lease)          (control.sock)    (decode, lease,     ├─▶ ListenerQueue ──▶ Outbox (Core)
                                                 dispatch)          └─▶ ThemeDesk ──▶ ThemeCatalog (Core), ThemeFiles (Store)
listener ──▶ havooch wait / ack / status / reply / ask ──▶ ControlServer ──▶ ListenerQueue, ReviewDesk
             (no lease)
```

The person and the operator reach the same `AppModel` methods, so a UI action and its CLI command are one code path.

| You want to | Open |
|---|---|
| see where the app starts | `Sources/ReviewApp/HavoochApp.swift`, then `AppModel.swift` |
| see where the CLI starts | `Sources/ReviewCLI/main.swift`, then `Sources/ReviewCommand/CommandTable.swift` |
| add a CLI command | [Extensibility](#5-extensibility), first row |
| change a thread or message rule, or a state | `Sources/ReviewCore/VideoReview.swift`, `MessageState.swift` |
| change what `wait` prints | `Sources/ReviewCore/SendPayload.swift` |
| change when a send is delivered again | `Sources/ReviewCore/Outbox.swift` |
| change the lease | `Sources/ReviewLease/ControlLease.swift` |
| change where a file is kept | `Sources/ReviewStore/SupportLayout.swift` |
| add a colour token or a built-in theme | `Sources/ReviewCore/Theme/ThemeToken.swift`, `Packaging/Themes/` |
| add a known agent harness or its logo | `Sources/ReviewCore/KnownAgent.swift`, `assets/images/agent-logos/`, `make agent-logos`, `Packaging/AgentLogos/NOTICE.md` |
| follow a command from the shell to the player | [Trace 1](#trace-1-a-cli-command-comment-add-on-a-region) |
| follow a send from Cmd+Enter to `wait`, and a follow-up | [Trace 2](#trace-2-a-send-from-cmdenter-to-wait-then-a-follow-up) |

## 1. Requirements

The 92 user stories of the spec are the requirements. They group into these capabilities (story numbers in brackets).

### Capabilities

1. **Play** a local mp4, mov or m4v with QuickTime-like keys and a compact player bar. (1 to 4)
2. **Write a message** on the current frame (C, or the Comment button) or on a drawn region, in the comment popover. The message joins the thread of that exact frame, or starts one. (5 to 12)
3. **Close the popover safely**: a click outside queues the text, × or Escape discards it, a change of the moment queues text at its original time and region and discards an empty popover. (14 to 18)
4. **Queue**: messages wait as `queued`; a queued message can be edited or deleted. (19)
5. **Send**: Cmd+Enter, the Send button or `havooch send` sends every queued message of the open video, on any threads, as one send. (20 to 22)
6. **Pins**: one pin per thread on the timeline, its shape from its regions, its colour from its state or, while the agent waits for an answer, the question's (L35), its details on hover; a click seeks and opens the thread popover. (23 to 27)
7. **Thread popover**: outlines and number badges on the frame; the popover holds the conversation above the field, drags and resizes, and keeps its frame per thread. Nothing opens during playback. (28 to 34)
8. **Sidebar**: the thread list, grouped by who must act next, and the thread view of one thread with Back, Previous and Next; message bubbles with crops, one composer at the sidebar's foot, resizable. (35 to 44, 65; 0.2.0: L38 to L41)
9. **Agent**: the listener gets each send through `wait`, grouped by thread, acknowledges, replies, sets each message's state and asks on a thread; an answer to a question goes at once. Notices name the thread. (45 to 49, 71 to 81)
10. **Header and presence**: the file name, the folder, the floating group (agent-control icon, Context, sidebar toggle), the footer with presence, queued count and Send. (50 to 58)
11. **Themes**: every colour is a token; built-in and user themes, light and dark, follow the system or a pinned one, per-token overrides, reload on change. (59 to 64)
12. **Persist** threads, messages, states, popover frames and the theme per video, keyed by content. (66, 67)
13. **Context and transcript**: the context sidecar plus the in-app note, given once per listener session; the transcript from voiceover, subtitles or speech in the background. (68 to 70)
14. **Agent control**: every action through the CLI under the lease; `state --json`; screenshots in light and dark; demo mode. (82 to 89)
15. **Build**: version 0.2.0 (0.1.0 before effort 0.2.0); the agent-side modules build and test on Linux; the listener skill. (90 to 92)

### Rules and completion

- A thread belongs to one video and one keyframe. Its key is the exact frame time. Its number is unique in the review and starts at 1. The General thread is number 0 and has no keyframe; every review has one.
- A person message of the kind `message` moves `queued → sent → acknowledged → working → done | failed`. Forward only, skips allowed, `done` and `failed` final. The one move back: a send requeued for a new listener session returns its unfinished messages to `sent`.
- Only a `queued` message can be edited or deleted. Agent messages, questions and answers have no state.
- The state of a thread is the state of its latest open person message (open: not `done` or `failed`). With none open, it is the state of its latest person message. With no person message, the thread has no state (D 3.9).
- A send is every queued person message of the open video at the moment of sending. It is finished when each of its messages is `done` or `failed`.
- A thread has at most one open question. An answer goes to the waiting `ask` at once and never into the queue (D 2.16).
- An `ask` may offer quick-reply choices (`--choice`, repeatable, #46). The question keeps them; the thread view shows one chip button per choice under the open question, and a click (or `thread choose <thread> <number>`) answers with that choice at once.
- The outbox delivers sends first in, first out, one per `wait`. A new holder key on `wait` is a new listener session: its predecessor's unfinished sends return to `pending` and the context is due again (D A.11).
- The listener is present while a `wait` or an `ask` is open, with proto-2's grace times (5 s listening, 120 s working).
- The lease follows ADR 0001 unchanged.
- A request of another protocol version is refused, naming both versions.

### Error handling

- Every refusal is a reply with `ok` false and one line in `error`; the CLI prints it on standard error.
- Exit codes: 0 done; 1 refused or failed; 2 a held request ran out of time (`wait --timeout`, `ask --wait`); 64 wrong usage.
- Invalid input is refused before any state changes: a time outside the video, a region outside 0..1 or with no area, an empty text, an unknown or malformed id, a thread id of another video for `comment add --thread`, a relative screenshot path, an unknown theme name.
- Illegal moves are refused with the rule broken: editing a sent message, a state moving back, `ask` while a question is open, `thread answer` or `thread choose` with no open question, `thread choose` with no such choice, an `ask` choice with no words, `reply` on a thread with nothing sent.
- A file AVPlayer cannot play is refused; the open video stays open. A transcript source that fails gives no lines and never blocks a send.
- A store file from a newer schema, or one that does not read, is never written over; the video's history is refused with the reason.
- A theme file that does not read, has an unknown `kind`, or forms an `extends` loop is left out of `theme list` with a line on standard error; a token with a bad colour falls back as a missing token does.
- A reply that cannot be written undoes what only the client would know: a granted `take` is released, a delivered send goes back to `pending`.

### Scope

In: all of the above. Out, as the spec says: a redesign of the comment popover, a rule for a listener that never comes back, fonts and spacing in themes, video editing, formats AVPlayer cannot play, URLs, system-wide hotkeys, more than one listener, shapes other than rectangles, developer ID signing, ReviewMate code. Out by this design: more than one window, system notifications, undo, an Allow button after Stop, editing overrides in the app's UI.

### Requirement to module

| Requirement | Module and files | Ticket |
|---|---|---|
| 1, 14, 15 port, player, CLI, lease, version | ReviewLease, ReviewWire, ReviewCommand, ReviewApp `Player/`, `Control/` | #22 |
| 11 themes | ReviewCore `Theme/`, ReviewStore `ThemeFiles`, ReviewApp `ThemeDesk`, `UI/Palette` | #23 |
| 2, 4, 12 threads and messages | ReviewCore `VideoReview`, `ReviewThread`, `Message`, `ItemID`, ReviewStore `SupportLayout`, `Library` | #24 |
| 5, 9, 13 the send, `wait`, the outbox | ReviewCore `Send`, `SendPayload`, `Outbox`, ReviewApp `ListenerQueue`, `TranscriptDesk` | #25 |
| 9 `ack`, `status`, `reply`, `ask`, `thread answer`, `thread choose` | ReviewCore `VideoReview`, ReviewApp `ListenerQueue`, `Notice` | #26 |
| 9 the listener skill | `.agents/skills/havooch-mate/` | #27 |
| 6 pins | ReviewApp `UI/PlayerBar/` | #28 |
| 2, 3 comment popover, region | ReviewApp `UI/Stage/` | #29 |
| 8 sidebar | ReviewApp `UI/Sidebar/` | #30 |
| 7 thread popover | ReviewApp `UI/Stage/ThreadPopover`, `FrameMarks` | #31 |
| 10 header, icon, footer, notices | ReviewApp `UI/Header/`, `UI/Sidebar/SidebarFooter`, `UI/Stage/Notices` | #32 |
| acceptance | `scripts/acceptance.sh` | #33 |

## 2. Entities and relationships

Entities (hold changing state or enforce rules):

| Entity | Owns | Lives in |
|---|---|---|
| `AppModel` (orchestrator) | the open video, the open popover and its draft, the thread the sidebar shows (none for the thread list), the notices | ReviewApp |
| `PlayerEngine` | the AVPlayer, the time, playing or paused, the frame time of a moment | ReviewApp |
| `VideoReview` | one video's threads, messages and sends, and every rule about them | ReviewCore |
| `ReviewDesk` | the one path for changing a `VideoReview`: change, save, publish | ReviewApp |
| `Outbox` | pending and taken sends, the listener session, the context already sent, presence | ReviewCore |
| `ListenerQueue` | the open `wait` and `ask`s, payload assembly | ReviewApp |
| `ThemeCatalog` | the known themes and how a theme resolves to every token | ReviewCore |
| `ThemeDesk` | the active theme, the pin, the overrides, the file watch | ReviewApp |
| `Library` | loading and saving the store's JSON files | ReviewStore |
| `ControlLease` | who holds the lease, the line of waiters, the bars | ReviewLease |
| `ControlServer` | the one lease instance, dispatch of decoded requests | ReviewApp |
| `SocketListener` | the socket, each connection, the heartbeat | ReviewApp |
| `TranscriptSources`, `SpeechSource`, `TranscriptDesk` | as in proto-2 | ReviewTranscript, ReviewApp |

Fields, not entities: `Region`, `Message`, `MessageState`, `Send`, `SendRef`, `PopoverFrame`, `Holder`, `LeaseTerm`, `TranscriptLine`, `ThemeFile`, `ThemeColor`, `Settings`, `SendPayload`, `Notice`, `Draft`.

```text
AppModel ──owns──▶ PlayerEngine
AppModel ──owns──▶ ReviewDesk ──holds──▶ VideoReview ──contains──▶ ReviewThread ──contains──▶ Message
                        │                     └──contains──▶ Send ──refers to──▶ Message (by id); keeps the transcript per thread
                        └──saves through──▶ Library ──paths from──▶ SupportLayout
AppModel ──owns──▶ ListenerQueue ──holds──▶ Outbox ──refers to──▶ Send (SendRef: id + content hash)
                        ├──changes reviews through──▶ ReviewDesk
                        └──reads──▶ ContextReader, SupportLayout (image paths)
AppModel ──owns──▶ TranscriptDesk ──asks──▶ TranscriptSources        (read at send time, not at delivery)
AppModel ──owns──▶ ThemeDesk ──resolves with──▶ ThemeCatalog; ──reads──▶ ThemeFiles, Settings
SocketListener ──hands bytes to──▶ ControlServer ──holds──▶ ControlLease
ControlServer ──calls──▶ AppModel (operator and free), ListenerQueue (listener)
UI views ──read──▶ AppModel, ReviewDesk, ListenerQueue, PlayerEngine, ThemeDesk (as Palette)   ──call──▶ AppModel
```

Where each rule lives:

- "Which thread does a message at this frame join? Can this message be edited, change state, be answered?" lives in `VideoReview`.
- "What is the state of this thread?" lives in `ReviewThread.state`.
- "Which send does this `wait` get, is this a new listener, is the context due?" lives in `Outbox`.
- "Which colour does this token have now?" lives in `ThemeCatalog.resolve`.
- "May this holder drive the app now?" lives in `ControlLease`.
- "Which frame is this moment? Is a video open? What happens to the open popover when the moment changes?" lives in `AppModel`.

Module dependencies run one way (D A.7, D A.9):

```text
ReviewLease       ← Foundation only (Darwin or Glibc for the process table)
ReviewWire        ← ReviewLease
ReviewCommand     ← ReviewWire, ReviewLease, Synchronization; AppKit for the launcher only, behind #if canImport(AppKit)
ReviewCLI         ← ReviewCommand

ReviewCore        ← Foundation only
ReviewTranscript  ← Foundation, Synchronization; AVFoundation and Speech in AppleSpeechRecognizer only, behind #if canImport
ReviewStore       ← ReviewCore, ReviewTranscript; CryptoKit in ContentHash, ImageIO in ImageFiles, behind #if canImport
ReviewApp         ← all of the above, SwiftUI, AVKit, ScreenCaptureKit; macOS only
```

`ReviewCore` does not import `ReviewWire`, and `ReviewCommand` does not import `ReviewCore`: the payload, the state report and the theme list cross the socket as text in `output`. Off the Mac the package is the seven modules without `ReviewApp`.

## 3. Class design

### Folder tree

What changed from proto-2, in short:

```diff
  Sources/
-   ReviewWire/Holder.swift, LeaseTerm.swift
+   ReviewLease/Holder.swift, ProcessTable.swift, LeaseTerm.swift          (D A.7)
-   ReviewCore/Comment.swift, CommentState.swift, Batch.swift, BatchPayload.swift, ThreadMessage.swift
+   ReviewCore/ReviewThread.swift, Message.swift, MessageState.swift, Region.swift, Send.swift, SendPayload.swift
+   ReviewCore/Theme/                                                       (D 5.1 to 5.8)
+   ReviewStore/SupportLayout.swift, ThemeFiles.swift, Settings.swift      (D A.6)
+   ReviewApp/Control/SocketListener.swift                                  (D A.8)
+   ReviewApp/ThemeDesk.swift
-   ReviewApp/UI/Theme.swift, LeaseBanner.swift, Rail/, Timeline/
+   ReviewApp/UI/Palette.swift, Metrics.swift, Header/, PlayerBar/, Sidebar/
+ Packaging/Themes/                                                         built-in theme files
```

```text
Package.swift                      targets below; macOS 26; no dependencies; ReviewApp and its tests under #if os(macOS)
Makefile                           test, build, bundle, install, acceptance, agent-logos, identity, clean; reads VERSION from ReviewWire/Version.swift
Packaging/Info.plist               the bundle's template (name, bundle id, version stamped by make bundle)
Packaging/Themes/                  Default Light.json, Default Dark.json, Dimmed.json (the defaults), eight themes from popular VS Code themes (docs/research/2026-10-05-popular-vs-code-themes.md) and NOTICE.md crediting them; copied to Contents/Resources/Themes/
Packaging/AgentLogos/              the nine agent harnesses' logos as PDFs (OpenCode has a -dark file), drawn by make agent-logos
Packaging/Logo/                    the cat mark (logo v2 "Havuç") as PDFs, the full mark and the small cut, drawn by make logo; copied to Contents/Resources/Logo/
                                   from assets/images/agent-logos/*.svg, and NOTICE.md (Shipyard's attribution at 74b9695);
                                   copied to Contents/Resources/AgentLogos/
scripts/acceptance.sh              the 0.2.0 acceptance scenario, CLI only (#33, #44)
scripts/install.sh                 installs the latest release (or --from <zip>): the app, a link to its command, the mate skill; --uninstall (#49)
scripts/update-tap.sh              writes the cask's version and sha256 into the tap repository; run by the release workflow (#49)
Packaging/homebrew/havooch.rb      the cask the tap carries; version and sha256 filled in by scripts/update-tap.sh
.github/workflows/release.yml      on a v* tag: make test, make bundle, the zip and its .sha256 as a GitHub Release, then the tap
LICENSE, README.md                 MIT; what the app is, install, first launch, build from source
scripts/screenshots.sh             the 0.2.0 gallery: states/ in light and dark, themes/ the list and a thread view per built-in theme (#33, #44)
.agents/skills/havooch-mate/  the listener skill (#27)
fixtures/sample/                   the fixture video and its sidecars

Sources/
  ReviewLease/
    Holder.swift                   who sends a request: key, name, place; Holder.find (HAVOOCH_CONTROL_KEY, CLAUDE_CODE_SESSION_ID, ancestor)
    ProcessTable.swift             the process table Holder.find walks (sysctl on macOS, /proc on Linux), and its protocol
    LeaseTerm.swift                a lease held: holder, taken, ends
    ControlLease.swift             the lease rules as a pure value: use, take, release, stop, settle, giveUp, status
  ReviewWire/
    AppIdentity.swift              the app name, bundle id, support folder name ("Havooch", no suffix)
    Version.swift                  the app version "0.2.0" and the protocol version 3 (L44)
    ControlRequest.swift           every request as an enum case; its role; how long the app may hold it
    ControlMessage.swift           request plus holder as one JSON object; decode refuses another version
    ControlReply.swift             {ok, output, error, lease?, timedOut?}
    ControlProtocolError.swift     unreadable, otherVersion, unknownCommand
    TimeCode.swift                 "90", "1:30", "0:01:30.5" to seconds and back
    UnixSocket.swift               POSIX calls; the short-link address for a long path
    ControlClient.swift            one exchange over the socket, skipping heartbeat spaces; the ControlTransport seam
    ControlSocket.swift            where control.sock is; follows the demo pointer
    DemoPointer.swift              demo.json in the normal support folder
    SupportFolder.swift            the support folder; HAVOOCH_SUPPORT_DIR moves it
  ReviewCommand/
    CommandTable.swift             the commands by name, usage text, global --json
    HavoochCLI.swift               run(arguments, environment) → output, error, exit code
    AppCommands.swift              app status | open [--demo] | quit, state, --version
    ControlCommands.swift          control take [--wait] | release
    PlayerCommands.swift           player open | play | pause | seek
    CommentCommands.swift          comment add | open | compose | edit | delete, send, thread answer | choose | open | show | list, context set
    ThemeCommands.swift            theme list | set
    ScreenshotCommand.swift        screenshot <abs.png> [--appearance] [--hide-agent-indicator] [--window main|settings|about] (L42)
    ListenerCommands.swift         wait, ack, status, reply, ask
    AppLauncher.swift              starts the app through Launch Services; the AppLaunching seam
  ReviewCLI/
    main.swift                     exit(HavoochCLI.run(...))
  ReviewCore/
    ItemID.swift                   t-<hash8>-<n>, m-<hash8>-<n>, s-<hash8>-<n>: parse, make, the hash prefix;
                                   ThreadID, MessageID, SendID; ThreadRef (a full id or a bare number, L5)
    Region.swift                   x, y, w, h in 0..1 from the top left; validation; pixels in a picture
    Message.swift                  id, author, kind, text, at, region, state, sendID, sessionName (L40)
    MessageState.swift             the six states, the legal moves, editable, open
    ReviewThread.swift             id, number, time (nil for General), messages, popoverFrame, lastSeen; state; openQuestion; isUnread
    Send.swift                     id, sentAt, message ids, the transcript lines cut per thread; SendRef
    VideoReview.swift              one video's review: every rule about threads, messages and sends; the counters
    ReviewRefusal.swift            why a change is refused, as the line the CLI prints
    Outbox.swift                   the listener outbox: pending, in flight, taken, session, context sent, presence
    KnownAgent.swift               the nine agent harnesses a session's name says ("Claude Code" → claude), each one's
                                   AgentLogo (colour, light and dark, template); ListenerSession.agent (from Shipyard)
    SendPayload.swift              the JSON `wait` prints, grouped by thread, and how it is assembled
    Theme/
      ThemeToken.swift             every semantic colour token, by name
      ThemeColor.swift             a colour as "#rrggbb" or "#rrggbbaa": parse and print
      ThemeFile.swift              a theme file as decoded: name, kind, extends, tokens
      ThemeCatalog.swift           the known themes; resolve(name, overrides) → every token; the active theme for an appearance
  ReviewTranscript/                unchanged from proto-2
    TranscriptLine.swift, Transcriber.swift, TranscriptWindow.swift, TranscriptSources.swift,
    VoiceoverSource.swift, SubtitleSource.swift, SpeechSource.swift, AppleSpeechRecognizer.swift
  ReviewStore/
    SupportLayout.swift            every path under a support folder (pure), and the pending name of a picture (L19)
    Library.swift                  reviews, the outbox, recent, settings: load and save, the schema version; the hash-prefix index
    ContentHash.swift              SHA-256 of the file, streamed
    ImageFiles.swift               writing and removing a PNG at a layout path; a small copy for a row
    TranscriptFiles.swift          the finished speech transcript: load and save
    ThemeFiles.swift               read the built-in and the user theme files into ThemeFile values, with each file's path
    Settings.swift                 the pinned theme, the overrides, the sidebar width; settings.json load and save
  ReviewApp/
    HavoochApp.swift               @main; the one window, Settings (L42); the menu commands
    AppModel.swift                 the orchestrator; every action a person or an operator can take
    Draft.swift                    `AppModel.Draft`: the open popover's time, text and region (view state, never
                                   saved; its thread number is `AppModel.draftThreadNumber`); `PopoverClose`; `FrameMark`
    ReviewDesk.swift               change a review, save it, publish it
    ListenerQueue.swift            open waits and asks; delivery; payload assembly; presence; the listener's answers
    TranscriptDesk.swift           the videos opened in this run; the window's lines, read at send time
    ThemeDesk.swift                the active theme, pin and overrides; watches Themes/ and settings.json; AppModel's theme actions
    ContextReader.swift            the sidecar context file plus the note
    DemoRun.swift                  "Try the demo": the bundled sample, a demo folder under the temporary folder, the launch (L27)
    Notice.swift                   one notice: its thread, the agent's name, the words, when it fades
    Player/
      PlayerEngine.swift           AVPlayer: open, play, pause, exact seek, time, frameTime(of:)
      PlayerSurface.swift          AVPlayerView without controls
      FrameGrabber.swift           keyframe and crop PNGs from the asset, at the exact time
      Shortcuts.swift              the player's keys, off while a text field has the focus; Space and Return press a control with the keyboard focus (L45)
    Control/
      SocketListener.swift         the listening socket off the main actor; one task per connection; the 2 s heartbeat
      ControlServer.swift          decode, the lease gate, dispatch, held takes; the written/undelivered outcome
      AgentControlIcon.swift       the lease as the agent-control icon shows it
      StateReport.swift            `state` and `app status` as JSON and as lines
      ThemeReport.swift            the theme in `state`, `theme list` and `theme set`
      Screenshotter.swift          the app window, or Settings (L42), through ScreenCaptureKit, in an appearance
    UI/
      RootView.swift               stage, player bar, sidebar, header, all on the `window` surface; injects the Palette; a pinned theme's kind as the window's colour
                                   scheme; `SidebarColumn`: the threads, the composer and the footer, resizable, the width kept in settings, proto-1's spring in and out, a
                                   hairline on its leading edge; `Hairline`, one pixel of `separator`
      Palette.swift                the resolved tokens as SwiftUI colours, a `system` surface as the native one (L37), in the environment; the only way a view gets a colour
      Metrics.swift                measures: bar height (= footer height), paddings, sidebar limits; StateLook, a state's glyph and name
      SettingsView.swift           the Settings window (⌘,) with the cat mark, the name and version, and the theme picker View › Theme shares; `SettingsWindow` opens and finds it for app control (L42)
      MessageEditor.swift          the one text view messages are written in, its keys, and `MessageField`'s look with the system focus ring (L42)
      EmptyState.swift             `ContentUnavailableView` with the cat mark, "Open a Video…" and "Try the Demo", the drop target over it (L42)
      AgentMark.swift              `AgentLogoImage`, the logo loader (Contents/Resources/AgentLogos/, else Packaging/AgentLogos/);
                                   `AgentMark`, a known agent's logo at any size; `AgentAvatar`, the logo or the neutral symbol
      HavoochMark.swift            the cat mark at any size (the small cut at 32 pt and under), on the empty screen, in Settings and in the header
      AboutPanel.swift             Havooch › About Havooch: the standard About panel with the app icon and the name's story; found for `screenshot --window about`
      KeyPress.swift               `pressedByKeys(in:isFocused:action:)`: a control tells the model when it has the keyboard focus and what pressing it does, and can follow its focus to show itself (L45)
      Header/
        TitleView.swift            the cat mark at the leading edge; video icon and file name; folder icon and folder, shortened in the middle, or "Demo"
        FloatingControls.swift     the group at the top right: agent-control icon, Context, sidebar toggle
        AgentControl.swift         the icon and its popover: who, where, time left, Stop (words as a pure struct)
        ContextPopover.swift       sidecar text, the editable note, the transcript part
        TranscriptChip.swift       the transcript's source and progress as words (pure)
      Stage/
        StageView.swift            the video, the overlay, the popover, the notices
        VideoFrameGeometry.swift   view points to normalized frame coordinates and back (pure)
        RegionOverlay.swift        draw a rectangle with its size label; takes the mouse; the popover's region
        FrameMarks.swift           each thread's region outlines and number badge on the current frame
        OutsideClicks.swift        a click in the window outside the stage closes the popover as a click outside
        CommentPopover.swift       the one popover, for a new message and a thread (#29, #31): `#3 · 0:12`, ×, the
                                   conversation, a field that fills it, quiet hints; the header drags it, the corner
                                   grip resizes it; where it opens beside a region or above the bar's playhead (pure)
        ThreadPopover.swift        a thread's kept popover frame on the stage, fitted to it (pure); the conversation
                                   above the field, in the sidebar's `MessageBubble`s (#31)
        Notices.swift              the brief notices that name the thread, with the agent's logo (`AgentAvatar`)
      PlayerBar/
        PlayerBar.swift            play and pause, time / duration, speed, the timeline, the Comment button
        Timeline.swift             the track, ticks and time labels, the pins
        ThreadPin.swift            one pin: circle or rounded square, the state's colour or the question's, the hover line (pure words)
      Sidebar/
        SidebarView.swift          the thread list or the thread view, with the slide between them
        ThreadList.swift           "Threads", the summary line, the groups under pinned headers, the rows
        ThreadGroup.swift          `ThreadGroup` (Needs you, With agent, Queued, Done) and `ThreadListSummary` (pure)
        ThreadRow.swift            a row: thumbnail with regions, number, time, state, relative time, two-line preview,
                                   the right-click menu (`RowAction`); `ThreadSummary`, its words, and `RelativeTime` (pure)
        QuickReplies.swift         the open question's choices as chip buttons under it in the thread view, "Quick reply" in front;
                                   hidden while the person points at a region (#46)
        ThreadView.swift           one thread: the top bar (Back, number and time, Previous and Next), the `Conversation`
                                   (shared with the thread popover)
        ActivityLine.swift         what the agent does now (#47): `ThreadActivity` under a thread view's conversation,
                                   `ActivityLine`, the working glyph and the words
        Composer.swift             the one composer at the sidebar's foot (L41): the target line, the region chip, the
                                   General toggle, a field that grows with the words and draws the system focus ring
        MessageBubble.swift        one message as a chat (L40): the person's trailing with the quiet line, the agent's leading
                                   with its logo, the question card, the crop, edit in place, the right-click menu;
                                   `MessageWriter`, `ChatRun`, `MessageVoice`, `MessageAction` (pure), `StateChip`, `RowButton`
        SidebarPicture.swift       a keyframe or a crop read off the main actor at the size it shows, with region outlines
        SidebarFooter.swift        the presence pill and the newest live line, the queued count, Send; as tall as the player bar
        PresencePill.swift         the pill's words, the agent's name on hover and the logo in place of the glyph (pure)

Tests/
  ReviewLeaseTests/                time-driven tables; Holder.find; the real process table
  ReviewWireTests/                 version refusal, message round trips, time codes, the demo pointer
  ReviewCommandTests/              parsing, the request sent, output, exit codes; fake transport and launcher
  ReviewCoreTests/                 threads, joining, states, thread state, send, requeue, payload, outbox, theme resolution, known agents
  ReviewTranscriptTests/           the window cut, the source order, srt, vtt, voiceover (fixtures/sample)
  ReviewStoreTests/                SupportLayout, round trips, a renamed copy's hash, the hash-prefix index, theme files (Packaging/Themes)
  ReviewAppTests/                  macOS only: the server over the real socket, the heartbeat, the lease gate, AppModel on the fixture
                                   (threads, popover close rules, send), region crops at several window sizes, restarts,
                                   ThemeDesk (pin, overrides, reload on a file change), the raw-colour check of every view,
                                   every agent logo in light and dark (AgentLogoTests),
                                   the palette's system surfaces and every shipped theme's contrast as the window draws it
```

A module and a type never share a name. `ReviewThread` is not called `Thread`, which is Foundation's.

### ReviewLease

proto-1's split (D A.7): `Holder`, `ProcessTable` and `LeaseTerm` move here from proto-2's `ReviewWire`, so the lease module depends on nothing and `ReviewWire` imports it. The rules are proto-2's `ControlLease`, unchanged: `renewal` 60 s, `cap` 5 min, `bar` 5 min, the time passed into every call; `use`, `take`, `release`, `stop`, `settle`, `giveUp`, `status`, `nextEnd`; `Decision` with its transitions; `Refusal` with its line; `handover` across a relaunch in `HAVOOCH_CONTROL_LEASE`.

`Holder.find(variables, workingDirectory, processes)`: `HAVOOCH_CONTROL_KEY`, else `CLAUDE_CODE_SESSION_ID`, else the nearest ancestor process that is not a shell, as `process:<pid>@<start>`.

### ReviewWire

As proto-2, with these changes:

- `AppIdentity` has no variant: `appName` "Havooch", `bundleID` "com.yahyabedirhan.havooch", support folder `~/Library/Application Support/Havooch/` (D A.10). The name's one definition is `ControlLease.appName`, since the lease's refusals name the app and `ReviewLease` depends on nothing; `AppIdentity.appName` is that value, and the `Makefile` reads it there.
- `Version.app` is "0.2.0"; `havooch --version` prints it. `Version.controlProtocol` is 3 (L1, L44).
- `ControlRequest` follows the spec's contract:

| Role | Cases | Lease |
|---|---|---|
| free | `appStatus`, `state`, `controlTake(waitSeconds?)`, `controlRelease`, `themeList` | none |
| operator | `appOpen`, `appQuit`, `playerOpen(path)`, `playerPlay`, `playerPause`, `playerSeek(seconds)`, `commentAdd(text, at?, region?, thread?)`, `commentOpen(text, region?)`, `commentCompose(text, region?, general)`, `commentEdit(id, text)`, `commentDelete(id)`, `send`, `threadAnswer(thread, text)`, `threadOpen(thread, frame?)`, `threadShow(thread)`, `threadList`, `contextSet(text)`, `themeSet(name)`, `screenshot(path, appearance?, hideAgentIndicator, window)` | takes or renews |
| listener | `wait(timeout?)`, `ack(sendID, text?)`, `status(messageID, state)`, `reply(thread, text)`, `ask(thread, question, waitSeconds?, choices)` | none |

- A thread reference on the wire (`commentAdd.thread`, `threadAnswer`, `threadOpen`, `threadShow`, `reply`, `ask`) is a `ThreadRef`: a full thread id, or a bare number for the open video (`0` is General) (L5). The CLI sends the text as written; the server resolves it.
- `ControlClient` reads to the end; the server's heartbeat spaces before the reply are skipped as JSON allows, and a reply of spaces only is an app that went away (D A.8). Its timeout is proto-2's, applied to each read: 15 s plus the request's `holdSeconds`, and no limit for a `wait` or an `ask` with no limit. With the heartbeat no read of a healthy held request waits more than 2 s.

### ReviewCommand

As proto-2, with the spec's names and outputs:

| Command | Prints | `--json` |
|---|---|---|
| `comment add <text> [--at] [--region] [--thread]` | `m-f92cbb2a-3 queued on #2 at 0:12` (`… on the region 0.25,0.2,0.3,0.25`) | `{"message": {…}, "thread": {"id", "number"}}` |
| `comment edit <message-id> <text>` | `m-f92cbb2a-3 edited` | `{"message": {…}}` |
| `comment delete <message-id>` | `m-f92cbb2a-3 deleted` | `{"deleted": "m-…"}` |
| `comment open [<text>] [--region]` (L22) | `popover open on #1 at 0:12.5` (`… on the region 0.25,0.2,0.3,0.25`) | `{"popover": {"thread", "time", "text", "region"}}` |
| `send` | `s-f92cbb2a-1 sent: 3 messages on 2 threads, taken by the listener` (or `…, waiting for a listener`) | `{"send": {"id", "sentAt", "messageIds", "threadIds"}}` |
| `thread answer <thread> <text>` | `#1 answered` | `{"message": {…}}` |
| `thread choose <thread> <number>` | `#1 answered: <choice>` | `{"message": {…}}` |
| `thread open <thread> [--frame x,y,w,h]` (L29) | `popover open on #3 at 0:12.5` | `{"popover": {"thread", "time", "text", "region"}}` |
| `thread show <thread>` (L39) | `the sidebar shows #1` | `{"sidebar": {"thread": "t-…", "width": 340, "composer": {…}}}` |
| `thread list` (L39) | `the sidebar shows the thread list` | `{"sidebar": {"thread": null, "width": 340, "composer": {…}}}` |
| `comment compose [<text>] [--region] [--general]` (L41) | `the composer says "New thread at 0:12"` (`… with the region 0.25,0.2,0.3,0.25`) | `{"composer": {"target", "kind", "thread", "number", "time", "general", "text", "region"}}` |
| `theme list` | one line per theme: name, kind, `built-in` or `user`, `active` / `pinned` marks; then `left out: <reason>` per file left out | `{"themes": [{"name", "kind", "source", "path", "active", "pinned"}], "problems": ["…"]}` |
| `theme set <name>` | `theme Dimmed pinned`, or `theme follows the system (Default Dark)` for `system`; names match without regard to case | `{"theme": {…}}` as in `state` |
| `wait [--timeout]` | the payload JSON, with or without `--json` | same |
| `ack <send-id> [<text>]` | `s-f92cbb2a-1 acknowledged, 3 messages` | `{"send": {…}}` |
| `status <message-id> working\|done\|failed [<text>]` (#47; the text with `working` only) | `m-f92cbb2a-3 working` | `{"message": {…}}` |
| `reply <thread> <text>` | `m-f92cbb2a-7 on #2` | `{"message": {…}}` |
| `ask <thread> <question> [--choice <text>]... [--wait]` | the answer's text, exit 0; exit 2 and nothing when the wait runs out | `{"answer": {…}}` |

`wait` connects again while the app is not running, as in proto-2. Every other proto-2 rule of the command layer holds: options and words (D201), `app open` relaunch and handover, the launcher, exit 64 for wrong usage.

### ReviewCore: the thread model

```swift
public struct VideoReview: Codable, Equatable {          // one video's review
    public var video: VideoInfo                           // contentHash, title, duration, path, frameRate (as last opened)
    public var note: String                               // the in-app context note
    public private(set) var threads: [ReviewThread]       // General first, then in time order
    public private(set) var sends: [Send]                 // in the order sent
    private var counters: Counters                        // next thread number, next message n, next send n; never reused

    // the person and the operator
    mutating func write(text:, at time: Double?, region: Region?, to thread: ThreadID?, now:) throws(ReviewRefusal) -> (Message, ReviewThread)
                                                          // joins the thread at that frame time, or starts one; time nil and thread nil: General
    mutating func edit(_ id: MessageID, text:) throws(ReviewRefusal) -> Message          // queued only
    mutating func delete(_ id: MessageID) throws(ReviewRefusal) -> Message               // queued only; an empty thread goes, its number is not reused
    mutating func send(at now:, transcript: (ReviewThread) -> [SendPayload.Line]) throws(ReviewRefusal) -> Send
                                                          // every queued person message → sent; the window cut per thread; refused when nothing is queued
    mutating func answer(_ thread: ThreadID, text:, now:) throws(ReviewRefusal) -> Message   // needs an open question
    mutating func setPopoverFrame(_ thread: ThreadID, _ frame: PopoverFrame) throws(ReviewRefusal)
    mutating func markSeen(_ thread: ThreadID, at now:) throws(ReviewRefusal)           // the thread view opened: lastSeen = now (L46)

    // the listener
    mutating func acknowledge(_ send: SendID, text:, session:, now:) throws(ReviewRefusal) -> Send  // sent → acknowledged; text → General
    mutating func setState(_ message: MessageID, _ state: MessageState) throws(ReviewRefusal) -> Message   // working | done | failed, forward only
    mutating func reply(on thread: ThreadID, text:, session:, now:) throws(ReviewRefusal) -> Message
    mutating func ask(on thread: ThreadID, question:, choices:, session:, now:) throws(ReviewRefusal) -> Message  // refused while a question is open
    func choice(_ number: Int, on thread: ThreadID) throws(ReviewRefusal) -> String  // the open question's choice, from 1
    mutating func requeue(_ send: SendID) -> [MessageID]                                      // unfinished → sent

    func thread(atFrame time: Double) -> ReviewThread?
    var queue: [Message] { get }                         // queued person messages, threads in time order, then written order
    func isFinished(_ send: SendID) -> Bool
}
```

- **Joining** (D 3.1, D 3.8): `write` with a time finds the thread whose `time` equals it exactly. The time is already the frame time (`PlayerEngine.frameTime(of:)`, L2), so two moments inside one frame give the same key and one frame later gives another. With `to:` it writes on that thread, General included; a time given beside a thread is refused when it is another frame (L6).
- **A new thread** takes the next number and the id `t-<hash8>-<number>`; General is `t-<hash8>-0`, made with the review (L3). The keyframe is written before the thread exists (proto-2 D47), at `frames/<thread-id>.png`.
- **A message** is `id` (`m-<hash8>-<n>`), `author` (`person` | `agent`), `kind` (`message` | `question` | `answer`), `text` (trimmed, never empty), `at`, `region` (person messages only), `state` (person `message`s only), `sendID` (once sent) `sessionName` (agent messages only: the listener session's name when it was written, L40) and `choices` (a question's quick replies, trimmed, each once; nil with none, #46). `StateReport.Message` names `choices` only for a question with some. A region message's crop is `crops/<message-id>.png`, written before the message enters the review.
- **States**: `MessageState` is `queued`, `sent`, `acknowledged`, `working`, `done`, `failed`. `canMove(to:)` is forward only with skips; the state a message already has is accepted and changes nothing (proto-2 D122). There is no draft state (D 1.4).
- **Thread state** (D 3.9): `ReviewThread.state` is the state of the latest person `message` that is not `done` or `failed`, else of the latest person `message`, else nil. A new person message on a finished thread makes it `queued`, so active again (D 2.12) with no extra rule.
- **Questions**: `openQuestion` is the last agent `question` with no person `answer` after it. `ask` is refused while one is open; `answer` is refused with none; a `reply` does not close it.
- **The listener's reach**: `setState`, `reply` and `ask` need something sent on the thread (`notSent`); General takes `reply` and `ask` always. `acknowledge` moves each message of the send still `sent` and leaves the ones further on.
- **Popover frame** (D 2.10): `PopoverFrame` is `x, y, w, h` in normalized coordinates of the video area, nil until the person moves or resizes the popover.
- `ReviewRefusal` is `emptyText`, `unknownID(id)`, `otherVideo(id)`, `notQueued(id, state)`, `badRegion`, `nothingQueued`, `emptyMessage`, `notSent(thread)`, `illegalMove(id, from, to)`, `questionOpen(thread)`, `noQuestion(thread)`, `emptyChoice`, `noChoice(thread, number)`, `frameMismatch(thread, time)`, `noFrame` (a time or a region on General), each with its `line`.

**Ids** (D A.5): `ItemID` is `<kind>-<hash8>-<n>` with `t`, `m` or `s`, where `hash8` is the first eight hex digits of the video's content hash and `n` a counter of the review. A listener's command finds its video from the prefix (`Library.contentHash(prefix:)`), so it works after another video opens. Numbers come from the review's counters and are never given twice, so tests are deterministic with no injected ids.

### ReviewCore: the send

```swift
public struct Send: Codable, Equatable {
    public let id: SendID                                  // s-<hash8>-<n>
    public let sentAt: Date
    public let messageIDs: [MessageID]                     // threads in time order, General first; written order within a thread
    public let transcripts: [ThreadID: [SendPayload.Line]] // cut at send time (D A.4); General has none
}                                                          // kept in review.json as { "t-…-1": [lines] }; a send kept without it reads as none
public struct SendRef: Codable, Hashable { public let id: SendID; public let contentHash: String }
```

`AppModel.send()` queues the open popover's text first (as proto-2 did with a draft), then calls `VideoReview.send` with a closure that reads `TranscriptDesk.lines(around: thread.time)` for each thread in the send with a frame, and hands the `SendRef` to `ListenerQueue`. The lines are the ones the source has at that moment; every delivery, the first included, uses the kept lines and needs no transcriber (D A.4). `ReviewCore` keeps a line as its own small value, `SendPayload.Line` (`start`, `end`, `text`), so it still does not import `ReviewTranscript`; `ItemID` is `CodingKeyRepresentable`, so the map by thread is a JSON object.

### ReviewCore: the outbox

proto-2's `Outbox`, with `BatchRef` renamed `SendRef`: `pending` and `taken` lists, `session` (holder key, name, place), `contextSent` (content hash → digest), `isWaitOpen`, `openAsks`, `lastHeard`; `enqueue`, `waitOpened(by:at:)` (a new key: taken → front of pending, `contextSent` emptied), `handOut`, `written`, `undelivered`, `discard`, `finished`, `context(for:text:)`, `heard`, `askOpened`, `askClosed`, `presence(at:)` (`listening` | `working` | `absent`), `reconcile(unfinished:)`. Its rules do not change (D A.11), with one addition from proto-1 (L16): `handOut` gives the open `wait` the first pending send that is not in flight and marks it in flight (`inFlight`, send → the session key, never saved), so it stays in `pending` and no other `wait` gets it. `written` moves it from `pending` to `taken` once the reply is written, unless another session started meanwhile: then it stays in line for that session. `undelivered` only clears the mark and forgets the video's context digest, so the send keeps its place first in line. `finished` removes a send from all three.

The context is given once per listener session per video. `contextSent` is keyed by the video's content hash and holds a digest of the context text that session last got: the first send of a video in a session carries `context`, later sends of that video carry `null`, and a send carries it again when the sidecar or the note changes (a new digest) or when a new holder key starts a new session (`contextSent` emptied). A send of another video carries that video's context once too. The reason: the agent keeps what it has read for the length of its session, and the context can be long, so repeating it on every send costs the agent's context window and says nothing new; a new session is a new agent that has read nothing.

### ReviewCore: the send payload

`SendPayload.assemble(review, send, context:, images:)` builds the spec's JSON. `images` (`SendPayload.Images`) holds two closures, a thread's keyframe path and a message's crop path, which the app answers from `SupportLayout`, so `ReviewCore` needs no `ReviewStore`. `SupportLayout.keyframe(of:on:)` and `crop(of:on:)` hold the rule that General has no keyframe and only a region message has a crop; `AppModel`, `StateReport` and `ListenerQueue` all ask them.

- `threads[]` has one entry for each thread with an unfinished message in the send, General first, then in time order. A send delivered again carries only its unfinished messages.
- `transcript[]` is the send's kept lines for the thread.
- `history[]` is every message of the thread that is not in this entry's `messages[]` and not `queued`, in the order written (L7). On a first send it is `[]`.
- `messages[]` are the person messages of this send on the thread, with `region` and `cropPath` or `null`.
- `video.title` is the file name with its extension, as the header shows it (L8).
- `json` prints sorted keys, `null` for no value, times as ISO 8601.

```json
{
  "send":    { "id": "s-f92cbb2a-2", "sentAt": "2026-10-05T19:02:11Z" },
  "video":   { "path": "/abs/sample.mp4", "contentHash": "f92cbb2a…", "duration": 21.233, "title": "sample.mp4" },
  "context": null,
  "threads": [
    { "id": "t-f92cbb2a-1", "number": 1, "time": 10.017,
      "keyframePath": "/abs/demo/videos/f92cbb2a…/frames/t-f92cbb2a-1.png",
      "transcript": [ { "start": 6.067, "end": 14.333, "text": "Your comments queue up. …" } ],
      "history": [
        { "id": "m-f92cbb2a-1", "author": "person", "kind": "message", "text": "The title is cut off", "region": null, "cropPath": null },
        { "id": "m-f92cbb2a-2", "author": "person", "kind": "message", "text": "This box is too dark",
          "region": { "x": 0.47, "y": 0.27, "w": 0.29, "h": 0.15 }, "cropPath": "/abs/…/crops/m-f92cbb2a-2.png" },
        { "id": "m-f92cbb2a-5", "author": "agent", "kind": "question", "text": "Which box?", "region": null, "cropPath": null },
        { "id": "m-f92cbb2a-6", "author": "person", "kind": "answer", "text": "The left one", "region": null, "cropPath": null },
        { "id": "m-f92cbb2a-7", "author": "agent", "kind": "message", "text": "Fixed in 4e1c2aa", "region": null, "cropPath": null }
      ],
      "messages": [ { "id": "m-f92cbb2a-9", "text": "Now make it lighter still", "region": null, "cropPath": null } ] }
  ]
}
```

### ReviewCore: theme resolution

```swift
public enum ThemeToken: String, CaseIterable, Codable { … }        // the semantic tokens below
public struct ThemeColor: Codable, Equatable { r, g, b, a }        // reads and writes "#rrggbb" and "#rrggbbaa"
public struct ThemeFile: Codable, Equatable {
    public let name: String; public let kind: ThemeKind; public let extends: String?   // ThemeKind: light | dark
    public let tokens: [String: String]                            // token name → colour text, as written
}
public struct ThemeCatalog: Equatable {
    public init(builtIn: [ThemeFile], user: [ThemeFile])           // a user theme with a built-in's name replaces it
    public var names: [String] { get }
    public func resolve(_ name: String, overrides: [String: String]) throws(ThemeRefusal) -> ResolvedTheme
    public func active(pinned: String?, appearance: ThemeKind) -> String // pinned when it exists, else "Default Light" or "Default Dark"
}
public struct ResolvedTheme: Equatable { public let name: String; public let kind: ThemeKind; public let colors: [ThemeToken: ThemeColor] }
```

`resolve` walks the `extends` chain first, then the default theme of the theme's kind, then applies the overrides (D 5.2, D 5.5). A token name the catalog does not know is ignored, and a colour text that does not parse counts as missing. A chain that loops, or names a theme that does not exist, leaves that theme out of the catalog, with its reason in `problems`; resolving a name the catalog does not have is `ThemeRefusal.unknown`. Names match without regard to case. A user theme named `Default Dark` replaces the built-in one, but the built-in defaults stay the last fallback, so a partial replacement still resolves every token. The two default themes must define every token; a test proves it.

The tokens (each addition is one case and one value in each default theme). 0.2.0 put the whole window on one surface (L36) and removed `stage`, `bar`, `sidebar`, `sidebarSection`, `sidebarRowHover`, `sidebarRowSelected` and `header`, and the native buttons left `controlPressed` with no view (L43); a user theme that still sets one loads, since an unknown token is ignored. A token may carry an alpha (`#rrggbbaa`): the hover fill, the region's dim and the shadow do. A surface token (`window`, `popover`, `notice`, `field`, `separator`) may be `system`, the native macOS part; the default themes set all five so (L37).

| Group | Tokens |
|---|---|
| surfaces | `window`, `letterbox`, `popover`, `popoverBorder`, `field`, `well`, `track`, `knob`, `shadow`, `controlHover` |
| text | `textPrimary`, `textSecondary`, `textTertiary`, `textOnAccent` |
| accent | `accent`, `control` (the agent-control icon), `separator` |
| messages | `person`, `agent`, `question`, `bubblePerson`, `bubbleAgent`, `bubbleQuestion` |
| frame | `regionOutline`, `regionDim`, `badge`, `badgeText`, `sizeLabel` |
| states | `stateQueued`, `stateSent`, `stateAcknowledged`, `stateWorking`, `stateDone`, `stateFailed` |
| presence | `presenceListening`, `presenceWorking`, `presenceAbsent` |
| notices | `notice`, `noticeText` |

The default themes use natural backgrounds and pastel state colours, with no pink. Dimmed extends Default Dark with proto-2's softer background (D 5.7).

### ReviewTranscript

Unchanged from proto-2: the `Transcriber` protocol (`transcript(of:)`, `prepare`, `lines(for:in:)`), `TranscriptSources.standard(speech:)` in the order voiceover, subtitles, speech, `TranscriptWindow` (15 s each side, lines kept whole), `SpeechSource` with its `SpeechRecognizing` seam and its `@concurrent` work, and `AppleSpeechRecognizer` behind `#if canImport(Speech)`. The only change is the caller: `TranscriptDesk` is read at send time, not at delivery.

### ReviewStore

`SupportLayout` (D A.6) is a pure value that owns every path of the store; `Library`, `ImageFiles`, `TranscriptFiles`, `ThemeFiles` and the payload's `images` closure all ask it. The socket and the demo pointer stay in `ReviewWire`, since the CLI needs them and does not link the store.

```text
<support>/                               ~/Library/Application Support/Havooch/, or the demo folder
  control.sock                           while the app runs (ReviewWire)
  demo.json                              the demo pointer; only in the normal folder (ReviewWire)
  outbox.json                            the Outbox
  recent.json                            the last open video
  settings.json                          pinned theme or null, token overrides, sidebar width
  Themes/<any name>.json                 user themes
  videos/<contentHash>/
    review.json                          one VideoReview: video, note, threads, sends, counters, schemaVersion
    transcript.json                      the finished speech transcript
    frames/<thread-id>.png               a thread's keyframe, at the video's own size
    crops/<message-id>.png               a region message's crop
```

```swift
public struct SupportLayout: Sendable {
    public let root: URL
    public var outboxFile, recentFile, settingsFile, themesFolder, videosFolder: URL
    public func folder(_ hash: String) -> URL
    public func reviewFile(_ hash: String) -> URL
    public func transcriptFile(_ hash: String) -> URL
    public func keyframe(_ thread: ThreadID, of hash: String) -> URL
    public func crop(_ message: MessageID, of hash: String) -> URL
    public func pendingImage(_ token: String, of hash: String) -> URL   // frames/.pending-<token>.png (L19)
}
```

- `Library(layout:)` only loads and saves: reviews, the outbox (through `Outbox.reconcile` with the unfinished sends on disk), `recent.json` and `settings.json`. Its `init` reads every `review.json` once for the hash-prefix index (`contentHash(prefix:)`) and the unfinished sends. It writes nothing until the first save.
- Every save is atomic, pretty-printed, sorted keys, ISO 8601 with milliseconds, with `schemaVersion`. `review.json` starts at schema 1 again for this product (L9); the prototypes' files are never read, since they live in other support folders.
- A file from a newer schema, or one that does not read, is never written over (proto-2 D140).
- `ThemeFiles.read(folder)` reads the built-in themes from `Contents/Resources/Themes/` in the app (`Packaging/Themes/` in tests and in a build that is not bundled); `ThemeFiles.user(layout)` reads `Themes/`. A file that does not read is skipped with its reason.
- `Settings` is `{ theme: String?, overrides: [String: String], sidebarWidth: Double? }`, with its own `load(layout)` and `save(layout)` beside `Library`: a file the person edits by hand has no `schemaVersion`, and every key may be left out. A missing file is the defaults. A file that does not read is never written over: `theme set` is refused until it reads.

### ReviewApp

`AppModel` (`@Observable`, main actor by the module's default isolation, D A.2) is the orchestrator. Its methods are the product's actions:

| Method | Rules it owns | Refuses |
|---|---|---|
| `open(url)` | as proto-2: hash, load the review, load the video, record path and frame rate, prepare the transcript, read the context, remember as recent; closes any popover | a file AVPlayer cannot play; a review that does not read |
| `play()`, `seek(seconds)`, `togglePlay()` to play, `scrub`, `skip`, `step(frames)`, `showThread(thread)` with a frame, `addMessage` that seeks, `open(url)` | each one is a **moment change**: it first calls `closePopover(.momentChanged)` (D 2.2, D 2.3); `seek` and `open` wait until those words are queued. Pausing is none (L23) | no video; a time outside the video |
| `startDraft(region?)` | C, the Comment button, the end of a drag: pause, fix the frame time, open the popover on the thread at that frame (or the next number) with an empty draft. C over an open popover does nothing; a new region closes it as a click outside (L24) | no video |
| `closePopover(reason)` | `.clickOutside`: queue the text; `.discard` (× or Escape): drop it; `.momentChanged`: queue text at its own time and region, drop an empty draft and its region. An empty draft is only closed in every case (D 1.4). A click on the frame, the start of a drag, and `OutsideClicks` are clicks outside | |
| `openPopover(text, region?)` | `comment open` (L22): an open popover closes as a click outside, then `startDraft(region)` with `text` in the field | no video |
| `commitDraft()` | Return in the field and Queue (Answer): on a thread with an open question the text is an `answer` at once (D 2.16, L14), else it is queued; the popover stays open on its thread with an empty field and no region. A click outside, a change of the moment and Cmd+Enter answer an open question the same way (L31) | empty text |
| `addMessage(text, at?, region?, thread?)` | the CLI's path: pause, seek to `at`, snap to the frame, write the images, write the message | no video; empty text; bad time, region or thread |
| `editMessage`, `deleteMessage` | through `ReviewDesk`; delete removes the crop, and the keyframe when the thread goes | not queued; unknown id |
| `openThread(id)` | a pin, a badge, a notice, a row's frame button, `thread open` (L29): seek to the thread's frame (a moment change for a popover open on another frame; one open on this thread keeps its words), pause, select the thread, open its popover at its kept frame | General; with `thread open`, no video, an unknown thread, another video's thread |
| `showThread(id)` | a click on a row, Previous and Next (`showNeighbour`), Up and Down: the sidebar shows the thread's view (`shown`, apart from the pin's `selection`, L38), the player pauses and moves to the thread's frame (a change of the moment). `openThread` (a pin, a badge, a notice) shows its thread too; a written message does not. `showThread(ref)` is `thread show`, which answers once the player is on the frame | a thread of another video |
| `showOnVideo(id)`, `deleteQueued(on:)` | a row's menu (L40): Show on Video picks out the pin and pauses the player on the thread's frame, the sidebar stays on the list; Delete Queued Messages deletes each queued message of the thread as its Delete does (a thread left empty goes). `rowActions(for:)` says which of Open, Show on Video and Delete Queued Messages apply | General has no frame |
| `showThreadList()` | Back, Escape (after a drawn rectangle and the popover) and `thread list`: the sidebar shows the thread list; the player stays | |
| `composerTarget`, `composerText`, `composerRegion` | the composer at the sidebar's foot (L41): `ComposerTarget.resolve` (pure) from the thread shown, the General toggle, the thread of the frame on the stage and the drawn region; the text is the target's draft in `composerDrafts`, one per thread and one for a new thread | |
| `writeComposer()`, `submitComposer()` | Return in the composer: an answer at once with an open question (D 2.16), else queued on the target (a new thread at the frame, the frame's thread, General, the thread shown), with the region chip when it fits; the draft, the chip and the General toggle are spent; the player stays. `sendQueue` takes the words too; `send()` answers first | empty text; no video |
| `compose(text, region?, general)` | `comment compose` (L41): the words, a region chip on the player's frame and the General toggle in the composer, which takes the keys | no video |
| `keepSidebarWidth(width)` | the end of a drag on the sidebar's edge: the width, inside `Metrics.sidebarWidthRange`, goes to `settings.json` through `ThemeDesk.keepSidebarWidth`; `sidebarWidth` reads it back, the default 340 without one | |
| `movePopover(id, frame)` | the end of a drag or a resize: saves the `PopoverFrame` | |
| `send()` | answer with the composer's words when it answers, queue the open draft's text and the composer's, then `ReviewDesk.change { $0.send(…) }`, then `ListenerQueue.enqueue`; does nothing while a send is under way | nothing queued (`send` exits 1) |
| `answer(thread, text)` | `thread answer` and the field: through `ReviewDesk`, then `ListenerQueue.answered` | no open question |
| `choose(thread, choice:)`, `chooseAnswer` | `thread choose` and a quick-reply chip: `answer` with the open question's choice of that number | no open question; no such choice |
| `setContextNote(text)` | as proto-2 | no video |
| `setTheme(name)` | through `ThemeDesk`; `system` unpins | unknown theme |

- `Draft` is view state only: `time`, `region`, `text`. The thread it writes to is computed (`draftThreadNumber`: the thread at that frame, or the number a new thread will take). It is never saved (D 1.4). `state --json` reports it as `popover`, with that number.
- **Frame time** (L2): `PlayerEngine.frameTime(of: t)` is the start of the frame shown at `t` (from the track's nominal frame rate), raised to the next millisecond, as proto-2 raised a comment's time (D46). Every thread time goes through it, from the UI and from `--at`. The frame length comes from the nominal rate snapped to a whole or an NTSC rate (L20).
- `ReviewDesk.change(hash) { … }` is proto-2's one path for a change: load or take from memory, run, save, publish when open; a refusal or a failed save changes nothing.
- `ListenerQueue` is proto-2's with sends: `enqueue`, `wait(by:timeout:connection:)` → `Outcome` (`send(ref, payload)`, `ranOut`, `replaced`, `gone`), `written`, `undelivered`, `isDelivered`, `connectionClosed`, `ack`, `status`, `reply`, `ask`, `answered`. A send is marked `taken` only once its reply was written (proto-1's in-flight rule): until then it is kept out of every other `wait`. `ack`, `reply` and `ask` hand a `Notice` to `AppModel`; `status` raises none. `status working` with a text sets the thread's live line (`Activity`: thread, message, text, time; #47), the latest one per thread and kept in memory only; `done` or `failed` on its message, an empty text, and a new listener session clear it. `activities(at:)` and `activity(on:at:)` give nothing while the presence is absent, and `state` reports them, newest first, as `listener.activity`.
- `Notice` is `thread` (id and number), `agent`, `kind`, `words`, `expires` (5 s for every kind, a question too: the question stays open on its thread, L28). Its title is `#3 · Claude Code: …`, General's `General · Claude Code: …` (D 4.10). A click calls `openThread`, or shows General's thread view.
- `ThemeDesk` holds the `ThemeCatalog`, the `Settings` and the system appearance, and publishes the `ResolvedTheme`. The system appearance is `NSApp.effectiveAppearance`, observed, so a screenshot in the other appearance shows that appearance's default theme. `DispatchSource`s on `Themes/`, each theme file and `settings.json` reload the themes 150 ms after a change (D 5.6); the watches are made again after each reload, since an editor that saves by replacing a file makes a new one. One more on the support folder catches a `settings.json` that appears for the first time or is replaced: it reloads only when the file's number or modification date differs from the last reload's, so the outbox's and the reviews' saves there read nothing. `startWatching` makes `Themes/`, so a person finds where their themes go. A theme or settings problem is written to standard error once. `Palette` turns the resolved tokens into `Color`s, reaches every view through the environment (`@Environment(\.palette)`), and is the only colour source a view has (D 5.1); a test in `ReviewAppTests` fails on a raw colour anywhere in `Sources/ReviewApp`, and in `Palette.swift` on anything but a colour from numbers or a `system` surface (L37). The letterbox is a token too. While a theme is pinned, the window takes its kind's appearance, so the title bar and the system's controls match; with no pin it inherits the app's. `RootView` sets it with `preferredColorScheme`, never on the `NSWindow` itself: SwiftUI sets the window's appearance on each update from that preference, and an AppKit view that set it as well fought SwiftUI in an endless update loop when a light theme was pinned under a dark system. The View menu's Theme picker and the Settings window's (`ThemePicker`, L42) pin a theme or follow the system, as `theme set` does.
- `SocketListener` (D A.8, proto-1) accepts on `control.sock` (mode 0600) off the main actor, reads one request per connection, awaits `ControlServer.reply(to:)` in a task, and writes one space every 2 s while the answer is pending. A heartbeat that cannot be written tells the server the client hung up (`connectionClosed`), which ends a held `wait` or `ask` as `gone`. It then writes the reply; a reply that was written goes to the server as `written` (a send it carried is taken), and one that cannot be written as `undelivered` (L16). The heartbeat replaces proto-2's look at the connection every 0.5 s.
- `ControlServer` only decodes, checks the lease, dispatches and keeps the queued `take`s. It owns the one `ControlLease` and settles it on a timer. It depends on the `AppControlling` protocol, which `AppModel` implements and the tests fake.
- `AgentControlIcon` is the lease as the agent-control icon shows it. `AgentControlButton` (in `Header/AgentControl.swift`) is the icon, left of Context, only while an agent holds the lease, and its popover: who, where, time left, how many wait, Stop (D 4.7). The icon shows in screenshots unless `--hide-agent-indicator` (L10).
- `StateReport` builds `state --json`:

```json
{
  "app":      { "version": "0.2.0", "demo": true, "support": "/abs/demo" },
  "lease":    { "holder": {…}, "taken": "…", "ends": "…", "secondsLeft": 48, "waiting": 0 },
  "listener": { "presence": "listening", "waitOpen": true, "session": "Claude Code", "pendingSends": 0, "takenSends": 0, "activity": [] },
  "theme":    { "active": "Default Dark", "kind": "dark", "pinned": null, "appearance": "dark", "overrides": 0 },
  "video":    { "path": "/abs/sample.mp4", "contentHash": "…", "duration": 21.233, "title": "sample.mp4", "contextNote": "" },
  "player":   { "time": 10.017, "playing": false },
  "transcript": { "source": "voiceover", "complete": true, "lines": 3, "problem": null },
  "popover":  null,
  "sidebar":  { "thread": null, "width": 340, "composer": { "target": "Reply on #1", "kind": "reply", … } },
  "threads":  [ { "id": "t-f92cbb2a-0", "number": 0, "time": null, "state": null, "keyframePath": null, "unread": false, "messages": [] },
                { "id": "t-f92cbb2a-1", "number": 1, "time": 10.017, "state": "queued", "keyframePath": "/abs/…png",
                  "popoverFrame": null, "unread": false,
                  "messages": [ { "id": "m-f92cbb2a-1", "author": "person", "kind": "message", "text": "…", "at": "…",
                                  "state": "queued", "region": null, "cropPath": null, "sendId": null } ] } ],
  "queue":    [ "m-f92cbb2a-1" ],
  "sends":    [ { "id": "s-…", "sentAt": "…", "messageIds": [ "m-…" ] } ]
}
```

- `Screenshotter`, `PlayerEngine`, `PlayerSurface`, `FrameGrabber` (keyframe at the thread's time, crop cut from it in memory), `Shortcuts`, `ContextReader`, `TranscriptDesk` and `VideoFrameGeometry` keep proto-2's rules. `Shortcuts` adds proto-1's J and L (10 s back and forward) and the comma and the period (one frame), and `PlayerEngine` adds proto-1's speeds (0.5× to 2×, through `defaultRate`). proto-1's region-crop tests at several window sizes come with `VideoFrameGeometry`.

### The UI

Each choice cites its decision; the views get every colour from `Palette` and every measure from `Metrics`.

| Part | Design | From |
|---|---|---|
| Player bar | proto-1's bar: play/pause, `m:ss / m:ss`, speed, the timeline with ticks and labels, the Comment button. One `ThreadPin` per thread (not General): a rounded square when any message has a region, else a circle; the colour is the thread state's token; hover shows `#3 · 0:12 · 2 regions · Working` (`1 region`, `no region`). A queued pin is a ring; a later state fills it, with the state's glyph in `textOnAccent`. While the thread has an open question (`ReviewThread.openQuestion`), the pin is filled in the `question` token with a `questionmark` glyph, its stem takes that colour, and the hover line ends `Question waiting` in place of the state; the answer gives the pin its state back (L35). A click calls `select`. Its height is `Metrics.barHeight`, which the sidebar footer shares. | D 1.1, D 1.3, D 1.6 |
| Region | proto-2's drag selection with proto-1's live `412 × 236` size label in frame pixels; the popover header names the thread number it writes to. | D 2.1, D 2.4 |
| Comment popover (#29) | proto-2's `Composer` (`CommentPopover` since L41) with 8 pt padding, a field across its whole width, `#3 · 0:12` (whole seconds, as the bar) and ×, quiet `textTertiary` key hints. On a moment its notch points at the player bar's playhead (`trackArea`, L25); on a region it sits beside the rectangle. | D 1.2, D 1.7, D 1.8 |
| Frame marks | On the current frame, while paused or playing: each thread's region outlines and one number badge per thread (at its first region's corner, or the frame's top-left corner for a thread without a region). A badge click is `openThread`. Nothing opens by itself. | D 2.6, D 2.11 |
| Thread popover | One component for a new message and for an existing thread: header `#3 · 0:12` and ×, the conversation (empty for a new thread) above a field that fills the width, quieter key hints, less padding than proto-2. Drag by its header, resize from its corner, inside the video area; the end of either saves the frame (only on an existing thread, L30). Opens at its kept frame, fitted to the stage (L32), else beside the draft's region or the thread's first region, else above the playhead. | D 1.2, D 1.7, D 1.8, D 2.7 to D 2.10 |
| Sidebar | Two views (L38). The thread list: the title "Threads" and a summary line (`6 threads · 1 needs you · 2 queued`), then the groups Needs you, With agent, Queued, Done under headers with a glyph and a count that stay at the top while the list scrolls; Queued's says `⌘↩ sends them all`. A `ThreadRow`: an 88 × 50 pt keyframe thumbnail with its region outlines (a globe for General), the number and time, the state chip, the relative time, a chevron, and a two-line preview that names the writer (`You:`, `Asks:`, the agent), led by the agent's logo (or the sparkle) on an agent's message. An unread row (L46) has an 8 pt `accent` dot at its left, straddling the row's edge on the first line, its title bold, its preview in `textPrimary` and its time in `accent`; VoiceOver reads `Unread` first. A right-click on a row offers Open, Show on Video (not General) and Delete Queued Messages (when it has any), L40. Tab under keyboard navigation reaches each row, with the system focus ring, and Space or Return opens it (L43, L45). The thread view: a 44 pt top bar (Back with the count of the other threads that need the person, the number and time, Previous and Next), the conversation as a chat (L40) from the newest, and the field at the foot (answer at once when a question is open, else queue); no keyframe. The view slides in from the trailing edge with the sidebar's spring, a fade with Reduce Motion. On the window's surface (L36): a row under the pointer takes `controlHover`, the row of the thread on the stage sits in a `well`, no cards. Resizable between the bounds of `Metrics.sidebarWidthRange` (300 to 460), width kept in `settings.json`, proto-1's animation for open and close. | D 3.1, D 3.2, D 3.7, D 4.5, D 5.10; replaces D 3.3, D 3.5, D 3.6 (spec 0.2.0) |
| Conversation | A chat (L40), from variant 02. The person's messages trailing, 46 pt in from the leading side, in `bubblePerson` (16 pt corners, a 5 pt corner at the trailing foot for the tail), no avatar; a quiet line under the bubble holds the state chip (an answer: `Answer · sent at once` in `question`), the `Region` tag in `regionOutline` and the time. A queued message: a dashed `stateQueued` outline, `controlHover` on hover, Edit and Delete beside it on hover, edited in place (Return saves, Escape cancels). An answer: `question` at 15% with a 40% border. The agent's messages leading, 34 pt in from the trailing side, in `bubbleAgent` (the tail at the leading foot); the 24 pt avatar (the harness logo, else the sparkle) beside the last bubble of a run, the name (`agent`) and time over the first. A question: a card in `bubbleQuestion` with a `question` border at 32%, headed `<agent> asks`; an answered one at 80% opacity. A region message's crop under its bubble. Messages 8 pt apart, 4 pt inside a run of the agent's. The name and logo are the message's `sessionName`, else the listener's. A right-click: Edit, Delete (queued only), Copy. VoiceOver reads one element per message: writer, kind, state, words (`MessageVoice`), with the menu's actions. The thread popover shows the same `Conversation`. In the thread view only, an open question with choices has a row under it: `Quick reply` in `textTertiary`, then one capsule chip per choice in `question` at 12% (22% on hover) with a 45% border, wrapping; a click answers at once. The row hides while a rectangle is drawn and while a drawn one is in the composer (`isPointingAtRegion`), #46. | D 3.4 replaced (spec 0.2.0) |
| Composer | Variant 02's composer at the sidebar's foot, above the footer, under a hairline (L41): a 22 pt target line (glyph, "New thread at 0:12", "Reply on #3", "Follow up on #3", or "Answer #3 · goes at once" in `question`), the `regionOutline` region chip with its ×, and in the list the General toggle (native borderless). The field: `field` with a `separator` border (`question` for an answer), 15 pt corners, the keys at its trailing foot, the system focus ring round the whole field; it grows from one line to about six. | L41 |
| Footer | proto-3's line: presence pill (`Listening`, `Working`, `No listener`; hover names the agent), the queued count, Send. Same height as the player bar, a `separator` hairline above it inside that height (L36). | D 4.8, D 4.9 |
| Header | Title: video icon, full file name with extension. Subtitle: folder icon, the folder shortened in the middle, full path on hover, "Demo" in demo mode. Floating group at the top right: agent-control icon (while held), Context, sidebar toggle. proto-2's Context popover. The title is a toolbar item with no shared background; the band is the `window` token, or the native toolbar when `window` is `system` (L26, L36, L37). | D 4.1 to D 4.4, D 4.7 |
| Notices | Top right of the stage, name the thread, open it on click, fade after 5 s, a question's too (L28). | D 4.10 |
| Structure | One surface, `window`, for the header, the stage, the player bar, the sidebar and its footer, native in the default themes (L37); `separator` hairlines on the sidebar's leading edge and above the footer; bubbles only for messages; no bordered cards. | L36, L37, replaces D 5.9 |
| Empty screen | The native `ContentUnavailableView` with the cat mark, "Open a Video…" and "Try the Demo" (opens the bundled fixture in a demo folder under the user's temporary folder, L27). The whole stage is the drop target; a dashed accent outline shows over it while a file is over it (L42). | D 5.11 |

### The listener skill

`.agents/skills/havooch-mate/SKILL.md` stays one file. For threads:

```text
on a send     `ack <send-id> "<line>"`, then a new background `wait`
per thread    read the keyframe, the crops, the transcript, history[] and the context
per message   `status working "<what you do now>"`, again at each step → the work → one commit when files changed, its body ending `Havooch-Message: <message-id>`
              → `reply <thread-id>` with the short SHA → `status done`
              cannot be done: `reply <thread-id>` with the reason → `status failed`
unclear       `ask <thread-id>` in the background; the next thread goes on
whole send    `reply t-<hash8>-0` (General) with one line
```

## 4. Implementation

### The methods that carry the logic

Writing a message (the UI and `comment add` meet in `AppModel.addMessage` and `commitDraft`):

```text
AppModel.addMessage(text, at, region, thread)
  require a video and words
  target  = thread ref → ThreadID (number of the open video, or a full id of the open video)   else refused
  time    = frameTime(at) ?? target's time (nil for General) ?? frameTime(player.time)   // the thread key
  a trial write on a copy of the review: every refusal comes here, before the player moves (L6)
  pause; seek(time) when there is one (a moment change: closePopover(.momentChanged))
AppModel.queueMessage(text, time, region, thread)                    // also the popover's path
  planned = trial write                                              // starts a thread? which frame?
  FrameGrabber.writeImages(frame) → frames/.pending-<token>-keyframe.png (a new thread),
                                    frames/.pending-<token>-crop.png (a region)          // @concurrent
  written = desk.change { try $0.write(text:, at: time, region:, to: target, now:) }     // no await from here on
  move the pending keyframe to frames/<thread id>.png when the thread has none,
  the pending crop to crops/<message id>.png (a crop that can't be moved deletes the message again)
  remove what's left pending
```

Closing the popover:

```text
AppModel.closePopover(reason)
  guard let draft
  draft.text empty                → drop the draft (and its region); done
  reason == .discard              → drop the draft; done
  reason == .clickOutside / .momentChanged
                                  → write(draft.text, at: draft.time, region: draft.region, to: draft.thread)   // its own moment
  popover = nil
```

Sending and delivering:

```text
AppModel.send()
  closePopover(.clickOutside)                                         // the open text is queued first
  send = desk.change { try $0.send(at: now, transcript: { transcripts.lines(around: $0.time, of: video) }) }
  listeners.enqueue(SendRef(send.id, hash))

ListenerQueue.wait(holder, timeout, connection) async -> Outcome
  requeued = outbox.waitOpened(by: holder, at: now)                   // a new key: taken → front of pending; contextSent cleared
  for ref in requeued: desk.change(ref.hash) { $0.requeue(ref.id) }   // unfinished → sent
  resume an older open wait with .replaced
  if let outcome = takeNext(): return outcome
  if timeout == 0: return .ranOut
  suspend; start the timeout when there is one

ListenerQueue.takeNext()
  while a wait is open and a send is first in line and not in flight
    review unreadable, or nothing unfinished: outbox.discard; next
    context = outbox.context(for: ref.hash, text: ContextReader.text(for: review))   // nil when sent unchanged
    payload = SendPayload.assemble(review, send, context, images: layout paths)
    outbox.handOut (in flight); return .send(ref, payload)

SocketListener   writes the payload → server.written(ref) → outbox.written (pending → taken)
                 the write fails   → server.undelivered(ref) → back in line, the video's digest forgotten
```

Answering on a thread:

```text
ListenerQueue.ask(thread, question, waitSeconds, connection) async -> Asked
  outbox.heard; hash = library.contentHash(prefix: thread.hash8)      else refused: unknown id
  desk.change(hash) { try $0.ask(on: thread, question:, now:) }       // refused while a question is open
  announce a notice "#n · Claude Code: <question>"
  waitSeconds == 0 → .ranOut; else outbox.askOpened; suspend under the thread id
AppModel.answer(thread, text)                                         // the field, or `thread answer`
  message = desk.change(hash) { try $0.answer(thread, text:, now:) }
  listeners.answered(thread, message)                                 // the ask exits 0 with the text
```

Edge cases:

- `comment add --thread 3 --at 0:15` where #3 is at 0:12: refused (`frameMismatch`) before any image is written (L6).
- `comment add --thread t-0a1b2c3d-2` while another video is open: refused (`otherVideo`). Listener commands work on any video; operator writes need the open one.
- `comment delete` on the only message of thread #4: the thread and its keyframe go; the next thread is #5 (L4).
- `status m-… done` twice: the second changes nothing and answers as the first.
- A person message on a done thread: the thread is `queued` again; its pin turns the queued colour.
- The moment changes with an empty popover over a drawn region: the draft and the region go; no thread is made.
- `send` with nothing queued: exit 1, no send. Cmd+Enter with nothing queued does nothing.
- An answer typed in the sidebar field while the thread's question is open: it is an `answer`, it never enters the queue, and the waiting `ask` exits at once.
- A `reply` on a thread whose only messages are queued: refused (`notSent`). On General: accepted.
- Speech still transcribing at send time: each thread keeps the lines that exist then; a redelivery gives the same lines.
- `theme set Purple` with no such theme: exit 1, `no theme Purple; havooch theme list names them`.
- A user theme file is saved with a syntax error: the catalog leaves it out; when it was active, the app falls back to the default of the appearance and `state` reports the active name.

### Trace 1: a CLI command, `comment add` on a region

Start: the app runs on demo data with the fixture open, paused at 10.0 s. Thread #1 is at frame time 10.017 with one queued message `m-f92cbb2a-1` and no region. The lease is free. The caller is a Claude Code session.

Command: `havooch comment add "This box is too dark" --region 0.47,0.27,0.29,0.15`

```text
ReviewCLI/main.swift                   HavoochCLI.run(["comment","add",…], environment)
ReviewCommand/CommandTable.swift         `comment add` → CommentCommands.add
ReviewCommand/CommentCommands.swift      --region → ControlRequest.Rectangle(0.47,0.27,0.29,0.15)   (not four numbers: exit 64)
ReviewLease/Holder.swift                 Holder.find → "CLAUDE_CODE_SESSION_ID=…", "Claude Code", the working folder
ReviewWire/ControlSocket.swift           demo.json → the demo's control.sock
ReviewWire/ControlClient.swift           writes {"command":"comment.add","holder":{…},"region":{…},"text":"…","version":3}, half-closes
ReviewApp/Control/SocketListener.swift   reads to the end; task awaits ControlServer.reply(to:); heartbeat armed
ReviewApp/Control/ControlServer.swift    decode: version 2 = 2 → .commentAdd(text, at: nil, region, thread: nil)
ReviewLease/ControlLease.swift           use(by: holder, at: 12:00:00) → started, ends 12:01:00      state: the agent-control icon shows
ReviewCore/Region.swift                  Region(0.47,0.27,0.29,0.15): inside 0..1 → valid
ReviewApp/AppModel.swift                 addMessage: video open; no seek; pause
ReviewApp/Player/PlayerEngine.swift      frameTime(of: 10.0) → 10.017 (frame 300 at 29.97 fps, raised to the ms)
ReviewCore/VideoReview.swift             thread(atFrame: 10.017) → #1 (t-f92cbb2a-1); its keyframe exists
ReviewApp/Player/FrameGrabber.swift      crop → crops/m-f92cbb2a-2.png (557 × 162 of the 1920 × 1080 keyframe)
ReviewStore/SupportLayout.swift          crop(m-f92cbb2a-2, of: f92cbb2a…) → <demo>/videos/f92cbb2a…/crops/m-f92cbb2a-2.png
ReviewApp/ReviewDesk.swift               change { write(text, at: 10.017, region, to: nil, now) }
ReviewCore/VideoReview.swift               appends m-f92cbb2a-2 (person, message, queued, region) to #1
ReviewStore/Library.swift                  review.json written
                                         state: #1 has 2 queued messages; its pin turns a rounded square; queue = [m-1, m-2]
ReviewApp/Control/ControlServer.swift    done("m-f92cbb2a-2 queued on #1 at 0:10 on the region 0.47,0.27,0.29,0.15")
ReviewApp/Control/SocketListener.swift   heartbeat stopped; reply written; connection closed
ReviewCommand/HavoochCLI.swift           prints the line, exit 0
```

The rejection: five seconds later another holder runs `havooch comment add "x"`.

```text
ControlLease.use(by: other, at: 12:00:05) → .inUse(term); nothing reaches AppModel
reply {"ok":false,"error":"Havooch is in use by Claude Code in /…/repo until 12:01:00 (55s left); `havooch control take --wait <seconds>` to queue"}
CLI: the line on standard error, exit 1
```

A CLI of a prototype build sends `"version": 1`: `decode` refuses it before the lease is asked, naming both versions.

### Trace 2: a send, from Cmd+Enter to `wait`, then a follow-up

Start: after Trace 1, the person seeks to 0:15 and draws a region; thread #2 starts at 15.015 with `m-f92cbb2a-3` (region). The queue is `m-1`, `m-2` (#1) and `m-3` (#2). A listener session L1 has `havooch wait` open and has not had this video's context. Its outbox: `session = L1`, nothing pending or taken.

```text
ReviewApp/Player/Shortcuts.swift         Cmd+Return → AppModel.send()
ReviewApp/AppModel.swift                 closePopover(.clickOutside): no draft
ReviewApp/TranscriptDesk.swift           lines(around: 10.017) → 2 voiceover lines; lines(around: 15.015) → 2 lines
ReviewApp/ReviewDesk.swift               change { send(at: 19:02:11Z, transcript:) }
ReviewCore/VideoReview.swift               m-1, m-2, m-3 queued → sent, sendID s-f92cbb2a-1; transcripts kept for #1 and #2
ReviewStore/Library.swift                  review.json written
                                         state: queue = []; both pins the sent colour; footer "0 queued"
ReviewApp/ListenerQueue.swift            enqueue(s-f92cbb2a-1): pending = [s-1]; outbox.json written; takeNext()
ReviewCore/Outbox.swift                    context(for: hash, text): no digest this session → the text; digest recorded
ReviewApp/ContextReader.swift              sample.context.md (+ the note)
ReviewCore/SendPayload.swift               threads: #1 (history [], messages m-1, m-2), #2 (history [], messages m-3);
                                           keyframes and crops as absolute paths; transcript as kept
ReviewApp/Control/SocketListener.swift   the held wait resumes; payload written → written(s-1)
ReviewCore/Outbox.swift                    written: pending = [], taken = [s-1]          state: presence working; pill "Working"
ReviewCommand/ListenerCommands.swift     prints the payload, exit 0
```

Then, as the listener: `ack s-f92cbb2a-1 "On it"` moves m-1..m-3 to `acknowledged` and writes the agent message `m-4` on General (notice `General · Claude Code: On it`). `ask t-f92cbb2a-1 "Which box?"` writes `m-5` (question) on #1 and holds; `thread answer t-f92cbb2a-1 "The left one"` writes `m-6` (answer) and the `ask` exits 0 with it. `reply t-f92cbb2a-1 "Fixed in 4e1c2aa"` (`m-7`), `reply t-f92cbb2a-2 …` (`m-8`), and `status … done` on m-1, m-2 and m-3 finish the send: `Outbox.finished(s-1)`, both pins the done colour.

The follow-up:

```text
operator: comment add "Now make it lighter still" --thread t-f92cbb2a-1
ReviewApp/AppModel.swift                 addMessage: seek to #1's time 10.017 (a moment change; no popover open); pause
ReviewCore/VideoReview.swift             write on #1: m-f92cbb2a-9 queued              state: #1 is queued again (D 2.12)
operator: send
ReviewCore/VideoReview.swift             send s-f92cbb2a-2: [m-9]; transcript for #1 cut again now
ReviewApp/ListenerQueue.swift            the listener's next wait: deliver s-2
ReviewCore/Outbox.swift                    context(for: hash, text): same digest for L1 → nil
ReviewCore/SendPayload.swift               threads: #1 only; history = m-1, m-2, m-5, m-6, m-7 in order; messages = [m-9]; "context": null
```

The rejections:

```text
comment edit m-f92cbb2a-1 "new text" after the send
  VideoReview.edit → m-1 is sent → ReviewRefusal.notQueued → exit 1, nothing saved

the listener restarts as session L2 while s-2 is taken and m-9 is working
  Outbox.waitOpened(by: L2): a new key → s-2 to the front of pending; contextSent emptied
  VideoReview.requeue(s-2): m-9 working → sent
  takeNext(): L2 gets s-2 with m-9, its kept transcript, the same history, and the context again
```

### Build and tests

- `Package.swift`: tools 6.2, macOS 26, no dependencies; `ReviewApp` uses `.defaultIsolation(MainActor.self)`; explicit `@MainActor` marks that the default makes redundant are removed (D A.2). `ReviewApp`, `ReviewAppTests` and the `HavoochApp` product are added under `#if os(macOS)` (D A.9).
- `make bundle` stamps `Havooch`, the bundle id and `0.2.0` into `Info.plist`, copies the app icon (`assets/images/logo/v2-havuc/AppIcon-light.icns`, `CFBundleIconFile`) to `Contents/Resources/AppIcon.icns` and `Packaging/Logo/` to `Contents/Resources/Logo/`, copies `Packaging/Themes/` to `Contents/Resources/Themes/`, `Packaging/AgentLogos/` (the logo PDFs and their `NOTICE.md`) to `Contents/Resources/AgentLogos/` and `fixtures/sample/` to `Contents/Resources/Demo/` (L17), and signs ad hoc. `make install` installs `/Applications/Havooch.app` and never touches the prototype apps; with `HAVOOCH_SUPPORT_DIR` set it opens the app on that folder.
- A release is a `v<version>` tag; the tag must match `Version.app`. `.github/workflows/release.yml` reads the name, the command and the version through `make identity`, zips the bundle with `ditto -c -k --keepParent` as `<command>-<version>.zip` with `<command>-<version>.zip.sha256` beside it, and publishes both. `scripts/install.sh` reads the app and command names from the zip, never from a constant; it finds an installed copy for `--uninstall` by the bundle id `com.<repository owner>.<command>`. The app is ad-hoc signed and not notarized, so the first launch needs Open Anyway (#49).
- Owner tests, one per contract at its strongest boundary:

| Contract | Owner test |
|---|---|
| version refusal, wire round trips | `ReviewWireTests` |
| the lease rules, the holder key order | `ReviewLeaseTests` |
| CLI parsing, output, exit codes | `ReviewCommandTests` |
| joining, thread numbers, states, thread state, send, transcript kept, requeue, payload shape, outbox, context once per session | `ReviewCoreTests` |
| theme resolution: extends, fallback, overrides, loops, the defaults define every token | `ReviewCoreTests`, `ReviewStoreTests` (the shipped files) |
| the window cut, the source order | `ReviewTranscriptTests` |
| paths, round trips, the hash-prefix index | `ReviewStoreTests` |
| popover close rules, frame time, the send through `AppModel` | `ReviewAppTests` on the fixture |
| the server, the heartbeat, a gone client | `ReviewAppTests` over the real socket |
| the listener's round: ack, status, reply, ask and answer, a follow-up, a listener restart | `ReviewAppTests` over the real socket (`ListenerSocketTests`) |
| region crops at several window sizes | `ReviewAppTests` (proto-1's) |
| what a restart keeps | `ReviewAppTests`, a second `AppModel` on the same support folder |
| everything end to end | `scripts/acceptance.sh`, the spec's 10 steps against the installed app in demo mode |

## 5. Extensibility

| Change | What you touch |
|---|---|
| A new CLI command | a case in `ControlRequest`, a parser in `ReviewCommand`, a branch in `ControlServer`, a method on `AppModel` or `ListenerQueue`. The compiler finds the two `switch`es. |
| A new UI action | a method on `AppModel`, then its CLI command (ADR 0001). |
| A new colour token | one `ThemeToken` case and its value in the two default theme files; the test of the defaults fails until both have it. |
| A new built-in theme | one JSON file in `Packaging/Themes/`. |
| Fonts or spacing in themes (after 0.1.0) | a second map in `ThemeFile` and `ResolvedTheme`; `Metrics` reads it as `Palette` reads colours. |
| A better transcription source | one `Transcriber`, one line in `TranscriptSources.standard`. |
| A new field in the payload | `SendPayload` and `assemble`. |
| A new message state | `MessageState`, `canMove`, a `state…` token. |
| A rule for a listener that never comes back (D A.11) | `Outbox.waitOpened` and a time check in `Outbox.presence`; nothing outside the outbox. |
| The popover redesign (D 1.8) | `ThreadPopover`, `CommentPopover.placement` and `StageView.Placement` only; the close rules stay in `AppModel`. |
| A database in place of JSON files | `Library` only. |

Refused for now: more than one listener or window, undo, an Allow button, system notifications, a plug-in registry of commands.

## 6. Decisions the spec left open

| # | Decision | Reason |
|---|---|---|
| L1 | The protocol version is 2 (3 since L44). | The requests changed shape (`send`, `--thread`, thread ids). A prototype's CLI that reaches this app is told to reinstall, not given a wrong answer. |
| L2 | A thread's key is the frame's start time from the nominal frame rate, raised to the next millisecond (`PlayerEngine.frameTime`). | "The exact frame" (D 3.8) must be one number for two moments inside one frame, from the UI and from `--at`. Raising, not rounding, keeps proto-2's D46 rule. |
| L3 | The thread id carries its number: `t-<hash8>-<number>`, General `t-<hash8>-0`. Messages and sends count on their own (`m-<hash8>-<n>`, `s-<hash8>-<n>`). | The id a listener holds and the `#n` the person sees are the same thing. One counter per kind keeps ids short and deterministic. |
| L4 | A thread whose last message is deleted goes away; its number is not reused. | An empty thread has nothing to show. A reused number would make an old reference point at another frame. |
| L5 | `--thread`, `thread answer`, `reply` and `ask` take a full thread id or a bare number of the open video. | The spec's `--thread 0` for General is a number. Full ids keep listener commands working after another video opens (D A.5). |
| L6 | `comment add --thread <id> --at <time>` is refused when the time is another frame than the thread's. Without `--at`, `--thread` seeks to the thread's frame. | A message must never join a thread of another frame (D 3.1). The operator does what the person does: writing on a thread shows its frame. |
| L7 | `history[]` is every message of the thread that is not in this send's `messages[]` and not queued, in order, also agent messages written after an earlier delivery. | "The conversation so far" (D 2.15). A redelivery then includes the agent's own partial replies. |
| L8 | The payload's and the state's `video.title` is the file name with its extension. | One title everywhere, as the header shows it (D 4.1). Replaces proto-2's D23. |
| L9 | Store files start at `schemaVersion` 1 again. The prototypes' data is never migrated. | Different support folders; the spec asks for no migration. |
| L10 | The agent-control icon shows in screenshots by default, as the person sees the window. `screenshot --hide-agent-indicator` leaves it out. | The maintainer's decision, which replaces proto-2's D28 (the icon left out unless `--with-control-icon`). The option is an addition to the contract. |
| L11 | Theme resolution lives in `ReviewCore/Theme/`, theme files in `ReviewStore`, the watch and the `Palette` in the app. The built-in themes are JSON files in `Packaging/Themes/`, copied into the bundle's resources. | The spec keeps eight targets and wants the resolution unit-tested without the app, on Linux. Plain files in the bundle avoid SwiftPM resource bundles and are examples for user themes. |
| L12 | Settings live in `settings.json`: the pinned theme (`null` follows the system), the overrides, the sidebar width. `theme set system` unpins. The app watches it beside `Themes/`. | The contract has one `theme set`; one word must return to the default (D 5.4). Overrides are edited in the file, so the file must reload. |
| L13 | Thread state with no person message (General with only agent messages) is no state; General has no pin. | D 3.9 defines state from person messages only. General has no keyframe to pin. |
| L14 | The open popover's field answers at once when the thread has an open question, else it queues. | D 2.16 and D 3.6 for one field, with no second control. |
| L15 | (Replaced by L46.) No unread marks. A notice and the thread's state carry the news. | The spec names none. proto-2's unread set was in memory only. |
| L16 | A send is marked `taken` only after its reply was written; until then it is in flight and no other `wait` gets it. | proto-1's rule, which pairs with the heartbeat of D A.8: a dead listener never loses a send. |
| L17 | "Try the demo" opens the fixture bundled in the app in a demo folder under the user's temporary folder. | The empty screen needs a demo with no command line (D 5.11), and demo data must never mix with the person's. |
| L18 | Notices for General say `General · <agent>: …` and show General's thread view on click (L38). | General has no frame to open (D 4.10). |
| L19 | A message's pictures are written under a pending name in `frames/` and renamed to `frames/<thread-id>.png` and `crops/<message-id>.png` once the review gave the ids. | The ids come from the review's counters, and a listener's `reply` written while the frame is read takes the next message number. Predicted names could be taken or overwritten; a rename on the main actor right after the write can't. |
| L20 | `PlayerEngine` snaps the track's nominal frame rate to a whole rate or an NTSC rate (n × 1000 / 1001) when it is within 0.001 of one. | AVFoundation gives the rate as a `Float` a hair off (29.999998 for 30), which put 10.0 s in the frame before. |
| L21 | `--thread 0` with `--at` or `--region` is refused (`noFrame`); without `--thread` a message always has a frame time. | General has no keyframe, so a time or a region on it means nothing. |
| L22 | `comment open [<text>] [--region x,y,w,h]` opens the comment popover at the player's frame, as C or a drawn rectangle does. An operator command, an addition to the contract. | The CLI cannot click or draw. Without it the popover, a drawn region and the close rules can't be shown, checked or screenshotted in the real app. |
| L23 | Pausing is no change of the moment: the popover stays open. | The popover only opens on a paused frame, so a pause changes no frame (D 2.3 lists seek, scrub, play, timeline click, frame step). |
| L24 | A drag on the frame with the popover open is a click outside it: the words are queued on their region, or an empty popover goes, and the new rectangle opens a new popover. | D 1.4 for every click outside. proto-2 moved the open popover to the new region instead. |
| L25 | The popover on a moment points at the playhead on the player bar's track, whose frame in the window the bar reports (`AppModel.trackArea`). | The bar's track sits between its buttons, not under the stage's whole width. |
| L26 | (Replaced by L36: the band is `window`.) The `header` token paints the window's toolbar band (`toolbarBackground`), behind the title and the floating group. | The token was in the palette with no view; the header is a surface of its own, and a theme may set it apart from `window` (the built-in themes keep them equal). |
| L27 | "Try the demo" on a run on the person's data starts a new copy of the app on `<temporary folder>/Havooch Demo`, with `HAVOOCH_OPEN_VIDEO` naming the bundled `Contents/Resources/Demo/sample.mp4`, records the demo pointer, and quits. A demo run opens the video itself. | The support folder is fixed for a run, and demo data must never mix with the person's (L17). The pointer lets `havooch` reach the demo copy as after `app open --demo`. |
| L28 | Every notice fades after 5 s, a question's too. The question stays open on its thread and in `state`. | D 4.10 says a notice fades; a question that stayed over the video had no way to close but a click (the 0.1.0 acceptance run). |
| L29 | `thread open <thread> [--frame x,y,w,h]` opens a thread's popover on its frame, as a click on its pin or badge does; `--frame` first keeps the popover at that rectangle of the video area, as a drag and a resize leave it. An operator command, an addition to the contract. | The CLI cannot click, drag or resize. Without it the thread popover, its kept frame and its persistence can't be shown, checked or screenshotted in the real app. |
| L30 | Only a popover on an existing thread drags and resizes. A popover that will start a thread opens at its placement and gets the handles once its first message is queued. | The frame is kept per thread (D 2.10); before the first message there is no thread to keep it on, and a frame held in the draft would be lost on every close. |
| L31 | Words in the popover on a thread with an open question are an answer however they leave it: Return, a click outside, a change of the moment, Cmd+Enter. | L14 names one field; a click outside that queued the words instead would leave the agent's question waiting while the words sit in the queue. |
| L32 | The video area of a `PopoverFrame` is the stage (the video with its letterbox). A kept frame is fitted on screen: at least 280 × 190 pt, at most the stage, 8 pt inside its edges. | The popover moves over the whole stage, not only the picture; normalized to the stage, it lands in the same place at any window size and is never lost off screen or too small to use. |
| L33 | (Replaced by L38: the sidebar shows a thread view or the list.) The sidebar's one expanded thread is `AppModel.expanded`, apart from the pin's `selection`. A row click, `thread expand`, and every way the thread popover opens (a pin, a badge, the keyframe, a notice) expand a thread; a message written selects its pin but leaves every thread collapsed. | D 3.3 says collapsed by default and expand on a click. A message written from the popover or the CLI expanding its thread scrolled the sidebar away from General each time. |
| L34 | (Replaced by L39: `thread show` and `thread list`.) `thread expand <thread>` expands a thread of the open video in the sidebar, as a click on its row does. An operator command, an addition to the contract. | The CLI cannot click. Without it an expanded thread can't be shown, checked or screenshotted in the real app. |
| L35 | A thread with an open question draws its pin in the `question` token with a question mark, keeping its shape, and its hover line says `Question waiting`; the answer gives the pin its state colour back. Every built-in theme keeps `question` at least 10 apart (CIE76) from each state colour and at 3:1 on the bar (the `window` surface since L36), which a test checks; Default Light's `question` went from `#4f918f` to `#4a8a88` for it. The maintainer chose it. | The person sees from the timeline alone that the agent waits for an answer. It replaces the earlier rule that a pin's colour is the thread state only. |
| L36 | The whole window is on one surface, `window`: the header (the toolbar band), the stage, the player bar, the sidebar and its footer. A `separator` hairline, one pixel, is on the sidebar's leading edge and above the footer, inside the footer's height, so the footer stays as tall as the player bar. A sidebar row under the pointer takes `controlHover`; the row of the thread on the stage sits in a `well`. The tokens `stage`, `bar`, `sidebar`, `sidebarSection`, `sidebarRowHover`, `sidebarRowSelected` and `header` are gone from the token list and the built-in themes; `stage` and `sidebarRowHover` went with the five the spec names, since nothing drew them any more. | Spec 0.2.0 (#36), ticket #37: colour bands made the window look like parts of different apps. Replaces D 5.9. |
| L37 | A theme may set a token of `ThemeToken.systemSurfaces` (`window`, `popover`, `notice`, `field`, `separator`) to `system`; on any other token `system` counts as missing. `ResolvedTheme.system` holds those tokens, with no painted colour. `Palette` makes them: `window` is `windowBackgroundColor`, `field` is `textBackgroundColor`, `separator` is `separatorColor`; a popover and a notice (`Palette.surface`) are the ultra-thick material under `windowBackgroundColor` at 80%, and their solid colour, for a test or a `Color`, is `windowBackgroundColor`. With a `system` `window`, `RootView` leaves the toolbar background to the system (`.automatic`), so the native macOS 26 toolbar shows. A native popover (Context, agent control) keeps the system's background in a native theme and takes `popover` in a painted one (`popoverSurface`). Default Light and Default Dark set all five to `system`; Dimmed and the eight VS Code themes paint all five; a test checks that no shipped theme mixes them. A person's theme may mix them (one that extends a default and paints `window` alone keeps native popovers); resolution does not force the set together, since it would have to invent painted colours the theme never named. The raw-colour test reads `Palette.swift` too and allows there only the colour from numbers, the `NSColor` it returns, `systemColor` and the one material. The contrast test lives in `ReviewAppTests` (`PaletteTests`) and resolves each surface as the window draws it, in the theme's appearance. | Spec 0.2.0 (#36), ticket #40: the default themes feel like a Mac app, and the VS Code themes keep their colours. A bare material over a dark video turned a light popover grey and its quiet words unreadable, so the window colour sits on it. `separator` and `field` are in the set so no painted warm line or box sits on a native surface. |
| L38 | The sidebar shows the thread list or one thread's view: `AppModel.shown`, nil for the list, apart from the pin's `selection`. A row click, Previous and Next, Up and Down, `thread show`, a pin, a badge and a notice show a thread's view, pause the player and move it to the thread's frame; a written message leaves the list as it is. Back, Escape and `thread list` show the list. The list groups the threads as Needs you (an open question), With agent (a message sent, acknowledged or working), Queued (a queued message), Done (the rest, General with no message of the person's too), each in the first group it matches, in time order with General first. Previous and Next go in that time order, not the groups'. The row of the thread whose frame is on the stage (`stageThread`) sits in a `well`. The field stays at the foot of the thread view until the composer moves to the sidebar's foot (#42). | Spec 0.2.0 (#36), ticket #39, from variant 02 of the prototype: the keyframe in the sidebar repeated the stage, and the person reads first what waits for them. Replaces D 3.3, D 3.5, D 3.6 and L33. |
| L39 | `thread show <thread>` shows a thread's view, as a click on its row does, and answers once the player is on the thread's frame; `thread list` shows the list. `state` names the thread the sidebar shows in `sidebar.thread`, `null` for the list. Operator commands, additions to the contract. | The CLI cannot click. Without them neither view can be shown, checked or screenshotted in the real app. Replaces L34 and `thread expand`. |
| L40 | The conversation is a chat (spec 0.2.0, ticket #41): see the Conversation row of the UI table. An agent's message (`ack` text, `reply`, `ask`) keeps the name of the listener session it was written under (`Message.sessionName`), and shows that name and its logo; one kept before the field existed has none and shows the current listener's. A right-click on a message offers Edit and Delete on a queued message only and Copy on every message; on a row, Open, Show on Video (not General: it moves the player to the frame and leaves the list showing) and Delete Queued Messages (only with a queued message). The question card's heading is `<agent> asks`, as the ticket says, not the prototype's `Needs your answer`; the region tag sits on the quiet line under the bubble, as the ticket says, not inside it. A bubble's words are not selectable: a selectable text takes the right-click for its own menu, and Copy is in the message's. | A later listener renamed every old reply, so the conversation lied about who wrote what. The menus follow the macOS convention of offering only what applies. |
| L41 | One composer at the sidebar's foot (ticket #42), `Composer` in `UI/Sidebar/`; the stage popover's view is `CommentPopover`, as the glossary names them. Its target (`ComposerTarget`): in a thread view a follow-up on the thread, or the answer to its open question; in the list the thread of the frame on the stage ("Reply on #3"), a new thread there ("New thread at 0:12"), or General with the General toggle ("Reply on General"), and the answer when the frame's thread has an open question. A drawn region opens the comment popover as before and is the composer's chip too, while the stage shows its frame and the target is on it; the popover's words or its discard take it, and a click into the composer closes the empty popover and leaves the chip. A chip turns an answer into a message on the frame, since an answer takes no region. One draft per target thread and one for a new thread, in memory, cleared when written and when another video opens; the General toggle goes off once written to. Clicking into the field pauses the player. Cmd+Return queues the words, or answers, then sends. `comment compose [<text>] [--region] [--general]` puts words, a chip and the toggle in it; `state` reports it as `sidebar.composer`, its `target` the line it shows. An operator command, an addition to the contract. | Spec 0.2.0 (#36): stories 36 to 46. The prototype's region went to the composer only; the spec keeps the popover on a drawn region (story 46), so the region is offered to both. The CLI cannot type or draw. |
| L42 | Native parts (ticket #43). The empty first screen and "No Threads Yet" are `ContentUnavailableView`s ("No Threads Yet" in a compact form since L43); the first screen's drop target stays on the whole stage, with a dashed outline over it only while a file is over it. `QuietButtonStyle` is gone: symbol buttons are native `.borderless` buttons with a `textSecondary` label, so they dim on press and when disabled and take the focus ring under keyboard navigation; the hover fill went with it (the `controlPressed` token has no view now). `MessageField` draws the field colour with a `separator` hairline at rest and the system focus ring (`FocusRing`, 3 pt outside the edge in `Palette.focusRing`, the system's `keyboardFocusIndicatorColor`) while its text view has the focus in the key window, in place of the permanent accent stroke; `FocusTextView` reports the focus. Tab and Shift+Tab in the editor move to the next and the previous control, as in a text field. A `Settings` scene (⌘,) holds the theme picker; View › Theme stays, and both use `ThemePicker`, the same choice as `theme set`. Settings takes the pinned theme's appearance and accent. `screenshot --window settings` opens Settings as ⌘, does (SwiftUI's `openSettings`, handed over by the player's window through `SettingsWindow`), captures it, and closes it when it was closed before; an operator command option, an addition to the contract. | Spec 0.2.0 (#36): the app feels like a Mac app. The focus ring is drawn by the field, since an `NSTextView` in a scroll view draws none of its own, and the raw-colour test allows the one system focus colour in `Palette`. `screenshot` captured only the player's window, and Settings has to be checked and shown without a click. |
| L43 | The 0.2.0 polish pass (ticket #44), after a review of the whole window against the macOS conventions, the Shipyard app and variant 02 of the prototype. `controlPressed` is gone from the token list and the two default themes, as L36 removed the others; a person's theme that still sets it loads. A notice is a native `.borderless` button, so it dims while pressed and takes the focus ring under keyboard navigation, in place of `.plain`. "No Threads Yet" is the compact form of the native empty state: a light symbol, a headline and a callout, centred, in place of `ContentUnavailableView`'s large title. The thread view's Previous and Next name their keys in their help (↑, ↓). The timeline's pins keep `.plain`: the player bar stays as it is (spec 0.2.0: "Keep the player bar"). A `ThreadRow` is a `Button` with `RowButtonStyle`, which draws the row as it is, so keyboard navigation reaches it and the system focus ring goes around its rounded shape; the focused row was `AppModel.focusedRow`, and Space, Return and Enter on it opened its thread through `Shortcuts`, since the player's key monitor takes those keys before SwiftUI (replaced by L45: the row reports its focus as every other control does). A click, those keys, the menu and VoiceOver go through `AppModel.perform(_:on:)`. | Spec 0.2.0 (#36): the app feels like a Mac app. The large title was heavier than the thread list's own heading in a sidebar 340 pt wide, and the prototype's empty list is one quiet line. |
| L44 | The protocol version is 3. | 0.2.0 changed the requests' shape: `thread.expand` became `thread.show`, `state` names `sidebar.thread` in place of `sidebar.expanded`, and `screenshot` takes a `window` that a 0.1.0 app would ignore and capture the player's window. A 0.1.0 CLI or app that meets this one is told to reinstall, not given a wrong answer (L1). |
| L45 | Space and Return press the control with the keyboard focus (ticket #52). Under keyboard navigation every focusable control in the player's window reports its focus through `pressedByKeys(in:action:)`: a thread row, a notice card, the header's symbol buttons (agent control, Context, the sidebar toggle), the thread view's Back, Previous and Next, a queued message's Edit and Delete and its editor's Cancel and Save, the composer's region × and General toggle, the footer's Send, the comment popover's Discard and Answer or Queue, the player bar's Play and Comment, the timeline's pins, and Stop in the agent-control popover. `AppModel` keeps the focused controls of the key window as a stack (`focusControl`, `blurControl`, `pressFocusedControl`): the last to take the focus is pressed, and `blurControl` removes only its own entry, so when a popover's control (Stop) loses the focus or goes, a control still focused in the player's window gets the keys again. `Shortcuts` gives Space, Return and Enter with no modifier to it (`pressControl`) in place of play, a new message or the row's own rule; `AppModel.focusedRow` is gone. An AppKit control that is the first responder (a pop-up button) takes those keys itself, only while keyboard navigation is on (`Shortcuts.isControlFocused`, `NSApp.isFullKeyboardAccessEnabled`): with it off a clicked AppKit control can stay first responder, and Space still plays and pauses. A queued message's Edit and Delete, hidden until hover, also show while either has the keyboard focus (`pressedByKeys`' `isFocused`), so a key never presses a button the person can't see. With no control focused, Space plays and pauses as before. | The player's key monitor sees every key before SwiftUI, so a focused button never got Space; one general rule replaces the thread row's own. |
| L46 | Unread threads (ticket #48). `ReviewThread.lastSeen` is when the person last opened the thread's view, kept in the review file (`null` until then); `isUnread` is whether an agent message (`reply`, `ask`, an `ack`'s words on General) is newer than it, or there is one and it's `null`. `AppModel.shown`'s `didSet` calls `VideoReview.markSeen` with the time now, so a row click, Previous and Next, `thread show`, a pin, a badge and a notice all clear it; an agent message on the thread the sidebar shows is read as it comes (`raise`). A review file from before has no `lastSeen` key, and its agent messages count as read, so an update marks nothing. `state --json` reports `unread` per thread, and `state` ends a thread's line with `unread`. | Spec 0.2.0 (#36), ticket #48. The thread view is the one place the conversation shows in full; the popover shows the thread view too. Replaces L15. |
