# Havooch 0.2.0: low-level design

Written 2026-10-05, before the first build ticket of `effort:0.1.0`, from `Spec: Havooch 0.1.0` (#20), the prototype decisions in `docs/prototypes/2026-10-05-decisions.md` (cited as D x.y), ADR 0001 and the tickets #22 to #33. It is documentation for the maintainer, not a review gate. When the code and this document disagree, fix one of them in the same change. `Spec: Havooch 0.2.0` (#36) and its tickets #37 to #44 changed it since; their decisions are L36 to L44.

It starts from proto-2's low-level design (`proto-2:docs/low-level-design.md`, PR #18), since proto-2's code is the base (D A.1). It keeps what proto-2 got right and changes four things: the **thread model** replaces comments and batches, the **send** cuts the transcript at send time, every colour comes from a **theme**, and the module changes A.2 to A.10 come from proto-1 (`proto-1:docs/low-level-design.md`, PR #17). proto-2's own decisions (D1 to D216 in its document) still hold where this document does not replace them; the decisions this design takes on its own are numbered L1, L2… under [Decisions](#6-decisions-the-spec-left-open).

NOTE: Domain words follow `GLOSSARY.md`. In particular, a **message** is what the person or the agent writes, a **thread** holds the messages about one keyframe, and a **send** is what Cmd+Enter delivers. "Comment" survives only as the CLI's `comment` commands and the UI's Comment button; "batch" is gone.

## For a newcomer, in one screen

Havooch is one Swift package. It builds two executables: the macOS app (`/Applications/Havooch.app`) and the `havooch` command, which ships inside the bundle at `Contents/Helpers/havooch`. The code is nine modules, split by concern. The agent side never links the app's rules.

```text
agent side (no app rules, no UI; builds and tests on Linux)
  ReviewLease       Holder and how it is found; the lease rules as a pure value. Depends on nothing.
  ReviewWire        the control protocol: request, reply, socket framing, socket and support folder locations, the app identity and version
  ReviewCommand     the command table of `havooch`: parse, send one request, print the reply, pick the exit code
  ReviewCLI         main.swift only
  ReviewConfig      config.toml (ADR 0002): where it is, reading it with each problem on its line, the verdict, targeted writes. TOMLDecoder.

app side
  ReviewCore        threads, messages, regions, states, the send, the send payload, the outbox, theme resolution. Pure logic, given the time.
  ReviewTranscript  the Transcriber interface, its three sources and the window cut
  ReviewStore       SupportLayout (every path), Library (load and save), images, the speech cache, theme files
  ReviewSetup       what Havooch can detect of setup (the command link, the skill per harness, the harnesses),
                    Link, the skill install, the prompt per harness; file system and processes behind seams (L52)
  ReviewApp         the SwiftUI app: player, stage, popovers, sidebar, header, control server, listener queue. macOS only.

havooch (CLI)   → ReviewLease + ReviewWire + ReviewCommand + ReviewConfig
Havooch.app     → everything
```

```text
person ──keys, mouse──▶ a window's UI ─────────────────────────▶ WindowModel ──▶ PlayerEngine (AVPlayer)
                                                                   │
operator ──▶ havooch ──▶ SocketListener ──▶ ControlServer ── --window ──┤   (one per window)
             (lease)          (control.sock)    (decode, lease,    or key  │
                                                 dispatch)         window  └──▶ AppModel ─▶ ReviewDesk ──▶ Review (Core) ──▶ Library (Store)
person/agent ──▶ havooch open ──▶ ControlServer ──▶ AppModel ──▶ WindowRegistry   ├─▶ ListenerHub ──▶ ListenerQueue* ──▶ Outbox (Core)
                 (no lease)                         (the window that holds it)    ├─▶ ThemeDesk ──▶ ThemeCatalog (Core), ThemeFiles (Store)
                                                                                  ├─▶ ConfigDesk ──▶ ConfigLocation, ConfigFile (ReviewConfig)
                                                                                  └─▶ SetupDesk ──▶ SetupProbe, SkillInstall (ReviewSetup)
listener ──▶ havooch wait [--video] / ack / status / reply / ask ──▶ ControlServer ──▶ ListenerHub ──▶ that review's ListenerQueue, ReviewDesk
             (no lease)
```

The person and the operator reach the same `WindowModel` methods, so a UI action and its CLI command are one code path. `AppModel` holds what is the app's: the windows, the data, the theme and the recent videos (L54).

| You want to | Open |
|---|---|
| see where the app starts | `Sources/ReviewApp/HavoochApp.swift`, then `AppModel.swift` and `Windows/` |
| change how an open finds its window | `AppModel.openInFront`, `AppModel.openFromFinder`, `AppModel.windowFor`, `Windows/WindowRegistry.swift` |
| see where the CLI starts | `Sources/ReviewCLI/main.swift`, then `Sources/ReviewCommand/CommandTable.swift` |
| add a CLI command | [Extensibility](#5-extensibility), first row |
| change a thread or message rule, or a state | `Sources/ReviewCore/Review.swift`, `MessageState.swift` |
| change what `wait` prints | `Sources/ReviewCore/SendPayload.swift` |
| change when a send is delivered again | `Sources/ReviewCore/Outbox.swift` |
| change which listener a send or a `wait` goes to | `Sources/ReviewApp/ListenerHub.swift` |
| change the lease | `Sources/ReviewLease/ControlLease.swift` |
| change where a file is kept | `Sources/ReviewStore/SupportLayout.swift` |
| change a project rule (versions, thread anchors, moving a video's threads in) | `Sources/ReviewCore/Review.swift`, `VersionAnchor.swift`; `ReviewApp/AppModel.swift` (`projectNew`, `projectAdd`, `resolveTarget`) (L59) |
| add a colour token or a built-in theme | `Sources/ReviewCore/Theme/ThemeToken.swift`, `Packaging/Themes/` |
| change what setup detects, or a harness's prompt | `Sources/ReviewSetup/SetupProbe.swift`, `HarnessCatalog.swift` |
| add or change a `config.toml` key | `Sources/ReviewConfig/ConfigFile.swift`, `ConfigReader.swift`, `schema/config.schema.json`, the skill's Settings table (L53) |
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
8. **Sidebar**: the thread list, grouped by who must act next (in a project, by version: L61), and the thread view of one thread with Back, Previous and Next; message bubbles with crops, one composer at the sidebar's foot, resizable. (35 to 44, 65; 0.2.0: L38 to L41)
9. **Agent**: the listener gets each send through `wait`, grouped by thread, acknowledges, replies, sets each message's state and asks on a thread; an answer to a question goes at once. Notices name the thread. (45 to 49, 71 to 81)
10. **Header and presence**: the file name, the folder, the floating group (agent-control icon, Context, sidebar toggle), the footer with presence, queued count and Send. (50 to 58)
11. **Themes**: every colour is a token; built-in and user themes, light and dark, follow the system or a pinned one, reload on change; the pin in `config.toml` and the person's themes beside it, per-token overrides gone (L53). (59 to 64)
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

In: all of the above. Out, as the spec says: a redesign of the comment popover, a rule for a listener that never comes back, fonts and spacing in themes, video editing, formats AVPlayer cannot play, URLs, system-wide hotkeys, more than one listener, shapes other than rectangles, developer ID signing, ReviewMate code. Out by this design: system notifications, undo, an Allow button after Stop, editing overrides in the app's UI.

### Requirement to module

| Requirement | Module and files | Ticket |
|---|---|---|
| 1, 14, 15 port, player, CLI, lease, version | ReviewLease, ReviewWire, ReviewCommand, ReviewApp `Player/`, `Control/` | #22 |
| 11 themes | ReviewCore `Theme/`, ReviewStore `ThemeFiles`, ReviewApp `ThemeDesk`, `UI/Palette` | #23 |
| 2, 4, 12 threads and messages | ReviewCore `Review`, `ReviewThread`, `Message`, `ItemID`, ReviewStore `SupportLayout`, `Library` | #24 |
| 5, 9, 13 the send, `wait`, the outbox | ReviewCore `Send`, `SendPayload`, `Outbox`, ReviewApp `ListenerQueue`, `TranscriptDesk` | #25 |
| 9 `ack`, `status`, `reply`, `ask`, `thread answer`, `thread choose` | ReviewCore `Review`, ReviewApp `ListenerQueue`, `Notice` | #26 |
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
| `AppModel` (app-wide) | the windows (`WindowRegistry`), the `DataFolder` the run is on and whether an in-app demo runs (L27), the theme, the recent videos and their thumbnails, the sidebar's width; routes `havooch open` and the person's opens to a window (L54) | ReviewApp |
| `WindowRegistry` | which window holds which video, which one is key, the windows waiting for their scene, ids `w1`, `w2`… | ReviewApp |
| `WindowModel` (per window, the orchestrator of one window) | its open video, its player, the open popover and its draft, the thread the sidebar shows (none for the thread list), the composer, the notices; every action a person or an operator takes in it | ReviewApp |
| `PlayerEngine` | the AVPlayer, the time, playing or paused, the frame time of a moment | ReviewApp |
| `Review` | one video's threads, messages and sends, and every rule about them | ReviewCore |
| `ReviewDesk` | the one path for changing a `Review`: change, save, publish | ReviewApp |
| `Outbox` | pending and taken sends, the listener session, the context already sent, presence | ReviewCore |
| `ListenerHub` | one `ListenerQueue` per review (L56); which review a `wait` binds to; routes the listener's commands by the id prefix | ReviewApp |
| `ListenerQueue` | one review's open `wait` and `ask`s, payload assembly, takeover | ReviewApp |
| `ReviewKey` | which review something belongs to: `.video(contentHash)` now, a project's later; names its outbox file | ReviewCore |
| `ThemeCatalog` | the known themes and how a theme resolves to every token | ReviewCore |
| `ThemeDesk` | the active theme, the pin `config.toml` names, the watch of the person's theme files | ReviewApp |
| `ConfigDesk` | `config.toml` as the app runs it: the last valid settings, the verdict, the watch, the theme write, the one-time move from `settings.json` (L53) | ReviewApp |
| `Library` | loading and saving the store's JSON files | ReviewStore |
| `ControlLease` | who holds the lease, the line of waiters, the bars | ReviewLease |
| `ControlServer` | the one lease instance, dispatch of decoded requests | ReviewApp |
| `SocketListener` | the socket, each connection, the heartbeat | ReviewApp |
| `TranscriptSources`, `SpeechSource`, `TranscriptDesk` | as in proto-2 | ReviewTranscript, ReviewApp |

Fields, not entities: `Region`, `Message`, `MessageState`, `Send`, `SendRef`, `PopoverFrame`, `Holder`, `LeaseTerm`, `TranscriptLine`, `ThemeFile`, `ThemeColor`, `Settings`, `SendPayload`, `Notice`, `Draft`, `WindowTarget`.

```text
AppModel ──owns──▶ WindowRegistry ──holds──▶ WindowModel* ──holds──▶ WindowTarget? (a video's content hash, or nothing)
WindowModel ──owns──▶ PlayerEngine;  ──reads──▶ its review in ReviewDesk, by its video's content hash
AppModel ──owns──▶ DataFolder (support folder, SupportLayout; replaced on entering and leaving the demo, L27; every window is on it)
DataFolder ──holds──▶ ReviewDesk ──holds──▶ Review ──contains──▶ ReviewThread ──contains──▶ Message
                        │                     └──contains──▶ Send ──refers to──▶ Message (by id); keeps the transcript per thread
                        └──saves through──▶ Library ──paths from──▶ SupportLayout
DataFolder ──holds──▶ ListenerHub ──holds──▶ ListenerQueue* (one per review) ──holds──▶ Outbox ──refers to──▶ Send (SendRef: id + content hash)
                        ├──changes reviews through──▶ ReviewDesk
                        └──reads──▶ ContextReader, SupportLayout (image paths)
DataFolder ──holds──▶ TranscriptDesk ──asks──▶ TranscriptSources        (read at send time, not at delivery)
AppModel ──owns──▶ ThemeDesk ──resolves with──▶ ThemeCatalog; ──reads──▶ ThemeFiles, Settings   (on the folder the run started on)
SocketListener ──hands bytes to──▶ ControlServer ──holds──▶ ControlLease
ControlServer ──calls──▶ AppModel (person, free, the window commands), the WindowModel `--window` or the key window names (operator), the ListenerHub the AppModel is on now (listener)
UI views ──read──▶ their WindowModel, ReviewDesk, their window's ListenerQueue, PlayerEngine, ThemeDesk (as Palette)   ──call──▶ their WindowModel
```

Where each rule lives:

- "Which thread does a message at this frame join? Can this message be edited, change state, be answered?" lives in `Review`.
- "What is the state of this thread?" lives in `ReviewThread.state`.
- "Which send does this `wait` get, is this a new listener, is the context due?" lives in `Outbox`.
- "Which colour does this token have now?" lives in `ThemeCatalog.resolve`.
- "May this holder drive the app now?" lives in `ControlLease`.
- "Which frame is this moment? Is a video open in this window? What happens to the open popover when the moment changes?" lives in `WindowModel`.
- "Which window holds this video? Which window is key? Which window does this open go to?" lives in `WindowRegistry` and `AppModel.windowFor`.

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
+ Sources/ReviewConfig/, schema/config.schema.json, Package.resolved         config.toml (L53)
```

```text
Package.swift                      targets below; macOS 26; one dependency, TOMLDecoder, for ReviewConfig (L53); ReviewApp and its tests under #if os(macOS)
schema/config.schema.json          the JSON Schema config.toml names on its #:schema line; ReviewConfigTests keeps it equal to the reader (L53)
Makefile                           test, build, bundle, install, acceptance, agent-logos, identity, clean; reads VERSION from ReviewWire/Version.swift
Packaging/Info.plist               the bundle's template (name, bundle id, version stamped by make bundle); `public.movie` as Viewer, rank Alternate (L55)
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
fixtures/sample/                   the fixture video and its sidecars, for the tests
fixtures/launch/                   the launch explainer and its sidecars, the bundled demo

Sources/
  ReviewLease/
    Holder.swift                   who sends a request: key, name, place; Holder.find (HAVOOCH_CONTROL_KEY, the Claude Code, Codex or Pi session, ancestor)
    ProcessTable.swift             the process table Holder.find walks (sysctl on macOS, /proc on Linux), and its protocol
    LeaseTerm.swift                a lease held: holder, taken, ends
    ControlLease.swift             the lease rules as a pure value: use, take, release, stop, settle, giveUp, status
  ReviewWire/
    AppIdentity.swift              the app name, bundle id, support folder name ("Havooch", no suffix)
    Version.swift                  the app version "0.4.0" and the protocol version 6 (L44, L54, L59, L61)
    ControlRequest.swift           every request as an enum case; its role; how long the app may hold it
    Compare.swift                  `CompareSide`, `CompareLayout` and `CompareChange`, the names compare's commands and the app share (L63)
    ControlMessage.swift           request plus holder as one JSON object; decode refuses another version
    ControlReply.swift             {ok, output, error, lease?, timedOut?}
    ControlProtocolError.swift     unreadable, otherVersion, unknownCommand
    TimeCode.swift                 "90", "1:30", "0:01:30.5" to seconds and back
    UnixSocket.swift               POSIX calls; the short-link address for a long path
    ControlClient.swift            one exchange over the socket, skipping heartbeat spaces; the ControlTransport seam
    ControlSocket.swift            where control.sock is; follows the demo pointer
    DemoPointer.swift              demo.json in the normal support folder
    SupportFolder.swift            the support folder; HAVOOCH_SUPPORT_DIR moves it; HAVOOCH_DEMO_RUN marks the demo run (L27)
  ReviewCommand/
    CommandTable.swift             the commands by name, usage text, global --json
    HavoochCLI.swift               run(arguments, environment) → output, error, exit code
    OpenCommand.swift              open <path> [--project]: the person's open, no lease; launches the app in front when it doesn't run (L51, L59)
    ProjectCommands.swift          project new | add (through the app, no lease) | list (reads config.toml, no app) (L59)
    CompareCommands.swift          version show <n> | pick [<query>] | close, on a window (L62);
                                   compare open | pick <side> [<query>] | set | swap | start | exit, on a window (L63)
    WindowCommands.swift           window list | new | close [<id>] (L54); `--window <id>` on the commands that act on one window
    AppCommands.swift              app status | open [--demo] | home | demo | quit, state, --version (L49)
    ControlCommands.swift          control take [--wait] | release
    PlayerCommands.swift           player open | play | pause | seek
    CommentCommands.swift          comment add | open | compose | edit | delete, send, thread answer | choose | open | show | list, context set;
                                   thread versions [--search] [--close], thread version <n> [--remove] (L61)
    ThemeCommands.swift            theme list | set
    SetupCommands.swift            setup status | link [--dry-run] | install [--harness]... [--dry-run] | cancel (L52)
    ConnectCommands.swift          connect show | pick <harness> | disconnect | forget (L57)
    TourCommands.swift             tour show | next | skip | close (L58)
    FirstRunCommands.swift         first-run show [<step>] | next | back | pick <harness> | demo | skip (L60)
    ConfigCommands.swift           config path | check: read config.toml with no app and no lease; config dismiss closes the settings notice (L53)
    ScreenshotCommand.swift        screenshot <abs.png> [--appearance] [--hide-agent-indicator] [--window main|settings|about|first-run] (L42, L60)
    ListenerCommands.swift         wait [--video | --project], ack, status, reply, ask
    AppLauncher.swift              starts the app through Launch Services, in the background or in front, and brings a process to the front; the AppLaunching seam
  ReviewCLI/
    main.swift                     exit(HavoochCLI.run(...))
  ReviewConfig/                    config.toml (ADR 0002, L53), after Swift Lab's LabConfig (ADR 0016)
    ConfigLocation.swift           the folder: <support>/config/ with HAVOOCH_SUPPORT_DIR, else $XDG_CONFIG_HOME/havooch/, else ~/.config/havooch/;
                                   config.toml and themes/ in it; ~ expansion
    ConfigFile.swift               the settings as decoded (theme, projects); decode(text) → settings and warnings, or problems with lines;
                                   the header; ConfigIssue, ConfigProblems
    ConfigReader.swift             walks the parsed file key by key; unknown keys are warnings with the nearest known key
    TOMLSourceMap.swift            the line of each key, from Swift Lab's
    ProjectEntry.swift             one [[projects]] table: slug, title, versions [{path, label}]; versionNumber(of:)
    ConfigVerdict.swift            {accepted, checked, config, configModified, problems, warnings}; config-status.json; read and check
    ConfigWriter.swift             the targeted writes: the header for a missing file, the theme line (set, replace, remove)
    ConfigWriter+Projects.swift    append a [[projects]] table; append a version to one project's versions (L59)
  ReviewCore/
    ItemID.swift                   t-<hash8>-<n>, m-<hash8>-<n>, s-<hash8>-<n>: parse, make, the hash prefix;
                                   ThreadID, MessageID, SendID; ThreadRef (a full id or a bare number, L5)
    Region.swift                   x, y, w, h in 0..1 from the top left; validation; pixels in a picture
    Message.swift                  id, author, kind, text, at, region, state, sendID, sessionName (L40), choices
    MessageState.swift             the six states, the legal moves, editable, open
    ReviewThread.swift             id, number, time (nil for General), messages, popoverFrame, lastSeen; state; openQuestion; isUnread
    Send.swift                     id, sentAt, message ids, the transcript lines cut per thread; SendRef
    Review.swift                   one review, a plain video's or a project's: its key, its stored id prefix, every rule about
                                   threads, messages and sends; the counters; adoption into a project (L59)
    VersionAnchor.swift            a thread's version by path; ProjectOutline (a project as the rules read it); VersionTag (L59)
    ReviewRefusal.swift            why a change is refused, as the line the CLI prints
    Outbox.swift                   the listener outbox: pending, in flight, taken, session, context sent, presence
    ReviewKey.swift                which review a thing belongs to (`.video(contentHash)` or `.project(slug)`); its outbox file name (L56, L59)
    KnownAgent.swift               the nine agent harnesses a session's name says ("Claude Code" → claude), each one's
                                   AgentLogo (colour, light and dark, template); ListenerSession.agent (from Shipyard)
    SendPayload.swift              the JSON `wait` prints, grouped by thread, and how it is assembled; `video.demo` (L60)
    DemoVideo.swift                the bundled demo video's content hash, which marks a send as the demo's (L60)
    Theme/
      ThemeToken.swift             every semantic colour token, by name
      ThemeColor.swift             a colour as "#rrggbb" or "#rrggbbaa": parse and print; WCAG contrast; `filled()`, the fill white text reads on (L50)
      ThemeFile.swift              a theme file as decoded: name, kind, extends, tokens
      ThemeCatalog.swift           the known themes; resolve(name, overrides) → every token; the active theme for an appearance
  ReviewTranscript/                unchanged from proto-2
    TranscriptLine.swift, Transcriber.swift, TranscriptWindow.swift, TranscriptSources.swift,
    VoiceoverSource.swift, SubtitleSource.swift, SpeechSource.swift, AppleSpeechRecognizer.swift
  ReviewStore/
    SupportLayout.swift            every path under a support folder (pure), and the pending name of a picture (L19)
    Library.swift                  reviews, the outbox, the recent videos, settings: load and save, the schema version; the hash-prefix index
    RecentVideo.swift              one recent video: path, content hash, opened time, last position
    ContentHash.swift              SHA-256 of the file, streamed; ContentHashCache keeps it by path, size and modification time (L51)
    ImageFiles.swift               writing and removing a PNG at a layout path; a small copy for a row
    TranscriptFiles.swift          the finished speech transcript: load and save
    ThemeFiles.swift               read the built-in and the user theme files into ThemeFile values, with each file's path
    Settings.swift                 the sidebar width, an agent connected once, the first run done (app state) in settings.json; Former, an older build's theme and overrides, read once (L53)
  ReviewSetup/                     (L52)
    HarnessCatalog.swift           per harness: user skills folders, presence hints, the -a name, the prompt form; PromptTarget
    SetupProbe.swift               Detection (detected | notDetected | cannotKnow), HarnessSetup, SetupReport; the probe
    SetupFileSystem.swift          the FileSystem seam (item, target, make folder, make link, remove); LocalFileSystem
    CommandLink.swift              ~/.local/bin/havooch: state, make, the ln -sf fallback line
    SkillInstall.swift             npx skills add … through the login shell: command lines, run, Outcome; the ProcessRunner
                                   seam and LocalProcessRunner (lines as they come, cancel stops the program)
  ReviewApp/
    HavoochApp.swift               @main; `WindowGroup(for: WindowTarget.self)`, Settings (L42); the menu commands: File › New Window and Open…,
                                   File > Close Video (L49) and Playback on the focused window; the app stays with no window, the Dock icon makes one (L54);
                                   `application(_:open:)`: Finder's Open With, a Dock drop and `open -a` go to `AppModel.openFromFinder` (L55)
    AppModel.swift                 the app: the windows, the data, the demo, the recent videos, the theme's actions; which window an open goes to (L54)
    Windows/
      WindowModel.swift            one window's orchestrator; every action a person or an operator can take in it; compare's
                                   popover, the pair of players, the active side (L63)
      CompareSession.swift         a comparison as words and numbers: the sides' versions, the layout, Flip's side, the slider,
                                   the side picker; it opens on the previous version and the one on screen; a pick swaps (pure, L63)
      WindowConnect.swift          the Connect view's entry, banner, picked harness, readiness and Disconnect (L57)
      WindowTour.swift             the setup tour: `TourState`, its steps and rings, what moves it on, Finish setup's count (L58)
      WindowRegistry.swift         the windows, by id (`w1`…), the key window, the window that holds a video, the ones waiting for a scene
      WindowTarget.swift           what a window holds, as its scene's value: a video by content hash, or a project by slug (L59)
      WindowScene.swift            a window's scene: takes its `WindowModel`, follows its target, hands `openWindow` to the registry,
                                   tells the app its `NSWindow`; `FocusedValues.playerWindow` for the menus
    Draft.swift                    `WindowModel.Draft`: the open popover's time, text and region (view state, never
                                   saved; its thread number is `WindowModel.draftThreadNumber`); `PopoverClose`; `FrameMark`
    ReviewDesk.swift               change a review by its key, save it, publish it; move a video's review into a project (L59)
    ListenerHub.swift              review key → ListenerQueue, made lazily; binds a wait; routes ack/status/reply/ask by id prefix (L56)
    ListenerQueue.swift            one review's open waits and asks; delivery; payload assembly; presence; takeover; the listener's answers
    TranscriptDesk.swift           the videos opened in this run; the window's lines, read at send time
    ThemeDesk.swift                the active theme and the pin config.toml names; watches themes/; AppModel's theme actions
    ConfigDesk.swift               config.toml in the app: reload, verdict to config-status.json, theme write, the move from settings.json; ConfigWatcher (L53)
    SetupDesk.swift                the latest probe, Link and its failure, the running install and its log, the suggested harness and a harness's
                                   readiness; AppModel's setup actions (L52)
    FirstRun.swift                 the first-run window's model (steps, picked harness, problem); `SetupSteering`, what the setup steps act on;
                                   AppModel's first-run actions and `firstRun` in `state` (L60)
    ContextReader.swift            the sidecar context file plus the note
    DataFolder.swift               the data a run is on: support folder, SupportLayout, ReviewDesk, ListenerHub, TranscriptDesk (L27)
    DemoRun.swift                  "Try the demo": the bundled launch video, the demo folder under the temporary folder (L17)
    Notice.swift                   one notice: its thread, the agent's name, the words, when it fades
    Player/
      PlayerEngine.swift           AVPlayer: open, play, pause, exact seek, time, frameTime(of:); play at a host time, retire (L63)
      PlayerPair.swift             two PlayerEngines on one clock: play on one host time, pause, seek, speed, drift corrected, only the lead heard
                                   on the lead's ticks (P8, L63)
      PlayerSurface.swift          AVPlayerView without controls
      FrameGrabber.swift           keyframe and crop PNGs from the asset, at the exact time
      Shortcuts.swift              the player's keys, on the window they're pressed in, off while a text field has the focus; Space and Return press a control with the keyboard focus (L45); backslash flips Compare's Flip (L63)
    Control/
      SocketListener.swift         the listening socket off the main actor; one task per connection; the 2 s heartbeat
      ControlServer.swift          decode, the lease gate, dispatch, held takes; the written/undelivered outcome
      AgentControlIcon.swift       the lease as the agent-control icon shows it
      StateReport.swift            `state` and `app status` as JSON and as lines
      SetupState.swift             `setup` in `state`, and what the setup commands print (L52)
      ThemeReport.swift            the theme in `state`, `theme list` and `theme set`
      Screenshotter.swift          a player window (`--window`, else the key one), or Settings (L42), through ScreenCaptureKit, in an appearance
    UI/
      RootView.swift               stage, player bar, sidebar, header, all on the `window` surface; with no video the home screen or the empty state (`StageContent`); injects the Palette; a pinned theme's kind as the window's colour
                                   scheme; `SidebarColumn`: the threads, the composer and the footer, resizable, the width kept in settings, proto-1's spring in and out, a
                                   hairline on its leading edge; `Hairline`, one pixel of `separator`
      Palette.swift                the resolved tokens as SwiftUI colours, a `system` surface as the native one (L37), in the environment; the only way a view gets a colour; `filledButton`, every prominent button on `accentFill` (L50)
      Metrics.swift                measures: bar height (= footer height), paddings, sidebar limits; StateLook, a state's glyph and name
      ConfigBanner.swift           the settings notice at the top of the window: what the move did, or a save's problems; its close button (L53)
      SettingsView.swift           the Settings window (⌘,) with the cat mark, the name and version, and the theme picker View › Theme shares; `SettingsWindow` opens and finds it for app control (L42)
      MessageEditor.swift          the one text view messages are written in, its keys, and `MessageField`'s look with the system focus ring (L42)
      EmptyState.swift             `ContentUnavailableView` with the cat mark, "Open a Video…" and "Try the Demo"; `videoDropTarget`, the drop target and its
                                   outline, which the home screen shares (L42)
      Home/
        HomeScreen.swift           `StageContent` (player, home or empty, and whether the sidebar shows); `HomeScreen`: the cat mark, the name,
                                   "Open a Video…", "Try the Demo" and the "Recent Videos" grid of adaptive columns (L48)
        ProjectCard.swift          one project on home: its latest version's thumbnail with vN, title, versions and when opened (L59)
        RecentCard.swift           one recent video: thumbnail at 16:9, name without extension, relative time, the path on hover; the context
                                   menu; dimmed with the "unavailable" symbol and a trash button when its file is gone (L48)
        Thumbnails.swift           the cards' thumbnails, made with `AVAssetImageGenerator` and kept in memory only, by content hash and position (L48);
                                   the compare popover's stills of a version at a time (L63)
      AgentMark.swift              `AgentLogoImage`, the logo loader (Contents/Resources/AgentLogos/, else Packaging/AgentLogos/);
                                   `AgentMark`, a known agent's logo at any size; `AgentAvatar`, the logo or the neutral symbol
      HavoochMark.swift            the cat mark at any size (the small cut at 32 pt and under), on the empty screen, the home screen, in Settings and in the header, where it goes home (L49)
      AboutPanel.swift             Havooch › About Havooch: the standard About panel with the app icon and the name's story; found for `screenshot --window about`
      KeyPress.swift               `pressedByKeys(in:isFocused:action:)`: a control tells the model when it has the keyboard focus and what pressing it does, and can follow its focus to show itself (L45)
      Header/
        TitleView.swift            the cat mark at the leading edge; video icon and file name; folder icon and folder, shortened in the middle, or "Demo";
                                   in a project the project's title with the switcher, and under it the version on screen, then the folder (L62);
                                   the Compare button after the switcher, and while comparing the two versions and Exit Compare in its place (L63)
        VersionSwitcher.swift      a project's switcher: the last three versions as segments, the field and its searchable picker;
                                   `VersionSwitch` and `VersionPicker`, the words and numbers, pure (L62)
        FloatingControls.swift     Finish setup with its count (L58), then the group at the top right: agent-control icon, Connect an Agent
                                   with its dot, Open, Context, sidebar toggle
        AgentControl.swift         the icon and its popover: who, where, time left, Stop (words as a pure struct)
        ContextPopover.swift       sidecar text, the editable note, the transcript part
        TranscriptChip.swift       the transcript's source and progress as words (pure)
      Stage/
        StageView.swift            the video, the overlay, the popover, the notices; `StagePane`, one picture with its overlay and marks;
                                   `StagePopoverLayer`, the popover on the active picture; the compare stage while comparing (L63)
        VideoFrameGeometry.swift   view points to normalized frame coordinates and back (pure)
        RegionOverlay.swift        draw a rectangle with its size label; takes the mouse; the popover's region; while comparing, a
                                   click or a drag on a side makes it active first (L63)
        FrameMarks.swift           each thread's region outlines and number badge on the current frame, of its compare side (L63)
      Compare/
        CompareControl.swift       the Compare button and its popover (layout segments, the mini window with stills, a chip per side
                                   and swap, the footer); a side's search picker; `ComparingBadge`, the header while comparing (L63)
        CompareStage.swift         side by side, Flip with its bar, Slider with its handle, over the `PlayerPair`; each side labelled,
                                   the active one filled (L63)
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
      Tour/
        TourPanel.swift            the setup tour's coach panel over the foot of the stage (L58)
        CoachRing.swift            the pulsing ring 9 points outside the part a tour step is about (L58)
      Connect/
        ConnectView.swift          the Connect view: Back, the outbox banner, the step timeline (L57)
        SetupSteps.swift           the command line and skill steps, and the folded "Set up" line
        HarnessPicker.swift        your agent: the picker, the readiness of the picked harness, its prompt
        ListenerCard.swift         connected and reconnecting, with Copy Path, Disconnect and Forget
        CopyBox.swift              text on top, Copy in a footer bar (I5)
        RunBox.swift               the skill install command on top, Run Command and a copy icon in a footer bar; the live log and Cancel while it runs (L64)
      FirstRun/
        FirstRunWindow.swift       the first-run window, an AppKit window of its own; its close button is Skip Setup (L60)
        FirstRunView.swift         Welcome, Tools, Connect, Try it, from first-run V1, on the Connect view's steps (L60)
      Sidebar/
        SidebarView.swift          the thread list, the thread view or the Connect view, with the slide between them
        ThreadList.swift           "Threads", the summary line, the groups under pinned headers (a plain video) or the
                                   `VersionList` (a project); `ThreadRows`, the rows with their hairlines
        ThreadGroup.swift          `ThreadGroup` (Needs you, With agent, Queued, Done) and `ThreadListSummary` (pure)
        VersionTree.swift          `VersionTree` (a project's sections by version) and `AllVersionsMenu` (pure) (L61)
        VersionList.swift          a project's list: the All versions bar and menu, version headers, the older footer (L61)
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
  ReviewSetupTests/                the probe on a fake file system, Link, the prompt per harness, the install on a fake
                                   process runner, LocalProcessRunner on /bin/sh (lines, cancel)
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

`Holder.find(variables, workingDirectory, processes)`: `HAVOOCH_CONTROL_KEY`, else a harness's session from `Holder.sessionVariables` (`CLAUDE_CODE_SESSION_ID` named "Claude Code", `CODEX_THREAD_ID` named "Codex", `PI_SESSION_ID` named "Pi"), else the nearest ancestor process that is not a shell, as `process:<pid>@<start>`, named for its process (`cursor-agent`, `opencode`). `HAVOOCH_CONTROL_KEY` replaces the key only, so the name still says the harness. When one harness runs inside another, both session variables are set; the session whose harness process (`claude`, `codex`, `pi`) is the nearer ancestor wins, else the table's order. The name is what the app's `KnownAgent` reads for the harness logo (decision G12).

### ReviewWire

As proto-2, with these changes:

- `AppIdentity` has no variant: `appName` "Havooch", `bundleID` "com.yahyabedirhan.havooch", support folder `~/Library/Application Support/Havooch/` (D A.10). The name's one definition is `ControlLease.appName`, since the lease's refusals name the app and `ReviewLease` depends on nothing; `AppIdentity.appName` is that value, and the `Makefile` reads it there.
- `Version.app` is "0.2.0"; `havooch --version` prints it. `Version.controlProtocol` is 3 (L1, L44).
- `ControlRequest` follows the spec's contract:

| Role | Cases | Lease |
|---|---|---|
| free | `appStatus`, `state`, `controlTake(waitSeconds?)`, `controlRelease`, `themeList` | none |
| person (L51) | `open(path)` | none, and no agent-control icon |
| operator | `appOpen`, `appQuit`, `appHome`, `appDemo`, `playerOpen(path)`, `playerPlay`, `playerPause`, `playerSeek(seconds)`, `commentAdd(text, at?, region?, thread?)`, `commentOpen(text, region?)`, `commentCompose(text, region?, general)`, `commentEdit(id, text)`, `commentDelete(id)`, `send`, `threadAnswer(thread, text)`, `threadChoose(thread, choice)`, `threadOpen(thread, frame?)`, `threadShow(thread)`, `threadList`, `contextSet(text)`, `themeSet(name)`, `screenshot(path, appearance?, hideAgentIndicator, window)` | takes or renews |
| listener | `wait(timeout?, video?)`, `ack(sendID, text?)`, `status(messageID, state, text?)`, `reply(thread, text)`, `ask(thread, question, waitSeconds?, choices)` | none |

- A thread reference on the wire (`commentAdd.thread`, `threadAnswer`, `threadChoose`, `threadOpen`, `threadShow`, `reply`, `ask`) is a `ThreadRef`: a full thread id, or a bare number for the open video (`0` is General) (L5). The CLI sends the text as written; the server resolves it.
- `ControlClient` reads to the end; the server's heartbeat spaces before the reply are skipped as JSON allows, and a reply of spaces only is an app that went away (D A.8). Its timeout is proto-2's, applied to each read: 15 s plus the request's `holdSeconds`, and no limit for a `wait` or an `ask` with no limit. With the heartbeat no read of a healthy held request waits more than 2 s.

### ReviewCommand

As proto-2, with the spec's names and outputs:

| Command | Prints | `--json` |
|---|---|---|
| `open <path> [--project <slug>]` (L51, L59) | `opened cut2.mp4 (0:55.033) in w1, playing` (`opened cut2.mp4 (0:55.033) in project launch-video (v2) in w1, playing` in a project); exit 1 with `can't play …` or `no video file at …`; `--project` with a path the project doesn't list is refused, naming `project add` | `{"app": {…, "active": true}, "window", "screen": "player", "video": {…}, "player": {…}, "project": {…}}` |
| `window list` (L54) | `windows: 2`, then a line per window | `{"windows": [{"id", "key", "onScreen", "screen", "video", "listener"}]}` |
| `window new` (L54) | `w2 opened, showing home` | `{"window": "w2", "windows": […]}` |
| `window close [<id>]` (L54) | `w2 closed` | `{"window": "w2", "windows": […]}` |
| `project new <slug> --from <path> [--title <title>]` (L59) | `project launch-video made with cut1.mp4 as v1`; refused for a slug in use and a missing or unplayable file | `{"project": {…}}` |
| `project add <slug> <path> [--label <label>]` (L59) | `cut2.mp4 added to launch-video as v2, shown in w1`; refused for a listed path, an unknown slug and a missing or unplayable file | `{"window", "video": {…}, "project": {…}}` |
| `project list` (L59), with no app | `launch-video "Launch video", 2 versions`, then `  v1 /abs/cut1.mp4 (<label>)` per version; `no projects; …` with none | `{"projects": [{"slug", "title", "versions": [{"number", "path", "label"}]}]}` |
| `config path` (L53), with no app | the path of `config.toml` | `{"config", "themes", "exists"}` |
| `config check` (L53), with no app | `config.toml reads: <path>` (`doesn't read`), then a line per problem and warning; exit 1 when it doesn't read | the verdict, as `config-status.json` holds it |
| `config dismiss` (L53) | `the settings notice is closed` (`no settings notice was up`) | `{"dismissed": true}` |
| `app home` (L49) | `home, 3 recent videos, your data` (`demo data` on a run started with `app open --demo`) | `{"app": {…}, "screen": "home"}` |
| `app demo` (L49) | `opened havooch-demo.mp4 (0:55.033) on demo data in w1` | `{"app": {…}, "window", "screen": "player", "video": {…}, "player": {…}}` |
| `comment add <text> [--at] [--region] [--thread]` | `m-f92cbb2a-3 queued on #2 at 0:12` (`… on the region 0.25,0.2,0.3,0.25`) | `{"message": {…}, "thread": {"id", "number"}}` |
| `comment edit <message-id> <text>` | `m-f92cbb2a-3 edited` | `{"message": {…}}` |
| `comment delete <message-id>` | `m-f92cbb2a-3 deleted` | `{"deleted": "m-…"}` |
| `comment open [<text>] [--region]` (L22) | `popover open on #1 at 0:12.5` (`… on the region 0.25,0.2,0.3,0.25`) | `{"popover": {"thread", "time", "text", "region"}}` |
| `send` | `s-f92cbb2a-1 sent: 3 messages on 2 threads, taken by the listener` (or `…, waiting for a listener`) | `{"send": {"id", "sentAt", "messageIds", "threadIds"}}` |
| `thread answer <thread> <text>` | `#1 answered` | `{"message": {…}}` |
| `thread choose <thread> <number>` | `#1 answered: <choice>` | `{"message": {…}}` |
| `thread open <thread> [--frame x,y,w,h]` (L29) | `popover open on #3 at 0:12.5` | `{"popover": {"thread", "time", "text", "region"}}` |
| `thread show <thread>` (L39) | `the sidebar shows #1` | `{"sidebar": {"thread": "t-…", "width": 340, "composer": {…}}}` |
| `thread list` (L39) | `the sidebar shows the thread list`; it leaves the Connect view too | `{"sidebar": {"mode": "threads", "thread": null, "width": 340, "composer": {…}, "connect": null}}` |
| `thread versions [--search <text>] [--close]` (L61) | `All versions is open` (`All versions is closed`); refused on a plain video | `{"sidebar": {…, "versions": {…, "menu": {"search", "inList", "stillOpen", "older"}}}}` |
| `thread version <n> [--remove]` (L61) | `the thread list shows v12` (`v12 left the thread list`); refused on a plain video, outside the list, and, with `--remove`, for a version that isn't picked | `{"sidebar": {…, "versions": {"sections", "removedSection", "onScreen", "picked", "showing", "older", "stillOpen", "menu"}}}` |
| `version show <n>` (L62) | `v1 on screen in w1 at 0:01.5`; refused on a plain video and outside the list | `{"window", "video", "player", "project": {…, "switcher": {…}}}` |
| `compare open`, `compare pick <left\|right> [<query>]` (L63) | `compare: popover, v3 on the left and v4 on the right, side by side`, then an open picker's `  picker left "v1": 1 match, v1 highlighted`; refused on a plain video, a project of one version and while comparing | `{"window", "player", "project": {…, "compare": {"phase", "left", "right", "layout", "showing", "slider", "active", "picker": {"side", "query", "matches", "highlighted"}}}}` |
| `compare set [--left <n>] [--right <n>] [--layout <l>] [--side <s>] [--slider <0-1>]`, `compare swap`, `compare start` (L63) | `compare: v3 on the left and v4 on the right, side by side, messages go to v4 on the right`; set and swap are refused with Compare closed, `--side` in the popover, a version outside the list | the same |
| `compare exit` (L63) | `Compare is closed: v4 on screen in w1` (`Compare wasn't open`) | `{"window", "player", "project", "dismissed"}` |
| `version pick [<query>]`, `version close` (L62) | `the version picker is open: 1 of 4 versions match `v1`, v1 highlighted` (`the version picker is closed`); pick is refused on a plain video and for three versions or fewer | `{"window", "project": {…, "switcher": {"segments", "selected", "field", "picker": {"query", "matches", "highlighted"}}}}` |
| `connect show` (L57) | `the sidebar shows the Connect view` | `{"sidebar": {"mode": "connect", …, "connect": {"reason", "phase", "harness", "readiness", "prompt", "banner", "listener"}}}` |
| `connect pick <harness>` (L57) | `picked codex: the skill isn't detected; …`, then `prompt: $havooch-mate listen for my feedback on <video>` | `{"sidebar": {…}}` |
| `connect disconnect` (L57) | `Claude Code disconnected`; refused with no agent connected | `{"sidebar": {…}}` |
| `first-run show [<step>]` (L60) | `the first-run window shows welcome`; refused for a step that isn't one | `{"firstRun": {"showing", "step", "done", "harness", "readiness", "prompt", "agentConnected", "problem"}}` |
| `first-run next`, `first-run back` (L60) | `the first-run window shows tools`; refused past the last or the first step, and with the window closed | `{"firstRun": {…}}` |
| `first-run pick <harness>` (L60) | `picked codex`, then `prompt: $havooch-mate use Havooch to open the demo video and listen for my feedback` | `{"firstRun": {…}}` |
| `first-run demo` (L60) | `opened havooch-demo.mp4 in w1, playing; the first-run window is closed`; refused in a build with no bundled video | `{"firstRun": {…}}` |
| `first-run skip` (L60) | `the first-run window is closed`; refused with it closed | `{"firstRun": {…}}` |
| `connect forget` (L57) | `Claude Code forgotten: no agent is waited for`; refused with none reconnecting | `{"sidebar": {…}}` |
| `tour show` (L58) | `the tour shows step 1 of 5: Give your agent two tools` | `{"tour": {"open", "step", "stepNumber", "steps", "title", "rings", "replied", "finishSetup", "setupItemsLeft"}}` |
| `tour next` (L58) | `the tour shows step 2 of 5: Connect your agent`; after the last step `the tour is finished`; refused while the tour doesn't show | `{"tour": {…}}` |
| `tour skip` (L58) | `the tour is skipped; Finish setup or havooch tour show starts it again`; refused while it doesn't show | `{"tour": {…}}` |
| `tour close` (L58) | `the tour is closed at step 2 of 5; havooch tour show opens it there`; refused while it doesn't show | `{"tour": {…}}` |
| `comment compose [<text>] [--region] [--general]` (L41) | `the composer says "New thread at 0:12"` (`… with the region 0.25,0.2,0.3,0.25`) | `{"composer": {"target", "kind", "thread", "number", "time", "general", "text", "region"}}` |
| `theme list` | one line per theme: name, kind, `built-in` or `user`, `active` / `pinned` marks; then `left out: <reason>` per file left out | `{"themes": [{"name", "kind", "source", "path", "active", "pinned"}], "problems": ["…"]}` |
| `theme set <name>` | `theme Dimmed pinned`, or `theme follows the system (Default Dark)` for `system`; names match without regard to case | `{"theme": {…}}` as in `state` |
| `setup status` (L52) | `command line: detected, <link> links to <command>`, then `harnesses:` and one row per harness (`Codex  harness detected, skill not detected`), then the install's line and its last 20 log lines | `{"commandLine": {"detection", "path", "destination", "command", "failure", "fallback"}, "harnesses": [{"name", "installName", "presence", "skill", "skillFolder", "prompt"}], "install": {…} \| null}` |
| `setup link [--dry-run]` (L52) | `linked <link> to <command>`; refused with the reason and `Run this in a terminal: mkdir -p ~/.local/bin && ln -sf …`; `would link …` for a dry run | `{"setup": {…}}` |
| `setup install [--harness <name>]... [--dry-run]` (L52) | `install: running for Codex: npx skills add …` and how to follow it; `would run: npx skills add …` for a dry run | `{"install": {"state", "harnesses", "command", "repositoryCommand", "exitStatus", "log"}}` |
| `setup cancel` (L52) | `install: cancelled for Codex: npx skills add …`, once it has stopped; refused with no install running | `{"install": {…}}` |
| `wait [--video <path> \| --project <slug>] [--timeout]` (L56, L59) | the payload JSON, with or without `--json`; with neither flag, the key window's review | same |
| `ack <send-id> [<text>]` | `s-f92cbb2a-1 acknowledged, 3 messages` | `{"send": {…}}` |
| `status <message-id> working\|done\|failed [<text>]` (#47; the text with `working` only) | `m-f92cbb2a-3 working` | `{"message": {…}}` |
| `reply <thread> <text>` | `m-f92cbb2a-7 on #2` | `{"message": {…}}` |
| `ask <thread> <question> [--choice <text>]... [--wait]` | the answer's text, exit 0; exit 2 and nothing when the wait runs out | `{"answer": {…}}` |

`wait` connects again while the app is not running, as in proto-2. Every other proto-2 rule of the command layer holds: options and words (D201), `app open` relaunch and handover, the launcher, exit 64 for wrong usage.

### ReviewCore: the thread model

```swift
public struct Review: Codable, Equatable {          // one video's review
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
- **A message** is `id` (`m-<hash8>-<n>`), `author` (`person` | `agent`), `kind` (`message` | `question` | `answer`), `text` (trimmed, never empty), `at`, `region` (person messages only), `state` (person `message`s only), `sendID` (once sent), `sessionName` (agent messages only: the listener session's name when it was written, L40) and `choices` (a question's quick replies, trimmed, each once; nil with none, #46). `StateReport.Message` names `choices` only for a question with some. A region message's crop is `crops/<message-id>.png`, written before the message enters the review.
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

`AppModel.send()` queues the open popover's text first (as proto-2 did with a draft), then calls `Review.send` with a closure that reads `TranscriptDesk.lines(around: thread.time)` for each thread in the send with a frame, and hands the `SendRef` to `ListenerQueue`. The lines are the ones the source has at that moment; every delivery, the first included, uses the kept lines and needs no transcriber (D A.4). `ReviewCore` keeps a line as its own small value, `SendPayload.Line` (`start`, `end`, `text`), so it still does not import `ReviewTranscript`; `ItemID` is `CodingKeyRepresentable`, so the map by thread is a JSON object.

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
- `video.demo` is `true` when the content hash is the bundled demo video's (`DemoVideo.contentHash`, P12): the skill then reads its demo reference (L60).
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
extension ThemeColor {
    public static let filledTextContrast = 4.5                     // white text on a filled control (ADR 0006)
    public func contrast(with other: ThemeColor) -> Double         // the WCAG ratio, 1 to 21
    public func filled() -> ThemeColor                             // itself, or darkened in 1% steps until white reads at 4.5:1
}
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

`resolve` walks the `extends` chain first, then the default theme of the theme's kind, then applies the overrides (D 5.2, D 5.5). A token name the catalog does not know is ignored, and a colour text that does not parse counts as missing. A chain that loops, or names a theme that does not exist, leaves that theme out of the catalog, with its reason in `problems`; resolving a name the catalog does not have is `ThemeRefusal.unknown`. Names match without regard to case. A user theme named `Default Dark` replaces the built-in one, but the built-in defaults stay the last fallback, so a partial replacement still resolves every token. The two default themes must define every token; a test proves it. One exception to the order: when a theme sets `accent` nearer than `accentFill` (in itself, a theme it extends, or an override), `accentFill` is that accent's `filled()`, so a person's brown theme gets a brown fill that white text reads on, not the default's blue (L50).

The tokens (each addition is one case and one value in each default theme). 0.2.0 put the whole window on one surface (L36) and removed `stage`, `bar`, `sidebar`, `sidebarSection`, `sidebarRowHover`, `sidebarRowSelected` and `header`, and the native buttons left `controlPressed` with no view (L43); a user theme that still sets one loads, since an unknown token is ignored. A token may carry an alpha (`#rrggbbaa`): the hover fill, the region's dim and the shadow do. A surface token (`window`, `popover`, `notice`, `field`, `separator`) may be `system`, the native macOS part; the default themes set all five so (L37).

| Group | Tokens |
|---|---|
| surfaces | `window`, `letterbox`, `popover`, `popoverBorder`, `field`, `well`, `track`, `knob`, `shadow`, `controlHover` |
| text | `textPrimary`, `textSecondary`, `textTertiary`, `textOnAccent` |
| accent | `accent` (lines, selections, rings, pins; no text on it), `accentFill` (the fill of filled controls, white text on it at 4.5:1 or more, L50), `control` (the agent-control icon), `separator` |
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
  outboxes/video-<contentHash>.json      one review's Outbox (L56)
  outbox.json                            an older build's one Outbox: split once into outboxes/, then deleted (L56)
  recents.json                           the 10 recent videos, the newest first: path, content hash, opened time, last position
  settings.json                          the sidebar width (app state); an older build's theme and overrides, until the move (L53)
  config-status.json                     the verdict on config.toml after the app's last reload (L53)
  config/                                with HAVOOCH_SUPPORT_DIR only: config.toml and themes/ (L53)
  videos/<contentHash>/
    review.json                          one Review: video, note, threads, sends, counters, schemaVersion
    transcript.json                      the finished speech transcript
    frames/<thread-id>.png               a thread's keyframe, at the video's own size
    crops/<message-id>.png               a region message's crop
```

```swift
public struct SupportLayout: Sendable {
    public let root: URL
    public var recentsFile, settingsFile, themesFolder, videosFolder, outboxesFolder: URL
    public func outboxFile(_ key: ReviewKey) -> URL                   // outboxes/<key.fileName>.json (L56)
    public var formerOutboxFile: URL                                    // outbox.json, split once into outboxes/
    public var formerRecentFile: URL                                    // recent.json, read once into recents.json
    public func folder(_ hash: String) -> URL
    public func reviewFile(_ hash: String) -> URL
    public func transcriptFile(_ hash: String) -> URL
    public func keyframe(_ thread: ThreadID, of hash: String) -> URL
    public func crop(_ message: MessageID, of hash: String) -> URL
    public func pendingImage(_ token: String, of hash: String) -> URL   // frames/.pending-<token>.png (L19)
}
```

- `Library(layout:)` only loads and saves: reviews, each review's outbox (`loadOutbox(key)`, `save(_:of:)`, through `Outbox.reconcile` with that review's unfinished sends on disk; `migrateFormerOutbox()` splits an older build's one outbox, L56), `recents.json` and `settings.json`. Its `init` reads every `review.json` once for the hash-prefix index (`contentHash(prefix:)`), the path index and the unfinished sends. It writes nothing until the first save.
- The recent videos: `recents()`, `recordOpened(url, contentHash:, at:)`, `savePosition(seconds, of:)` and `removeRecent(contentHash)`. At most `recentLimit` (10) entries, the newest first. Opening a video on the list moves it to the front with its new path and keeps its position; the match is by content hash. Removing an entry leaves its review on disk. The list is read once and kept in memory. On the first read with no `recents.json` and a `recent.json`, the old path becomes the one entry, with the hash of the review that records that path, else of the file itself (no entry when neither is there), and the file's modification time as its opened time; then `recent.json` is deleted. A `recents.json` from a newer schema is never written over.
- Every save is atomic, pretty-printed, sorted keys, ISO 8601 with milliseconds, with `schemaVersion`. `review.json` starts at schema 1 again for this product (L9); the prototypes' files are never read, since they live in other support folders.
- A file from a newer schema, or one that does not read, is never written over (proto-2 D140).
- `ThemeFiles.read(folder)` reads the built-in themes from `Contents/Resources/Themes/` in the app (`Packaging/Themes/` in tests and in a build that is not bundled); the person's are read from `themes/` beside `config.toml` (`ConfigLocation.themesFolder`). A file that does not read is skipped with its reason.
- `Settings` is `{ sidebarWidth: Double? }`, app state, with its own `load(layout)` and `save(layout)` beside `Library`. A missing file is the defaults. A file that does not read is never written over. `Settings.former(layout)` reads the `theme` and `overrides` an older build left in it, for the one-time move into `config.toml` (L53); the next save leaves them out.

### ReviewSetup

What Havooch can say of the person's setup, and the two actions that change it (L52, ADR 0005). It depends on Foundation and `ReviewCore` (`KnownAgent`) only.

- `Detection` has three answers: `detected`, `notDetected`, `cannotKnow` (a folder on the way does not read). There is no "missing".
- `HarnessCatalog.all`: Claude Code, Codex, Cursor, Pi and OpenCode, each with its user skills folders, its presence hints (its app in `/Applications` or `~/Applications`, its command in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.bun/bin`, `~/.npm-global/bin`, and a few of its own), its `-a` name and its prompt form. `Harness.prompt(for:)` names the video's file name or `project <slug>`. `harness(named:)` takes an install name or a session's name.
- `SetupProbe(fileSystem, home).probe()` → `SetupReport`: the command link (`CommandLink.state()`: detected when `~/.local/bin/havooch` is a link to `…/<name>.app/Contents/Helpers/havooch` and that file is there; a relative link is read from its folder), the skill per harness (detected when `havooch-mate/SKILL.md` is a file, links followed, in one of its folders) and each harness's presence (any hint path there). It reads only these places, never a repository. `harnessesLackingSkill` is what an install with no harness named is for: found, and the skill not detected.
- `CommandLink.make(to:)` makes `~/.local/bin` and the link; a link already there is replaced, as `ln -sf` does, and anything else there is left alone. Every failure is a `Failure` with its reason and the fallback line `mkdir -p ~/.local/bin && ln -sf '<command>' ~/.local/bin/havooch`.
- `SkillInstall(for: harnesses, shell:)` holds `npx skills add yahyabedirhan/havooch --skill havooch-mate -g -y -a <name>…` and the same without `-g` for one repository. `run(with: runner, line:)` first runs `<shell> -l -c "command -v npx"` (no `npx` ends as `.noNode` and runs nothing), then `<shell> -l -c "exec <command>"`, each line handed on as it comes, and ends as `.finished(status)` or, when its task is cancelled, `.cancelled`. `LocalProcessRunner` runs a `Process` with standard output and standard error on one pipe, read on a thread of its own; cancelling terminates it.

### ReviewApp

`AppModel` (`@Observable`, main actor by the module's default isolation, D A.2) is the app (L54). Its methods are the app's actions:

| Method | Rules it owns | Refuses |
|---|---|---|
| `openInFront(url)` | `havooch open` (L51, L54): refuses a missing file or one AVPlayer cannot play (`PlayerEngine.checkPlayable`) before anything changes, then `leaveDemo()` as the Open panel does; `windowFor(url)` finds the window: the one that holds the video (by content hash) comes forward as it is, else the key window when it holds nothing, else a new window (made, the video opened in it, then its scene opened); then play, `focus(window)` and `bringToFront` (the app sets it: `NSApp.activate()`) | no file; a file AVPlayer cannot play; as `WindowModel.open` |
| `openFromFinder(urls)` | Finder's Open With, a drop on the Dock icon and `open -a` (L55): each file through `openInFront`, one after another (also across two handovers in a row), so the first fills an empty key window and the next ones open in new windows. Before the launch's first scene appears (`WindowRegistry.openScene` is nil) the files wait, and `sceneAppeared` opens them. A refusal is the key window's `problem`, or a new window's with none | as `openInFront` |
| `openForPerson(url, from:)`, `openFromPanel(from:)` | the Open panel, a drop and a recent card in a window (nil from the menu with no window): `leaveDemo()`, then the window that holds the video comes forward, else the window it came from opens it, else as `openInFront`. A refusal is the window's `problem` | as `WindowModel.open` |
| `makeWindow()`, `newWindow()`, `sceneAppeared(target:)` | a window's model: made with the next id; `newWindow` (File › New Window, the Dock icon with no window, `window new`) also opens its scene, which takes it as it appears (`WindowRegistry.place`); a scene that appears with none waiting (the launch) gets a new empty one | |
| `window(id, making:)` | the window an operator command acts on: `--window`'s, else the key window; `player open`, `app home` and `app demo` make one when there is none | an unknown id, listing the windows; no window |
| `windowList()`, `openWindow()`, `closeWindow(id)` | `window list`, `window new`, `window close`: closing pauses the window's video, keeps its position and drops the window (`windowClosed`); the app runs on with no window | an unknown id; no window |
| `state(window:)` | `state`: the window's report, with every window; with no window, `screen: none` and no video | an unknown id |
| `enterDemo(video, in:)`, `leaveDemo()` | the in-app demo (L27): every window queues its popover's words and closes its video, the `DataFolder` switches to the demo folder, and the window opens the video there; or every window's video closes and the data switches back to `launchSupport`; a run started on demo data never switches | as `WindowModel.open` |
| `openDemo(in:)` | "Try the Demo" and `app demo` (L49): `enterDemo` on the bundled video (`demoVideo`, `DemoRun.video()` by default) in that window | no bundled video; as `enterDemo` |
| `recents`, `refreshRecents()`, `removeRecent`, `savePositions()` | the recent videos of the data, the same in every window (L48); every window's position on quit | |
| `keepSidebarWidth(width)` | the sidebar's width, one for every window (below) | |
| `setTheme(name)`, `themeList()` | through `ThemeDesk`; `system` unpins | unknown theme |

`WindowModel` (`@Observable`) is one window's orchestrator. Its methods are the product's actions in that window:

| Method | Rules it owns | Refuses |
|---|---|---|
| `open(url)` | as proto-2: hash, load the review, load the video, record path and frame rate, prepare the transcript, read the context, save the position of the video that goes, put it first on the recent videos; closes any popover. The review is the desk's, by content hash (`review`) | a file AVPlayer cannot play; a review that does not read; a video another window holds (`… is open in window w1`), checked before and after the load |
| `goHome()`, `goHomeForPerson()` | home (L49): an in-app demo is left (`AppModel.leaveDemo`, every window goes home); otherwise the popover's words are queued on their video (`settle`), the position saved and the video closed (`leaveData`). Then `refreshRecents()`, so a moved file's card turns unavailable. `goHomeForPerson` runs it from the header's mark and File > Close Video | |
| `openDemo()`, `tryDemo()` | `AppModel.openDemo(in: self)` | as `openDemo(in:)` |
| `closed()` | its window closed (Cmd+W, `window close`): the popover's words are queued, the video pauses and its position is kept; the review stays (L54) | |
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
| `versionTree`, `allVersionsMenu` | a project's thread list by version (L61), from `projectOutline`, the threads, the version on screen and `pickedVersions`; the menu while `versionMenu` (its search) is set | nil on a plain video |
| `openVersionMenu(search:)`, `closeVersionMenu()`, `pickVersion(_:)`, `removePickedVersion(_:)` | All versions and `thread versions`; a pick in it, a Still open chip and `thread version`: an older version joins `pickedVersions`, the menu closes, `versionJump` scrolls the list; a picked section's close button and `--remove`. A change of project empties both; Escape closes the menu first | a plain video; a number outside the list; removing a version that isn't picked |
| `versionSwitch`, `versionPicker`, `projectWords` | the header's switcher and title in a project (L62): `VersionSwitch` (pure) from `projectOutline`, the threads per version and each file's date; the picker's search and highlight | |
| `switchVersion(to:)`, `openVersionPicker(query:)`, `closeVersionPicker()`, `typeVersionQuery`, `moveVersionHighlight`, `openHighlightedVersion` | a segment, the field, the picker's keys and rows, `version show`, `version pick`, `version close`: the version comes on screen with the playhead at the same time; the thread list's on-screen section follows it (`versionTree` reads the version on screen) | plain video; outside the list; pick on three versions or fewer |
| `compare`, `pair`, `companion`, `activeSide`, `canCompare`, `compareReport` | Compare (L63): the popover's `CompareSession` or the comparison; while comparing, `engine` and `video` are the active side's and `companion` the other side's version | |
| `openCompare()`, `toggleCompare()`, `pickCompareSide(_:query:)`, `typeCompareQuery`, `moveCompareHighlight`, `pickHighlightedCompareVersion`, `closeComparePicker()` | the Compare button and `compare open`, a side's chip or picture and `compare pick`, the picker's keys and rows | plain video; one version; while comparing |
| `setCompare(_:)`, `swapCompare()`, `startCompare()`, `exitCompare()` | `compare set`, the swap button, the popover's action and `compare start`, Exit Compare, Escape and `compare exit`: a side's new version loads on its own player at the playhead's time; start loads the other side's player and makes the `PlayerPair`; exit retires the left side's player and keeps the right one | Compare closed; a version outside the list |
| `activate(_:)`, `clickFrame(on:)`, `beginRegion(on:)`, `flipCompare()`, `slideCompare(to:)`, `frameMarks(on:)` | a click or a drag on a side, a thread of the other side's version, `version show` of a side's version and `compare set --side`: the side becomes active (words in the popover are queued first on their version, captured in `Showing`); the flip key; the slider's handle; each side's marks | |
| `composerTarget`, `composerText`, `composerRegion` | the composer at the sidebar's foot (L41): `ComposerTarget.resolve` (pure) from the thread shown, the General toggle, the thread of the frame on the stage and the drawn region; the text is the target's draft in `composerDrafts`, one per thread and one for a new thread | |
| `writeComposer()`, `submitComposer()` | Return in the composer: an answer at once with an open question (D 2.16), else queued on the target (a new thread at the frame, the frame's thread, General, the thread shown), with the region chip when it fits; the draft, the chip and the General toggle are spent; the player stays. `sendQueue` takes the words too; `send()` answers first | empty text; no video |
| `compose(text, region?, general)` | `comment compose` (L41): the words, a region chip on the player's frame and the General toggle in the composer, which takes the keys | no video |
| `keepSidebarWidth(width)` | the end of a drag on the sidebar's edge: `AppModel.keepSidebarWidth`, the width, inside `Metrics.sidebarWidthRange`, goes to `settings.json` on the folder the run started on (`AppModel.keptSidebarWidth`); `sidebarWidth` reads it back, the default 340 without one, the same in every window | |
| `movePopover(id, frame)` | the end of a drag or a resize: saves the `PopoverFrame` | |
| `send()` | answer with the composer's words when it answers, queue the open draft's text and the composer's, then `ReviewDesk.change { $0.send(…) }`, then the window's `ListenerQueue.enqueue`; does nothing while a send is under way | nothing queued (`send` exits 1) |
| `answer(thread, text)` | `thread answer` and the field: through `ReviewDesk`, then the review's `ListenerQueue.answered` | no open question |
| `choose(thread, choice:)`, `chooseAnswer` | `thread choose` and a quick-reply chip: `answer` with the open question's choice of that number | no open question; no such choice |
| `setContextNote(text)` | as proto-2 | no video |
| `state()`, `report(isKey:)` | the window's `state`, with `window` (its id) and `windows[]`; its line in `window list` | |

- `Draft` is view state only: `time`, `region`, `text`. The thread it writes to is computed (`draftThreadNumber`: the thread at that frame, or the number a new thread will take). It is never saved (D 1.4). `state --json` reports it as `popover`, with that number.
- **Frame time** (L2): `PlayerEngine.frameTime(of: t)` is the start of the frame shown at `t` (from the track's nominal frame rate), raised to the next millisecond, as proto-2 raised a comment's time (D46). Every thread time goes through it, from the UI and from `--at`. The frame length comes from the nominal rate snapped to a whole or an NTSC rate (L20).
- `ReviewDesk.change(hash) { … }` is proto-2's one path for a change: load or take from memory, run, save, publish; a refusal or a failed save changes nothing. The desk keeps no open review any more: each window reads its own by content hash (`opened(hash)`, never from disk), and `threadID(text, open:)` takes the window's video for a bare number (L54).
- `ListenerHub` (L56) holds one `ListenerQueue` per `ReviewKey`, made the first time a review needs it and kept for the run. `ControlServer` asks `AppModel.listenedReview(video:)` which review a `wait` binds to, then waits on that queue; `ack` and `status` find their queue by the id's `hash8`, `reply` and `ask` by the thread id's (a bare number: the key window's video). `isDelivered`, `connectionClosed` and `stop` go to every queue. A `WindowModel`'s `listener` is its review's queue; the footer's presence pill, the activity lines and the agent's name read it.
- `ListenerQueue` is proto-2's with sends, one per review: `enqueue`, `wait(by:timeout:connection:)` → `Outcome` (`send(ref, payload)`, `ranOut`, `replaced`, `takenOver(by:)`, `gone`), `written`, `undelivered`, `isDelivered`, `connectionClosed`, `ack`, `status`, `reply`, `ask`, `answered`. A send is marked `taken` only once its reply was written (proto-1's in-flight rule): until then it is kept out of every other `wait`. `ack`, `reply` and `ask` hand a `Notice` to `AppModel`, which raises it in the window that holds the thread's video, and in no window when none does; `status` raises none. A bare thread number in `reply` and `ask` is the key window's video (`ListenerHub.keyVideo`). A `wait` from another holder while the last one was present (not absent) is a takeover: the older `wait` ends as `takenOver(by:)`, `takeover` keeps who from whom, and a `.takeover` notice "<new> took over from <old>" goes up on General in the window that holds the review. `status working` with a text sets the thread's live line (`Activity`: thread, message, text, time; #47), the latest one per thread and kept in memory only; `done` or `failed` on its message, an empty text, and a new listener session clear it. `activities(at:)` and `activity(on:at:)` give nothing while the presence is absent, and `state` reports them, newest first, as `listener.activity`.
- `Notice` is `thread` (id and number), `agent`, `kind`, `words`, `expires` (5 s for every kind, a question too: the question stays open on its thread, L28). Its title is `#3 · Claude Code: …`, General's `General · Claude Code: …` (D 4.10). A click calls `openThread`, or shows General's thread view.
- `ThemeDesk` holds the `ThemeCatalog`, the `ConfigDesk` whose `config.toml` names the pin, and the system appearance, and publishes the `ResolvedTheme`; it reads the themes again each time `ConfigDesk` applies other settings (L53). The system appearance is `NSApp.effectiveAppearance`, observed, so a screenshot in the other appearance shows that appearance's default theme. `DispatchSource`s on `themes/` beside `config.toml` and each theme file reload the themes 150 ms after a change (D 5.6); the watches are made again after each reload, since an editor that saves by replacing a file makes a new one. `startWatching` makes `themes/`, so a person finds where their themes go. A theme problem, or a pin no theme has, is written to standard error once and listed by `theme list`. `Palette` turns the resolved tokens into `Color`s, reaches every view through the environment (`@Environment(\.palette)`), and is the only colour source a view has (D 5.1); a test in `ReviewAppTests` fails on a raw colour anywhere in `Sources/ReviewApp`, and in `Palette.swift` on anything but a colour from numbers or a `system` surface (L37). The letterbox is a token too. While a theme is pinned, the window takes its kind's appearance, so the title bar and the system's controls match; with no pin it inherits the app's. `RootView` sets it with `preferredColorScheme`, never on the `NSWindow` itself: SwiftUI sets the window's appearance on each update from that preference, and an AppKit view that set it as well fought SwiftUI in an endless update loop when a light theme was pinned under a dark system. The View menu's Theme picker and the Settings window's (`ThemePicker`, L42) pin a theme or follow the system, as `theme set` does.
- `SetupDesk` (L52), app-wide on `AppModel.setup`, reads `HOME` and `SHELL` from the app's environment, and finds this bundle's `Contents/Helpers/havooch` (none in a build that isn't bundled). It probes at launch, on `applicationDidBecomeActive`, after Link and after an install ends, and on `setup status`; it never polls (P10). `link()` keeps a failure (`linkFailure`) for the view and refuses with the `ln -sf` line. `startInstall(for:)` refuses while one runs, for a name no harness has, and with nothing to install for; it keeps the install as `InstallRun` (`running`, `done`, `failed`, `cancelled`, `noNode`, the exit status, the last 500 log lines) after it ends. The runner's lines reach the main actor in order through an `AsyncStream`. `cancelInstall()` cancels the install's task and answers once it has ended. `state --json` reports it all as `setup` (`StateReport.Setup`), with each harness's prompt for the open video, and `state` prints one `setup:` line. The Connect view (L57) reads the same desk: `isLinked`, `isSkillDetected` (detected for one harness at least and every harness found) and `isDetected`.
- `SocketListener` (D A.8, proto-1) accepts on `control.sock` (mode 0600) off the main actor, reads one request per connection, awaits `ControlServer.reply(to:)` in a task, and writes one space every 2 s while the answer is pending. A heartbeat that cannot be written tells the server the client hung up (`connectionClosed`), which ends a held `wait` or `ask` as `gone`. It then writes the reply; a reply that was written goes to the server as `written` (a send it carried is taken), and one that cannot be written as `undelivered` (L16). The heartbeat replaces proto-2's look at the connection every 0.5 s.
- `ControlServer` only decodes, checks the lease, dispatches and keeps the queued `take`s. It owns the one `ControlLease` and settles it on a timer. It depends on the `AppControlling` protocol (the app: `state(window:)`, `controlledWindow`, `openInFront`, the window commands, the themes), which `AppModel` implements, and `WindowControlling` (one window's actions), which `WindowModel` implements; the tests' fake is both. An operator request acts on `ControlMessage.window` (`--window`), else the key window (L54).
- `AgentControlIcon` is the lease as the agent-control icon shows it. `AgentControlButton` (in `Header/AgentControl.swift`) is the icon, left of Context, only while an agent holds the lease, and its popover: who, where, time left, how many wait, Stop (D 4.7). The icon shows in screenshots unless `--hide-agent-indicator` (L10).
- `StateReport` builds `state --json`:

```json
{
  "app":      { "version": "0.4.0", "demo": true, "support": "/abs/demo", "active": true },
  "window":   "w1",
  "windows":  [ { "id": "w1", "key": true, "onScreen": true, "screen": "player",
                  "video": { "path": "/abs/cut2.mp4", "title": "cut2.mp4", "contentHash": "…", "project": "launch-video", "version": 2 },
                  "listener": { "presence": "listening", "session": "Claude Code" } } ],
  "screen":   "player",
  "lease":    { "holder": {…}, "taken": "…", "ends": "…", "secondsLeft": 48, "waiting": 0 },
  "listener": { "presence": "listening", "waitOpen": true, "session": "Claude Code", "pendingSends": 0, "takenSends": 0, "activity": [],
                "tookOverFrom": null },
  "theme":    { "active": "Default Dark", "kind": "dark", "pinned": null, "appearance": "dark", "accentFill": "#48689d" },
  "setup":    { "commandLine": { "detection": "detected", "path": "…", … }, "harnesses": [ { "name", "installName", "presence", "skill", "skillFolder", "prompt" } ],
                "install": null, "agentConnectedOnce": true, "needsFinishing": false },
  "firstRun": { "showing": false, "step": "welcome", "done": true, "harness": "claude-code", "readiness": "ready", "prompt": "…",
                "agentConnected": true, "problem": null },
  "config":   { "path": "/abs/demo/config/config.toml", "themes": "/abs/demo/config/themes", "status": "/abs/demo/config-status.json",
                "accepted": true, "problems": [], "warnings": [], "notes": [], "notice": null },
  "video":    { "path": "/abs/cut2.mp4", "contentHash": "…", "duration": 21.233, "title": "cut2.mp4", "contextNote": "" },
  "project":  { "slug": "launch-video", "title": "Launch video", "version": 2,
                "versions": [ { "number": 1, "path": "/abs/cut1.mp4", "label": null }, { "number": 2, "path": "/abs/cut2.mp4", "label": "tighter intro" } ],
                "switcher": { "segments": [1, 2], "selected": 2, "field": null, "picker": null }, "compare": null },
  "player":   { "time": 10.017, "playing": false },
  "transcript": { "source": "voiceover", "complete": true, "lines": 3, "problem": null },
  "popover":  null,
  "sidebar":  { "mode": "threads", "thread": null, "width": 340, "composer": { "target": "Reply on #1", "kind": "reply", … },
                "connect": null, "versions": { "sections": [2, 1], "removedSection": false, "onScreen": 2, … } },
  "tour":     { "open": false, "step": "tools", "stepNumber": 1, "steps": 5, "title": "…", "rings": [], "replied": false,
                "finishSetup": false, "setupItemsLeft": 0 },
  "threads":  [ { "id": "t-f92cbb2a-0", "number": 0, "time": null, "version": null, "state": null, "keyframePath": null, "unread": false, "messages": [] },
                { "id": "t-f92cbb2a-1", "number": 1, "time": 10.017, "version": { "number": 1, "path": "/abs/cut1.mp4", "label": null },
                  "state": "queued", "keyframePath": "/abs/…png", "popoverFrame": null, "unread": false,
                  "messages": [ { "id": "m-f92cbb2a-1", "author": "person", "kind": "message", "text": "…", "at": "…",
                                  "state": "queued", "region": null, "cropPath": null, "sendId": null } ] } ],
  "queue":    [ "m-f92cbb2a-1" ],
  "sends":    [ { "id": "s-…", "sentAt": "…", "messageIds": [ "m-…" ], "threadIds": [ "t-…" ] } ],
  "recents":  [ { "path": "/abs/sample.mp4", "title": "sample", "contentHash": "…", "openedAt": "…", "position": 10.017, "available": true } ],
  "projects": [ { "slug": "launch-video", "title": "Launch video", "versions": 2, "latestPath": "/abs/cut2.mp4", "available": true, "openedAt": "…" } ]
}
```

`project` is `null` on a plain video, `sidebar.versions` too; `project.compare` is the comparison while Compare is open (L63), `project.switcher` the header's switcher (L62).

- `state` describes one window, `--window`'s or the key window (`window`), and lists every window (`windows[]`: id, whether it is key, whether it is on screen, its `screen` and the video it holds); with no window open, `window` is null, `windows` empty and `screen` is `none`. Its lines say `window: w1` under the first line and end with `windows: N` and a line per window, as `window list` prints them.
- Recent videos: `WindowModel.open` calls `Library.recordOpened` (the newest first, matched by content hash, at most 10). `WindowModel.savePosition()` keeps the player's time on the window's video's entry; `open` calls it for the video that goes, `closed()` when the window closes, `AppModel.savePositions()` for every window in `applicationWillTerminate`, and `goHome()` (L49). `AppModel.recents` is the list as `StateReport.Recent` (path, title without the extension, content hash, opened time, position, `available`: whether the file is there now), read from `desk.library` on each call, so it belongs to the data folder the run is on; a revision counter makes views follow it. Nothing tells the app that a file moved, so `refreshRecents()` has the views read the list again, with each file's `available` as it is now: `goHome()` calls it, and `AppDelegate` on `applicationDidBecomeActive`, when the person comes back from Finder. `removeRecent(contentHash)` takes an entry off the list and leaves the review on disk. `openRecent(recent)` opens an available entry's video for the person and does nothing for one whose file is gone. The home screen shows the list (L48). `state` reports the list as `recents`, and its lines end with one line per entry. `state` reports `screen`: `player` with a video open, else `home`, for the home screen and the empty state alike (`StageContent.screen`, L49); its lines say `screen: home` under the first line.

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
| Sidebar | Two views (L38). The thread list: the title "Threads" and a summary line (`6 threads · 1 needs you · 2 queued`), then the groups Needs you, With agent, Queued, Done under headers with a glyph and a count that stay at the top while the list scrolls; Queued's says `⌘↩ sends them all`. A `ThreadRow`: an 88 × 50 pt keyframe thumbnail with its region outlines (a globe for General), the number and time, the state chip, the relative time, a chevron, and a two-line preview that names the writer (`You:`, `Asks:`, the agent), led by the agent's logo (or the sparkle) on an agent's message. An unread row (L46) has an 8 pt `accent` dot at its left, straddling the row's edge on the first line, its title bold, its preview in `textPrimary` and its time in `accent`; VoiceOver reads `Unread` first. A right-click on a row offers Open, Show on Video (not General) and Delete Queued Messages (when it has any), L40. Tab under keyboard navigation reaches each row, with the system focus ring, and Space or Return opens it (L43, L45). The thread view: a 44 pt top bar (Back with the count of the other threads that need the person, the number and time, Previous and Next), the conversation as a chat (L40) from the newest, under it the thread's activity (the working glyph and the words in `textSecondary`, #47), and the field at the foot (answer at once when a question is open, else queue); no keyframe. The view slides in from the trailing edge with the sidebar's spring, a fade with Reduce Motion. On the window's surface (L36): a row under the pointer takes `controlHover`, the row of the thread on the stage sits in a `well`, no cards. Resizable between the bounds of `Metrics.sidebarWidthRange` (300 to 460), width kept in `settings.json`, proto-1's animation for open and close. | D 3.1, D 3.2, D 3.7, D 4.5, D 5.10; replaces D 3.3, D 3.5, D 3.6 (spec 0.2.0) |
| Conversation | A chat (L40), from variant 02. The person's messages trailing, 46 pt in from the leading side, in `bubblePerson` (16 pt corners, a 5 pt corner at the trailing foot for the tail), no avatar; a quiet line under the bubble holds the state chip (an answer: `Answer · sent at once` in `question`), the `Region` tag in `regionOutline` and the time. A queued message: a dashed `stateQueued` outline, `controlHover` on hover, Edit and Delete beside it on hover, edited in place (Return saves, Escape cancels). An answer: `question` at 15% with a 40% border. The agent's messages leading, 34 pt in from the trailing side, in `bubbleAgent` (the tail at the leading foot); the 24 pt avatar (the harness logo, else the sparkle) beside the last bubble of a run, the name (`agent`) and time over the first. A question: a card in `bubbleQuestion` with a `question` border at 32%, headed `<agent> asks`; an answered one at 80% opacity. A region message's crop under its bubble. Messages 8 pt apart, 4 pt inside a run of the agent's. The name and logo are the message's `sessionName`, else the listener's. A right-click: Edit, Delete (queued only), Copy. VoiceOver reads one element per message: writer, kind, state, words (`MessageVoice`), with the menu's actions. The thread popover shows the same `Conversation`. In the thread view only, an open question with choices has a row under it: `Quick reply` in `textTertiary`, then one capsule chip per choice in `question` at 12% (22% on hover) with a 45% border, wrapping; a click answers at once. The row hides while a rectangle is drawn and while a drawn one is in the composer (`isPointingAtRegion`), #46. | D 3.4 replaced (spec 0.2.0) |
| Composer | Variant 02's composer at the sidebar's foot, above the footer, under a hairline (L41): a 22 pt target line (glyph, "New thread at 0:12", "Reply on #3", "Follow up on #3", or "Answer #3 · goes at once" in `question`), the `regionOutline` region chip with its ×, and in the list the General toggle: a `separator` outline, `controlHover` under the pointer; on, `accent` at 14% (22% under the pointer) with a 40% border (#74). The field: `field` with a `separator` border (`question` for an answer), 15 pt corners, the keys at its trailing foot, the system focus ring round the whole field; it grows from one line to about six. | L41 |
| Footer | proto-3's line: presence pill (`Listening`, `Working`, `Reconnecting`, `No agent`; hover names the agent; a click opens the Connect view, L57), the newest activity in `textSecondary` beside it (#47; it takes the width first and truncates only when the count and Send leave no room), the queued count, Send. Same height as the player bar, a `separator` hairline above it inside that height (L36). | D 4.8, D 4.9 |
| Header | The cat mark at the leading edge, a button that goes home (`goHome`, help tag "Home", L49). Title: video icon, full file name with extension. Subtitle: folder icon, the folder shortened in the middle, full path on hover, "Demo" in demo mode. Floating group at the top right: agent-control icon (while held), "Open a Video…" (the `folder` symbol, the Open panel, L49), Context, sidebar toggle. proto-2's Context popover. The title is a toolbar item with no shared background; the band is the `window` token, or the native toolbar when `window` is `system` (L26, L36, L37). | D 4.1 to D 4.4, D 4.7 |
| Notices | Top right of the stage, name the thread, open it on click, fade after 5 s, a question's too (L28). | D 4.10 |
| Structure | One surface, `window`, for the header, the stage, the player bar, the sidebar and its footer, native in the default themes (L37); `separator` hairlines on the sidebar's leading edge and above the footer; bubbles only for messages; no bordered cards. | L36, L37, replaces D 5.9 |
| Empty screen | The native `ContentUnavailableView` with the cat mark, "Open a Video…" and "Try the Demo" (switches the run to a demo folder under the user's temporary folder and opens the bundled launch video there, in the same window, L27). The whole stage is the drop target; a dashed accent outline shows over it while a file is over it (L42). | D 5.11 |
| Home screen | With no video and one or more recent videos, in place of the empty screen (L48): the cat mark at 64 pt and the app's name, "Open a Video…" (the default button) and "Try the Demo", then "Recent Videos" over a grid of adaptive columns (200 to 300 pt) of 16:9 cards, the newest first. A card: the thumbnail on the `well` surface with a `separator` outline (`accent` on hover), the name without its extension, the relative time in `textSecondary`, the path as its help tag. An unavailable card: dimmed, `video.slash` in place of the thumbnail, "Unavailable" in place of the time, a trash button at its top-right corner. No sidebar. The whole screen is the drop target, with the empty screen's outline. | Spec 0.3.0 (#65) |

### The listener skill

`.agents/skills/havooch-mate/SKILL.md`, with one reference, `references/first-demo.md`, which the agent reads only when a send's `video.demo` is `true` (L60). For threads:

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
ReviewCore/Review.swift             thread(atFrame: 10.017) → #1 (t-f92cbb2a-1); its keyframe exists
ReviewApp/Player/FrameGrabber.swift      crop → crops/m-f92cbb2a-2.png (557 × 162 of the 1920 × 1080 keyframe)
ReviewStore/SupportLayout.swift          crop(m-f92cbb2a-2, of: f92cbb2a…) → <demo>/videos/f92cbb2a…/crops/m-f92cbb2a-2.png
ReviewApp/ReviewDesk.swift               change { write(text, at: 10.017, region, to: nil, now) }
ReviewCore/Review.swift               appends m-f92cbb2a-2 (person, message, queued, region) to #1
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
ReviewCore/Review.swift               m-1, m-2, m-3 queued → sent, sendID s-f92cbb2a-1; transcripts kept for #1 and #2
ReviewStore/Library.swift                  review.json written
                                         state: queue = []; both pins the sent colour; footer "0 queued"
ReviewApp/ListenerQueue.swift            enqueue(s-f92cbb2a-1): pending = [s-1]; outboxes/video-<hash>.json written; takeNext()
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
ReviewCore/Review.swift             write on #1: m-f92cbb2a-9 queued              state: #1 is queued again (D 2.12)
operator: send
ReviewCore/Review.swift             send s-f92cbb2a-2: [m-9]; transcript for #1 cut again now
ReviewApp/ListenerQueue.swift            the listener's next wait: deliver s-2
ReviewCore/Outbox.swift                    context(for: hash, text): same digest for L1 → nil
ReviewCore/SendPayload.swift               threads: #1 only; history = m-1, m-2, m-5, m-6, m-7 in order; messages = [m-9]; "context": null
```

The rejections:

```text
comment edit m-f92cbb2a-1 "new text" after the send
  Review.edit → m-1 is sent → ReviewRefusal.notQueued → exit 1, nothing saved

the listener restarts as session L2 while s-2 is taken and m-9 is working
  Outbox.waitOpened(by: L2): a new key → s-2 to the front of pending; contextSent emptied
  Review.requeue(s-2): m-9 working → sent
  takeNext(): L2 gets s-2 with m-9, its kept transcript, the same history, and the context again
```

### Build and tests

- `Package.swift`: tools 6.2, macOS 26, no dependencies; `ReviewApp` uses `.defaultIsolation(MainActor.self)`; explicit `@MainActor` marks that the default makes redundant are removed (D A.2). `ReviewApp`, `ReviewAppTests` and the `HavoochApp` product are added under `#if os(macOS)` (D A.9).
- `make bundle` stamps `Havooch`, the bundle id and `0.2.0` into `Info.plist`, copies the app icon (`assets/images/logo/v2-havuc/AppIcon-light.icns`, `CFBundleIconFile`) to `Contents/Resources/AppIcon.icns` and `Packaging/Logo/` to `Contents/Resources/Logo/`, copies `Packaging/Themes/` to `Contents/Resources/Themes/`, `Packaging/AgentLogos/` (the logo PDFs and their `NOTICE.md`) to `Contents/Resources/AgentLogos/` and `fixtures/launch/` (the launch explainer) to `Contents/Resources/Demo/` (L17), and signs ad hoc. `make install` installs `/Applications/Havooch.app` and never touches the prototype apps; with `HAVOOCH_SUPPORT_DIR` set it opens the app on that folder.
- A release is a `v<version>` tag; the tag must match `Version.app`. `.github/workflows/release.yml` reads the name, the command and the version through `make identity`, zips the bundle with `ditto -c -k --keepParent` as `<command>-<version>.zip` with `<command>-<version>.zip.sha256` beside it, and publishes both. `scripts/install.sh` reads the app and command names from the zip, never from a constant; it finds an installed copy for `--uninstall` by the bundle id `com.<repository owner>.<command>`. The app is ad-hoc signed and not notarized, so the first launch needs Open Anyway (#49).
- Owner tests, one per contract at its strongest boundary:

| Contract | Owner test |
|---|---|
| version refusal, wire round trips | `ReviewWireTests` |
| the lease rules, the holder key order | `ReviewLeaseTests` |
| CLI parsing, output, exit codes | `ReviewCommandTests` |
| joining, thread numbers, states, thread state, send, transcript kept, requeue, payload shape, outbox, context once per session | `ReviewCoreTests` |
| theme resolution: extends, fallback, overrides, loops, the defaults define every token; `accentFill` made from a nearer `accent`; white on every shipped theme's `accentFill` at 4.5:1 | `ReviewCoreTests`, `ReviewStoreTests` (the shipped files) |
| `config.toml`: reading, problems on their lines, warnings, the location, the theme write keeping comments, the verdict, the schema equal to the reader | `ReviewConfigTests` |
| `config path`, `config check` with no app | `ReviewCommandTests` (`ConfigCommandTests`) |
| live reload, the last valid settings kept, `config-status.json`, the move from `settings.json`, app state kept out | `ReviewAppTests` (`ConfigDeskTests`, `ThemeDeskTests`) |
| the window cut, the source order | `ReviewTranscriptTests` |
| paths, round trips, the hash-prefix index | `ReviewStoreTests` |
| popover close rules, frame time, the send through `WindowModel` | `ReviewAppTests` on the fixture |
| which window an open goes to, what each window keeps, the window commands, `--window` (L54) | `ReviewAppTests` (`WindowTests`), `ReviewCommandTests`, `ReviewWireTests` |
| the server, the heartbeat, a gone client | `ReviewAppTests` over the real socket |
| the listener's round: ack, status, reply, ask and answer, a follow-up, a listener restart | `ReviewAppTests` over the real socket (`ListenerSocketTests`) |
| region crops at several window sizes | `ReviewAppTests` (proto-1's) |
| what a restart keeps | `ReviewAppTests`, a second `AppModel` on the same support folder |
| everything end to end | `scripts/acceptance.sh`, 20 steps against the installed app in demo mode: the spec's 10, `havooch open` (step 11, L51), the windows (12, L54), a listener per window (13, L56), the Connect view (14, L57), the tour (15, L58), projects (16, L59), the first-run window (17, L60), the thread list by version (18, L61), the version switcher (19, L62) and Compare (20, L63) |

## 5. Extensibility

| Change | What you touch |
|---|---|
| A new CLI command | a case in `ControlRequest`, a parser in `ReviewCommand` (`onAWindow()` when it acts on one window), a branch in `ControlServer`, a method on `WindowModel` (and `WindowControlling`), `AppModel` (and `AppControlling`) or `ListenerQueue`. The compiler finds the two `switch`es. |
| A new UI action | a method on `WindowModel`, or on `AppModel` when it is the app's, then its CLI command (ADR 0001). |
| A project in a window (#92) | a `WindowTarget` case; `WindowRegistry.holding` and `AppModel.windowFor` find it. |
| A new colour token | one `ThemeToken` case and its value in the two default theme files; the test of the defaults fails until both have it. |
| A new built-in theme | one JSON file in `Packaging/Themes/`. |
| Fonts or spacing in themes (after 0.1.0) | a second map in `ThemeFile` and `ResolvedTheme`; `Metrics` reads it as `Palette` reads colours. |
| A better transcription source | one `Transcriber`, one line in `TranscriptSources.standard`. |
| A new field in the payload | `SendPayload` and `assemble`. |
| A new message state | `MessageState`, `canMove`, a `state…` token. |
| A rule for a listener that never comes back (D A.11) | `Outbox.waitOpened` and a time check in `Outbox.presence`; nothing outside the outbox. |
| The popover redesign (D 1.8) | `ThreadPopover`, `CommentPopover.placement` and `StageView.Placement` only; the close rules stay in `AppModel`. |
| A database in place of JSON files | `Library` only. |

Refused for now: undo, an Allow button, system notifications, a plug-in registry of commands.

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
| L12 | Settings live in `settings.json`: the pinned theme (`null` follows the system), the overrides, the sidebar width. `theme set system` unpins. The app watches it beside `Themes/`. Replaced by L53. | The contract has one `theme set`; one word must return to the default (D 5.4). Overrides are edited in the file, so the file must reload. |
| L13 | Thread state with no person message (General with only agent messages) is no state; General has no pin. | D 3.9 defines state from person messages only. General has no keyframe to pin. |
| L14 | The open popover's field answers at once when the thread has an open question, else it queues. | D 2.16 and D 3.6 for one field, with no second control. |
| L15 | (Replaced by L46.) No unread marks. A notice and the thread's state carry the news. | The spec names none. proto-2's unread set was in memory only. |
| L16 | A send is marked `taken` only after its reply was written; until then it is in flight and no other `wait` gets it. | proto-1's rule, which pairs with the heartbeat of D A.8: a dead listener never loses a send. |
| L17 | "Try the demo" opens the launch explainer (`fixtures/launch/`) bundled in the app on the demo folder, `<temporary folder>/Havooch Demo`, in the same window (L27). The demo folder keeps its threads between demos. | The empty screen needs a demo with no command line (D 5.11), and demo data must never mix with the person's. |
| L18 | Notices for General say `General · <agent>: …` and show General's thread view on click (L38). | General has no frame to open (D 4.10). |
| L19 | A message's pictures are written under a pending name in `frames/` and renamed to `frames/<thread-id>.png` and `crops/<message-id>.png` once the review gave the ids. | The ids come from the review's counters, and a listener's `reply` written while the frame is read takes the next message number. Predicted names could be taken or overwritten; a rename on the main actor right after the write can't. |
| L20 | `PlayerEngine` snaps the track's nominal frame rate to a whole rate or an NTSC rate (n × 1000 / 1001) when it is within 0.001 of one. | AVFoundation gives the rate as a `Float` a hair off (29.999998 for 30), which put 10.0 s in the frame before. |
| L21 | `--thread 0` with `--at` or `--region` is refused (`noFrame`); without `--thread` a message always has a frame time. | General has no keyframe, so a time or a region on it means nothing. |
| L22 | `comment open [<text>] [--region x,y,w,h]` opens the comment popover at the player's frame, as C or a drawn rectangle does. An operator command, an addition to the contract. | The CLI cannot click or draw. Without it the popover, a drawn region and the close rules can't be shown, checked or screenshotted in the real app. |
| L23 | Pausing is no change of the moment: the popover stays open. | The popover only opens on a paused frame, so a pause changes no frame (D 2.3 lists seek, scrub, play, timeline click, frame step). |
| L24 | A drag on the frame with the popover open is a click outside it: the words are queued on their region, or an empty popover goes, and the new rectangle opens a new popover. | D 1.4 for every click outside. proto-2 moved the open popover to the new region instead. |
| L25 | The popover on a moment points at the playhead on the player bar's track, whose frame in the window the bar reports (`AppModel.trackArea`). | The bar's track sits between its buttons, not under the stage's whole width. |
| L26 | (Replaced by L36: the band is `window`.) The `header` token paints the window's toolbar band (`toolbarBackground`), behind the title and the floating group. | The token was in the palette with no view; the header is a surface of its own, and a theme may set it apart from `window` (the built-in themes keep them equal). |
| L27 | (Replaces the relaunch of 0.2.0, spec 0.3.0 #65, ticket #67.) `AppModel` holds the run's data as a `DataFolder` it can replace: the support folder, its `SupportLayout`, the `ReviewDesk`, the `ListenerQueue` and the `TranscriptDesk`. `enterDemo(video)` ("Try the Demo") queues the popover's words on their video, closes it and switches to a new `DataFolder` on `<temporary folder>/Havooch Demo`, then opens the bundled `Contents/Resources/Demo/havooch-demo.mp4` there; `leaveDemo()` closes the demo's video and switches back to the folder the run started on (`launchSupport`). The Open panel and a drop (`openForPerson`) leave an in-app demo first; `open` itself, and so `havooch open`, opens on the data the run is on. The `ListenerQueue` left behind ends its held `wait` and `ask`s as `gone`, as on quit, so their commands connect again; `ControlServer` asks `AppModel` for the current queue at each request, and hands a send's `written` or `undelivered` back to the queue that handed it out. An `open` still under way when the data switches, or when going home closes the video, is refused, and the player's time is not saved as a position while a load runs, and a message being queued keeps its review and pictures on the data its video is on. The `ThemeDesk` and the control socket stay on `launchSupport`, and no demo pointer is recorded. `isDemo` is true during an in-app demo and on a demo run: `app open --demo` launches the app with `HAVOOCH_DEMO_RUN=1` beside `HAVOOCH_SUPPORT_DIR` (`SupportFolder.isDemoRun`). On a demo run, "Try the Demo" opens the demo video on its own folder and never switches; its launch, as every launch, opens no video (L47). A run with `HAVOOCH_SUPPORT_DIR` alone, as a check's scratch `make install` has, is a normal run on that folder: its "Try the Demo" switches to the in-app demo, and leaving it comes back to the scratch folder. `HAVOOCH_OPEN_VIDEO` is gone. | A second copy of the app closed the window and changed the Dock icon. The theme is a preference, not review data. One socket keeps `havooch` on the same app all the time. |
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
| L44 | The protocol version is 3 (4 since L54: a request names its `window`; 5 since L59: `open` and `wait` name a `project`; 6 since L61 and L62: the version and compare commands). | 0.2.0 changed the requests' shape: `thread.expand` became `thread.show`, `state` names `sidebar.thread` in place of `sidebar.expanded`, and `screenshot` takes a `window` that a 0.1.0 app would ignore and capture the player's window. A 0.1.0 CLI or app that meets this one is told to reinstall, not given a wrong answer (L1). |
| L45 | Space and Return press the control with the keyboard focus (ticket #52). Under keyboard navigation every focusable control in the player's window reports its focus through `pressedByKeys(in:action:)`: a thread row, a notice card, the header's symbol buttons (agent control, Context, the sidebar toggle), the thread view's Back, Previous and Next, a queued message's Edit and Delete and its editor's Cancel and Save, the composer's region × and General toggle, the footer's Send, the comment popover's Discard and Answer or Queue, the player bar's Play and Comment, the timeline's pins, and Stop in the agent-control popover. `AppModel` keeps the focused controls of the key window as a stack (`focusControl`, `blurControl`, `pressFocusedControl`): the last to take the focus is pressed, and `blurControl` removes only its own entry, so when a popover's control (Stop) loses the focus or goes, a control still focused in the player's window gets the keys again. `Shortcuts` gives Space, Return and Enter with no modifier to it (`pressControl`) in place of play, a new message or the row's own rule; `AppModel.focusedRow` is gone. An AppKit control that is the first responder (a pop-up button) takes those keys itself, only while keyboard navigation is on (`Shortcuts.isControlFocused`, `NSApp.isFullKeyboardAccessEnabled`): with it off a clicked AppKit control can stay first responder, and Space still plays and pauses. A queued message's Edit and Delete, hidden until hover, also show while either has the keyboard focus (`pressedByKeys`' `isFocused`), so a key never presses a button the person can't see. With no control focused, Space plays and pauses as before. | The player's key monitor sees every key before SwiftUI, so a focused button never got Space; one general rule replaces the thread row's own. |
| L46 | Unread threads (ticket #48). `ReviewThread.lastSeen` is when the person last opened the thread's view, kept in the review file (`null` until then); `isUnread` is whether an agent message (`reply`, `ask`, an `ack`'s words on General) is newer than it, or there is one and it's `null`. `AppModel.shown`'s `didSet` calls `Review.markSeen` with the time now, so a row click, Previous and Next, `thread show`, a pin, a badge and a notice all clear it; an agent message on the thread the sidebar shows is read as it comes (`raise`). A review file from before has no `lastSeen` key, and its agent messages count as read, so an update marks nothing. `state --json` reports `unread` per thread, and `state` ends a thread's line with `unread`. | Spec 0.2.0 (#36), ticket #48. The thread view is the one place the conversation shows in full; the popover shows the thread view too. Replaces L15. |
| L47 | (Replaced in part by L54: any number of windows; closing one drops its model.) The window and launch (spec 0.3.0, ticket #66). `applicationShouldTerminateAfterLastWindowClosed` is false: Cmd+W closes the window, the app stays in the Dock with its `AppModel`, and Cmd+Q quits. `PlayerWindow` finds the player's window (titled, not a panel, not Settings; `Screenshotter` uses it too), watches `NSWindow.willCloseNotification` for it, which calls `AppModel.windowClosed()` to pause and save the position, and shows it again through SwiftUI's `openWindow`, captured when the window first appears. A click on the Dock icon with no window on screen shows it (`applicationShouldHandleReopen`); so does `open(url)`, through `AppModel.showWindow`, so a control command's open is seen, and `goHome()` (L49). `ControlServer.ready` is gone, since a launch opens nothing to wait for. Showing the window does not activate the app. A launch opens no video: the launch-time `openRecent()` and `openAtLaunch` are gone (`openRecent(_:)` is now a card's click, L48), and so is `HAVOOCH_OPEN_VIDEO`, since the demo runs in the same window (L27). | Spec 0.3.0, "The window and quitting": the window comes and goes, the app and its video stay. A control command must not take the person's focus from another app. |
| L48 | The home screen (spec 0.3.0, ticket #70). `StageContent` decides what the stage shows: the player with a video, the home screen with none and one or more recent videos, else the empty state; the sidebar shows beside the player only. A card's click calls `AppModel.openRecent`, which does nothing for an entry whose file is gone; the trash button and "Remove from Recents" call `removeRecent`, which leaves the review on disk; "Show in Finder" selects the file in Finder. A thumbnail is the frame at the entry's position, or at 1 second when the position is 0 (`RecentCard.thumbnailTime`), inside the video's duration, at most 640 × 360 pixels, made when the card first shows by `Thumbnails` on `AppModel` and kept in memory for the run, keyed by content hash and position; nothing is written to disk. The relative time is `RelativeDateTimeFormatter`'s, "Just now" under a minute, and moves on each minute. Cards show no thread counts or unread dots. | Spec 0.3.0, "The home screen". The frame where the person stopped costs no more than the first frame. In memory only, so the support folder holds no cache to clean. |
| L49 | (With L54, home is one window's, and nothing shows a closed window.) Going home from the player (spec 0.3.0, ticket #69). `AppModel.goHome()` leaves an in-app demo (`leaveDemo`), or else queues the popover's words on their video, saves the position and closes the video; then it shows a closed window (`showWindow`). Words in the composer go and the queue stays on the video's review, as when another video opens. Closing a video also closes `ReviewDesk`'s open review, so `state` reports no threads with no video. Its callers: the cat mark at the header's leading edge (`TitleView`, a plain button, help tag "Home"), File > Close Video with Shift+Cmd+W (disabled with no video), and `havooch app home`. The header's floating group has "Open a Video…" with the `folder` symbol beside a video, which calls `openFromPanel()` and leaves an in-app demo as the Open panel does. `havooch app demo` runs `openDemo()`, what "Try the Demo" does, and its open shows a closed window. `app home` and `app demo` are operator requests (`app.home`, `app.demo`); the protocol version stays 3, since an older app refuses an unknown command in words. `state` reports `screen` (`StateReport.Screen`): `player` with a video, else `home`, the empty state included. | Spec 0.3.0, "Going home from the player". Cmd+W is the window's Close (L47), so Close Video takes Shift+Cmd+W. `app demo` lets the visual checks run "Try the Demo" without a click. One `screen` word for every screen with no video keeps `state` simple; `recents` tells the home screen from the empty state. |
| L50 | Filled controls (ADR 0006, ticket #81). `ThemeToken.accentFill` is the fill of every prominent button; `accent` stays for lines, selections, rings and pins, and is still the window's tint. Views make a prominent button only through `View.filledButton(palette)` in `Palette.swift` (`.borderedProminent` tinted `accentFill`); a source test in `ReviewAppTests` (`ThemeDeskTests`) fails on `.borderedProminent` anywhere else. Its callers: Send, both "Open a Video…", the comment popover's Queue and Answer, the message editor's Save and the context note's Save. Answer was tinted `question`, which white text does not read on, so it is on `accentFill` too; the field's `question` border and the "Answer" key hint still mark an answer. Every shipped theme with its own `accent` sets `accentFill`: Default Light and Default Dark `#48689d` (Dimmed inherits it), the VS Code themes a deeper shade of their own accent. A theme that sets `accent` nearer than `accentFill` gets `accent.filled()`, so a theme written before this token keeps its hue and passes. `state` reports the active fill as `theme.accentFill`. | ADR 0006, decision I4: white text read at about 1.9:1 on Default Dark's light accent. A test in `ReviewStoreTests` checks white on every shipped theme's `accentFill` for 4.5:1, so a new theme cannot break it. |
| L51 | `havooch open <path>` (#82, decisions C1 and C2, target design Trace 1 and P6). A new request role, **person**: a request a person's click would make, which takes no lease, so the agent-control icon never shows for it; its one request is `open(path)` (wire `open`, protocol version stays 3 as in L49). The command (`OpenCommand`) refuses a path with no file before anything else. It asks the running app; when none answers it launches the app through `AppLaunching.launch(environment: [:], inFront: true)`, looks every 0.05 s with `app status` until the app answers (10 s at most), then asks for the open once, so a slow first look never opens the file twice. A launch in front never waits for or quits a running copy of the app, so the person's app survives. In the app, `ControlServer` calls `AppModel.openInFront`, which checks the file plays first (an in-app demo and the open video stay when it doesn't), leaves an in-app demo, opens, plays and calls `bringToFront`. macOS's cooperative activation keeps an app in the background from activating itself on a socket request, so the reply carries the app's `pid` (`ControlReply.pid`) and the command brings that process to the front (`AppLaunching.bringToFront(pid:)`, `NSRunningApplication.activate()`): by process, since the installed app and a build share the bundle id. When that fails the command still exits 0, with a note on standard error. `state` reports `app.active`. `ContentHashCache` keeps each content hash by path, size and modification time for the run, so opening a file again skips reading it whole. `player open` stays the operator's leased open, paused. The cold path launches the app and then asks it over the socket; the Launch Services open-document event (Finder's Open With, a Dock drop, `open -a`) is #83's. | C1: opening a file never takes control from the person. C2: 1 s warm, measured at 0.13 s to 0.47 s on this machine with the fixtures. A launch with the file as an open-document event would need the app to tell the command whether the file played; asking over the socket once the app answers gives the command the app's own refusal and exit code. |
| L52 | Setup detection and the skill install (effort `projects-and-onboarding`, ticket #88). A new module, `ReviewSetup` (target design P1), holds the probe, the catalog, Link and the install, with the file system (`SetupFileSystem`) and processes (`ProcessRunner`) behind seams, so its tests and the app's run on fakes and never touch the person's home or run `npx`. The app does the work and the CLI asks it, like the theme commands: `setup status` (free; reads the disk again), `setup link`, `setup install` and `setup cancel` (operator, under the lease), each with `--dry-run` where it changes the machine. `setup install` starts the install and answers; `setup status` and `state --json` follow its log. With no `--harness`, it installs for the harnesses found without the skill; with none such it is refused, naming the way to install anyway. Link replaces only a link: a plain file at `~/.local/bin/havooch` stays, and the failure gives the `ln -sf` line for the person to decide. `HOME` and `SHELL` come from the app's environment, so a check can point both at scratch places. The protocol version stays 3: an older app refuses the new commands in words (as L49). | ADR 0005; decisions G3, G4, G9, G10; target design, ReviewSetup and P10. One way in for the person and the agent (ADR 0001). A start-and-follow install keeps every request short, as the lease and the heartbeat expect. |
| L53 | Settings move to `config.toml` (ADR 0002, decisions D1 to D3, P7; ticket #84). A new module, `ReviewConfig`, reads it with TOMLDecoder, the package's first dependency, after Swift Lab's `LabConfig` (ADR 0016) and Shipyard's reader: keys `version`, `theme` and `[[projects]]` (`slug`, `title`, `versions = [{ path, label }]`); a problem rejects the file with its line, an unknown key is a warning with the nearest known key. `schema/config.schema.json` is named on the file's `#:schema` line, and a test keeps it equal to the reader. The folder is `<support>/config/` when `HAVOOCH_SUPPORT_DIR` moves the support folder, else `$XDG_CONFIG_HOME/havooch/`, else `~/.config/havooch/` (`ConfigLocation`), so a test, a check or a demo run never reads or writes the person's settings. `ConfigDesk` makes a missing file from the commented header at launch, watches the file (its folder and the file, debounced 200 ms, after Swift Lab's watcher), applies a save that reads at once, keeps the last valid settings for one that doesn't, and writes the verdict to `config-status.json` in the support folder after every reload. The person sees a new set of problems as a notice at the top of the window ("config.toml wasn't applied", each problem with its line; `ConfigDesk.notice`, drawn by `UI/ConfigBanner.swift`), never a modal alert, which would hold the main actor and the control socket until a click; its close button and `havooch config dismiss` (operator, `config.dismiss`) close it, and a file that reads again takes it away. The Settings window shows the file's path, Applied or Not applied, and each problem. `theme set`, View › Theme and the Settings picker write only the `theme` line (`ConfigWriter.settingTheme`: replace its value and keep a comment after it, insert it after the last top-level key, or take it out for `system`), in place, under a lock, and only when the result reads back as the same settings with only the theme changed; a file with a problem is never written. On the first launch the move from an older build happens once: `settings.json`'s `theme` goes into the file unless the file pins one, `Themes/` moves to `themes/` beside it, token overrides are dropped with a note, and `settings.json` keeps only the sidebar width (app state). While the file has a problem, `settings.json` waits for a later launch. The notes show once in the same notice and stay in `state --json` (`config.notes`) and Settings. `havooch config path` and `config check` read the file with no app and no lease; `check` exits 1 with each problem and its line, and `--json` prints the verdict. `state --json` reports `config` (path, themes, status, accepted, problems, warnings, notes, and `notice`: kind, title, lines, or null); `theme.overrides` is gone. Projects are read and checked, but nothing uses them yet. | ADR 0002 lists three targeted writes; the theme picker and `theme set` stay, so the theme line is a fourth, as Swift Lab's "Reset to default" added one line. `HAVOOCH_SUPPORT_DIR` already isolates every check and test (AGENTS.md); without the moved folder rule, every `AppModel` in a test would write the person's `~/.config/havooch`. |
| L54 | Any number of windows, each with one video or none (ADR 0003, decision F1, ticket #86); it replaces the one window of 0.3.0 (#72, L47). `HavoochApp` has `WindowGroup(for: WindowTarget.self)` in place of `Window`, with restoration off, so a launch shows one empty window on home and opens no video; the app runs on with no window, and the Dock icon with none makes an empty one. `WindowTarget` is `.video(contentHash, path)`, equal by content hash, so a moved or renamed copy is the same video. `AppModel` is now the app: the windows (`WindowRegistry`), the `DataFolder`, the in-app demo, the recent videos, the theme's actions and the sidebar's width, one for every window. Everything that was "the open video" moved to `WindowModel`, one per window, with an id (`w1`, `w2`…, never used twice in a run): its player, popover, sidebar, composer, notices and problem. A window's queue is its review's queue, so each window sends only its own messages. `ReviewDesk` keeps every review by content hash and no open one; a window reads its own (`opened`). No two windows hold one video: `WindowModel.open` refuses a video another window holds, naming it. `havooch open` (and Open With, once #83 routes it) goes to the window that holds the video, which comes forward as it is; else the key window when it holds nothing; else a new window, made, the video opened in it, then its scene opened through the `openWindow` a scene handed to the registry. The Open panel, a drop and a recent card open in their window unless another one holds the video, which then comes forward. File › New Window (Cmd+N) and `window new` make an empty window; `window list` lists them (free); `window close [<id>]` closes one as its close button does (its popover's words are queued, its video pauses and keeps its position). Operator commands take `--window <id>` (`ControlMessage.window`, protocol version 4) and act on the key window without it: the one with the keys, else the one that had them last, else the one made last. `player open`, `app home` and `app demo` make a window when there is none; the others are refused with "no window is open". `screenshot --window` takes `main`, `settings`, `about` or a window id. `state` reports `window` and `windows[]`, and `screen: none` with no window. The keys (`Shortcuts`), the clicks outside the popover (`OutsideClicks`) and the menus act on the window they happen in (`FocusedValues.playerWindow` for the menus). A notice goes to the window that holds its thread's video. The listener stays one for the app until #87 gives each window its own; a bare thread number in `reply` and `ask` is the key window's video. Entering or leaving the in-app demo switches the data for every window, so every window goes home. `config.toml` (`ConfigDesk`, L53) and the setup (`SetupDesk`, L52) are the app's: the settings notice shows in every window and its close button in any window closes it in all, `setup` and `config` commands take no `--window`, and the prompts in a window's `state` name that window's video (the key window's for `setup status`). | ADR 0003: two agents work on two videos side by side. The window's model is its own object, so #87 and #92 add a listener and a project per window without touching the others. The scene value is the target, so SwiftUI's own windows and ours agree on what each holds; the registry, not SwiftUI, decides which window an open goes to, since an open must also reach a window that is already on screen. One data folder for every window keeps the demo apart from the person's reviews (L27) with no second listener. |
| L55 | Videos open from Finder's Open With, a drop on the Dock icon and `open -a Havooch <file>` (decision C3, ticket #83). `Packaging/Info.plist` declares one document type, `public.movie`, with role Viewer and rank Alternate, so Havooch shows in Open With and takes a Dock drop but never asks to be the default player. `AppDelegate.application(_:open:)` hands the file URLs to `AppModel.openFromFinder`, which opens each one through `openInFront`, the open `havooch open` uses (L51, L54): the window that holds the video comes forward, else the empty key window, else a new window; then play, focus and `bringToFront`. Files arrive one after another. At a launch by Open With the files can arrive before the first scene appears, when no window can open, so they wait and `sceneAppeared` opens them in the launch's empty window. A file that doesn't play is the key window's `problem` ("The video didn't open"), or a new window's when none is open. No new CLI command and no new `state` field: `havooch open` is this open's command, and `state` already reports the window and its video. | C3. One open path for the person, whoever starts it. Waiting for the first scene keeps the launch to one window: a window made before any scene exists would have no scene to show it. |
| L56 | A listener per review (ADR 0003, decisions F2 and F3, target design P3 and P5, ticket #87). `ListenerHub` on the `DataFolder` keeps one `ListenerQueue`, each with its own `Outbox`, per `ReviewKey` (a plain video's review, `.video(contentHash)`; a project's comes with #92). `havooch wait --video <path>` resolves the path as `open` would (a path with no file is refused) and binds to that video's review, open in a window or not; `wait` with no flag binds to the key window's review, and is refused when the key window holds no video. `ack`, `status`, `reply` and `ask` find their review by the id's `hash8`, with no flag; a bare thread number is the key window's video. Each window's footer, activity lines, agent name and context check read its own review's queue; `state` reports the key or `--window` window's `listener`, and `windows[]` (also `window list`) each window's `listener` (`presence`, `session`). A `wait` from a new holder key while the last listener was present is a takeover: the older `wait` ends with exit 1 ("<new> took over listening to this review: one listener per video or project; …"), the window that holds the review shows the notice "<new> took over from <old>" (title "New listener", a click shows General), and `state` reports `listener.tookOverFrom` while the new session lasts. A new holder after an absent listener is no takeover, as before. The outboxes live in `outboxes/video-<contentHash>.json`. On launch, `Library.migrateFormerOutbox()` splits an older build's one `outbox.json` into the outbox of each review its sends are on (`Outbox.part(for:)`: the review's sends, the session, that review's context digests), skips a review that already has its own, and deletes the old file once every part is written. The `havooch-mate` skill finds its video's absolute path once and passes `--video <path>` on every `wait`. The protocol version stays 4 (L54): `wait`'s `path` is optional on the wire. | ADR 0003: two agents work on two videos at the same time. Queues are made lazily and kept for the run, so a listener of a video no window holds is still heard, and a window that opens it later shows it. A takeover only from a present listener, so a restarted agent or one that came back after a while is not announced as a new one. A bare `wait` binding to the key window keeps the skill installed before this ticket working (P5). |
| L57 | The Connect view (G1 to G11, ADR 0005, ticket #89), built from connect-flow V6 and connect-view V2 (`docs/prototypes/2026-10-08-lab/agent-onboarding/`, Swift Lab at `ccb82cb`). A window's sidebar shows the threads, a thread's view, or the Connect view (`WindowModel.connect`, a `ConnectEntry` with its reason: `pill`, `header` or `send`); `state` reports `sidebar.mode` and, while it shows, `sidebar.connect` (reason, phase, picked harness, readiness, prompt, banner, listener card). Three ways in: a click on the presence pill (now "No agent" when nobody listens), the header's Connect an Agent button, and a send made while nobody is there (`sendQueue` keeps it in the outbox and opens the view with the sends it waits for). The outbox banner counts those sends' messages while any is in line, then says "Delivered N messages to <agent>". The steps (`UI/Connect/`): the command line (Link, "Linked", a failure's `ln -sf` line in a `CopyBox`), the skill (a row per harness, Install for every harness found without it, the live log and Cancel, Node missing, the command for one repository) and your agent (the picker, `Readiness` of the picked harness: `ready`, `skillNotDetected` or `harnessNotDetected`, never an error, and its prompt always shown). The first step not done is open; a done step folds to one line. Copy boxes put the text on top and Copy in a footer bar (I5); copying is no state (G6). The listener phase (`ListenerQueue.phase(at:)`) is `connected`, `reconnecting` (a session the last run left, not heard from in this one, for 30 s after the data opened: `ListenerHub.startedAt`) or `none`; there is no other waiting state. Connected or reconnecting, the listener card (logo, agent, where, since, Copy Path, Disconnect or Forget, the prompt to listen again) leads and setup folds to one "Set up" line. A session keeps when its first `wait` opened (`ListenerSession.since`, kept on disk). Disconnect and Forget let the session go (`Outbox.letGo`): the open `wait` is refused with "the person disconnected you from this video or project" (an agent let go while it worked, with no `wait` open, gets the refusal on its next `wait`, once), and the taken sends go back in line with their messages `sent`. An agent's first `wait` ever is kept in `settings.json` (`agentConnectedOnce`); the connect button's dot shows while setup isn't fully detected and no agent has connected (P11), and `state` reports it as `setup.needsFinishing`. New operator commands, `--window` aware: `connect show`, `connect pick <harness>`, `connect disconnect`, `connect forget`; Back is `thread list`; Escape and Back in the view return to the thread list or the thread view the view covered, Link, Install and Cancel are the `setup` commands. Copy Prompt and Copy Path have no command: the text is in `state --json`. The protocol version stays 4: an older app refuses the new commands in words. | Spec #79, stories 66 to 86. One view for every way in, so the person always finds the next step. The listener card and the banner read the window's own `ListenerQueue`, so a window speaks only of its own agent (ADR 0003). Disconnect refuses the agent's `wait` in words, so an agent that loops on `wait` stops, as the skill's refusal list tells it. |
| L58 | The setup tour and "Finish setup" (H4, H5, P11, ticket #91), built from first-run V3's coach panel as connect-flow V6 draws it (`docs/prototypes/2026-10-08-lab/agent-onboarding/`, Swift Lab at `ccb82cb`). Each window has a `TourState` (`WindowModel.tour`: open or not, the step, and the send made in it). "Finish setup" sits in the header in a capsule of its own, before the floating group, with the count of setup items left (the command line, the skill and a first connection, each until detected); it shows beside a video while setup isn't fully detected and no agent has ever connected (`AppModel.showsConnectDot`, the connect button's dot rule, P11), and while the tour shows, so the button that closes it stays. It opens the tour at the step it was left on, and closes it. The panel (`UI/Tour/TourPanel`) floats over the foot of the stage: five dots and "Step N of 5", the title, the words, and Skip Tour, Next or Later, Write an Example and Finish; its close button keeps the step, Skip Tour and Finish start the next tour from the first. Each step shows the sidebar it is about and rings parts of the window (`WindowModel.tourRings`): tools rings the Connect view's command line and skill steps, connect rings its agent step, write rings the stage and the composer, send rings Send, and reply rings the agent step while the tour's send waits in the outbox, then the first thread of the send once every message in it is done or failed. A ring (`CoachRing`) stands 9 points outside its part with its radius grown by as much, so it never touches the content; in the thread list, whose margin is 8 points, it stands 6 points out. Steps move on by themselves: both tools detected (0.8 s later, so the checks show), an agent's `wait` opening on the window's review (`ListenerHub.connected` now names the review), a message queued on the write step, a send on the write or send step. New operator commands, `--window` aware: `tour show` (allowed after setup is finished too), `tour next` (Next, Later and Finish; after the reply step it ends the tour), `tour skip` and `tour close`; the last three are refused while the tour doesn't show. Write an Example is `comment compose`. `state --json` reports `tour` (`open`, `step`, `stepNumber`, `steps`, `title`, `rings`, `replied`, `finishSetup`, `setupItemsLeft`). The protocol version stays 4. | Spec #79, stories 91 to 93. The tour is per window, as the sidebar it drives is. The connect button's rule decides Finish setup too, so the two never disagree, and both go once an agent connects, since a real connection proves setup works (ADR 0005). The 9 point ring is the maintainer's change to first-run V3, from connect-flow V6. |
| L59 | Projects (ADR 0004, decisions C4 and E1 to E8, target design P2 to P4, ticket #92). `VideoReview` is `Review` (P2), with a `key` (`ReviewKey.video(contentHash)` or `.project(slug)`) and a stored `hash8` (P3): a review kept before it reads as a plain video's with its video's prefix. A project's review lives in `projects/<slug>/` (review, keyframes, crops) and its outbox in `outboxes/project-<slug>.json`; a video's transcript stays in `videos/<hash>/`. Each thread on a frame has an `anchor`, the absolute path of the version it was raised on (`VersionAnchor`); General has none and is the whole project's. Thread lookup by frame is per version, so v1 and v2 each have their own thread at 0:12; a follow-up joins its thread wherever it is anchored. The version's number comes from `config.toml` as it is now (`ConfigDesk.outline` gives a `ProjectOutline` with `~` expanded): a path that left the list is a removed version, and its thread stays and takes words on the whole frame. `Review.versions` keeps each version's video (content hash, duration, frame rate) as app state. `havooch project new <slug> --from <path> [--title]` and `project add <slug> <path> [--label]` are person requests (no lease, P4; protocol version 5): `ConfigWriter` appends a `[[projects]]` table or one project's `versions` array in place, read back before it is written. When no other project lists the video, `project new` moves its review (`Library.move`: the review file first, then frames and crops) with its ids, anchored to v1; the listener's queue is rekeyed with its open `wait` (`ListenerHub.rekey`, `Outbox.rekeyed`); the window holding the video holds the project. When another project lists it, the new project starts fresh with an id prefix of its own (`ReviewDesk` picks one no review has). `project add` refuses an unknown slug, a missing file, a file that doesn't play and a path the project lists already, then shows the version in the project's window (else the empty key window, else a new one) and brings it forward with the reply's `pid`, as `open` does. `project list` reads the file with no app. `open` and `wait --video` resolve a path through `AppModel.resolveTarget`: `--project`, else the most recently opened project that lists the path (`recents.json` keeps `projects` with their last open), else the plain video; `wait --project <slug>` binds to the project. A send keeps the version on screen (`Send.onScreen`); its payload carries `project {slug, title, onScreen, versions[]}` and each thread's `version {number, path, label}`, `null` on a plain video. Pins, the frame's marks and the composer's thread at the frame are the version on screen's; the thread list shows every thread with a `v1` or `Removed version` tag, and a click on a thread of another listed version opens that version first. The header's subtitle names the project and the version (L61 moves the project's title to the first line, with the switcher). The home screen shows a Projects row above the recent videos (`ProjectCard`: a click opens the latest version, as `open <path> --project <slug>`). `state` reports `project`, `projects[]`, each thread's `version` and each window's `video.project` and `video.version`. A project's version is not a recent video. | ADR 0004. Anchors by path keep the file hand-editable: a person who removes a version loses no thread. Rekeying the queue in place keeps the agent's `wait` open, so the skill's first change request needs no reconnect. One prefix per review keeps every id unambiguous when a plain video and a project share content. |
| L60 | The first-run window (H1 to H3, P12, ticket #90), built from first-run V1 (`docs/prototypes/2026-10-08-lab/agent-onboarding/first-run-V1/`, Swift Lab at `ccb82cb`). An AppKit window of its own (`FirstRunWindow`, 760 by 540, hosting `FirstRunView`), not a scene, so the model shows and closes it (`FirstRun.present`) and a command reaches it with no player window. Four steps on a progress bar, each a click away: Welcome (the loop as three pictures, the harnesses' logos), Tools, Connect and Try it (the loop's three keys on a picture of the demo). The footer has Skip Setup, a hint, Back, and Get Started, Continue (Continue Anyway, Later when the step isn't done) or, on Try it, Open the Demo; the close button is Skip Setup. Tools shows the Connect view's command line and skill steps, and Connect its harness picker and the picked harness's readiness, on the `FirstRun` model: the steps act on a `SetupSteering` (setup, the picked harness, its paste prompt, Link, Install, Cancel, and the player window whose keys a focused button takes, nil here), which `WindowModel` and `FirstRun` both are. `SetupDesk` holds the suggested harness and `readiness(of:)` for both. The prompt is the demo prompt, `Harness.demoPrompt` ("/havooch-mate use Havooch to open the demo video and listen for my feedback" in each harness's form; OpenCode's "Use the havooch-mate skill to open the demo video in Havooch and listen for my feedback"). Connect says whether an agent listens from `agentConnectedOnce`; there is no waiting state (G6). Open the Demo opens the bundled video with `openInFront`, the open `havooch open` uses, on the person's own data, then closes the window. It shows by itself once, at launch, when `settings.json` reads and has no `firstRunDone`, no agent ever connected and no recent video (a person of an earlier build isn't new), and never on a demo run; showing marks it done in `settings.json`. A send on the demo video, known by its content hash (`DemoVideo`, checked against the fixture by a test), carries `video.demo: true`; the skill opens the demo with `havooch open <app>/Contents/Resources/Demo/havooch-demo.mp4` (now in its command list) and reads `references/first-demo.md` only for such a send: no repo work, every step of the loop visible, one next thing to try per send. New operator commands, app-wide: `first-run show [welcome|tools|connect|try-it]`, `next`, `back`, `pick <harness>`, `demo`, `skip`; `screenshot --window first-run`. `state` reports `firstRun` (showing, step, done, harness, readiness, prompt, agentConnected, problem). The protocol version stays 5 (L59). | Spec #79, stories 87 to 90 and 94. The person's own agent runs the demo, so the first send teaches the real loop (H3). The demo on the person's data is the review the agent opened, whichever of the two opens it first. Showing marks it done, so a person who quits during it isn't shown it again: the tour (#91) is the way back. One set of step views for the Connect view and the first run, so their setup never says two things. |
| L61 | A project's thread list by version (E9, ticket #94), built from thread-list V5 "Final: Jump menu" (`docs/prototypes/2026-10-08-lab/project-versions/thread-list-V5/`, Swift Lab at `ccb82cb`). A plain video's list stays by group (L38). In a project, `VersionTree` (pure) lays the list out: General first with no header, then the last three versions as sections, newest first, then an older version on screen, then each version picked from All versions (the latest pick first), then a "Removed version" section while a thread's version left the list (E6: nothing hides). A section's header (`VersionList`) names the version and its label, marks the version on screen with "On screen", counts its threads by group, and has a close button when picked; its rows are today's rows with their state chips and no version tag, and a thread off the version on screen has a quieter keyframe and title, nothing else (a click opens its version, L59). The bar over the list says "Showing v48 to v50" (a range in words, no dash) and opens All versions: a search field (a number, with or without `v`, matches the numbers it starts; other words match a label), then In the list, Still open on older versions and Older, each newest first, with each version's open threads by group and its thread count; its badge counts the open threads on the versions with no section. The footer counts the older versions and has a chip per open thread on them; a chip, like a pick in the menu, adds the version's section and scrolls to it. The window keeps the picks (`pickedVersions`) and the menu's search (`versionMenu`) until its project changes. The summary line adds the version count. New operator commands, `--window` aware: `thread versions [--search <text>] [--close]` and `thread version <n> [--remove]`; `state` reports `sidebar.versions` (`null` on a plain video). Protocol version 6. All versions uses `clock.arrow.circlepath`, not V5's `square.stack`, by the stacked-layers rule. | Spec #79, stories 49 to 56. The last three versions keep a long project short; the menu and the footer reach every older thread, so an open one never hides. The layout is a pure value, so the app model, `state` and the view read one answer. |
| L62 | The version switcher (E10, ticket #93), built from version-switcher V5 "Recent plus picker" (Swift Lab session `project-versions`, lab commit `ccb82cb`). In a project the header's first line is the project's title with the `film.stack` icon and the switcher after it, and the line under it is the version on screen (`v2 · tighter intro`, else `v2 · Oct 6` from the file's date, else `a removed version`), then the folder, quieter (`HeaderWords.Project`, `WindowModel.projectWords`). The switcher (`UI/Header/VersionSwitcher.swift`) shows the last three versions as segments, the one on screen raised; a project of more versions adds a field, `All 50`, which names an older version while it is on screen (`v12`, raised) and opens a popover picker: a search field ("Go to version…", by number with or without `v`, or by label), every version newest first with its label, thread count and date, a check on the one on screen, the highlight moved by Up and Down, Return to open, Escape to close. The words and numbers are `VersionSwitch` and `VersionPicker`, pure; the picker's state is the window's (`WindowModel.versionPicker`), so the CLI drives it. A plain video has no switcher. `WindowModel.switchVersion(to:)` keeps the playhead's time, inside the new version's length, and plays on when it played. A switch to another version of the same project keeps the sidebar's view, the composer's drafts, the General toggle, the Connect view and the notices; only the popover, the drawn region, the context popover and the picker go (`forgetVideoViews(keepingReview:)`). `havooch version show <n>` (`3` or `v3`), `version pick [<query>]` and `version close` are operator requests on a window (protocol version 6); `version pick` is refused on a project of three versions or fewer. `state` reports `project.switcher {segments, selected, field, picker {query, matches, highlighted}}`, and a `switcher:` line. The segment's raised fill is `knob` in a light theme and `popoverBorder` in a dark one, the track `controlHover`, the highlighted row `accent` with `textOnAccent`. | E10 and the maintainer's final variant. Threads are the project's (E6), so the sidebar and the drafts stay on a switch; #92 reset them, as it reset everything but the notices. The picker's state in the model makes it reachable without a click (ADR 0001). The lab's raw colours become theme tokens, since views take colours only from the palette. |
| L63 | Compare two versions (E11, target design P8 and P9, ticket #95), built from compare-control V4 "Final: Live search picker" (`docs/prototypes/2026-10-08-lab/project-versions/compare-control-V4/`, Swift Lab session `project-versions`, lab commit `ccb82cb`). In a project of two versions or more, a Compare button follows the switcher in the header (`UI/Compare/CompareControl.swift`). It opens a popover: the title and its hint, the layout's segments (Side by side, Flip, Slider), a mini window with each side's still at the playhead (`Thumbnails.still`), a chip per side with the swap button between them, the shared playhead, and a footer with "Opens on v3 and v4", Cancel and Show side by side (Compare in the other layouts, Return). A click on a side's picture or chip hangs its search picker under the chip: "Left side shows" with "N of M", a search field ("Find a version or label", by number with or without `v`, or by label, as the switcher's), every version newest first with its still and label, a check on the side's version, the tags "on screen" and "on right · swaps", Up, Down, Return and Escape. The rules are `CompareSession` (pure, `Windows/CompareSession.swift`): it opens on the previous version on the left and the one on screen on the right (v1 on screen: v1 and v2; a removed version on screen: the last two; refused under two versions); picking the version on the other side swaps the sides, so a version is never compared with itself. Start loads the other side's version on a player of its own at the playhead's time (when neither side is on screen the right one comes on screen first, as `version show` would) and makes a `PlayerPair` (`Player/PlayerPair.swift`) of the two: both start with `setRate(_:time:atHostTime:)` on one host time 0.1 s ahead, with `automaticallyWaitsToMinimizeStalling` off; pause pauses both and puts the other side on the lead's time; a seek and the speed are both sides'; on each periodic tick of the lead (the active side) the other side is put back in step when it drifted more than 0.04 s, at most every 0.5 s, and it pauses when the lead pauses (P8). A side shorter than the playhead stops at its end. Only the lead is heard: the other side plays muted, the mute follows the lead, and the end of the comparison (Exit Compare, another version, the window closing) unmutes the player that stays and lets the other go. The stage (`UI/Compare/CompareStage.swift`) shows side by side two panes, Flip one picture with a bar at its foot ("v3 \ v4 press to flip", a click or backslash flips), Slider the right side under the left one wiped at a handle the person drags; each picture is labelled with its side (`A` and `B` in Flip) and version, the active side's label filled with `accentFill`. While comparing, `engine` and `video` are the active side's and `companion` the other side's version; the player bar, the frame marks, the popover, the composer and `state`'s `project.version` follow the active side. A click or a drag on the other side's picture, a thread of its version, `version show` of its version and `compare set --side` make it active (P9); the first click only picks the side, and a drag draws on it at once. Words in the popover are queued first, on the version they were written on: `queueMessage` takes a `Showing` (the video, its anchor, its player's asset and frame length) captured when the words leave the popover, and refuses only when the review changed. The composer writes to the active side, the right one until the person picks the left. Flip's side showing is the active side. Exit Compare (a button with `esc` in the header, where the switcher was, beside the filled "v3 · v4" capsule), Escape and `compare exit` make the right side active and retire the left side's player: the right side's version stays on screen at the playhead. Another version from the switcher, a thread of a third version, or opening another video ends the comparison first; going home ends it too. The header's line under the title says "Comparing v3 and v4". New operator commands, `--window` aware: `compare open`, `compare pick <left\|right> [<query>]`, `compare set [--left <n>] [--right <n>] [--layout side-by-side\|flip\|slider] [--side left\|right] [--slider <0-1>]`, `compare swap`, `compare start` (it starts on the opening choice with the popover closed) and `compare exit` (Cancel in the popover). `state` reports `project.compare {phase, left, right, layout, showing, slider, active, picker {side, query, matches, highlighted}}` (`null` while Compare is closed) and a `compare:` line. The protocol version stays 6: an older app refuses the new commands in words as unknown, and none of the old requests changed. | Spec #79, stories 57 to 65; E11; P8 and P9. Keeping the active side's player as the window's `engine` lets every existing action (draw, pins, the popover, the composer, `comment add`) act on the active side unchanged, and a side switch costs no reload. The popover's choice in the model makes it reachable without a click (ADR 0001). The composer has no side of its own, so it writes where a popover would: the active side, which is the right one until the person picks the left (P9). Flip's bar says "press to flip": a held key that flips back on release is not built. The lab's raw colours become theme tokens. |
| L64 | The skill install command in a box with Run Command (ticket #118), built from connect-view V3 "Run command box" (Swift Lab session `agent-onboarding`). Step 2 and step 3's `skillNotDetected` show `SkillInstall.commandLine` in a `RunBox` (`UI/Connect/RunBox.swift`), the shape of `CopyBox`: the command on top, a footer bar with "Login shell", a copy icon and Run Command, which starts the same install the old Install button did (`installSkill(for:)`). Step 2 says "Run Command installs it for <agents> in your login shell:" above it, and "Cancelled." or the exit status line above that after a cancel or a failure. While the install runs, the box keeps its place, its command dims, and its footer holds a small progress indicator, the last log line and Cancel (Cancel in step 2 only, as in the lab); "In one repo…" hides. Step 3's box runs only while the running install includes its harness; while another runs, its Run Command is dimmed and does nothing. Node missing keeps its `CopyBox` and Check Again, and a harness that isn't detected keeps its command in a `CopyBox`. No control output changed: `setup install` and `setup cancel` are Run Command and Cancel, and `state` already reports the command as `setup.install.command`. | The person sees what runs in their login shell before it runs, and has the line to run alone if it fails. The copy icon stays small, so Run Command leads the footer. |
