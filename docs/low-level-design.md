# Havooch: low-level design

This document is the design of Havooch's code as it is: the modules and their files, the types that hold state and enforce rules, how a click or a command travels to the store and back, and the decisions behind them. It covers the whole package at version 0.4.1, control protocol 6: the player, threads and sends, windows, projects and versions, Compare, themes, `config.toml`, setup, the Connect view, the first run and the tour, the `havooch` command and the listener skill.

Read it before adding or moving a module. When the code and this document disagree, fix one of them in the same change.

NOTE: Domain words follow `GLOSSARY.md`. A **message** is what the person or the agent writes, a **thread** holds the messages about one keyframe, a **send** is what Cmd+Enter delivers, and a **review** is everything kept for one plain video or one project. "Comment" survives only as the CLI's `comment` commands and the UI's Comment button.

The decisions this design takes are numbered L1, L2… in [Decisions](#6-decisions). The numbers stay fixed, since code comments cite them; a number that is missing was replaced by a later decision. Other short references cite the decisions in `docs/prototypes/`: `D 2.10` and `D A.5` (with a space) are `2026-10-05-decisions.md`, and `C1`, `E6`, `G6` and the like are `2026-10-08-decisions.md`.

## For a newcomer, in one screen

Havooch is one Swift package. It builds two executables: the macOS app (`/Applications/Havooch.app`) and the `havooch` command, which ships inside the bundle at `Contents/Helpers/havooch`. The code is ten modules, split by concern. The agent side never links the app's rules.

```text
agent side (no app rules, no UI; builds and tests on Linux)
  ReviewLease       Holder and how it is found; the lease rules as a pure value. Depends on nothing.
  ReviewWire        the control protocol: request, reply, socket framing, socket and support folder locations,
                    the app identity and version
  ReviewConfig      config.toml (ADR 0002): where it is, reading it with each problem on its line, the verdict,
                    the targeted writes, [[projects]]. TOMLDecoder.
  ReviewCommand     the command table of `havooch`: parse, send one request, print the reply, pick the exit code
  ReviewCLI         main.swift only

app side
  ReviewCore        reviews, threads, messages, regions, states, version anchors, the send, the send payload,
                    the outbox, theme resolution. Pure logic, given the time.
  ReviewTranscript  the Transcriber interface, its three sources and the window cut
  ReviewStore       SupportLayout (every path), Library (load and save), images, the speech cache, theme files, settings
  ReviewSetup       what Havooch can detect of setup (the command link, the skill per harness, the harnesses),
                    the link, the skill install, the prompt per harness; file system and processes behind seams
  ReviewApp         the SwiftUI app: windows, player, stage, popovers, sidebar, header, Compare, Connect view,
                    first run, tour, control server, listeners. macOS only.

havooch (CLI)   → ReviewLease + ReviewWire + ReviewConfig + ReviewCommand
Havooch.app     → everything
```

How a request finds its window and its review:

```text
person ──keys, mouse──▶ a window's UI ──────────────────────────────▶ WindowModel ──▶ PlayerEngine (a PlayerPair while comparing)
                                                                        │
operator ──▶ havooch ──▶ SocketListener ──▶ ControlServer ── --window ──┤   (one per window)
             (lease)       (control.sock)    (decode, lease,  or key    │
                                              dispatch)       window    └──▶ ReviewDesk ──▶ Review (Core) ──▶ Library (Store)
person/agent ──▶ havooch open | project new | project add ──▶ ControlServer ──▶ AppModel ──▶ WindowRegistry
                 (no lease)                                                     │   (the window that holds the target)
                                                                                ├─▶ ConfigDesk ──▶ ConfigLocation, ConfigFile (ReviewConfig)
                                                                                ├─▶ ThemeDesk ──▶ ThemeCatalog (Core), ThemeFiles (Store)
                                                                                ├─▶ SetupDesk ──▶ SetupProbe, SkillInstall (ReviewSetup)
                                                                                └─▶ FirstRun (the first-run window)
listener ──▶ havooch wait --video <path> | --project <slug> ──▶ ControlServer ──▶ ListenerHub ──▶ that review's ListenerQueue ──▶ Outbox (Core)
             ack / status / reply / ask (no lease)                                (found by the id's prefix)
```

The person and the operator reach the same `WindowModel` methods, so a UI action and its CLI command are one code path. `AppModel` holds what is the app's: the windows, the data folder, the config, the theme, setup, the first run and the recent videos. `WindowModel` holds what is one window's: its target, player, popover, sidebar, composer, notices, Compare and tour.

| You want to | Open |
|---|---|
| see where the app starts | `Sources/ReviewApp/HavoochApp.swift`, then `AppModel.swift` and `Windows/` |
| see what a window holds and how an open finds its window | `Windows/WindowRegistry.swift`, `WindowTarget.swift`; `AppModel.openInFront`, `openFromFinder`, `resolveTarget` |
| see where the CLI starts | `Sources/ReviewCLI/main.swift`, then `Sources/ReviewCommand/CommandTable.swift` |
| add a CLI command | [Extensibility](#5-extensibility), first row |
| change a thread or message rule, or a state | `Sources/ReviewCore/Review.swift`, `MessageState.swift` |
| change a project rule (versions, thread anchors, moving a video's threads in) | `ReviewCore/Review.swift`, `VersionAnchor.swift`; `AppModel.projectNew`, `projectAdd`, `resolveTarget` |
| change what `wait` prints | `Sources/ReviewCore/SendPayload.swift` |
| change when a send is delivered again | `Sources/ReviewCore/Outbox.swift` |
| change which listener a send or a `wait` goes to | `Sources/ReviewApp/ListenerHub.swift` |
| change the lease | `Sources/ReviewLease/ControlLease.swift` |
| change where a file is kept | `Sources/ReviewStore/SupportLayout.swift` |
| add a colour token or a built-in theme | `Sources/ReviewCore/Theme/ThemeToken.swift`, `Packaging/Themes/` |
| add or change a `config.toml` key | `Sources/ReviewConfig/ConfigFile.swift`, `ConfigReader.swift`, `schema/config.schema.json`, the skill's Settings section |
| change what setup detects, or a harness's prompt | `Sources/ReviewSetup/SetupProbe.swift`, `HarnessCatalog.swift` |
| change the Connect view, the first run or the tour | `ReviewApp/UI/Connect/`, `UI/FirstRun/`, `UI/Tour/`; their rules in `Windows/WindowConnect.swift`, `FirstRun.swift`, `Windows/WindowTour.swift` |
| change Compare | `Windows/CompareSession.swift` (rules), `Player/PlayerPair.swift` (clock), `UI/Compare/` (views) |
| add a known agent harness or its logo | `Sources/ReviewCore/KnownAgent.swift`, `ReviewSetup/HarnessCatalog.swift`, `assets/images/agent-logos/`, `make agent-logos`, `Packaging/AgentLogos/NOTICE.md` |
| follow a command from the shell to the player | [Trace 1](#trace-1-a-cli-command-comment-add-on-a-region) |
| follow a send from Cmd+Enter to `wait`, and a follow-up | [Trace 2](#trace-2-a-send-from-cmdenter-to-wait-then-a-follow-up) |
| follow `havooch open` from the shell to a window | [Trace 3](#trace-3-havooch-open-from-the-shell-to-a-window) |
| follow a plain video that becomes a project and gets v2 | [Trace 4](#trace-4-a-plain-video-becomes-a-project-and-gets-v2) |
| follow a send with no listener, then an agent connecting | [Trace 5](#trace-5-a-send-with-no-listener-then-an-agent-connects) |

## 1. Requirements

The requirements are the user stories of `Spec: Havooch 0.1.0` (#20), `Spec: Havooch 0.2.0` (#36), `Spec: Havooch 0.3.0` (#65) and `Spec: Projects, windows and agent onboarding` (#79), each changing the one before. They group into these capabilities.

### Capabilities

1. **Play** a local mp4, mov or m4v with QuickTime-like keys and a compact player bar.
2. **Open in one step**: `havooch open`, Finder's Open With, a drop on the Dock icon and `open -a`, with no lease; the window that holds the video comes forward.
3. **Windows**: any number, each holding nothing, one plain video or one project; a new window is empty and shows the home screen; no two windows hold the same target.
4. **Write a message** on the current frame (C, or the Comment button) or on a drawn region, in the comment popover or the composer at the sidebar's foot. The message joins the thread of that exact frame, or starts one.
5. **Close the popover safely**: a click outside queues the text, × or Escape discards it, a change of the moment queues text at its original time and region and discards an empty popover.
6. **Queue**: messages wait as `queued`; a queued message can be edited or deleted.
7. **Send**: Cmd+Enter, the Send button or `havooch send` sends every queued message of the window's review, on any threads, as one send.
8. **Pins and marks**: one pin per thread on the timeline, its shape from its regions, its colour from its state or, while the agent waits for an answer, the question's; region outlines and number badges on the frame.
9. **Thread popover**: the conversation above the field on the stage; drags and resizes, and keeps its frame per thread.
10. **Sidebar**: the thread list (grouped by who must act next; in a project, by version), the thread view of one thread, or the Connect view; one composer at its foot.
11. **Agent**: the listener gets each send through `wait`, grouped by thread, acknowledges, sets each message's state, shows its activity, replies and asks, with quick-reply choices; an answer goes at once. Notices name the thread.
12. **A listener per window**: `wait --video <path>` or `--project <slug>`; one listener session per review; a takeover is announced.
13. **Projects**: made by the agent (`project new`, `project add`), listed in `config.toml`; a plain video's threads move in; threads are anchored to the version they were raised on and never hidden; the version switcher, the thread list by version and Compare.
14. **Settings file**: `config.toml` with a schema, a verdict, `config check`, live reload, the last valid settings kept and targeted writes; app state stays out of it.
15. **Themes**: every colour is a token; built-in and user themes, light and dark, follow the system or a pinned one, reload on change.
16. **Setup and onboarding**: what Havooch can detect (the command link, the skill per harness, the harnesses), Link and the skill install, the Connect view, the first-run window, the tour and Finish setup, a demo the person's own agent runs.
17. **Persist** reviews, popover frames and the recent videos, keyed by content; the sidebar width and app state in `settings.json`.
18. **Context and transcript**: the context sidecar plus the in-app note, given once per listener session; the transcript from voiceover, subtitles or speech in the background.
19. **Agent control**: every UI action through the CLI, operator actions under the lease; `state --json`; screenshots in light and dark; demo mode.
20. **Build**: the agent-side modules build and test on Linux; a release publishes the app, the Homebrew cask and the listener skill.

### Rules and completion

- A window holds at most one **target**: a plain video (by content hash) or a project (by slug). No two windows hold the same target.
- A **review** belongs to one target: a plain video's is keyed by content hash, a project's by slug. Its id prefix (`hash8`) is fixed when it is made and never changes, so ids stay valid when a plain video's review becomes a project's.
- A project's versions are its `versions` list in `config.toml`, in order; version number = position + 1. A thread's version is found by its anchor path; a path no longer listed is a removed version, and the thread stays.
- A thread belongs to one review and one keyframe; in a project, to one version too. Its key is the exact frame time. Its number is unique in the review and starts at 1. The General thread is number 0 and has no keyframe; every review has one.
- A person message of the kind `message` moves `queued → sent → acknowledged → working → done | failed`. Forward only, skips allowed, `done` and `failed` final. The one move back: a send requeued for a new listener session returns its unfinished messages to `sent`.
- Only a `queued` message can be edited or deleted. Agent messages, questions and answers have no state.
- The state of a thread is the state of its latest open person message (open: not `done` or `failed`). With none open, it is the state of its latest person message. With no person message, the thread has no state.
- A send is every queued person message of the window's review at the moment of sending. It is finished when each of its messages is `done` or `failed`.
- A thread has at most one open question. An answer goes to the waiting `ask` at once and never into the queue.
- The outbox delivers a review's sends first in, first out, one per `wait`. A new holder key on that review's `wait` is a new listener session: its predecessor's unfinished sends return to `pending` and the context is due again.
- The listener is present while a `wait` or an `ask` is open, with grace times of 5 s while listening and 120 s while working.
- **Detection** has three answers: detected, not detected, cannot know. Only detected shows a check (ADR 0005).
- The lease follows ADR 0001.
- A request of another protocol version is refused, naming both versions.

### Error handling

- Every refusal is a reply with `ok` false and one line in `error`; the CLI prints it on standard error.
- Exit codes: 0 done; 1 refused or failed; 2 a held request ran out of time (`wait --timeout`, `ask --wait`); 64 wrong usage.
- Invalid input is refused before any state changes: a time outside the video, a region outside 0..1 or with no area, an empty text, an unknown or malformed id, a thread of another review for `comment add --thread`, a relative screenshot path, an unknown theme name, an unknown window id, a slug that isn't one.
- Illegal moves are refused with the rule broken: editing a sent message, a state moving back, `ask` while a question is open, `thread answer` or `thread choose` with no open question, `thread choose` with no such choice, an `ask` choice with no words, `reply` on a thread with nothing sent.
- A file AVPlayer cannot play is refused; nothing opens and the open video stays. A transcript source that fails gives no lines and never blocks a send.
- `project new` with a slug in use, `project add` on an unknown slug or a path the project lists already, `wait --project` on an unknown slug, `wait --video` and `open` on a path with no file: refused with the reason.
- An operator command with no `--window` and no window open is refused; an unknown `--window` is refused, listing the windows.
- A store file from a newer schema, or one that does not read, is never written over; that review is refused with the reason.
- A `config.toml` that does not read: the last valid settings stay, the verdict holds each problem with its line, and nothing writes the file.
- A theme file that does not read, has an unknown `kind`, or forms an `extends` loop is left out of `theme list` with its reason; a token with a bad colour falls back as a missing token does.
- A skill install that fails shows its log; nothing else changes. With no `npx`, the view says Node is needed.
- A reply that cannot be written undoes what only the client would know: a granted `take` is released, a delivered send goes back to `pending`.

### Scope

In: all of the above. Out: a rule for a listener that never comes back, fonts and spacing in themes, video editing, formats AVPlayer cannot play, URLs, system-wide hotkeys, shapes other than rectangles, developer ID signing, Havooch Studio, starting agent sessions from Havooch, branching versions, a project rename, system notifications, undo, an Allow button after Stop.

### Requirement to module

| Requirement | Module and files |
|---|---|
| 1, 19, 20 player, CLI, lease, version | ReviewLease, ReviewWire, ReviewCommand, ReviewApp `Player/`, `Control/` |
| 2, 3 open and windows | ReviewCommand `OpenCommand`, `WindowCommands`; ReviewApp `AppModel`, `Windows/`, `HavoochApp` |
| 4, 6, 17 threads and messages | ReviewCore `Review`, `ReviewThread`, `Message`, `ItemID`; ReviewStore `SupportLayout`, `Library`; ReviewApp `UI/Stage/`, `UI/Sidebar/Composer` |
| 5 popover close rules | ReviewApp `WindowModel.closePopover`, `UI/Stage/OutsideClicks` |
| 7, 11, 18 the send, `wait`, the outbox, the listener's answers | ReviewCore `Send`, `SendPayload`, `Outbox`; ReviewApp `ListenerQueue`, `TranscriptDesk`, `ContextReader`, `Notice` |
| 8, 9, 10 pins, popovers, sidebar | ReviewApp `UI/PlayerBar/`, `UI/Stage/`, `UI/Sidebar/` |
| 12 a listener per window | ReviewApp `ListenerHub`, `ListenerQueue`; ReviewCore `ReviewKey` |
| 13 projects, versions, Compare | ReviewConfig `ProjectEntry`, `ConfigWriter+Projects`; ReviewCore `VersionAnchor`; ReviewApp `AppModel`, `ReviewDesk.adopt`, `Windows/CompareSession`, `Player/PlayerPair`, `UI/Header/VersionSwitcher`, `UI/Sidebar/VersionTree`, `VersionList`, `UI/Compare/` |
| 14 `config.toml` | ReviewConfig; ReviewApp `ConfigDesk`, `UI/ConfigBanner` |
| 15 themes | ReviewCore `Theme/`, ReviewStore `ThemeFiles`, ReviewApp `ThemeDesk`, `UI/Palette` |
| 16 setup and onboarding | ReviewSetup; ReviewApp `SetupDesk`, `FirstRun`, `Windows/WindowConnect`, `Windows/WindowTour`, `UI/Connect/`, `UI/FirstRun/`, `UI/Tour/` |
| 11 the listener skill | `.agents/skills/havooch-mate/` |
| everything end to end | `scripts/acceptance.sh` |

## 2. Entities and relationships

Entities (hold changing state or enforce rules):

| Entity | Owns | Lives in |
|---|---|---|
| `AppModel` (app-wide) | the windows (`WindowRegistry`), the `DataFolder` the run is on and whether an in-app demo runs, the `ConfigDesk`, `ThemeDesk`, `SetupDesk` and `FirstRun`, the recent videos and their thumbnails, the sidebar's width; routes `open`, `project new` and `project add` to a window | ReviewApp |
| `WindowRegistry` | which window holds which target, which one is key, the windows waiting for their scene, ids `w1`, `w2`… | ReviewApp |
| `WindowModel` (per window, the orchestrator of one window) | its target, its player (or pair), the open popover and its draft, the sidebar (the thread shown, or the Connect view), the composer, the notices, the version picker, Compare, the tour; every action a person or an operator takes in it | ReviewApp |
| `PlayerEngine` | the AVPlayer, the time, playing or paused, the frame time of a moment | ReviewApp |
| `PlayerPair` | two `PlayerEngine`s on one clock while comparing | ReviewApp |
| `CompareSession` | the two sides' versions, the layout, Flip's side, the slider, the side picker | ReviewApp (per window) |
| `TourState` | the tour's step, whether it shows, the send made in it | ReviewApp (per window) |
| `Review` | one target's threads, messages and sends, their version anchors, and every rule about them | ReviewCore |
| `ReviewDesk` | the one path for changing any review: change, save, publish; moving a video's review into a project | ReviewApp |
| `Outbox` | one review's pending and taken sends, the listener session, the context already sent, presence | ReviewCore |
| `ListenerHub` | one `ListenerQueue` per review, made lazily; which review a `wait` binds to; routes the listener's commands by the id prefix | ReviewApp |
| `ListenerQueue` | one review's open `wait` and `ask`s, payload assembly, takeover, the listener's phase and activity | ReviewApp |
| `ConfigDesk` | `config.toml` as the app runs it: the last valid settings, the verdict, the watch, the targeted writes, the notice, the one-time move from `settings.json` | ReviewApp |
| `ThemeCatalog` | the known themes and how a theme resolves to every token | ReviewCore |
| `ThemeDesk` | the active theme, the pin `config.toml` names, the watch of the person's theme files | ReviewApp |
| `SetupProbe` | what is on disk: the command link, each harness's skills folders, each harness's presence | ReviewSetup |
| `SkillInstall` | one run of `npx skills add`, its lines, cancel | ReviewSetup |
| `SetupDesk` | the latest probe, Link and its failure, the running install and its log, the suggested harness and readiness | ReviewApp |
| `FirstRun` | the first-run window's step, picked harness and problem | ReviewApp |
| `Library` | loading and saving the store's JSON files, the id-prefix index | ReviewStore |
| `ControlLease` | who holds the lease, the line of waiters, the bars | ReviewLease |
| `ControlServer` | the one lease instance, dispatch of decoded requests | ReviewApp |
| `SocketListener` | the socket, each connection, the heartbeat | ReviewApp |
| `TranscriptSources`, `SpeechSource`, `TranscriptDesk` | the transcript sources in order, background speech, the lines of a window of time | ReviewTranscript, ReviewApp |

Fields, not entities: `Region`, `Message`, `MessageState`, `Send`, `SendRef`, `ReviewKey`, `VersionAnchor`, `ProjectOutline`, `VersionTag`, `PopoverFrame`, `Holder`, `LeaseTerm`, `TranscriptLine`, `ThemeFile`, `ThemeColor`, `Settings`, `SendPayload`, `Notice`, `Draft`, `WindowTarget`, `ConnectEntry`, `ProjectEntry`, `ConfigVerdict`, `HarnessSetup`, `Detection`, `CompareLayout`.

```text
AppModel ──owns──▶ WindowRegistry ──holds──▶ WindowModel* ──holds──▶ WindowTarget? (.video(contentHash, path) | .project(slug))
WindowModel ──owns──▶ PlayerEngine | PlayerPair (while comparing), CompareSession?, TourState, ConnectEntry?
WindowModel ──reads──▶ its review in ReviewDesk and its queue in ListenerHub, by its target's ReviewKey; its project's outline from ConfigDesk
AppModel ──owns──▶ DataFolder (support folder, SupportLayout; replaced on entering and leaving the in-app demo; every window is on it)
DataFolder ──holds──▶ ReviewDesk ──holds──▶ Review* ──contains──▶ ReviewThread ──contains──▶ Message
                        │                     │                     └──anchored by──▶ VersionAnchor (a version's path)
                        │                     └──contains──▶ Send ──refers to──▶ Message (by id); keeps the transcript per thread
                        └──saves through──▶ Library ──paths from──▶ SupportLayout
DataFolder ──holds──▶ ListenerHub ──holds──▶ ListenerQueue* (one per ReviewKey) ──holds──▶ Outbox ──refers to──▶ Send (SendRef: id + review key)
                        ├──changes reviews through──▶ ReviewDesk
                        └──reads──▶ ContextReader, SupportLayout (image paths), ConfigDesk (a project's outline)
DataFolder ──holds──▶ TranscriptDesk ──asks──▶ a Transcriber (TranscriptSources.standard)    (read at send time, not at delivery)
AppModel ──owns──▶ ConfigDesk ──reads and writes──▶ ConfigLocation, ConfigFile (ReviewConfig) ──lists──▶ ProjectEntry*
AppModel ──owns──▶ ThemeDesk ──resolves with──▶ ThemeCatalog; ──reads──▶ ThemeFiles; the pin from ConfigDesk   (on the folder the run started on)
AppModel ──owns──▶ SetupDesk ──uses──▶ SetupProbe, CommandLink, SkillInstall, HarnessCatalog (ReviewSetup)
AppModel ──owns──▶ FirstRun ──reads──▶ SetupDesk
SocketListener ──hands bytes to──▶ ControlServer ──holds──▶ ControlLease
ControlServer ──calls──▶ AppModel (person and app-wide requests), the WindowModel `--window` or the key window names (operator),
                         the ListenerHub the AppModel is on now (listener)
UI views ──read──▶ their WindowModel, ReviewDesk, their window's ListenerQueue, PlayerEngine, ThemeDesk (as Palette)   ──call──▶ their WindowModel
```

Where each rule lives:

- "Which thread does a message at this frame join? Can this message be edited, change state, be answered?" lives in `Review`.
- "What is the state of this thread?" lives in `ReviewThread.state`.
- "Which version is this thread on?" lives in `ProjectOutline.tag` (anchor path → number, or removed).
- "Which send does this `wait` get, is this a new listener, is the context due?" lives in `Outbox`.
- "Which listener gets this send? Which review does this `wait` bind to?" lives in `ListenerHub` and `AppModel.listenedReview`.
- "Which review does this video open into?" lives in `AppModel.resolveTarget`: `--project`, else the most recently opened project that lists the path, else the plain video.
- "Which window holds this target? Which window is key? Which window does this open go to?" lives in `WindowRegistry` and `AppModel.windowFor`.
- "Which frame is this moment? What happens to the open popover when the moment changes?" lives in `WindowModel`.
- "Is this `config.toml` valid?" lives in `ConfigFile.decode`.
- "Which colour does this token have now?" lives in `ThemeCatalog.resolve`.
- "Is this detected? What prompt does this harness take?" lives in `SetupProbe` and `HarnessCatalog`.
- "Show Finish setup and the connect button's dot?" lives in `AppModel.showsConnectDot`.
- "May this holder drive the app now?" lives in `ControlLease`.

Module dependencies run one way:

```text
ReviewLease       ← Foundation only (Darwin or Glibc for the process table)
ReviewWire        ← ReviewLease; Darwin or Glibc for the socket
ReviewConfig      ← Foundation, TOMLDecoder (the package's one dependency)
ReviewCommand     ← ReviewWire, ReviewLease, ReviewConfig, Synchronization; AppKit for the launcher only, behind #if canImport(AppKit)
ReviewCLI         ← ReviewCommand

ReviewCore        ← Foundation only
ReviewTranscript  ← Foundation, Synchronization; AVFoundation and Speech in AppleSpeechRecognizer only, behind #if canImport
ReviewStore       ← ReviewCore, ReviewTranscript; CryptoKit in ContentHash, ImageIO in ImageFiles, behind #if canImport
ReviewSetup       ← ReviewCore (KnownAgent)
ReviewApp         ← all of the above, SwiftUI, AVKit, ScreenCaptureKit; macOS only
```

`ReviewCore` does not import `ReviewWire`, and `ReviewCommand` does not import `ReviewCore`: the payload, the state report and the theme list cross the socket as text in `output`. `ReviewCommand` links `ReviewConfig` so `config path`, `config check` and `project list` run with no app. Off the Mac the package is the nine modules without `ReviewApp`.

## 3. Class design

### Folder tree

```text
Package.swift                      targets below; tools 6.2, macOS 26; one dependency, TOMLDecoder, for ReviewConfig (L53);
                                   ReviewApp, ReviewAppTests and the HavoochApp product under #if os(macOS)
Package.resolved                   TOMLDecoder pinned
schema/config.schema.json          the JSON Schema config.toml names on its #:schema line; ReviewConfigTests keeps it equal to the reader (L53)
Makefile                           all, build, test, bundle, install, acceptance, agent-logos, logo, identity, clean; reads the app name from
                                   ReviewLease/ControlLease.swift, the bundle id from ReviewWire/AppIdentity.swift, the version from ReviewWire/Version.swift
Packaging/Info.plist               the bundle's template (name, bundle id, version stamped by make bundle); `public.movie` as Viewer, rank Alternate (L55)
Packaging/Themes/                  Default Light.json, Default Dark.json, Dimmed.json (the defaults), eight themes from popular VS Code themes
                                   (docs/research/2026-10-05-popular-vs-code-themes.md) and NOTICE.md crediting them; copied to Contents/Resources/Themes/
Packaging/AgentLogos/              the nine agent harnesses' logos as PDFs (OpenCode has a -dark file), drawn by make agent-logos from
                                   assets/images/agent-logos/*.svg, and NOTICE.md (Shipyard's attribution); copied to Contents/Resources/AgentLogos/
Packaging/Logo/                    the cat mark as PDFs, the full mark and the small cut, drawn by make logo; copied to Contents/Resources/Logo/
Packaging/homebrew/havooch.rb      the cask the tap carries; version and sha256 filled in by scripts/update-tap.sh
scripts/acceptance.sh              the acceptance scenario, 20 steps through the CLI against the installed app in demo mode
scripts/screenshots.sh             the gallery: states/ in light and dark, themes/ the list and a thread view per built-in theme
scripts/showcase.sh                a scripted review of the Halcyon teaser (fixtures/showcase/) through the CLI in demo mode; the landing page's
                                   screenshots into assets/screenshots/showcase/
scripts/site-shots.sh              that gallery as the WebP files in site/assets/shots/ (ffmpeg, cwebp)
scripts/site-og.html               the 1200 × 630 link preview, rendered to site/assets/og.png
scripts/install.sh                 installs the latest release (or --from <zip>): the app and a link to its command, then a Next line;
                                   --with-skill adds the mate skill for Claude Code, Codex, Cursor, Pi and OpenCode (npx run from $HOME,
                                   stdin from /dev/null); --uninstall (with --with-skill, the skill too)
scripts/update-tap.sh              writes the cask's version and sha256 into the tap repository; run by the release workflow
scripts/update-mate.sh             writes .agents/skills/havooch-mate into yahyabedirhan/havooch-mate, the repository the skill installs from;
                                   run by the release workflow
.github/workflows/release.yml      on a v* tag: the tag checked against the version, make test, make bundle, the zip and its .sha256 as a GitHub
                                   Release; then the tap job and the mate job
.github/workflows/pages.yml        deploys site/ to GitHub Pages on a push to main that touches it
site/                              the landing page, with cli/ and studio/ pages
.agents/skills/havooch-mate/       the listener skill: SKILL.md and references/first-demo.md
fixtures/sample/                   the fixture video and its sidecars, for the tests
fixtures/launch/                   the launch explainer and its sidecars, the bundled demo
fixtures/showcase/                 the Halcyon teaser and its sidecars, with its Remotion source in studio/, for showcase.sh
LICENSE, README.md                 MIT; the welcome (what Havooch is, install, connect an agent); docs/guide.md is the reference
CITATION.cff                       how to cite Havooch

Sources/
  ReviewLease/
    Holder.swift                   who sends a request: key, name, place; Holder.find (HAVOOCH_CONTROL_KEY, the Claude Code, Codex or Pi session,
                                   else the nearest ancestor that is not a shell)
    ProcessTable.swift             the process table Holder.find walks (sysctl on macOS, /proc on Linux), and its protocol
    LeaseTerm.swift                a lease held: holder, taken, ends
    ControlLease.swift             the lease rules as a pure value: use, take, release, stop, settle, giveUp, status; the app's name
  ReviewWire/
    AppIdentity.swift              the app name, bundle id, support folder name ("Havooch", no suffix)
    Version.swift                  the app version "0.4.1" and the control protocol version 6 (L44)
    ControlRequest.swift           every request as an enum case; its role; how long the app may hold it; Rectangle, Status, Appearance, Window
    Compare.swift                  `CompareSide`, `CompareLayout` and `CompareChange`, the words compare's commands and the app share (L63)
    ControlMessage.swift           request, holder and `window` as one JSON object; decode refuses another version
    ControlReply.swift             {ok, output, error, lease?, timedOut?, pid?}
    ControlProtocolError.swift     unreadable, otherVersion, unknownCommand
    TimeCode.swift                 "90", "1:30", "0:01:30.5" to seconds and back
    UnixSocket.swift               POSIX calls; the short-link address for a long path
    ControlClient.swift            one exchange over the socket, skipping heartbeat spaces; the ControlTransport seam, UnixSocketTransport
    ControlSocket.swift            where control.sock is; follows the demo pointer
    DemoPointer.swift              demo.json in the normal support folder
    SupportFolder.swift            the support folder; HAVOOCH_SUPPORT_DIR moves it; HAVOOCH_DEMO_RUN marks the demo run (L27)
  ReviewConfig/                    config.toml (ADR 0002, L53)
    ConfigLocation.swift           the folder: <support>/config/ with HAVOOCH_SUPPORT_DIR, else $XDG_CONFIG_HOME/havooch/, else ~/.config/havooch/;
                                   config.toml and themes/ in it; ~ expansion; createIfMissing
    ConfigFile.swift               the settings as decoded (theme, projects); decode(text) → settings and warnings, or problems with lines;
                                   the header; ConfigIssue, ConfigProblems
    ConfigReader.swift             walks the parsed file key by key; unknown keys are warnings with the nearest known key
    TOMLSourceMap.swift            the line of each key
    ProjectEntry.swift             one [[projects]] table: slug, title, versions [{path, label}]; isSlug; versionNumber(of:in:)
    ConfigVerdict.swift            {accepted, checked, config, configModified, version, problems, warnings}; config-status.json; read and check
    ConfigWriter.swift             the targeted writes, in place under a lock: the theme line (set, replace, remove); setTheme
    ConfigWriter+Projects.swift    append a [[projects]] table; append a version to one project's versions; projects(listing:in:)
  ReviewCommand/
    CommandTable.swift             the commands by name, usage text, global --json; onAWindow() for --window
    HavoochCLI.swift               run(arguments, environment) → output, error, exit code; --version
    OpenCommand.swift              open <path> [--project <slug>]: the person's open, no lease; launches the app in front when it doesn't run (L51)
    ProjectCommands.swift          project new | add (through the app, no lease) | list (reads config.toml, no app) (L59)
    WindowCommands.swift           window list | new | close [<id>] (L54)
    AppCommands.swift              app status | open [--demo <folder>] | home | demo | quit, state (L49)
    ControlCommands.swift          control take [--wait <seconds>] | release
    PlayerCommands.swift           player open | play | pause | seek
    CommentCommands.swift          comment add | open | compose | edit | delete, send, context set; thread answer | choose | open | show | list,
                                   thread versions [--search] [--close], thread version <n> [--remove] (L61)
    CompareCommands.swift          version show <n> | pick [<query>] | close (L62); compare open | pick | set | swap | start | exit (L63)
    ThemeCommands.swift            theme list | set
    ConfigCommands.swift           config path | check, with no app and no lease; config dismiss (L53)
    SetupCommands.swift            setup status | link [--dry-run] | install [--harness]... [--dry-run] | cancel (L52)
    ConnectCommands.swift          connect show | pick <harness> | disconnect | forget (L57)
    TourCommands.swift             tour show | next | skip | close (L58)
    FirstRunCommands.swift         first-run show [<step>] | next | back | pick <harness> | demo | skip (L60)
    ScreenshotCommand.swift        screenshot <abs.png> [--appearance] [--hide-agent-indicator] [--window main|settings|about|first-run|<id>]
    ListenerCommands.swift         wait [--video <path> | --project <slug>] [--timeout], ack, status, reply, ask
    AppLauncher.swift              starts the app through Launch Services, in the background or in front, and brings a process to the front;
                                   the AppLaunching seam
  ReviewCLI/
    main.swift                     exit(HavoochCLI.run(...))
  ReviewCore/
    ItemID.swift                   t-<hash8>-<n>, m-<hash8>-<n>, s-<hash8>-<n>: parse, make, the prefix; ThreadID, MessageID, SendID;
                                   ThreadRef (a full id or a bare number, L5)
    Region.swift                   x, y, w, h in 0..1 from the top left; validation; pixels in a picture
    Message.swift                  id, author, kind, text, at, region, state, sendID, sessionName (L40), choices
    MessageState.swift             the six states, the legal moves, editable, open, final
    ReviewThread.swift             id, number, time (nil for General), anchor, messages, popoverFrame, lastSeen; state; openQuestion; isUnread
    Send.swift                     id, sentAt, message ids, the transcript lines cut per thread, the version on screen; SendRef
    Review.swift                   one review, a plain video's or a project's: its key, its id prefix, its versions' videos, every rule about
                                   threads, messages and sends; the counters; adoption into a project (L59)
    VersionAnchor.swift            a thread's version by path; ProjectOutline (a project as the rules read it); VersionTag (L59)
    ReviewRefusal.swift            why a change is refused, as the line the CLI prints
    ReviewKey.swift                which review a thing belongs to (`.video(contentHash)` or `.project(slug)`); its file name, its context key
    Outbox.swift                   one review's listener outbox: pending, in flight, taken, session, context sent, presence
    SendPayload.swift              the JSON `wait` prints, grouped by thread, and how it is assembled; the project block; `video.demo` (L60)
    DemoVideo.swift                the bundled demo video's content hash, which marks a send as the demo's (L60)
    KnownAgent.swift               the nine agent harnesses a session's name says ("Claude Code" → claude), each one's AgentLogo
                                   (colour, light and dark, template); ListenerSession.agent
    Theme/
      ThemeToken.swift             every semantic colour token, by name; the system surfaces
      ThemeColor.swift             a colour as "#rrggbb" or "#rrggbbaa": parse and print; WCAG contrast; `filled()`, the fill white text reads on (L50)
      ThemeFile.swift              a theme file as decoded: name, kind, extends, tokens
      ThemeCatalog.swift           the known themes; resolve(name, overrides) → every token; the active theme for an appearance
  ReviewTranscript/
    TranscriptLine.swift, Transcriber.swift, TranscriptWindow.swift, TranscriptSources.swift,
    VoiceoverSource.swift, SubtitleSource.swift, SpeechSource.swift, AppleSpeechRecognizer.swift
  ReviewStore/
    SupportLayout.swift            every path under a support folder, by review key (pure), and the pending name of a picture (L19)
    Library.swift                  reviews, each review's outbox, the recent videos and the projects used: load and save, the schema version;
                                   the id-prefix index; moving a review into a project
    RecentVideo.swift              one recent video: path, content hash, opened time, last position
    ContentHash.swift              SHA-256 of the file, streamed; ContentHashCache keeps it by path, size and modification time (L51)
    ImageFiles.swift               writing and removing a PNG at a layout path; a small copy for a row
    TranscriptFiles.swift          the finished speech transcript: load and save
    ThemeFiles.swift               read the built-in and the user theme files into ThemeFile values, with each file's path
    Settings.swift                 settings.json, app state: the sidebar width, an agent connected once, the first run done; Former, an older
                                   build's theme and overrides, read once (L53)
  ReviewSetup/                     (L52)
    HarnessCatalog.swift           per harness: user skills folders, presence hints, the -a name, the prompt and the demo prompt; PromptTarget
    SetupProbe.swift               Detection (detected | notDetected | cannotKnow), HarnessSetup, SetupReport; the probe
    SetupFileSystem.swift          the FileSystem seam (item, target, make folder, make link, remove); FileItem; LocalFileSystem
    CommandLink.swift              ~/.local/bin/havooch: state, make, the ln -sf fallback line
    SkillInstall.swift             npx skills add … through the login shell: command lines, run, Outcome; the ProcessRunner seam and
                                   LocalProcessRunner (lines as they come, cancel stops the program)
  ReviewApp/
    HavoochApp.swift               @main; `WindowGroup(for: WindowTarget.self)`, Settings (L42); the menus: File › New Window, Open… and Close Video,
                                   View › Theme, Playback on the focused window; AppDelegate: the app stays with no window, the Dock icon makes one
                                   (L54), `application(_:open:)` goes to `AppModel.openFromFinder` (L55), the probe on becoming active, the
                                   first-run window
    AppModel.swift                 the app: the windows, the data, the demo, the recent videos and projects, `resolveTarget`, `projectNew`,
                                   `projectAdd`; which window an open goes to (L54)
    Windows/
      WindowModel.swift            one window's orchestrator; every action a person or an operator can take in it
      WindowRegistry.swift         the windows, by id (`w1`…), the key window, the window that holds a review, the ones waiting for a scene
      WindowTarget.swift           what a window holds, as its scene's value: a video by content hash and path, or a project by slug
      WindowScene.swift            a window's scene: takes its `WindowModel`, follows its target, hands `openWindow` to the registry,
                                   tells the app its `NSWindow`; `FocusedValues.playerWindow` for the menus
      CompareSession.swift         a comparison as words and numbers: the sides' versions, the layout, Flip's side, the slider, the side
                                   picker; it opens on the previous version and the one on screen; a pick swaps (pure, L63)
      WindowConnect.swift          the Connect view's model: `ConnectEntry`, `OutboxBanner`, `Readiness`, the listener phase, Disconnect and
                                   Forget; `AppModel.showsConnectDot` (L57)
      WindowTour.swift             the setup tour: `TourStep`, `TourState`, `TourRing`, what moves it on, Finish setup's count (L58)
    Draft.swift                    `WindowModel.Draft`: the open popover's time, text and region (view state, never saved); `PopoverClose`; `FrameMark`
    ComposerTarget.swift           where the composer's words go: a new thread, a reply, a follow-up or an answer (pure, L41)
    ReviewDesk.swift               change a review by its key, save it, publish it; move a video's review into a project (L59)
    ListenerHub.swift              review key → ListenerQueue, made lazily; binds a wait; routes ack/status/reply/ask by id prefix; rekey (L56)
    ListenerQueue.swift            one review's open wait and asks; delivery; payload assembly; presence and phase; takeover; activity
    TranscriptDesk.swift           the videos opened in this run; the lines around a time, read at send time
    ThemeDesk.swift                the active theme and the pin config.toml names; watches themes/; AppModel's theme actions
    ConfigDesk.swift               config.toml in the app: reload, verdict to config-status.json, the targeted writes, the notice, the move from
                                   settings.json, a project's outline; ConfigWatcher (L53)
    SetupDesk.swift                the latest probe, Link and its failure, the running install and its log, the suggested harness and a harness's
                                   readiness; AppModel's setup actions (L52)
    FirstRun.swift                 the first-run window's model (steps, picked harness, problem); `SetupSteering`, what the setup steps act on;
                                   AppModel's first-run actions and `firstRun` in `state` (L60)
    ContextReader.swift            the sidecar context file plus the note
    DataFolder.swift               the data a run is on: support folder, SupportLayout, ReviewDesk, ListenerHub, TranscriptDesk (L27)
    DemoRun.swift                  "Try the Demo": the bundled launch video, the demo folder under the temporary folder (L17)
    Notice.swift                   one notice: its thread, kind, the agent's name, the text, when it fades
    Player/
      PlayerEngine.swift           AVPlayer: open, play, pause, exact seek, time, frameTime(of:), speed; play at a host time, retire (L63)
      PlayerPair.swift             two PlayerEngines on one clock: play on one host time, pause, seek, speed, drift corrected on the lead's
                                   ticks, only the lead heard (L63)
      PlayerSurface.swift          AVPlayerView without controls
      FrameGrabber.swift           keyframe and crop PNGs from the asset, at the exact time
      Shortcuts.swift              the player's keys, on the window they're pressed in, off while a text field has the focus; Space and Return
                                   press a control with the keyboard focus (L45); backslash flips Compare's Flip (L63)
    Control/
      SocketListener.swift         the listening socket off the main actor; one task per connection; the 2 s heartbeat
      ControlServer.swift          decode, the lease gate, dispatch, held takes; the written/undelivered outcome; AppControlling, WindowControlling
      AgentControlIcon.swift       the lease as the agent-control icon shows it
      StateReport.swift            `state` and `app status` as JSON and as lines
      SetupState.swift             `setup` in `state`, and what the setup commands print (L52)
      ThemeReport.swift            the theme in `state`, `theme list` and `theme set`; `config` in `state`
      Screenshotter.swift          a player window (`--window <id>`, else the key one), Settings, About or the first-run window, through
                                   ScreenCaptureKit, in an appearance
    UI/
      RootView.swift               one window: stage, player bar, sidebar, header, all on the `window` surface; injects the Palette; a pinned theme's
                                   kind as the window's colour scheme; the tour panel over the stage, the config banner over the window;
                                   `SidebarColumn`, resizable, the width kept in settings; `Hairline`, one pixel of `separator`
      Palette.swift                the resolved tokens as SwiftUI colours, a `system` surface as the native one (L37), in the environment; the only
                                   way a view gets a colour; `filledButton`, every prominent button on `accentFill` (L50)
      Metrics.swift                measures: bar height 52 (= footer height), paddings, gutter, sidebar width 340 in 300 to 460;
                                   StateLook, a state's glyph and name
      ConfigBanner.swift           the settings notice at the top of the window: what the move did, or a save's problems; its close button (L53)
      SettingsView.swift           the Settings window (⌘,): the cat mark, the name and version, the theme picker View › Theme shares, the settings
                                   file's path, Applied or Not applied, problems and notes; `SettingsWindow` opens it for app control (L42)
      AboutPanel.swift             Havooch › About Havooch: the standard About panel with the app icon and the name's story
      MessageEditor.swift          the text view of the comment popover, edit in place and the context note, its keys, and `MessageField`'s look
                                   with the system focus ring; `FocusTextView` and `FocusRing`, which the composer shares (L42)
      EmptyState.swift             `ContentUnavailableView` with the cat mark, "Open a Video…" and "Try the Demo"; `videoDropTarget`, the drop
                                   target and its outline, which the home screen shares (L42)
      HavoochMark.swift            the cat mark at any size (the small cut, with its face, at 24 pt and under; the full mark from 32 pt)
      AgentMark.swift              `AgentLogoImage`, the logo loader (Contents/Resources/AgentLogos/, else Packaging/AgentLogos/); `AgentMark`, a
                                   known agent's logo at any size; `AgentAvatar`, the logo or the neutral symbol
      KeyPress.swift               `pressedByKeys(in:isFocused:action:)`: a control tells its window when it has the keyboard focus and what
                                   pressing it does (L45)
      Home/
        HomeScreen.swift           `StageContent` (player, home or empty, and whether the sidebar shows); `HomeScreen`: the cat mark, the name,
                                   "Open a Video…", "Try the Demo", the Projects row and the "Recent Videos" grid (L48)
        ProjectCard.swift          one project: its latest version's thumbnail with vN, title, versions and when opened (L59)
        RecentCard.swift           one recent video: thumbnail at 16:9, name without extension, relative time, the path on hover; the context menu;
                                   dimmed with the "unavailable" symbol and a trash button when its file is gone (L48)
        Thumbnails.swift           the cards' thumbnails, kept in memory only, by content hash and position (L48); Compare's stills (L63)
      Header/
        TitleView.swift            while a video is open: the cat mark (goes home), video icon and file name, folder icon and folder or "Demo"; in a
                                   project the title with the switcher and Compare, the version on screen under it (L62, L63); `HeaderWords`
        VersionSwitcher.swift      a project's switcher: the last three versions as segments, the field and its searchable picker;
                                   `VersionSwitch` and `VersionPicker`, the words and numbers, pure (L62)
        FloatingControls.swift     Finish setup with its count (L58), then the group at the top right: agent-control icon, Connect an Agent with
                                   its dot (L57), Open a Video…, Context, sidebar toggle
        AgentControl.swift         the icon and its popover: who, where, time left, Stop (words as a pure struct)
        ContextPopover.swift       sidecar text, the editable note, the transcript part
        TranscriptChip.swift       the transcript's source and progress as words (pure)
      Stage/
        StageView.swift            the video, the overlay, the popover, the notices; `StagePane`, one picture with its overlay and marks;
                                   `StagePopoverLayer`; the compare stage while comparing (L63)
        VideoFrameGeometry.swift   view points to normalized frame coordinates and back (pure)
        RegionOverlay.swift        draw a rectangle with its size label; takes the mouse; while comparing, a click or a drag on a side makes it
                                   active first (L63)
        FrameMarks.swift           each thread's region outlines and number badge on the current frame, of its compare side
        OutsideClicks.swift        a click in the window outside the stage closes the popover as a click outside
        CommentPopover.swift       the one popover, for a new message and a thread: `#3 · 0:12`, ×, the conversation, a field that fills it,
                                   quiet key hints; the header drags it, the corner grip resizes it; where it opens (pure)
        ThreadPopover.swift        a thread's kept popover frame on the stage, fitted to it (pure); the conversation above the field
        Notices.swift              the brief notices that name the thread, with the agent's logo (`AgentAvatar`), at most three
      Compare/
        CompareControl.swift       the Compare button and its popover (layout segments, the mini window with stills, a chip per side and swap,
                                   the footer); a side's search picker; `ComparingBadge`, the header while comparing (L63)
        CompareStage.swift         side by side, Flip with its bar, Slider with its handle, over the `PlayerPair`; each side labelled, the active
                                   one filled (L63)
      PlayerBar/
        PlayerBar.swift            play and pause, time / duration, speed, the timeline, the Comment button
        Timeline.swift             the track, ticks and time labels, the pins
        ThreadPin.swift            one pin: circle or rounded square, the state's colour or the question's, the hover line (pure words)
      Sidebar/
        SidebarView.swift          the thread list, the thread view or the Connect view, with the slide between them
        ThreadList.swift           "Threads", the summary line, the groups under pinned headers (a plain video) or the `VersionList` (a project)
        ThreadGroup.swift          `ThreadGroup` (Needs you, With agent, Queued, Done) and `ThreadListSummary` (pure)
        VersionTree.swift          `VersionTree` (a project's sections by version) and `AllVersionsMenu` (pure) (L61)
        VersionList.swift          a project's list: the All versions bar and menu, version headers, the older footer (L61)
        ThreadRow.swift            a row: thumbnail with regions, number, time, state chip or "Answer", version tag, relative time, two-line
                                   preview, the right-click menu (`RowAction`); `ThreadSummary` and `RelativeTime` (pure)
        ThreadView.swift           one thread: the top bar (Back, number and time, Previous and Next), the `Conversation` (shared with the popover)
        QuickReplies.swift         the open question's choices as chip buttons under it in the thread view
        ActivityLine.swift         what the agent does now: `ThreadActivity` under a thread view's conversation, `ActivityLine`
        Composer.swift             the one composer at the sidebar's foot (L41): the target line, the region chip, the General toggle, its own
                                   field (`ComposerEditor`) that grows with the words and draws the system focus ring
        MessageBubble.swift        one message as a chat (L40): the person's trailing, the agent's leading with its logo, the question card, the
                                   crop, edit in place, the right-click menu; `MessageWriter`, `ChatRun`, `MessageVoice`, `MessageAction` (pure)
        SidebarPicture.swift       a keyframe or a crop read off the main actor at the size it shows, with region outlines
        SidebarFooter.swift        the presence pill and the newest activity, the queued count, Send; as tall as the player bar
        PresencePill.swift         the pill's words, the agent's name on hover and the logo in place of the glyph (pure); `PresenceChip`, the drawing
      Connect/
        ConnectView.swift          the Connect view: Back ("Threads"), the outbox banner line, the step timeline (L57)
        SetupSteps.swift           the command line and skill steps, and the folded "Set up" line
        HarnessPicker.swift        your agent: the picker, the readiness of the picked harness, its prompt
        ListenerCard.swift         connected and reconnecting, with Copy Path, Disconnect and Forget
        CopyBox.swift              text on top, Copy in a footer bar (I5)
        RunBox.swift               the skill install command on top, Run Command and a copy icon in a footer bar; the live log and Cancel (L64)
      FirstRun/
        FirstRunWindow.swift       the first-run window, an AppKit window of its own, centred the first time it shows in a run (L60, L66)
        FirstRunView.swift         Welcome, Tools, Connect, Try it, on the Connect view's steps (L60)
      Tour/
        TourPanel.swift            the setup tour's coach panel over the foot of the stage (L58)
        CoachRing.swift            the pulsing ring 9 points outside the part a tour step is about (L58)

Tests/
  ReviewLeaseTests/                time-driven tables; Holder.find with the Claude Code, Codex and Pi keys; the real process table
  ReviewWireTests/                 version refusal, message round trips, time codes, where the app and socket are, the demo pointer; the
                                   compare, connect, first-run, setup, theme, tour and version requests
  ReviewConfigTests/               reading with problems on their lines, the location, the schema equal to the reader, the writes, the verdict,
                                   the project writes
  ReviewCommandTests/              parsing, the request sent, output, exit codes, per command family; fake transport and launcher (Doubles)
  ReviewCoreTests/                 threads, ids, choices, states, thread state, send, requeue, payload, outbox, context, themes, known agents,
                                   regions, unread, a project's review (adoption, anchors, rekey)
  ReviewTranscriptTests/           the window cut, the source order, srt, vtt, voiceover, background speech (fixtures/sample)
  ReviewStoreTests/                SupportLayout, round trips, a renamed copy's hash, the id-prefix index, projects, theme files (Packaging/Themes,
                                   white on every accentFill at 4.5:1), the speech cache
  ReviewSetupTests/                the probe on a fake file system, Link, the prompt per harness, the install on a fake process runner,
                                   LocalProcessRunner on /bin/sh (lines, cancel)
  ReviewAppTests/                  macOS only: the server over the real socket, the heartbeat, the lease gate, the listener's round, windows,
                                   projects, Compare, the Connect view, the tour, the first run, the home screen, the thread list by version,
                                   the switcher, region crops at several window sizes, restarts, ThemeDesk and ConfigDesk, the raw-colour check
                                   of every view, every agent logo in light and dark, every shipped theme's contrast as the window draws it
```

A module and a type never share a name. `ReviewThread` is not called `Thread`, which is Foundation's.

### ReviewLease

`Holder`, `ProcessTable` and `LeaseTerm` live here, so the lease module depends on nothing and `ReviewWire` imports it. `ControlLease` is the lease rules of ADR 0001 as a pure value: `renewal` 60 s, `cap` 5 min, `bar` 5 min, the time passed into every call; `use`, `take`, `release`, `stop`, `settle`, `giveUp`, `status`, `nextEnd`; `Decision` with its transitions; `Refusal` with its line; `handover` across a relaunch in `HAVOOCH_CONTROL_LEASE`. `ControlLease.appName` is the app name's one definition, since the lease's refusals name the app and this module depends on nothing; `AppIdentity.appName` is that value, and the `Makefile` reads it there.

`Holder.find(variables, workingDirectory, processes)`: the key is `HAVOOCH_CONTROL_KEY` (a blank one counts as unset), else a harness's session from `Holder.sessionVariables` (`CLAUDE_CODE_SESSION_ID` named "Claude Code", `CODEX_THREAD_ID` named "Codex", `PI_SESSION_ID` named "Pi"), else the nearest ancestor process that is not a shell, as `process:<pid>@<start>`, named for its process (`cursor-agent`, `opencode`). When every ancestor is a shell the farthest one is used; the walk stops at depth 64, and `process:unknown`, "an unknown agent" is the last fallback. `HAVOOCH_CONTROL_KEY` replaces the key only, so the name still says the harness. When one harness runs inside another, both session variables are set; the session whose harness process (`claude`, `codex`, `pi`) is the nearer ancestor wins, else the table's order. The place is `Herdr pane <HERDR_PANE_ID>`, else the working folder. The name is what the app's `KnownAgent` reads for the harness logo (G12).

### ReviewWire

- `AppIdentity`: `appName` "Havooch", `bundleID` "com.yahyabedirhan.havooch", support folder `~/Library/Application Support/Havooch/`.
- `Version.app` is "0.4.1"; `havooch --version` prints it. `Version.controlProtocol` is 6 (L44).
- `ControlMessage` is one JSON object: the request, the holder, the protocol version and `window` (`--window`, L54). `decode` refuses another version before anything else, naming both.
- `ControlReply` is `{ok, output, error, lease?, timedOut?, pid?}`; `pid` is the app's process, which the CLI brings to the front after a person request (L51).
- `ControlRequest` follows the contract by role (`ControlRequest.role`):

| Role | Cases | Lease |
|---|---|---|
| free | `appStatus`, `state`, `controlTake(waitSeconds?)`, `controlRelease`, `themeList`, `windowList`, `setupStatus` | none |
| person (L51) | `open(path, project?)`, `projectNew(slug, path, title?)`, `projectAdd(slug, path, label?)` | none, and no agent-control icon |
| operator | the app: `appOpen`, `appQuit`, `appHome`, `appDemo`, `screenshot(path, appearance?, hideAgentIndicator, window)`, `themeSet(name)`, `configDismiss`, `windowNew`, `windowClose`; the player: `playerOpen(path)`, `playerPlay`, `playerPause`, `playerSeek(seconds)`; messages: `commentAdd(text, at?, region?, thread?)`, `commentOpen(text, region?)`, `commentCompose(text, region?, general)`, `commentEdit(id, text)`, `commentDelete(id)`, `contextSet(text)`, `send`; threads: `threadAnswer(thread, text)`, `threadChoose(thread, choice)`, `threadOpen(thread, frame?)`, `threadShow(thread)`, `threadList`, `threadVersionsOpen(search?)`, `threadVersionsClose`, `threadVersion(number, remove)`; versions: `versionShow(number)`, `versionPick(query)`, `versionClose`, `compareOpen`, `comparePick(side, query)`, `compareSet(CompareChange)`, `compareSwap`, `compareStart`, `compareExit`; setup: `setupLink(dryRun)`, `setupInstall(harnesses, dryRun)`, `setupCancel`, `connectShow`, `connectPick(harness)`, `connectDisconnect`, `connectForget`, `tourShow`, `tourNext`, `tourSkip`, `tourClose`, `firstRunShow(step?)`, `firstRunNext`, `firstRunBack`, `firstRunPick(harness)`, `firstRunDemo`, `firstRunSkip` | takes or renews |
| listener | `wait(timeoutSeconds?, video?, project?)`, `ack(sendID, text?)`, `status(messageID, state, text?)`, `reply(thread, text)`, `ask(thread, question, waitSeconds?, choices)` | none |

- A thread reference on the wire (`commentAdd.thread`, `threadAnswer`, `threadChoose`, `threadOpen`, `threadShow`, `reply`, `ask`) is a `ThreadRef`: a full thread id, or a bare number for the key or `--window` window's review (`0` is General) (L5). The CLI sends the text as written; the server resolves it.
- `ControlRequest.longestWait`, `longestListen` (86400 s, for `wait --timeout` and `ask --wait`) and `largestMessage` (1 MiB) bound a request.
- `ControlClient` reads to the end; the server's heartbeat spaces before the reply are skipped as JSON allows, and a reply of spaces only is an app that went away (`notRunning`). Its timeout, applied to each read, is 15 s plus the request's `holdSeconds`, and no limit for a `wait` or an `ask` with no limit. With the heartbeat no read of a healthy held request waits more than 2 s. `ControlTransport` is the seam the command tests replace.

### ReviewConfig

`config.toml` (ADR 0002, L53), read with TOMLDecoder.

- `ConfigLocation` is the folder: `<support>/config/` when `HAVOOCH_SUPPORT_DIR` moves the support folder, else `$XDG_CONFIG_HOME/havooch/`, else `~/.config/havooch/`; `config.toml` and `themes/` in it. `createIfMissing()` writes `ConfigFile.header`, the commented header with the `#:schema` line. `expand` turns `~/` into the home folder.
- `ConfigFile.decode(_:) throws(ConfigProblems) -> Decoded {config, warnings}`. A problem is a `ConfigIssue {line?, message}`. The keys are `version` (required in a file that sets anything; `supportedVersion` 1), `theme` and `[[projects]]` (`slug`, `title`, `versions = [{ path, label }]`). `ConfigReader` walks the parsed file key by key (`topKeys`, `projectKeys`, `versionKeys`); an unknown key is a warning with the nearest known key; a version path must be absolute or start with `~/`. `TOMLSourceMap` gives each key its line.
- `ProjectEntry` is one `[[projects]]` table: `slug` (`isSlug`: 1 to 64 characters of lowercase letters, digits and single hyphens), `title` (`displayTitle`), `versions`; `versionNumber(of:in:)` is position + 1, with `~` expanded. `ConfigFile.project(_:)` and `projects(listing:in:)` find them.
- `ConfigVerdict` is `{accepted, checked, config, configModified, version, problems, warnings}`, as `config-status.json` holds it and `config check --json` prints it. `ConfigLocation.read()` and `check(at:)` make it.
- `ConfigWriter` never rewrites the whole file: each edit inserts or replaces text in place, so comments survive. The pure edits are `settingTheme(_:in:)` (replace the `theme` value and keep a comment after it, insert it after the last top-level key, or take it out for `system`), `appendingProject(slug:title:firstVersion:to:)` and `appendingVersion(_:toProject:in:)`. `ConfigLocation.setTheme`, `addProject` and `addVersion` run them under a lock (`flock`), and write only when the result reads back as the same settings with only that change. A file with a problem is never written.

### ReviewCommand

Each command parses its words, sends one request, prints the reply and picks the exit code. Options and words: `--` ends the options, `--json` is valid anywhere before it, `-h` and `--help` count only before the command name, and wrong usage exits 64. `onAWindow()` marks the commands that take `--window <id>`: `app home`, `app demo`, `state`, `player`, `comment`, `context`, `send`, `thread`, `connect`, `tour`, `version`, `compare` and `window close`; `screenshot` reads its own `--window`. The app-wide ones (`theme set`, `config dismiss`, `setup`, `first-run`, `project`) take none.

| Command | Prints | `--json` |
|---|---|---|
| `--version` | `0.4.1` | `{"version": "0.4.1"}` |
| `app status` | `running: Havooch 0.4.1`, then `data:`, `video:` and the lease; `not running` with exit 0 | `{"running", "version", "demo", "support", "video", "lease"}`, or `{"running": false}` |
| `app open [--demo <folder>]` | launches the app (on the demo folder with `HAVOOCH_DEMO_RUN`), or relaunches it with the lease handed over; then prints what `app status` prints | as `app status` |
| `app quit` | `Havooch quit`, once the app is gone (about 10 s at most, checked every 0.25 s) | `{"quit": true}` |
| `state` | the window's lines (below) | the state report (below) |
| `control take [--wait <seconds>]`, `control release` | the lease taken, or the refusal naming its holder; `--wait` 0 to 3600 queues; `released Havooch` | `{"lease": {…}}`, `{"released": true}` |
| `open <path> [--project <slug>]` (L51, L59) | `opened cut2.mp4 (0:55.033) in w1, playing` (`opened cut2.mp4 (0:55.033) in project launch-video (v2) in w1, playing` in a project); exit 1 with `can't play …` or `no video file at …`; `--project` with a path the project doesn't list is refused, naming `project add` | `{"app": {…, "active": true}, "window", "screen": "player", "video": {…}, "player": {…}, "project": {…}}` |
| `project new <slug> --from <path> [--title <title>]` (L59) | `project launch-video made with cut1.mp4 as v1`; refused for a slug in use and a missing or unplayable file | `{"project": {…}}` |
| `project add <slug> <path> [--label <label>]` (L59) | `cut2.mp4 added to launch-video as v2, shown in w1`; refused for a listed path, an unknown slug and a missing or unplayable file | `{"window", "video": {…}, "project": {…}}` |
| `project list` (L59), with no app | `launch-video "Launch video", 2 versions`, then `  v1 /abs/cut1.mp4 (<label>)` per version; `no projects; …` with none | `{"projects": [{"slug", "title", "versions": [{"number", "path", "label"}]}]}` |
| `window list` (L54) | `windows: 2`, then a line per window | `{"windows": [{"id", "key", "onScreen", "screen", "video", "listener"}]}` |
| `window new` (L54) | `w2 opened, showing home` | `{"window": "w2", "windows": […]}` |
| `window close [<id>]` (L54) | `w2 closed` | `{"window": "w2", "windows": […]}` |
| `app home` (L49) | `home in w1, 3 recent videos, your data` (`demo data` on a demo run) | `{"app": {…}, "window", "screen": "home"}` |
| `app demo` (L49) | `opened havooch-demo.mp4 (0:55.033) on demo data in w1` | `{"app": {…}, "window", "screen": "player", "video": {…}, "player": {…}}` |
| `player open <path>`, `play`, `pause`, `seek <seconds\|m:ss>` | the operator's leased open, paused: `opened sample.mp4 (0:21.233) in w1`; `playing from 0:10`; the time | `{"window", "video", "player"}`, `{"player"}` |
| `comment add <text> [--at] [--region] [--thread]` | `m-f92cbb2a-3 queued on #2 at 0:12` (`… on the region 0.25,0.2,0.3,0.25`) | `{"message": {…}, "thread": {"id", "number"}}` |
| `comment edit <message-id> <text>` | `m-f92cbb2a-3 edited` | `{"message": {…}}` |
| `comment delete <message-id>` | `m-f92cbb2a-3 deleted` | `{"deleted": "m-…"}` |
| `comment open [<text>] [--region]` (L22) | `popover open on #1 at 0:12.5` (`… on the region 0.25,0.2,0.3,0.25`) | `{"popover": {"thread", "time", "text", "region"}}` |
| `comment compose [<text>] [--region] [--general]` (L41) | `the composer says "New thread at 0:12"` (`… with the region 0.25,0.2,0.3,0.25`) | `{"composer": {"target", "kind", "thread", "number", "time", "general", "text", "region"}}` |
| `context set <text>` | `context note set (42 characters)` (`context note cleared`) | `{"video": {…}}` |
| `send` | `s-f92cbb2a-1 sent: 3 messages on 2 threads, taken by the listener` (or `…, waiting for a listener`) | `{"send": {"id", "sentAt", "messageIds", "threadIds"}}` |
| `thread answer <thread> <text>` | `#1 answered` | `{"message": {…}}` |
| `thread choose <thread> <number>` | `#1 answered: <choice>` | `{"message": {…}}` |
| `thread open <thread> [--frame x,y,w,h]` (L29) | `popover open on #3 at 0:12.5` | `{"popover": {"thread", "time", "text", "region"}}` |
| `thread show <thread>` (L39) | `the sidebar shows #1` | `{"sidebar": {"thread": "t-…", "width": 340, "composer": {…}}}` |
| `thread list` (L39) | `the sidebar shows the thread list`; it leaves the Connect view too | `{"sidebar": {"mode": "threads", "thread": null, "width": 340, "composer": {…}, "connect": null}}` |
| `thread versions [--search <text>] [--close]` (L61) | `All versions is open` (`All versions is closed`); refused on a plain video | `{"sidebar": {…, "versions": {…, "menu": {"search", "inList", "stillOpen", "older"}}}}` |
| `thread version <n> [--remove]` (L61) | `the thread list shows v12` (`v12 left the thread list`); refused on a plain video, outside the list, and, with `--remove`, for a version that isn't picked | `{"sidebar": {…, "versions": {"sections", "removedSection", "onScreen", "picked", "showing", "older", "stillOpen", "menu"}}}` |
| `version show <n>` (L62) | `v1 on screen in w1 at 0:01.5`; refused on a plain video and outside the list | `{"window", "video", "player", "project": {…, "switcher": {…}}}` |
| `version pick [<query>]`, `version close` (L62) | `the version picker is open: 1 of 4 versions match `v1`, v1 highlighted` (`the version picker is closed`); pick is refused on a plain video and for three versions or fewer | `{"window", "project": {…, "switcher": {"segments", "selected", "field", "picker": {"query", "matches", "highlighted"}}}}` |
| `compare open`, `compare pick <left\|right> [<query>]` (L63) | `compare: popover, v3 on the left and v4 on the right, side by side`, then an open picker's `  picker left "v1": 1 match, v1 highlighted`; refused on a plain video, a project of one version and while comparing | `{"window", "player", "project": {…, "compare": {"phase", "left", "right", "layout", "showing", "slider", "active", "picker": {"side", "query", "matches", "highlighted"}}}}` |
| `compare set [--left <n>] [--right <n>] [--layout side-by-side\|flip\|slider] [--side left\|right] [--slider <0-1>]`, `compare swap`, `compare start` (L63) | `compare: v3 on the left and v4 on the right, side by side, messages go to v4 on the right`; set and swap are refused with Compare closed, `--side` in the popover, a version outside the list | the same |
| `compare exit` (L63) | `Compare is closed: v4 on screen in w1` (`Compare wasn't open`) | `{"window", "player", "project", "dismissed"}` |
| `theme list` | one line per theme: name, kind, `built-in` or `user`, `active` and `pinned` marks; then `left out: <reason>` per file left out | `{"themes": [{"name", "kind", "source", "path", "active", "pinned"}], "problems": ["…"]}` |
| `theme set <name\|system>` | `theme Dimmed pinned`, or `theme follows the system (Default Dark)` for `system`; names match without regard to case | `{"theme": {…}}` as in `state` |
| `config path` (L53), with no app | the path of `config.toml` | `{"config", "themes", "exists"}` |
| `config check` (L53), with no app | `config.toml reads: <path>` (`doesn't read`), then `  problem, …` and `  warning, …` lines; exit 1 when it doesn't read | the verdict, as `config-status.json` holds it |
| `config dismiss` (L53) | `the settings notice is closed` (`no settings notice was up`) | `{"dismissed": true}` |
| `setup status` (L52) | `command line: detected, <link> links to <command>`, then `harnesses:` and one row per harness (`Codex  harness detected, skill not detected`), then the install's line and its last 20 log lines | `{"commandLine": {"detection", "path", "destination", "command", "failure", "fallback"}, "harnesses": [{"name", "installName", "presence", "skill", "skillFolder", "prompt"}], "install": {…} \| null}` |
| `setup link [--dry-run]` (L52) | `linked <link> to <command>`; refused with the reason and `Run this in a terminal: mkdir -p ~/.local/bin && ln -sf …`; `would link …` for a dry run | `{"setup": {…}}` |
| `setup install [--harness <name>]... [--dry-run]` (L52) | `install: running for Codex: npx skills add …` and how to follow it; `would run: npx skills add …` for a dry run | `{"install": {"state", "harnesses", "command", "repositoryCommand", "exitStatus", "log"}}` |
| `setup cancel` (L52) | `install: cancelled for Codex: npx skills add …`, once it has stopped; refused with no install running | `{"install": {…}}` |
| `connect show` (L57) | `the sidebar shows the Connect view` | `{"sidebar": {"mode": "connect", …, "connect": {"reason", "phase", "harness", "readiness", "prompt", "banner", "listener"}}}` |
| `connect pick <harness>` (L57) | `picked codex: the skill isn't detected; …`, then `prompt: $havooch-mate listen for my feedback on <video>` | `{"sidebar": {…}}` |
| `connect disconnect` (L57) | `Claude Code disconnected`; refused with no agent connected | `{"sidebar": {…}}` |
| `connect forget` (L57) | `Claude Code forgotten: no agent is waited for`; refused with none reconnecting | `{"sidebar": {…}}` |
| `tour show` (L58) | `the tour shows step 1 of 5: Give your agent two tools` | `{"tour": {"open", "step", "stepNumber", "steps", "title", "rings", "replied", "finishSetup", "setupItemsLeft"}}` |
| `tour next` (L58) | `the tour shows step 2 of 5: Connect your agent`; after the last step `the tour is finished`; refused while the tour doesn't show | `{"tour": {…}}` |
| `tour skip` (L58) | `the tour is skipped; Finish setup or havooch tour show starts it again`; refused while it doesn't show | `{"tour": {…}}` |
| `tour close` (L58) | `the tour is closed at step 2 of 5; havooch tour show opens it there`; refused while it doesn't show | `{"tour": {…}}` |
| `first-run show [welcome\|tools\|connect\|try-it]` (L60) | `the first-run window shows welcome`; refused for a step that isn't one | `{"firstRun": {"showing", "step", "done", "harness", "readiness", "prompt", "agentConnected", "problem"}}` |
| `first-run next`, `first-run back` (L60) | `the first-run window shows tools`; refused past the last or the first step, and with the window closed | `{"firstRun": {…}}` |
| `first-run pick <harness>` (L60) | `picked codex`, then `prompt: $havooch-mate use Havooch to open the demo video and listen for my feedback` | `{"firstRun": {…}}` |
| `first-run demo` (L60) | `opened havooch-demo.mp4 in w1, playing; the first-run window is closed`; refused in a build with no bundled video | `{"firstRun": {…}}` |
| `first-run skip` (L60) | `the first-run window is closed`; refused with it closed | `{"firstRun": {…}}` |
| `screenshot <abs.png> [--appearance light\|dark] [--hide-agent-indicator] [--window main\|settings\|about\|first-run\|<id>]` (L10, L42) | the path written; any other `--window` name is a player window's id | `{"path"}` |
| `wait [--video <path> \| --project <slug>] [--timeout <seconds>]` (L56, L59) | the payload JSON, with or without `--json`; with neither flag, the key window's review; both flags is wrong usage; exit 2 when the timeout runs out | same |
| `ack <send-id> [<text>]` | `s-f92cbb2a-1 acknowledged, 3 messages` | `{"send": {…}}` |
| `status <message-id> working\|done\|failed [<text>]` (the text with `working` only) | `m-f92cbb2a-3 working` | `{"message": {…}}` |
| `reply <thread> <text>` | `m-f92cbb2a-7 on #2` | `{"message": {…}}` |
| `ask <thread> <question> [--choice <text>]... [--wait <seconds>]` | the answer's text, exit 0; exit 2 and nothing when the wait runs out | `{"answer": {…}}` |

`wait` connects again every second while the app is not running, until its timeout. `open`, `project new` and `project add` refuse a path with no file before they launch anything; when no app answers, `open` and `project add` launch it in front and `project new` in the background (`AppLauncher`, through the `AppLaunching` seam), then ask it once it answers (L51).

### ReviewCore: the thread model

```swift
public struct Review: Codable, Equatable, Sendable {      // one review: a plain video's or a project's
    public private(set) var key: ReviewKey                // .video(contentHash) | .project(slug)
    public var video: VideoInfo                           // contentHash, title, duration, path, frameRate?; in a project, the version last opened
    public private(set) var versions: [VideoInfo]         // a project's versions as last opened, one per path; empty on a plain video
    public let hash8: String                              // the id prefix, fixed when the review is made (L59)
    public var note: String                               // the in-app context note
    public private(set) var threads: [ReviewThread]       // General first, then in time order
    public private(set) var sends: [Send]                 // in the order sent
    private var counters: Counters                        // next thread number, next message n, next send n; never reused

    init(video:, hash8: String? = nil)                    // a plain video's; hash8 defaults to the content hash's first 8 digits
    init(project slug:, video:, hash8:)                   // a project's, with a prefix no review has
    func adoptedIntoProject(_ slug:, anchor:) -> Review   // same ids; every thread on a frame anchored to `anchor` (L59)

    // the person and the operator
    mutating func write(text:, at time: Double?, region: Region? = nil, to thread: ThreadID? = nil, on anchor: VersionAnchor? = nil,
                        now:) throws(ReviewRefusal) -> Written                // {message, thread, startedThread}
                                                          // joins the thread at that frame time (and version), or starts one;
                                                          // time nil and thread nil: General
    mutating func edit(_ id: MessageID, text:) throws(ReviewRefusal) -> Message      // queued only
    mutating func delete(_ id: MessageID) throws(ReviewRefusal) -> Deleted           // queued only; {message, thread, removedThread};
                                                                                     // an empty thread goes, its number is not reused
    mutating func send(at now:, onScreen: VersionAnchor? = nil, transcript: (ReviewThread) -> [SendPayload.Line]) throws(ReviewRefusal) -> Send
                                                          // every queued person message → sent; the window cut per thread; refused when nothing is queued
    mutating func answer(_ thread: ThreadID, text:, now:) throws(ReviewRefusal) -> Message   // needs an open question
    mutating func setPopoverFrame(_ thread: ThreadID, _ frame: PopoverFrame?) throws(ReviewRefusal)   // nil clears it
    mutating func markSeen(_ thread: ThreadID, at now:) throws(ReviewRefusal)           // the thread view opened (L46)

    // the listener
    mutating func acknowledge(_ send: SendID, text: String? = nil, session: String? = nil, now:) throws(ReviewRefusal) -> Send
                                                          // sent → acknowledged; text → General
    mutating func setState(_ message: MessageID, _ state: MessageState) throws(ReviewRefusal) -> Message   // working | done | failed, forward only
    mutating func reply(on thread: ThreadID, text:, session: String? = nil, now:) throws(ReviewRefusal) -> Message
    mutating func ask(on thread: ThreadID, question:, choices: [String] = [], session: String? = nil, now:) throws(ReviewRefusal) -> Message
                                                          // refused while a question is open
    func choice(_ number: Int, on thread: ThreadID) throws(ReviewRefusal) -> String  // the open question's choice, from 1
    mutating func requeue(_ send: SendID) -> [MessageID]  // unfinished → sent

    func thread(atFrame time: Double, on anchor: VersionAnchor? = nil) -> ReviewThread?
    func threadID(_ ref: ThreadRef) throws(ReviewRefusal) -> ThreadID
    func video(at path: String) -> VideoInfo?             // a version's video
    mutating func show(_ video: VideoInfo)                // the version on screen; kept in `versions`
    var queue: [Message] { get }                          // queued person messages, threads in time order, then written order
    func isFinished(_ send: SendID) -> Bool
}
```

- **Joining** (D 3.1, D 3.8): `write` with a time finds the thread whose `time` equals it exactly, on the same version in a project. The time is already the frame time (`PlayerEngine.frameTime(of:)`, L2), so two moments inside one frame give the same key and one frame later gives another. With `to:` it writes on that thread, General included, wherever the thread is anchored; a time given beside a thread is refused when it is another frame (L6).
- **A new thread** takes the next number and the id `t-<hash8>-<number>`; General is `t-<hash8>-0`, made with the review (L3). In a project a new thread is anchored to the version on screen (`anchor`); General has no anchor and is the whole project's. The keyframe is written before the thread exists, at `frames/<thread-id>.png`.
- **A message** is `id` (`m-<hash8>-<n>`), `author` (`person` | `agent`), `kind` (`message` | `question` | `answer`), `text` (trimmed, never empty), `at`, `region` (person messages only), `state` (person `message`s only), `sendID` (once sent), `sessionName` (agent messages only: the listener session's name when it was written, L40) and `choices` (a question's quick replies, trimmed, each once; nil with none). A region message's crop is `crops/<message-id>.png`, written before the message enters the review.
- **States**: `MessageState` is `queued`, `sent`, `acknowledged`, `working`, `done`, `failed`. `canMove(to:)` is forward only with skips; the state a message already has is accepted and changes nothing. There is no draft state (D 1.4). `isFinal`, `isOpen` and `isEditable` read it.
- **Thread state**: `ReviewThread.state` is the state of the latest person `message` that is not `done` or `failed`, else of the latest person `message`, else nil (L13). A new person message on a finished thread makes it `queued`, so active again, with no extra rule.
- **Questions**: `openQuestion` is the last agent `question` with no person `answer` after it. `ask` is refused while one is open; `answer` is refused with none; a `reply` does not close it.
- **The listener's reach**: `setState`, `reply` and `ask` need something sent on the thread (`notSent`); General takes `reply` and `ask` always. `acknowledge` moves each message of the send still `sent` and leaves the ones further on.
- **Unread** (L46): `ReviewThread.lastSeen` is when the person last opened the thread's view; `isUnread` is whether an agent message is newer than it, or there is one and it's `null`.
- **Popover frame** (D 2.10): `PopoverFrame` is `x, y, w, h` in normalized coordinates of the stage, nil until the person moves or resizes the popover.
- `ReviewRefusal` is `emptyText`, `unknownID(id)`, `otherVideo(id)`, `notQueued(id, state)`, `badRegion(x, y, w, h)`, `nothingQueued`, `emptyMessage`, `notSent(thread)`, `illegalMove(id, from, to)`, `questionOpen(thread)`, `noQuestion(thread)`, `emptyChoice`, `noChoice(thread, number)`, `frameMismatch(thread, time)`, `noFrame` (a time or a region on General), each with its `line`.
- A review kept before projects reads as a plain video's, with its video's prefix as `hash8`.

**Ids** (D A.5): `ItemID` is `<kind>-<hash8>-<n>` with `t`, `m` or `s`, where `hash8` is the review's prefix and `n` a counter of the review. A plain video's prefix is the first eight hex digits of its content hash, unless another review has them; a project's is one no review has (`ReviewDesk` picks it). A listener's command finds its review from the prefix (`Library.key(prefix:)`), so it works after another video opens. Numbers come from the review's counters and are never given twice, so tests are deterministic with no injected ids.

**Versions** (L59): `VersionAnchor` is a version's absolute path, kept as a bare string. `ProjectOutline` is a project as the rules read it (`slug`, `title`, `versions [{path, label}]`), made from `config.toml` by `ConfigDesk.outline` with `~` expanded; `number(of:)` is position + 1, `tag(_:)` gives a `VersionTag` (`.number(n)` or `.removed`, with its `label`: `v2`, `Removed version`), `version(_:)` and `anchor(_:)` go the other way. `ReviewKey` names the review (`fileName`: `video-<hash>` or `project-<slug>`; `contextKey`: the content hash or `project-<slug>`).

### ReviewCore: the send

```swift
public struct Send: Codable, Equatable, Sendable {
    public let id: SendID                                  // s-<hash8>-<n>
    public let sentAt: Date
    public let messageIDs: [MessageID]                     // threads in time order, General first; written order within a thread
    public let transcripts: [ThreadID: [SendPayload.Line]] // cut at send time (D A.4); General has none
    public let onScreen: VersionAnchor?                    // the version on screen when the person sent; nil on a plain video
}                                                          // kept in review.json as { "t-…-1": [lines] }
public struct SendRef: Codable, Hashable, Sendable {       // kept as sendID plus contentHash or project
    public var sendID: SendID; public var review: ReviewKey
}
```

`WindowModel.sendQueue()` queues the open popover's text first, then calls `Review.send` with a closure that reads `TranscriptDesk.lines(around: thread.time, of: video)` for each thread with a frame, from the video of the version the thread is on, and hands the `SendRef` to the review's `ListenerQueue`. The lines are the ones the source has at that moment; every delivery, the first included, uses the kept lines and needs no transcriber (D A.4). `ReviewCore` keeps a line as its own small value, `SendPayload.Line` (`start`, `end`, `text`), so it does not import `ReviewTranscript`; `ItemID` is `CodingKeyRepresentable`, so the map by thread is a JSON object.

### ReviewCore: the outbox

One `Outbox` per review: `pending` and `taken` lists, `session` (`ListenerSession`: holder key, name, place, since), `contextSent` (context key → digest), `isWaitOpen`, `openAsks`, `lastHeard`, and `inFlight` (send → the session key, never saved). Its operations: `enqueue`; `waitOpened(by:at:)` (a new key: taken → front of pending, `contextSent` emptied, and the requeued sends returned); `handOut`; `written`; `undelivered`; `discard`; `finished`; `context(for:text:)` and `isContextDue`; `heard`, `askOpened`, `askClosed`, `waitClosed`; `presence(at:)` (`listening` | `working` | `absent`, with `listeningGrace` 5 s and `workingGrace` 120 s); `letGo()` (Disconnect and Forget, L57); `reconcile(unfinished:)`; `part(for:)` and `rekeyed(from:to:)` (L56, L59).

- `handOut` gives the open `wait` the first pending send that is not in flight and marks it in flight, so it stays in `pending` and no other `wait` gets it (L16). `written` moves it from `pending` to `taken` once the reply is written, unless another session started meanwhile: then it stays in line for that session. `undelivered` only clears the mark and forgets the review's context digest, so the send keeps its place first in line. `finished` removes a send from all three.
- The context is given once per listener session per review. `contextSent` is keyed by `ReviewKey.contextKey` and holds a digest (FNV-1a) of the context text that session last got: the first send of a review in a session carries `context`, later sends carry `null`, and a send carries it again when the sidecar or the note changes (a new digest) or when a new holder key starts a new session (`contextSent` emptied). The agent keeps what it has read for the length of its session, and the context can be long, so repeating it costs the agent's context window and says nothing new; a new session is a new agent that has read nothing.

### ReviewCore: the send payload

`SendPayload.assemble(review:send:context:images:project:)` builds the JSON `wait` prints. `images` (`SendPayload.Images`) holds two closures, a thread's keyframe path and a message's crop path, which the app answers from `SupportLayout`, so `ReviewCore` needs no `ReviewStore`. `SupportLayout.keyframe(of:on:)` and `crop(of:on:)` hold the rule that General has no keyframe and only a region message has a crop; `WindowModel`, `StateReport` and `ListenerQueue` all ask them. `project` is the project's `ProjectOutline` as `config.toml` lists it now.

- `threads[]` has one entry for each thread with an unfinished message in the send, General first, then in time order. A send delivered again carries only its unfinished messages.
- `transcript[]` is the send's kept lines for the thread.
- `history[]` is every message of the thread that is not in this entry's `messages[]` and not `queued`, in the order written (L7). On a first send it is `[]`.
- `messages[]` are the person messages of this send on the thread, with `region` and `cropPath` or `null`.
- `video` is the version on screen when the person sent (`Send.onScreen`), else the review's video. `video.title` is the file name with its extension, as the header shows it (L8). `video.demo` is `true` when the content hash is the bundled demo video's (`DemoVideo.contentHash`): the skill then reads its demo reference (L60).
- `project` is `{slug, title, onScreen, versions[{number, path, label}]}`, and each thread's `version` is `{number, path, label}` with a `null` number for a removed version; both are `null` on a plain video (E8).
- `json` prints sorted keys, `null` for no value (a key is never left out), times as ISO 8601.

```json
{
  "send":    { "id": "s-f92cbb2a-2", "sentAt": "2026-10-05T19:02:11Z" },
  "video":   { "path": "/abs/sample.mp4", "contentHash": "f92cbb2a…", "duration": 21.233, "title": "sample.mp4", "demo": false },
  "project": null,
  "context": null,
  "threads": [
    { "id": "t-f92cbb2a-1", "number": 1, "time": 10.017, "version": null,
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

In a project, `"project": { "slug": "launch-video", "title": "Launch video", "onScreen": 2, "versions": [ { "number": 1, "path": "/abs/cut1.mp4", "label": null }, … ] }` and each thread's `"version": { "number": 1, "path": "/abs/cut1.mp4", "label": null }`.

### ReviewCore: theme resolution

```swift
public enum ThemeToken: String, CaseIterable, Codable { … }        // the semantic tokens below; systemSurfaces
public struct ThemeColor: Equatable, Hashable, Sendable {          // red, green, blue, alpha as UInt8
    public init?(_ text: String)                                   // "#rrggbb" or "#rrggbbaa"
    public var text: String
    public static let filledTextContrast = 4.5                     // white text on a filled control (ADR 0006)
    public func contrast(with other: ThemeColor) -> Double         // the WCAG ratio, 1 to 21
    public func filled() -> ThemeColor                             // itself, or darkened in 1% steps until white reads at 4.5:1
}
public struct ThemeFile: Codable, Equatable {
    public var name: String; public var kind: ThemeKind; public var extends: String?   // ThemeKind: light | dark
    public var tokens: [String: String]                            // token name → colour text, as written
}
public struct ThemeCatalog: Equatable {
    public init(builtIn: [ThemeFile], user: [ThemeFile])           // a user theme with a built-in's name replaces it
    public var names: [String] { get }; public var entries: [Entry]; public var problems: [String]
    public func resolve(_ name: String, overrides: [String: String] = [:]) throws(ThemeRefusal) -> ResolvedTheme
    public func active(pinned: String?, appearance: ThemeKind) -> String // pinned when it exists, else "Default Light" or "Default Dark"
}
public struct ResolvedTheme: Equatable { name; kind; colors: [ThemeToken: ThemeColor]; system: Set<ThemeToken> }
```

`resolve` walks the `extends` chain first, then the default theme of the theme's kind, then applies the overrides (D 5.2, D 5.5). A token name the catalog does not know is ignored, and a colour text that does not parse counts as missing. A chain that loops, or names a theme that does not exist, leaves that theme out of the catalog, with its reason in `problems`; resolving a name the catalog does not have is `ThemeRefusal.unknown`. Names match without regard to case. A user theme named `Default Dark` replaces the built-in one, but the built-in defaults stay the last fallback, so a partial replacement still resolves every token. The two default themes must define every token; a test proves it. When a theme sets `accent` nearer than `accentFill` (in itself, a theme it extends, or an override), `accentFill` is that accent's `filled()`, so a brown theme gets a brown fill that white text reads on (L50). A surface token of `ThemeToken.systemSurfaces` (`window`, `popover`, `notice`, `field`, `separator`) may be `system`, the native macOS part, held in `ResolvedTheme.system` with no painted colour; on any other token `system` counts as missing (L37).

The tokens (each addition is one case and one value in each default theme). A token may carry an alpha (`#rrggbbaa`): the hover fill, the region's dim and the shadow do. A person's theme that sets a token no longer in the list still loads, since an unknown token is ignored.

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

The default themes use natural backgrounds and pastel state colours, with no pink; they set all five surfaces to `system`. Dimmed extends Default Dark with a softer painted background (D 5.7).

### ReviewTranscript

The `Transcriber` protocol (`transcript(of:)`, `prepare`, `lines(for:in:)`), `TranscriptSources.standard(speech:)` in the order voiceover (`voiceover.json`), subtitles (`.srt`, `.vtt`), speech, `TranscriptWindow` (15 s each side, lines kept whole), `SpeechSource` with its `SpeechRecognizing` seam, its cache and its `@concurrent` work, and `AppleSpeechRecognizer` behind `#if canImport(Speech)`. A `Transcript` is `{source, lines, complete, problem?}`. `TranscriptDesk` reads it at send time, not at delivery.

### ReviewStore

`SupportLayout` (D A.6) is a pure value that owns every path of the store, by `ReviewKey`; `Library`, `ImageFiles`, `TranscriptFiles`, `Settings` and the payload's `images` closures all ask it. The socket and the demo pointer stay in `ReviewWire`, since the CLI needs them and does not link the store.

```text
<support>/                               ~/Library/Application Support/Havooch/, or the demo folder
  control.sock                           while the app runs (ReviewWire)
  demo.json                              the demo pointer; only in the normal folder (ReviewWire)
  outboxes/video-<contentHash>.json      a plain video's review's Outbox (L56)
  outboxes/project-<slug>.json           a project's review's Outbox (L59)
  recents.json                           the 10 recent videos, the newest first (path, content hash, opened time, last position),
                                         and when each project was last opened
  settings.json                          app state: the sidebar width, an agent connected once, the first run done
  config-status.json                     the verdict on config.toml after the app's last reload (L53)
  config/                                with HAVOOCH_SUPPORT_DIR only: config.toml and themes/ (L53)
  videos/<contentHash>/
    review.json                          a plain video's Review: hash8, video, note, threads, sends, counters, schemaVersion
    transcript.json                      the video's finished speech transcript, a project's versions too
    frames/<thread-id>.png               a thread's keyframe, at the video's own size
    crops/<message-id>.png               a region message's crop
  projects/<slug>/
    review.json, frames/, crops/         a project's Review (with `project` and `versions`), keyframes and crops (L59)
  outbox.json, recent.json, Themes/      an older build's files: split, read or moved once, then gone (L53, L56)
```

```swift
public struct SupportLayout: Equatable, Sendable {
    public let root: URL
    public var recentsFile, settingsFile, videosFolder, projectsFolder, outboxesFolder: URL
    public var formerOutboxFile, formerRecentFile, formerThemesFolder: URL     // outbox.json, recent.json, Themes/: read once
    public func outboxFile(_ key: ReviewKey) -> URL                           // outboxes/<key.fileName>.json
    public func videoFolder(_ contentHash: String) -> URL
    public func folder(_ key: ReviewKey) -> URL                               // videos/<hash>/ or projects/<slug>/
    public func reviewFile(_ key: ReviewKey) -> URL
    public func transcriptFile(_ contentHash: String) -> URL
    public func framesFolder(_ key: ReviewKey) -> URL; public func cropsFolder(_ key: ReviewKey) -> URL
    public func keyframe(_ thread: ThreadID, of key: ReviewKey) -> URL
    public func crop(_ message: MessageID, of key: ReviewKey) -> URL
    public func keyframe(of thread: ReviewThread, on key: ReviewKey) -> URL?  // nil for General
    public func crop(of message: Message, on key: ReviewKey) -> URL?          // nil with no region
    public func pendingImage(_ token: String, of key: ReviewKey) -> URL       // frames/.pending-<token>.png (L19)
}
```

- `Library(layout:)` only loads and saves: reviews (`load(key)`, which refuses a file whose key is another review's; `save`), each review's outbox (`loadOutbox(key)`, `save(_:of:)`, through `Outbox.reconcile` with that review's unfinished sends on disk; `removeOutbox`; `migrateFormerOutbox()` splits an older build's one outbox, L56), the recent videos and the projects used. Its `init` reads every `videos/*/review.json` and `projects/*/review.json` once for the id-prefix index (`key(prefix:)`, `key(of:)`, `isTaken`), the path index and the unfinished sends. It writes nothing until the first save. `move(_:from:)` moves a video's review into a project's folder: the review file first, then frames and crops (L59).
- The recent videos: `recents()`, `recordOpened(url, contentHash:, at:)`, `savePosition(seconds, of:)` and `removeRecent(contentHash)`. At most `recentLimit` (10) entries, the newest first. Opening a video on the list moves it to the front with its new path and keeps its position; the match is by content hash. Removing an entry leaves its review on disk. The list is read once and kept in memory. A project's version is not a recent video: `recordProjectOpened(slug, at:)` and `projectsUsed()` keep each project's last open instead. An older build's `recent.json` becomes the one entry on the first read, then is deleted. A `recents.json` from a newer schema is never written over.
- Every save is atomic, pretty-printed, sorted keys, ISO 8601 with milliseconds, with `schemaVersion` (1, L9).
- A file from a newer schema, or one that does not read, is never written over.
- `ThemeFiles.read(folder)` reads the built-in themes from `Contents/Resources/Themes/` in the app (`Packaging/Themes/` in tests and in a build that is not bundled); the person's are read from `themes/` beside `config.toml` (`ConfigLocation.themesFolder`). A file that does not read is skipped with its reason.
- `Settings` is `{ sidebarWidth: Double?, agentConnectedOnce: Bool?, firstRunDone: Bool? }`, app state, with its own `load(layout)` and `save(layout)`. A missing file is the defaults. A file that does not read is never written over. `Settings.former(layout)` reads the `theme` and `overrides` an older build left in it, for the one-time move into `config.toml` (L53); the next save leaves them out.
- `ContentHash` streams SHA-256 over the file; `ContentHashCache` keeps each hash for the run by path, size and modification time, so opening a file again skips reading it whole (L51).

### ReviewSetup

What Havooch can say of the person's setup, and the two actions that change it (L52, ADR 0005). It depends on Foundation and `ReviewCore` (`KnownAgent`) only. The file system (`SetupFileSystem`, with `FileItem`: missing, file, folder, link, unreadable) and processes (`ProcessRunner`) are seams, so its tests and the app's run on fakes and never touch the person's home or run `npx`.

- `Detection` has three answers: `detected`, `notDetected`, `cannotKnow` (a folder on the way does not read). There is no "missing".
- `HarnessCatalog.all`, each with its user skills folders, presence hints (its app in `/Applications` or `~/Applications`, its command in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.bun/bin`, `~/.npm-global/bin`, and a few of its own), its `-a` name and its prompt form. `<target>` is the window's video file name or `project <slug>` (`PromptTarget`); `Harness.prompt(for:)` makes the line, and `demoPrompt` the first run's. `harness(named:)` takes an install name or a session's name.

| Harness | Skills folders checked (user level) | `-a` name | Prompt form |
|---|---|---|---|
| Claude Code | `~/.claude/skills` | `claude-code` | `/havooch-mate listen for my feedback on <target>` |
| Codex | `~/.agents/skills`, `~/.codex/skills` | `codex` | `$havooch-mate listen for my feedback on <target>` |
| Cursor | `~/.agents/skills`, `~/.cursor/skills` | `cursor` | `/havooch-mate listen for my feedback on <target>` (not yet checked in Cursor) |
| Pi | `~/.pi/agent/skills`, `~/.agents/skills` | `pi` | `/skill:havooch-mate listen for my feedback on <target>` |
| OpenCode | `~/.config/opencode/skills`, `~/.claude/skills`, `~/.agents/skills` | `opencode` | `Use the havooch-mate skill to listen for my feedback on <target>` |

- `SetupProbe(fileSystem:home:catalog:).probe()` → `SetupReport`: the command link (`CommandLink.state()`: detected when `~/.local/bin/havooch` is a link to `…/<name>.app/Contents/Helpers/havooch` and that file is there; a relative link is read from its folder), the skill per harness (detected when `havooch-mate/SKILL.md` is a file, links followed, in one of its folders; `HarnessSetup.skillFolder` names it) and each harness's presence (any hint path there). It reads only these places, never a repository. `harnessesLackingSkill` is what an install with no harness named is for: found, and the skill not detected.
- `CommandLink.make(to:)` makes `~/.local/bin` and the link; a link already there is replaced, as `ln -sf` does, and anything else there is left alone. Every failure is a `Failure` with its reason and the fallback line `mkdir -p ~/.local/bin && ln -sf '<command>' ~/.local/bin/havooch`.
- `SkillInstall(for: harnesses, shell:)` holds `commandLine`, `npx skills add yahyabedirhan/havooch-mate --skill havooch-mate -g -y -a <name>…`, and `repositoryCommandLine`, the same without `-g` for one repository. The source, `HarnessCatalog.source`, is a small repository of the skill alone: the skills CLI clones a repository source, and Havooch's own is large. The release workflow's `mate` job writes `.agents/skills/havooch-mate` into it (`scripts/update-mate.sh`). `run(with: runner, line:)` first runs `<shell> -l -c "command -v npx"` (no `npx` ends as `.noNode` and runs nothing), then `<shell> -l -c "exec env CI=true NO_COLOR=1 <command>"`, each line handed on as it comes with its colour codes stripped, and ends as `.finished(status)` or, when its task is cancelled, `.cancelled`. `LocalProcessRunner` runs a `Process` with standard output and standard error on one pipe, read on a thread of its own; cancelling terminates it.

### ReviewApp: the app

`AppModel` (`@Observable`, main actor by the module's default isolation, D A.2) is the app. Its methods are the app's actions:

| Method | Rules it owns | Refuses |
|---|---|---|
| `openInFront(url, project:)` | `havooch open` (L51, L54): refuses a missing file, an unknown project or a file AVPlayer cannot play (`PlayerEngine.checkPlayable`) before anything changes, then `leaveDemo()`; `windowFor(url, project:from:)` resolves the target (`resolveTarget`) and finds the window: the one that holds the review (`WindowRegistry.holding`) comes forward (a project's window opens the version asked for), else the key window when it holds nothing, else a new window (made, the video opened in it, then its scene opened); then play, `focus(window)` and `bringToFront` (`NSApp.activate()`) | no file; an unknown project; a file AVPlayer cannot play; as `WindowModel.open` |
| `openFromFinder(urls)` | Finder's Open With, a drop on the Dock icon and `open -a` (L55): each file through `openInFront`, one after another, so the first fills an empty key window and the next ones open in new windows. Before the launch's first scene appears the files wait, and `sceneAppeared` opens them. A refusal is the key window's `problem`, or a new window's with none | as `openInFront` |
| `openForPerson(url, from:)`, `openFromPanel(from:)`, `openProject(slug, from:)` | the Open panel, a drop, a recent card and a project card in a window (nil from the menu with no window): `leaveDemo()`, then the window that holds the review comes forward, else the window it came from opens it, else as `openInFront`. A project card opens its latest version. A refusal is the window's `problem` | as `WindowModel.open` |
| `resolveTarget(url, contentHash:, project:)` | which review a path opens into (C4): `--project`, else the most recently opened project that lists the path (`Library.projectsUsed`), else the plain video | `--project` that doesn't list the path, naming `project add` |
| `projectNew(slug, from:, title:)` | `project new` (L59): checks the file plays, appends the `[[projects]]` table (`ConfigDesk.addProject`); when no other project lists the video, moves its review in (`ReviewDesk.adopt`), rekeys its queue (`ListenerHub.rekey`) and the window that holds the video holds the project (`WindowModel.moveIntoProject`); else the project starts fresh (E4) | a slug in use; no file; a file that doesn't play; a review that doesn't read; a `config.toml` with a problem |
| `projectAdd(slug, video:, label:)` | `project add` (L59): appends the version (`ConfigDesk.addVersion`), `leaveDemo()`, then the version opens in the project's window (else the empty key window, else a new one), which comes forward | an unknown slug; no file; a path the project lists already; a file that doesn't play |
| `listenedReview(video:, project:)` | the review a `wait` binds to (L56): `--project`, else `--video` resolved as `open` would, else the key window's review (L56) | a path with no file; an unknown project; no video in the key window |
| `homeProjects` | the home screen's projects, the most recently opened first, each with its latest version | |
| `makeWindow()`, `newWindow()`, `sceneAppeared(target:)`, `attach(_:to:)`, `focus(_:)`, `windowClosed(_:)` | a window's model: made with the next id; `newWindow` (File › New Window, the Dock icon with no window, `window new`) also opens its scene, which takes it as it appears (`WindowRegistry.place`); a scene that appears with none waiting (the launch) gets a new empty one; `attach` ties the `NSWindow`, whose key changes `watchWindows()` follows | |
| `window(id, making:)`, `controlledWindow(id, making:)` | the window an operator command acts on: `--window`'s, else the key window (the one with the keys, else the one that had them last, else the one made last); `player open`, `app home` and `app demo` make one when there is none | an unknown id, listing the windows; no window is open |
| `windowList()`, `openWindow()`, `closeWindow(id)` | `window list`, `window new`, `window close`: closing pauses the window's video, keeps its position and drops the window; the app runs on with no window | an unknown id; no window |
| `state(window:)`, `appReport` | `state`: the window's report, with every window; with no window, `screen: none` and no video | an unknown id |
| `enterDemo(video, in:)`, `leaveDemo()` | the in-app demo (L27): every window queues its popover's words and closes its video, the `DataFolder` switches to the demo folder, and the window opens the video there; or every window's video closes and the data switches back to `launchSupport`; a demo run never switches | as `WindowModel.open` |
| `openDemo(in:)` | "Try the Demo" and `app demo` (L49): `enterDemo` on the bundled video (`DemoRun.video()`) in that window | no bundled video; as `enterDemo` |
| `recents`, `refreshRecents()`, `removeRecent`, `savePositions()` | the recent videos of the data, the same in every window (L48); every window's position on quit | |
| `keepSidebarWidth(width)` | the sidebar's width, one for every window, in `settings.json` on the folder the run started on | |
| `setTheme(name)`, `themeList()` | through `ThemeDesk`; `system` unpins | an unknown theme |
| `dismissConfigNotice()` | `config dismiss` and the banner's close button, in every window | |
| `setupReport`, `setupStatus`, `linkCommand`, `installSkill`, `cancelInstall` | through `SetupDesk` (L52) | as `SetupDesk` |
| `showFirstRunOnFirstLaunch()`, `showFirstRun`, `firstRun(_:)`, `openDemoFromFirstRun`, `firstRunReport` | the first-run window (L60) | as `FirstRun` |
| `showsConnectDot` | the connect button's dot and Finish setup: setup isn't fully detected and no agent has ever connected (L57) | |

`AppModel` owns the `ConfigDesk`, `ThemeDesk`, `SetupDesk` and `FirstRun`, the `ContentHashCache` (`hashes`) and the `Thumbnails`. `HavoochApp` holds the scenes and the menus; its `AppDelegate` keeps the app running with no window (`applicationShouldTerminateAfterLastWindowClosed` is false), makes an empty window when the Dock icon is clicked with none (`applicationShouldHandleReopen`), hands Finder's files to `openFromFinder`, probes setup again on `applicationDidBecomeActive`, saves every window's position on quit (a SIGTERM quits as Cmd+Q does), and owns the first-run window.

### ReviewApp: one window

`WindowModel` (`@Observable`) is one window's orchestrator. Its methods are the product's actions in that window:

| Method | Rules it owns | Refuses |
|---|---|---|
| `open(url)`, `open(url, project:)` | hash the file, resolve its target, load the review (`ReviewDesk.review(for:in:)`), load the video, record path and frame rate (`Review.show`), prepare the transcript, read the context, save the position of the video that goes, put a plain video first on the recent videos (a project's open goes to `recordProjectOpened`); closes any popover | a file AVPlayer cannot play; a review that does not read; a review another window holds (`… is open in window w1`), checked before and after the load |
| `moveIntoProject(slug)`, `showVersion(of:)` | the window's plain video became a project's v1 (L59); a thread of another listed version brings that version on screen first | |
| `goHome()`, `goHomeForPerson()` | home (L49): an in-app demo is left (`AppModel.leaveDemo`, every window goes home); otherwise the popover's words are queued on their review (`settle`), the position saved and the video closed (`leaveData`); the review stays in the desk. Then `refreshRecents()`, so a moved file's card turns unavailable. `goHomeForPerson` runs it from the header's mark and File › Close Video | |
| `openRecent(recent)`, `openDemo()`, `tryDemo()`, `openFromPanel()` | a recent card (nothing for one whose file is gone); "Try the Demo"; the header's Open | as `open` |
| `closed()` | its window closed (Cmd+W, `window close`): the popover's words are queued, the video pauses and its position is kept | |
| `play()`, `seek(seconds)`, `togglePlay()` to play, `scrub`, `skip`, `step(frames)`, `jumpToMarker`, `showThread(thread)` with a frame, `addMessage` that seeks, `open(url)` | each one is a **moment change**: it first calls `closePopover(.momentChanged)` (D 2.2, D 2.3); `seek` and `open` wait until those words are queued. Pausing is none (L23) | no video; a time outside the video |
| `startDraft(region?)` | C, the Comment button, the end of a drag: pause, fix the frame time, open the popover on the thread at that frame (or the next number) with an empty draft. C over an open popover does nothing; a new region closes it as a click outside (L24) | no video |
| `closePopover(reason)` | `.clickOutside`: deliver the words (`deliver`: an answer when the frame's thread has an open question, else queued); `.discard` (× or Escape): drop them and the composer's drawn region; `.momentChanged`: deliver the words at their own time and region. An empty draft is closed and its region stays as the composer's chip. An empty draft is only closed in every case (D 1.4). A click on the frame, the start of a drag, and `OutsideClicks` are clicks outside | |
| `openPopover(text, region?)` | `comment open` (L22): an open popover closes as a click outside, then `startDraft(region)` with `text` in the field | no video |
| `commitDraft()` | Return in the field and Queue (Answer): on a thread with an open question the text is an `answer` at once (L14), else it is queued; the popover stays open on its thread with an empty field and no region (L31) | (no words do nothing) |
| `addMessage(text:at:region:thread:)` | the CLI's path: a trial write refuses first, then a thread of another version comes on screen, pause, seek to the frame, write the images, write the message | no video; empty text; bad time, region or thread; a region on a removed version's thread |
| `editMessage`, `deleteMessage` | through `ReviewDesk`; delete removes the crop, and the keyframe when the thread goes | not queued; unknown id |
| `openThread(id)` | a pin, a badge, a notice, a row's frame button, `thread open` (L29): seek to the thread's frame (a moment change for a popover open on another frame; one open on this thread keeps its words), pause, select the thread, open its popover at its kept frame | General; with `thread open`, no video, an unknown thread, another review's thread |
| `showThread(id)` | a click on a row, Previous and Next (`showNeighbour`), Up and Down: the sidebar shows the thread's view (`shown`, apart from the pin's `selection`, L38), the player pauses and moves to the thread's frame. `shown`'s `didSet` marks the thread seen (L46). `showThread(ref)` is `thread show`, which answers once the player is on the frame | a thread of another review |
| `showOnVideo(id)`, `deleteQueued(on:)`, `perform(_:on:)` | a row's menu (L40): Show on Video picks out the pin and pauses the player on the thread's frame, the sidebar stays on the list; Delete Queued Messages deletes each queued message of the thread. `rowActions(for:)` says which of Open, Show on Video and Delete Queued Messages apply; a click, the keys, the menu and VoiceOver all go through `perform` | General has no frame |
| `showThreadList()`, `escape()` | Back, Escape and `thread list`: the sidebar shows the thread list; the player stays. Escape closes the first of: the version picker, Compare's picker, Compare's popover, a rectangle being drawn, the comment popover (discarded), the version menu, the comparison, the Connect view (back where it came from), the thread view | |
| `focusControl`, `blurControl`, `pressFocusedControl`, `isControlFocused` | the window's focused controls as a stack (L45): the last to take the focus is pressed by Space and Return | |
| `versionTree`, `allVersionsMenu` | a project's thread list by version (L61), from `projectOutline`, the threads, the version on screen and `pickedVersions`; the menu while `versionMenu` (its search) is set | nil on a plain video |
| `openVersionMenu(search:)`, `closeVersionMenu()`, `pickVersion(_:)`, `removePickedVersion(_:)` | All versions and `thread versions`; a pick in it, a Still open chip and `thread version`: an older version joins `pickedVersions`, the menu closes, `versionJump` scrolls the list; a picked section's close button and `--remove`. A change of project empties both | a plain video; a number outside the list; removing a version that isn't picked |
| `versionSwitch`, `versionPicker`, `projectWords` | the header's switcher and title in a project (L62): `VersionSwitch` (pure) from `projectOutline`, the threads per version and each file's date; the picker's search and highlight | |
| `switchVersion(to:)`, `openVersionPicker(query:)`, `closeVersionPicker()`, `typeVersionQuery`, `moveVersionHighlight`, `openHighlightedVersion` | a segment, the field, the picker's keys and rows, `version show`, `version pick`, `version close`: the version comes on screen with the playhead at the same time; the thread list's on-screen section follows it | a plain video; outside the list; pick on three versions or fewer |
| `compare`, `pair`, `companion`, `activeSide`, `canCompare`, `compareReport` | Compare (L63): the popover's `CompareSession` or the comparison; while comparing, `engine` and `video` are the active side's and `companion` the other side's version | |
| `openCompare()`, `toggleCompare()`, `pickCompareSide(_:query:)`, `typeCompareQuery`, `moveCompareHighlight`, `pickHighlightedCompareVersion`, `closeComparePicker()` | the Compare button and `compare open`, a side's chip or picture and `compare pick`, the picker's keys and rows | a plain video; one version; while comparing |
| `setCompare(_:)`, `swapCompare()`, `startCompare()`, `exitCompare()` | `compare set`, the swap button, the popover's action and `compare start`, Exit Compare, Escape and `compare exit`: a side's new version loads on its own player at the playhead's time; start loads the other side's player and makes the `PlayerPair`; exit retires the left side's player and keeps the right one | Compare closed; a version outside the list |
| `activate(_:)`, `clickFrame(on:)`, `beginRegion(on:)`, `flipCompare()`, `slideCompare(to:)`, `frameMarks(on:)` | a click or a drag on a side, a thread of the other side's version, `version show` of a side's version and `compare set --side`: the side becomes active (words in the popover are queued first on their version, captured in `Showing`); the flip key; the slider's handle; each side's marks | |
| `composerTarget`, `composerText`, `composerRegion` | the composer at the sidebar's foot (L41): `ComposerTarget.resolve` (pure) from the thread shown, the General toggle, the thread of the frame on the stage and the drawn region; the text is the target's draft in `composerDrafts`, one per thread and one for a new thread | |
| `writeComposer()`, `submitComposer()`, `toggleComposerGeneral()`, `removeComposerRegion()` | Return in the composer: an answer at once with an open question, else queued on the target, with the region chip when it fits; the draft, the chip and the General toggle are spent; the player stays | empty text; no video |
| `compose(text, region?, general)` | `comment compose` (L41): the words, a region chip on the player's frame and the General toggle in the composer, which takes the keys | no video |
| `send()` (`sendQueue()`) | Cmd+Enter, the Send button and `send`: the popover's words are queued (or answer), the composer's words are written, then `Review.send(at:onScreen:transcript:)` through `ReviewDesk`, then the review's `ListenerQueue.enqueue`; with nobody listening the Connect view opens on the send (`sentWithNoAgent`, L57); the tour notices it (L58) | nothing queued (`send` exits 1) |
| `answer(thread, text)`, `choose(thread, choice:)`, `chooseAnswer` | `thread answer`, the field, `thread choose` and a quick-reply chip: through `ReviewDesk`, then the review's `ListenerQueue.answered`; the question's notices go | no open question; no such choice |
| `movePopover(id, frame)` | the end of a drag or a resize: saves the `PopoverFrame` | |
| `keepSidebarWidth(width)` | the end of a drag on the sidebar's edge, inside `Metrics.sidebarWidthRange`: `AppModel.keepSidebarWidth`; `sidebarWidth` reads it back, the default 340 without one | |
| `setContextNote(text)`, `saveContextNote`, `readSidecar` | the context popover's Save and `context set` | no video |
| `toggleConnect`, `showConnect`, `closeConnect`, `pickHarness(named:)`, `disconnectAgent`, `forgetAgent`, `outboxBanner`, `listenerPhase(at:)`, `connectReport` | the Connect view (L57), in `Windows/WindowConnect.swift` | as `connect` commands |
| `toggleTour`, `showTour`, `nextTourStep`, `skipTour`, `closeTour`, `writeTourExample`, `tourRings`, `showsFinishSetup`, `setupItemsLeft`, `tourReport` | the tour and Finish setup (L58), in `Windows/WindowTour.swift` | as `tour` commands |
| `raise`, `dismiss`, `openNotice` | a notice: up for 5 s, a click opens its thread (L28) | |
| `state()`, `report(isKey:)` | the window's `state`, with `window` (its id) and `windows[]`; its line in `window list` | |

- `Draft` is view state only: `time`, `region`, `text`. The thread it writes to is computed (`draftThreadNumber`: the thread at that frame, or the number a new thread will take). It is never saved (D 1.4). `state --json` reports it as `popover`, with that number.
- **Frame time** (L2): `PlayerEngine.frameTime(of: t)` is the start of the frame shown at `t` (from the track's nominal frame rate), raised to the next millisecond. Every thread time goes through it, from the UI and from `--at`. The frame length comes from the nominal rate snapped to a whole or an NTSC rate (L20).
- **Showing**: `WindowModel.Showing` is the video on screen, its anchor, its player's asset and frame length, captured when words leave the popover, so a message is queued on the version it was written on even when a compare side becomes active meanwhile.
- `trackArea` is the frame of the player bar's track in the window, which the bar reports, so the popover on a moment points at the playhead (L25).

### ReviewApp: the desks and the listeners

- `ReviewDesk.change(key) { … }` is the one path for a change: load or take from memory, run, save, publish; a refusal or a failed save changes nothing. The desk keeps every review it has loaded by `ReviewKey` and no open one: each window reads its own (`opened(key)`, never from disk). `threadID(text, open:)` resolves a thread reference to a `ThreadID` and its review, a bare number on the window's review. `adopt(old, into: slug, anchor:)` moves a plain video's review into a project (`Library.move`), keeping its ids; `freeHash8` picks a prefix no review has for a new project's review.
- `ListenerHub` (L56), on the `DataFolder`, holds one `ListenerQueue` per `ReviewKey` (`queue(for:)`), made the first time a review needs it and kept for the run. `ControlServer` asks `AppModel.listenedReview(video:project:)` which review a `wait` binds to, then waits on that queue; `ack` and `status` find their queue by the id's prefix (`queue(of:)`), `reply` and `ask` by the thread id's (a bare number: the key window's review, `keyReview`). `rekey(old, to:)` moves a queue with its open `wait` to the project's key (L59). `isDelivered`, `connectionClosed` and `stop` go to every queue. `startedAt` is when the data opened, for the reconnecting phase. A `WindowModel`'s `listener` is its review's queue; the footer's presence pill, the activity lines, the agent's name and the Connect view read it.
- `ListenerQueue` holds one review's sends: `enqueue`, `wait(by:timeout:connection:)` → `Outcome` (`send(ref, payload)`, `ranOut`, `replaced`, `takenOver(by:)`, `disconnected`, `gone`), `written`, `undelivered`, `isDelivered`, `connectionClosed`, `ack`, `status`, `reply`, `ask`, `answered`, `rekey(to:)`, `phase(at:)`, `disconnect()`, `report(at:)`. A send is marked `taken` only once its reply was written: until then it is kept out of every other `wait` (L16). `ack`, `reply` and `ask` raise a `Notice` through `ListenerHub.announce` in the window that holds the review, and in no window when none does; `status` raises none. A `wait` from another holder while the last one was present (not absent) is a takeover: the older `wait` ends as `takenOver(by:)`, `takeover` keeps who from whom, and a `.takeover` notice "<new> took over from <old>" goes up on General. `status working` with a text sets the thread's activity (`Activity`: thread, message, text, time), the latest one per thread, kept in memory only; `done` or `failed` on its message, an empty text, Disconnect, and a new session that takes back sends clear it. `activities(at:)` and `activity(on:at:)` give nothing while the presence is absent, and `state` reports them, newest first, as `listener.activity`. The phase (`phase(at:)`) is `connected`, `reconnecting` (a session the last run left, not heard from in this one, for 30 s after the data opened) or `none` (L57).
- `Notice` is `id`, `thread` (id and number), `kind` (`acknowledgement`, `message`, `question`, `takeover`), `agent`, `text`, `expires` (5 s for every kind, L28), with its `title` (`#3 · Claude Code`, `General · Claude Code`, `New listener`) and `hint`. A click calls `openThread`, or shows General's thread view (L18).
- `ConfigDesk` (L53) makes a missing `config.toml` from the header at launch, watches the file and its folder (`ConfigWatcher`, debounced 200 ms), applies a save that reads at once, keeps the last valid settings for one that doesn't, and writes the verdict to `config-status.json` after every reload. A new set of problems is a `notice` drawn by `ConfigBanner` at the top of every window, never a modal alert. `addProject` and `addVersion` write through `ConfigLocation` and reload; `outline(slug)` and `outline(of:)` give a `ProjectOutline` with `~` expanded. The move from an older build runs once at launch: `settings.json`'s `theme` into the file unless it pins one, `Themes/` to `themes/` beside it, token overrides dropped with a note.
- `ThemeDesk` holds the `ThemeCatalog`, the `ConfigDesk` whose `config.toml` names the pin, and the system appearance, and publishes the `ResolvedTheme`; it reads the themes again each time `ConfigDesk` applies other settings. The system appearance is `NSApp.effectiveAppearance`, observed, so a screenshot in the other appearance shows that appearance's default theme. `DispatchSource`s on `themes/` and each theme file reload the themes 150 ms after a change (D 5.6); the watches are made again after each reload, since an editor that saves by replacing a file makes a new one. `startWatching` makes `themes/`, so a person finds where their themes go. A theme problem, or a pin no theme has, is written to standard error once and listed by `theme list`. While a theme is pinned, the window takes its kind's appearance through `RootView`'s `preferredColorScheme`, never on the `NSWindow` itself: SwiftUI sets the window's appearance from that preference on each update, and an AppKit view that set it as well fought SwiftUI in an endless update loop.
- `Palette` turns the resolved tokens into `Color`s, reaches every view through the environment (`@Environment(\.palette)`), and is the only colour source a view has (D 5.1); a test in `ReviewAppTests` fails on a raw colour anywhere in `Sources/ReviewApp`, and in `Palette.swift` on anything but a colour from numbers, a `system` surface or the focus ring (L37, L42).
- `SetupDesk` (L52), app-wide on `AppModel.setup`, reads `HOME` and `SHELL` from the app's environment, and finds this bundle's `Contents/Helpers/havooch` (none in a build that isn't bundled). It probes at launch, on `applicationDidBecomeActive`, after Link and after an install ends, on `setup status` and when the first-run window shows; it never polls. `link()` keeps a failure (`linkFailure`) for the view and refuses with the `ln -sf` line. `startInstall(for:)` refuses while one runs, for a name no harness has, and with nothing to install for; it keeps the install as `InstallRun` (`running`, `done`, `failed`, `cancelled`, `noNode`, the exit status, the last 500 log lines) after it ends. The runner's lines reach the main actor in order through an `AsyncStream`. `cancelInstall()` cancels the install's task and answers once it has ended. `isLinked`, `isSkillDetected` (detected for one harness at least and every harness found), `isDetected`, `suggestedHarness` and `readiness(of:)` (`ready`, `skillNotDetected`, `harnessNotDetected`) serve the Connect view and the first run.
- `FirstRun` (L60) is the first-run window's model: its step (`welcome`, `tools`, `connect`, `tryIt`), the picked harness, the problem. It and `WindowModel` are both a `SetupSteering`, what the setup step views act on (setup, the picked harness, its paste prompt, Link, Install, Cancel, the window whose keys a focused button takes).
- `TranscriptDesk` keeps the videos opened in this run and gives the lines around a time; `ContextReader` reads the sidecar `<video>.context.md` plus the note.

### ReviewApp: control

- `SocketListener` (D A.8) accepts on `control.sock` (mode 0600) off the main actor, reads one request per connection, awaits `ControlServer.reply(to:)` in a task, and writes one space every 2 s while the answer is pending. A heartbeat that cannot be written tells the server the client hung up (`connectionClosed`), which ends a held `wait` or `ask` as `gone`. It then writes the reply; a reply that was written goes to the server as `written` (a send it carried is taken), and one that cannot be written as `undelivered` (L16).
- `ControlServer` only decodes, checks the lease, dispatches and keeps the queued `take`s. It owns the one `ControlLease` and settles it on a timer. It depends on the `AppControlling` protocol (the app: `state(window:)`, `controlledWindow`, `openInFront`, the window, project, theme, config, setup and first-run commands), which `AppModel` implements, and `WindowControlling` (one window's actions, the connect, tour, version and compare commands included), which `WindowModel` implements; the tests' fake is both. An operator request acts on `ControlMessage.window`, else the key window (L54). It asks for the current `ListenerHub` at each request (`currentListeners`), and hands a send's `written` or `undelivered` back to the queue that handed it out.
- `AgentControlIcon` is the lease as the agent-control icon shows it. `AgentControlButton` (in `Header/AgentControl.swift`) is the icon, only while an agent holds the lease, and its popover: who, where, time left, how many wait, Stop (D 4.7). The icon shows in screenshots unless `--hide-agent-indicator` (L10).
- `Screenshotter` captures a player window (`--window <id>`, else the key one), Settings (opened as ⌘, does and closed again when it was closed), the About panel or the first-run window, through ScreenCaptureKit, in an appearance.
- `StateReport` builds `state --json` (its `config` part lives in `ThemeReport.swift`, its `setup` part in `SetupState.swift`):

```json
{
  "app":      { "version": "0.4.1", "demo": true, "support": "/abs/demo", "active": true },
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
  "threads":  [ { "id": "t-f92cbb2a-0", "number": 0, "time": null, "version": null, "state": null, "keyframePath": null, "popoverFrame": null,
                  "unread": false, "messages": [] },
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

- `project` is `null` on a plain video, `sidebar.versions` too; `project.compare` is the comparison while Compare is open (L63), `project.switcher` the header's switcher (L62). A question's message also names its `choices`.
- `state` describes one window, `--window`'s or the key window (`window`), and lists every window (`windows[]`: id, whether it is key, whether it is on screen, its `screen`, the video it holds and its listener); with no window open, `window` is null, `windows` empty and `screen` is `none`. `screen` is `player` with a video open, else `home`, for the home screen and the empty state alike (`StageContent.screen`). Its lines say `window: w1` and `screen:` under the first line, then list the threads, the recent videos and the projects, and end with `windows: N` and a line per window.
- Recent videos: `WindowModel.savePosition()` keeps the player's time on a plain video's entry; `open` calls it for the video that goes, `closed()` when the window closes, `AppModel.savePositions()` for every window in `applicationWillTerminate`, and `goHome()`. `AppModel.recents` is the list as `StateReport.Recent` (path, title without the extension, content hash, opened time, position, `available`: whether the file is there now), read on each call, so it belongs to the data folder the run is on; a revision counter makes views follow it. Nothing tells the app that a file moved, so `refreshRecents()` has the views read the list again: `goHome()` calls it, and `AppDelegate` on `applicationDidBecomeActive`.
- `PlayerEngine` holds the speeds (0.5× to 2×, through `defaultRate`); `Shortcuts` has J and L (10 s back and forward), the comma and the period (one frame), Cmd+Return (send) and the rest of the player's keys. `FrameGrabber` writes the keyframe at the thread's time and cuts the crop from it in memory.

### The UI

The views get every colour from `Palette` and every measure from `Metrics`, and they read their `WindowModel`; Settings reads the `AppModel`, the first run reads the `AppModel` and `FirstRun`, and the setup steps and the harness picker read a `SetupSteering` and the `SetupDesk`. Every prominent button is `View.filledButton(palette)`, on `accentFill` (L50). The stacked-layers symbol (`square.stack.3d.up` and its variants) is never used.

| Part | Design | From |
|---|---|---|
| Structure | One surface, `window`, for the header, the stage, the player bar, the sidebar and its footer, native in the default themes (L36, L37); `separator` hairlines on the sidebar's leading edge and above the footer; bubbles only for messages; no bordered cards. | L36, L37 |
| Player bar | Play and pause, `m:ss / m:ss`, speed, the timeline with ticks and labels, the Comment button. One `ThreadPin` per thread (not General): a rounded square when any message has a region, else a circle; the colour is the thread state's token; hover shows `#3 · 0:12 · 2 regions · Working` (`1 region`, `no region`). A queued pin is a ring; a later state fills it, with the state's glyph in `textOnAccent`. While the thread has an open question, the pin is filled in the `question` token with a `questionmark` glyph, its stem takes that colour, and the hover line ends `Question waiting` in place of the state (L35). A click opens the thread. Its height is `Metrics.barHeight` (52), which the sidebar footer shares. | D 1.1, D 1.3, D 1.6 |
| Region | A drag selection with a live `412 × 236` size label in frame pixels; the popover header names the thread number it writes to. | D 2.1, D 2.4 |
| Comment popover | One component for a new message and for an existing thread (`CommentPopover`): 8 pt padding, header `#3 · 0:12` (whole seconds, as the bar) and ×, the conversation (empty for a new thread) above a field across its whole width, quiet `textTertiary` key hints. On a moment its notch points at the playhead on the bar's track (L25); on a region it sits beside the rectangle. On an existing thread it drags by its header and resizes from its corner, inside the stage; the end of either saves the frame (L30). It opens at its kept frame, fitted to the stage (L32), else beside the draft's region or the thread's first region, else above the playhead. Nothing opens during playback. | D 1.2, D 1.7, D 1.8, D 2.7 to D 2.10 |
| Frame marks | On the current frame, while paused or playing: each thread's region outlines and one 20 pt number badge per thread (at its first region's corner, or the frame's top-left corner for a thread without a region), of the version on screen. A badge click opens the thread. | D 2.6, D 2.11 |
| Notices | Top right of the stage, at most three, 300 pt wide; they name the thread with the agent's logo, open it on click, and fade after 5 s, a question's too (L28). A notice is a native `.borderless` button. | D 4.10 |
| Header | While a video is open: the cat mark at the leading edge, a button that goes home (help tag "Home", L49); the video icon and the full file name; under it the folder icon and the folder, shortened in the middle, full path on hover, or "Demo". In a project the first line is the project's title with the `film.stack` icon, the switcher and the Compare button, and the line under it the version on screen (`v2 · tighter intro`, else `v2 · Oct 6`, else `a removed version`), then the folder (L62); while comparing, "Comparing v3 and v4", the filled "v3 · v4" capsule and Exit Compare in the switcher's place (L63). The home and empty screens show nothing in the header. The title is a toolbar item with no shared background; the band is the `window` token, or the native toolbar when `window` is `system`. | D 4.1 to D 4.4 |
| Floating controls | "Finish setup" (`checklist`, with its count in a `stateWorking` circle) in a capsule of its own (L58), then the group at the top right: the agent-control icon (while the lease is held), Connect an Agent (`antenna.radiowaves.left.and.right` with a 7 pt `stateWorking` dot while setup is unfinished, L57), "Open a Video…" (`folder`, the Open panel, L49), Context, the sidebar toggle. All but the agent-control icon show only while a video is open. | D 4.7 |
| Sidebar: thread list | The title "Threads" and a summary line (`6 threads · 1 needs you · 2 queued`; a project adds its version count), then on a plain video the groups Needs you, With agent, Queued, Done under headers with a glyph and a count that stay at the top while the list scrolls; Queued's says `⌘↩ sends them all` (L38). A `ThreadRow`: an 88 × 50 pt keyframe thumbnail with its region outlines (a globe for General), the number and time, the state chip (an "Answer" label in `question` while a question waits), a version tag in a project, the relative time, a chevron, and a two-line preview that names the writer (`You:`, `Asks:`, the agent), led by the agent's logo on an agent's message. An unread row (L46) has an 8 pt `accent` dot at its left, its title bold, its preview in `textPrimary` and its time in `accent`; VoiceOver reads `Unread` first. A right-click offers Open, Show on Video (not General) and Delete Queued Messages (when it has any), L40. A row is a `Button` with `RowButtonStyle`, so Tab reaches it with the system focus ring and Space or Return opens it (L43, L45). A row under the pointer takes `controlHover`; the row of the thread on the stage sits in a `well`. "No Threads Yet" is the compact native empty state. | D 3.1, D 3.2, D 3.7, D 4.5, D 5.10 |
| Sidebar: a project's list | `VersionList` from `VersionTree` (L61): General first with no header, then the last three versions as sections, newest first, then an older version on screen, then each version picked from All versions, then "Removed version" while a thread's version left the list. A section's header names the version and its label, marks "On screen", counts its threads by group and has a close button when picked; a thread off the version on screen has a quieter keyframe and title. The bar over the list says "Showing v48 to v50" and opens All versions (`clock.arrow.circlepath`): a search field, then In the list, Still open on older versions and Older, each newest first; its badge counts the open threads on versions with no section. The footer counts the older versions and has a chip per open thread on them. | E9 |
| Sidebar: thread view | A 44 pt top bar (Back with the count of the other threads that need the person, the number and time, Previous and Next with their keys ↑ and ↓ in their help), the conversation from the newest, under it the thread's activity (the working glyph and the words in `textSecondary`). The view slides in from the trailing edge with the sidebar's spring, a fade with Reduce Motion. Resizable between `Metrics.sidebarWidthRange` (300 to 460), the width kept in `settings.json`. | L38 |
| Conversation | A chat (L40), in the thread view and the thread popover alike. The person's messages trailing, 46 pt in from the leading side, in `bubblePerson` (16 pt corners, a 5 pt corner at the trailing foot for the tail), no avatar; a quiet line under the bubble holds the state chip (an answer: `Answer · sent at once` in `question`), the `Region` tag in `regionOutline` and the time. A queued message: a dashed `stateQueued` outline, `controlHover` on hover, Edit and Delete beside it on hover or while either has the keyboard focus, edited in place (Return saves, Escape cancels). An answer: `question` at 15% with a 40% border. The agent's messages leading, 34 pt in from the trailing side, in `bubbleAgent`; the 24 pt avatar (the harness logo, else the sparkle) beside the last bubble of a run, the name and time over the first. A question: a card in `bubbleQuestion` with a `question` border at 32%, headed `<agent> asks`; an answered one at 80% opacity. A region message's crop under its bubble. Messages 8 pt apart, 4 pt inside a run of the agent's. A right-click: Edit, Delete (queued only), Copy. VoiceOver reads one element per message (`MessageVoice`). In the thread view only, an open question with choices has a row under it: `Quick reply`, then one capsule chip per choice in `question` at 12% (22% on hover) with a 45% border, wrapping; a click answers at once. The row hides while a region is drawn or in the composer. | L40 |
| Composer | At the sidebar's foot, above the footer, under a hairline (L41): a 22 pt target line (glyph, "New thread at 0:12", "Reply on #3", "Follow up on #3", "Reply on General", or "Answer #3 · goes at once" in `question`), the `regionOutline` region chip with its ×, and in the list the General toggle (`accent` at 14%, 22% under the pointer, with a 40% border when on). The field: its own text view (`ComposerEditor`), `field` with a `separator` border (`question` for an answer), 15 pt corners, the keys at its trailing foot, the system focus ring round the whole field; it grows from one line to about six. Clicking into it pauses the player. | L41 |
| Footer | The presence pill (`Listening`, `Working`, `Reconnecting`, `No agent`; hover names the agent; the logo in place of the glyph; a click opens the Connect view, L57), the newest activity in `textSecondary` beside it (it takes the width first and truncates only when the count and Send leave no room), the queued count, Send. As tall as the player bar, a `separator` hairline above it inside that height. | D 4.8, D 4.9 |
| Connect view | The sidebar's third view (L57): a chevron with "Threads" (Back, Escape), the head "Connect an agent", the outbox banner line ("3 messages wait for an agent. They'll be delivered when one connects.", then "Delivered 3 messages to Claude Code"), and a step timeline: the command line (Link, a failure's `ln -sf` line in a `CopyBox`), the skill (a row per harness, the install command in a `RunBox` with Run Command, the live log and Cancel, Node missing, the command for one repository) and your agent (the harness picker, the picked harness's readiness, its prompt in a `CopyBox` with Copy Prompt). The first step not done is open; a done step folds to one line. Connected or reconnecting, the listener card (logo, agent, "Listening to <file>", since, Copy Path, Disconnect or Forget, the prompt to listen again) leads and setup folds to one "Set up" line. | G1 to G11, L64 |
| Tour | `TourPanel` over the foot of the stage (L58): five dots and "Step N of 5", the title, the words, and Skip Tour, Next or Later, Write an Example and Finish. Each step shows the sidebar it is about and rings parts of the window with a `CoachRing` 9 points outside its part (6 in the thread list). | H4, H5 |
| First run | An AppKit window of its own, its view 760 × 540, centred over the front player window (or the screen) the first time it shows in a run (L60, L66): Welcome (the loop as three pictures, the harnesses' logos), Tools (the Connect view's command line and skill steps), Connect (the harness picker and the readiness), Try it (the loop's three keys on a picture of the demo), on a progress bar. The footer has Skip Setup, a hint, Back, and Get Started, Continue (Continue Anyway or Later when the step isn't done) or Open the Demo. | H1 to H3 |
| Version switcher | `VersionSwitcher` (L62): the last three versions as segments, the one on screen raised (`knob` in a light theme, `popoverBorder` in a dark one, on a `controlHover` track); a project of more versions adds a field, `All 50`, which names an older version while it is on screen and opens a picker: "Go to version…" (a number with or without `v`, or a label), every version newest first with its label, thread count and date, a check on the one on screen, the highlight in `accent` with `textOnAccent`, Up, Down, Return, Escape. | E10 |
| Compare | `CompareButton` after the switcher in a project of two versions or more (L63). Its popover: the title and hint, the layout's segments (Side by side, Flip, Slider), a mini window with each side's still at the playhead, a chip per side with the swap button between them, the shared playhead, and a footer with "Opens on v3 and v4", Cancel and Show side by side (Compare in the other layouts). A side's chip or picture opens its picker: "Left side shows" with "N of M", a search field ("Find a version or label"), every version with its still and label, the tags "on screen" and "on right · swaps". `CompareStage` shows side by side two panes, Flip one picture with a bar at its foot ("v3 \ v4 press to flip"), Slider the right side under the left one wiped at a handle; each picture is labelled with its side and version, the active side's label filled with `accentFill`. | E11 |
| Empty screen | The native `ContentUnavailableView` with the cat mark, "Open a Video…" and "Try the Demo" (L27, L42). The whole stage is the drop target; a dashed accent outline shows over it while a file is over it. | D 5.11 |
| Home screen | With no video and one or more recent videos or projects (L48): the cat mark at 64 pt and the app's name, "Open a Video…" (the default button) and "Try the Demo", then "Projects" (`ProjectCard`: the latest version's thumbnail with vN, title, versions, when opened) and "Recent Videos" over grids of adaptive columns (200 to 300 pt) of 16:9 cards, the newest first. A recent card: the thumbnail on the `well` surface with a `separator` outline (`accent` on hover), the name without its extension, the relative time, the path as its help tag. An unavailable card: dimmed, `video.slash` in place of the thumbnail, "Unavailable" in place of the time, a trash button at its top-right corner. No sidebar. The whole screen is the drop target. | Spec 0.3.0 |
| Settings | The Settings window (⌘,): the cat mark, the name and version, the theme picker (`ThemePicker`, which View › Theme shares), and the settings file: its path, Applied or Not applied, each problem and note (L42, L53). | L42 |
| Settings notice | `ConfigBanner` at the top of every window: "config.toml wasn't applied" with each problem and its line, or what the move from an older build did; its close button closes it in every window (L53). | D1 to D3 |
| Keyboard | Under keyboard navigation every focusable control reports its focus through `pressedByKeys(in:isFocused:action:)`, and Space and Return press the last one focused (L45). `MessageField` and the composer draw the system focus ring (`FocusRing`, 3 pt outside the edge) while their text view has the focus (L42). | L42, L45 |

### The listener skill

`.agents/skills/havooch-mate/SKILL.md`, with one reference, `references/first-demo.md`, which the agent reads only when a send's `video.demo` is `true` (L60). The skill finds the command in the app bundle, picks its target (`--project <slug>`, `--video <path>`, the demo video it opens with `havooch open`, or the window `window list` names), and passes it on every `wait`.

```text
on a send     `ack <send-id> "<line>"`, then a new background `wait <target>`
per thread    read the keyframe, the crops, the transcript, history[], the version and the context
per message   `status working "<what you do now>"`, again at each step → the work → one commit when files changed, its body ending
              `Havooch-Message: <message-id>` (a re-send is checked with `git log --grep`) → `reply <thread-id>` → `status done`
              cannot be done: `reply <thread-id>` with the reason → `status failed`
unclear       `ask <thread-id>` (with `--choice` for quick replies) in the background; the next thread goes on
new render    `project new <slug> --from <path>` before the first change to the video itself, then `--project <slug>` on every
              `wait`; `project add <slug> <render> --label …` for each new version
whole send    `reply t-<hash8>-0` (General) with one line
refused       each refusal has its next step; "the person disconnected you" ends the loop: no more `wait`
```

It also names `config path` and `config check` for the person's settings.

## 4. Implementation

### The methods that carry the logic

Writing a message (the UI and `comment add` meet in `WindowModel.queueMessage`):

```text
WindowModel.addMessage(text, at, region, thread)                      (Windows/WindowModel.swift)
  require a video and words; `at` inside the video
  thread = ThreadRef → the review's thread (a number or a full id of this review)          else refused
  time   = frameTime(at) ?? thread's time (nil for General) ?? frameTime(player.time)      // the thread key
  a trial write on a copy of the review: every refusal comes here, before the player moves (L6)
  a thread of another version: that version comes on screen first (showVersion)
  pause; seek(time) when there is one (a moment change: closePopover(.momentChanged))
WindowModel.queueMessage(text, time, region, thread, on: Showing?)    // also the popover's and the composer's path
  showing = the video on screen, its anchor, asset and frame length
  planned = trial write                                                // starts a thread? which frame?
  FrameGrabber.writeImages → frames/.pending-<token>-keyframe.png (a new thread),
                             frames/.pending-<token>-crop.png (a region)                     // @concurrent
  refused when another video opened meanwhile
  written = desk.change(key) { try $0.write(text:, at: time, region:, to: thread, on: anchor, now:) }
  move the pending keyframe to frames/<thread id>.png when the thread has none,
  the pending crop to crops/<message id>.png (a crop that can't be moved deletes the message again)
  remove what's left pending; select the thread's pin
```

Closing the popover:

```text
WindowModel.closePopover(reason)
  guard let draft
  draft.text empty                → close it (a drawn region stays as the composer's chip); done
  reason == .discard              → drop the draft and the composer's drawn region; done
  reason == .clickOutside / .momentChanged
                                  → deliver(draft): the frame's thread has an open question → answer at once (L31),
                                    else queue(draft) → queueMessage(text, draft.time, draft.region, thread: nil)   // its own moment
  draft = nil
```

Sending and delivering:

```text
WindowModel.sendQueue()
  await the message whose pictures are still being written
  the popover's words: an answer when its thread has an open question (closePopover(.clickOutside)), else queueMessage
  the composer's words: writeComposer()
  send = desk.change(key) { try $0.send(at: now, onScreen: anchor,
                                        transcript: { transcripts.lines(around: $0.time, of: its version's video) }) }
  ref = SendRef(sendID: send.id, review: key)
  listener = listeners.queue(for: key); listener.enqueue(ref)
  listener.presence(at: now) == .absent → sentWithNoAgent(ref)        // the Connect view opens on the send (L57)
  tourNoticedSend(ref)                                                 // the tour moves on (L58)

ListenerQueue.wait(holder, timeout, connection) async -> Outcome
  the holder was let go (Disconnect, Forget)  → .disconnected, once
  requeued = outbox.waitOpened(by: holder, at: now)                   // a new key: taken → front of pending; contextSent cleared
  for ref in requeued: desk.change(ref.review) { $0.requeue(ref.sendID) }   // unfinished → sent
  a present last listener of another key → the takeover notice
  connected?()                                                         // the tour and the first connection hear of it
  resume an older open wait: .replaced (same key) or .takenOver(by: new)
  if let outcome = takeNext(): return outcome
  if timeout == 0: return .ranOut
  suspend; start the timeout when there is one

ListenerQueue.takeNext()
  while a wait is open and a send is first in line and not in flight
    review unreadable, or nothing unfinished: outbox.discard; next
    context = outbox.context(for: key.contextKey, text: ContextReader.text(for: review))   // nil when sent unchanged
    payload = SendPayload.assemble(review, send, context, images: layout paths, project: the outline now)
    outbox.handOut (in flight); return .send(ref, payload)

SocketListener   writes the payload → server.written(ref) → outbox.written (pending → taken)
                 the write fails   → server.undelivered(ref) → back in line, the review's digest forgotten
```

Answering on a thread:

```text
ListenerHub.ask(thread, question, choices, waitSeconds, connection) async -> Asked
  (id, key) = desk.threadID(thread, open: keyReview())               // a full id by its prefix; a bare number: the key window's review
  queue(for: key).ask(on: id, of: key, question:, choices:, waitSeconds:, connection:)
    outbox.heard; desk.change(key) { try $0.ask(on: id, question:, choices:, session:, now:) }   // refused while a question is open
    announce a notice "#n · Claude Code: <question>"
    waitSeconds == 0 → .ranOut; else outbox.askOpened; suspend under the thread id
WindowModel.answer(thread, text)                                      // the field, a chip, or `thread answer`
  (id, key) = desk.threadID(thread, open: reviewKey)
  message = desk.change(key) { try $0.answer(id, text:, now:) }
  listeners.queue(for: key).answered(id, with: message)               // the ask exits 0 with the text
```

Opening, and making a project:

```text
AppModel.openInFront(url, project?)                                   (AppModel.swift)
  needFile(url); the project known; PlayerEngine.checkPlayable(url)   else refused, nothing changes
  leaveDemo()
  window = windowFor(url, project, from: nil)
    hash   = ContentHashCache (path, size, modification time) or a streamed SHA-256
    target = resolveTarget(url, hash, project)                        // --project, else the latest project listing the path, else .video
    the window that holds target.reviewKey → it (a project's window opens the version asked for)
    else the key window when it holds nothing → it.open(url, project:)
    else makeWindow(); it.open(url, project:); windows.show(it)       // its scene opens through openWindow
  play; focus(window); bringToFront                                   // the reply carries the app's pid (L51)

AppModel.projectNew(slug, url, title?)
  needFile; the slug free in config.toml; checkPlayable; hash
  elsewhere = another project lists the path
  !elsewhere: desk.readable(.video(hash))                             // a review that doesn't read stops it here
  config.addProject(slug, title, firstVersion: url.path)              // ConfigLocation.addProject, then reload
  elsewhere → done: the project starts fresh (E4)
  desk.adopt(.video(hash), into: slug, anchor: url.path)              // Library.move; ids and hash8 kept; threads anchored to v1
  listeners.rekey(.video(hash), to: .project(slug))                   // the open wait stays open
  windows.holding(.video(hash))?.moveIntoProject(slug)
  library.recordProjectOpened(slug)

AppModel.projectAdd(slug, url, label?)
  needFile; the project known; the path not listed; checkPlayable
  config.addVersion({path, label}, toProject: slug)
  leaveDemo(); window = windowFor(url, project: slug, from: nil); focus; bringToFront
```

Edge cases:

- `comment add --thread 3 --at 0:15` where #3 is at 0:12: refused (`frameMismatch`) before any image is written (L6).
- `comment add --thread t-0a1b2c3d-2` while another review is open in the window: refused (`otherVideo`). Listener commands work on any review; operator writes need the window's.
- `comment delete` on the only message of thread #4: the thread and its keyframe go; the next thread is #5 (L4).
- `status m-… done` twice: the second changes nothing and answers as the first.
- A person message on a done thread: the thread is `queued` again; its pin turns the queued colour.
- The moment changes with an empty popover over a drawn region: the popover closes; no thread is made.
- `send` with nothing queued: exit 1, no send. Cmd+Enter with nothing queued does nothing.
- An answer typed in the composer while the thread's question is open: it is an `answer`, it never enters the queue, and the waiting `ask` exits at once.
- A `reply` on a thread whose only messages are queued: refused (`notSent`). On General: accepted.
- Speech still transcribing at send time: each thread keeps the lines that exist then; a redelivery gives the same lines.
- `theme set Purple` with no such theme: exit 1, `no theme Purple; havooch theme list names them`.
- A user theme file is saved with a syntax error: the catalog leaves it out; when it was active, the app falls back to the default of the appearance and `state` reports the active name.
- A version's path is taken out of `config.toml` by hand: its threads stay, tagged "Removed version", and take words on the whole frame.
- `project new` on a video another project lists: the new project starts fresh with an id prefix of its own; nothing moves.

### Trace 1: a CLI command, `comment add` on a region

Start: the app runs on demo data with the fixture open in `w1`, paused at 10.0 s. Thread #1 is at frame time 10.017 with one queued message `m-f92cbb2a-1` and no region. The lease is free. The caller is a Claude Code session.

Command: `havooch comment add "This box is too dark" --region 0.47,0.27,0.29,0.15`

```text
ReviewCLI/main.swift                   HavoochCLI.run(["comment","add",…], environment)
ReviewCommand/CommandTable.swift         `comment add` → CommentCommands
ReviewCommand/CommentCommands.swift      --region → ControlRequest.Rectangle(0.47,0.27,0.29,0.15)   (not four numbers: exit 64)
ReviewLease/Holder.swift                 Holder.find → "CLAUDE_CODE_SESSION_ID=…", "Claude Code", the working folder
ReviewWire/ControlSocket.swift           demo.json → the demo's control.sock
ReviewWire/ControlClient.swift           writes {"command":"comment.add","holder":{…},"region":{…},"text":"…","version":6}, half-closes
ReviewApp/Control/SocketListener.swift   reads to the end; task awaits ControlServer.reply(to:); heartbeat armed
ReviewApp/Control/ControlServer.swift    decode: version 6 = 6 → .commentAdd(text, at: nil, region, thread: nil)
ReviewLease/ControlLease.swift           use(by: holder, at: 12:00:00) → started, ends 12:01:00      state: the agent-control icon shows
ReviewApp/AppModel.swift                 controlledWindow(nil) → the key window, w1
ReviewCore/Region.swift                  Region(0.47,0.27,0.29,0.15): inside 0..1 → valid
ReviewApp/Windows/WindowModel.swift      addMessage: video open; trial write passes; no seek; pause
ReviewApp/Player/PlayerEngine.swift      frameTime(of: 10.0) → 10.017 (frame 300 at 29.97 fps, raised to the ms)
ReviewCore/Review.swift                  thread(atFrame: 10.017) → #1 (t-f92cbb2a-1); its keyframe exists
ReviewApp/Player/FrameGrabber.swift      crop → frames/.pending-<token>-crop.png (557 × 162 of the 1920 × 1080 frame)
ReviewApp/ReviewDesk.swift               change(.video(hash)) { write(text, at: 10.017, region, to: nil, on: nil, now) }
ReviewCore/Review.swift                    appends m-f92cbb2a-2 (person, message, queued, region) to #1
ReviewStore/Library.swift                  videos/f92cbb2a…/review.json written
ReviewStore/SupportLayout.swift          crop(m-f92cbb2a-2, of: .video(hash)) → the pending crop moves to <demo>/videos/f92cbb2a…/crops/m-f92cbb2a-2.png
                                         state: #1 has 2 queued messages; its pin turns a rounded square; queue = [m-1, m-2]
ReviewApp/Control/ControlServer.swift    done("m-f92cbb2a-2 queued on #1 at 0:10 on the region 0.47,0.27,0.29,0.15")
ReviewApp/Control/SocketListener.swift   heartbeat stopped; reply written; connection closed
ReviewCommand/HavoochCLI.swift           prints the line, exit 0
```

The rejection: five seconds later another holder runs `havooch comment add "x"`.

```text
ControlLease.use(by: other, at: 12:00:05) → .inUse(term); nothing reaches the window
reply {"ok":false,"error":"Havooch is in use by Claude Code in /…/repo until 12:01:00 (55s left); `havooch control take --wait <seconds>` to queue"}
CLI: the line on standard error, exit 1
```

A CLI of another protocol version sends `"version": 5`: `decode` refuses it before the lease is asked, naming both versions.

### Trace 2: a send, from Cmd+Enter to `wait`, then a follow-up

Start: after Trace 1, the person seeks to 0:15 and draws a region; thread #2 starts at 15.015 with `m-f92cbb2a-3` (region). The queue is `m-1`, `m-2` (#1) and `m-3` (#2). A listener session L1 has `havooch wait --video <sample.mp4>` open on this review and has not had its context. Its outbox: `session = L1`, nothing pending or taken.

```text
ReviewApp/Player/Shortcuts.swift         Cmd+Return → WindowModel.send() → sendQueue()
ReviewApp/Windows/WindowModel.swift      no draft; the composer is empty
ReviewApp/TranscriptDesk.swift           lines(around: 10.017) → 2 voiceover lines; lines(around: 15.015) → 2 lines
ReviewApp/ReviewDesk.swift               change(.video(hash)) { send(at: 19:02:11Z, onScreen: nil, transcript:) }
ReviewCore/Review.swift                    m-1, m-2, m-3 queued → sent, sendID s-f92cbb2a-1; transcripts kept for #1 and #2
ReviewStore/Library.swift                  review.json written
                                         state: queue = []; both pins the sent colour; footer "0 queued"
ReviewApp/ListenerQueue.swift            enqueue(s-f92cbb2a-1): pending = [s-1]; outboxes/video-<hash>.json written; takeNext()
ReviewCore/Outbox.swift                    context(for: hash, text): no digest this session → the text; digest recorded
ReviewApp/ContextReader.swift              sample.context.md (+ the note)
ReviewCore/SendPayload.swift               threads: #1 (history [], messages m-1, m-2), #2 (history [], messages m-3);
                                           keyframes and crops as absolute paths; transcript as kept; project null
ReviewApp/Control/SocketListener.swift   the held wait resumes; payload written → written(s-1)
ReviewCore/Outbox.swift                    written: pending = [], taken = [s-1]          state: presence working; pill "Working"
ReviewCommand/ListenerCommands.swift     prints the payload, exit 0
```

Then, as the listener: `ack s-f92cbb2a-1 "On it"` moves m-1..m-3 to `acknowledged` and writes the agent message `m-4` on General (notice `General · Claude Code`). `ask t-f92cbb2a-1 "Which box?"` writes `m-5` (question) on #1 and holds; `thread answer t-f92cbb2a-1 "The left one"` writes `m-6` (answer) and the `ask` exits 0 with it. `reply t-f92cbb2a-1 "Fixed in 4e1c2aa"` (`m-7`), `reply t-f92cbb2a-2 …` (`m-8`), and `status … done` on m-1, m-2 and m-3 finish the send: `Outbox.finished(s-1)`, both pins the done colour.

The follow-up:

```text
operator: comment add "Now make it lighter still" --thread t-f92cbb2a-1
ReviewApp/Windows/WindowModel.swift      addMessage: seek to #1's time 10.017 (a moment change; no popover open); pause
ReviewCore/Review.swift                  write on #1: m-f92cbb2a-9 queued              state: #1 is queued again
operator: send
ReviewCore/Review.swift                  send s-f92cbb2a-2: [m-9]; transcript for #1 cut again now
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
  L1 was present, so L2 took over: the notice "L2 took over from L1" on General
  takeNext(): L2 gets s-2 with m-9, its kept transcript, the same history, and the context again
```

### Trace 3: `havooch open` from the shell to a window

Start: the app runs with `w1` on home, empty and key. `config.toml` lists `cut2.mp4` as v2 of `launch-video`.

```text
$ havooch open ~/Movies/cut2.mp4
ReviewCommand/OpenCommand.swift          a file is there; the app answers the request (no launch)
ReviewWire/ControlClient.swift           .open(path: "/Users/me/Movies/cut2.mp4", project: nil); a person request, no lease
ReviewApp/Control/ControlServer.swift    → AppModel.openInFront(url, project: nil)
ReviewApp/AppModel.swift                 checkPlayable; leaveDemo (none); windowFor:
ReviewStore/ContentHash.swift              ContentHashCache: first read of the file → SHA-256
ReviewApp/AppModel.swift                   resolveTarget → .project("launch-video")    (the latest project that lists the path)
ReviewApp/Windows/WindowRegistry.swift     holding(.project("launch-video")) → none; the key window w1 holds nothing
ReviewApp/Windows/WindowModel.swift        w1.open(url, project: "launch-video") → ReviewDesk.review(for:in: .project(…)), v2 on screen
ReviewApp/AppModel.swift                 play; focus(w1); bringToFront
ReviewApp/Control/ControlServer.swift    "opened cut2.mp4 (0:55.033) in project launch-video (v2) in w1, playing", pid
ReviewCommand/OpenCommand.swift          AppLaunching.bringToFront(pid:); exit 0
state after: windows = [w1: project launch-video, v2 on screen]
```

Cold: with no app answering, `OpenCommand` launches it in front (`AppLaunching.launch(environment: [:], inFront: true)`), checks `app status` every 0.05 s for up to 10 s, then sends `.open` once. The rejection: `havooch open notes.txt` → `can't play notes.txt`, exit 1, the windows unchanged.

### Trace 4: a plain video becomes a project and gets v2

```text
the person writes 2 messages on cut1.mp4 (a plain video, window w1), Cmd+Enter
the listener (Claude Code, wait --video …/cut1.mp4) gets the send; a message asks to tighten the intro
skill, before the first change: havooch project new launch-video --from …/cut1.mp4 --title "Launch video"
  AppModel.projectNew
    ConfigDesk.addProject: config.toml += [[projects]] slug = "launch-video", versions = [{ path = ".../cut1.mp4" }]
    ReviewDesk.adopt: videos/<hash>/ → projects/launch-video/ (the transcript stays); threads anchored to cut1.mp4 (v1); hash8 kept
    ListenerHub.rekey: the queue is now launch-video's; its open wait stays open
    w1.moveIntoProject: the header shows the project and v1
the agent renders cut2.mp4 → havooch project add launch-video …/cut2.mp4 --label "tighter intro"
  ConfigDesk.addVersion: versions += { path = ".../cut2.mp4", label = "tighter intro" }
  w1 shows v2 and comes forward; the thread list: v2 (empty), v1 (2 threads)
the agent: reply t-<hash8>-1 "Done in v2" (its review found by the prefix); wait --project launch-video from now on
state after: one review, threads tagged v1, the switcher shows v1 v2
rejection: project add launch-videoo … → "no project `launch-videoo` in config.toml; the projects are launch-video", exit 1
```

### Trace 5: a send with no listener, then an agent connects

```text
w1 holds onboarding-cut-v3.mp4, 3 queued, nobody listening
Cmd+Enter → WindowModel.sendQueue: outbox(.video(h)) pending = 1 send (3 messages); presence absent
     sentWithNoAgent(ref) → connect = ConnectEntry(reason: .send, waiting: [ref])
     the outbox banner: "3 messages wait for an agent. They'll be delivered when one connects."
SetupDesk report: link detected; skill: claude-code detected, codex not detected
the person picks Claude Code → readiness ready; the prompt "/havooch-mate listen for my feedback on onboarding-cut-v3.mp4" → Copy Prompt
the agent runs havooch wait --video …/onboarding-cut-v3.mp4 → ListenerHub binds → delivers the pending send
w1: the banner says "Delivered 3 messages to Claude Code"; the listener card leads; settings.json keeps agentConnectedOnce,
    so Finish setup and the connect button's dot go
the other path: Codex picked → readiness skillNotDetected: the words say the skill wasn't detected and the prompt still shows,
    with the install command in a RunBox (Run Command)
```

### Build and tests

- `Package.swift`: tools 6.2, macOS 26, one dependency (TOMLDecoder, for `ReviewConfig` only); `ReviewApp` and `ReviewAppTests` use `.defaultIsolation(MainActor.self)` (D A.2). `ReviewApp`, `ReviewAppTests` and the `HavoochApp` product are added under `#if os(macOS)` (D A.9). With the Command Line Tools alone, the `Makefile` points the compiler at their Testing framework and shares one module cache.
- `make bundle` stamps the name, the bundle id and the version (`Version.app`) into `Info.plist`, writes `PkgInfo`, copies the app icon to `Contents/Resources/AppIcon.icns`, `Packaging/Logo/` to `Contents/Resources/Logo/`, `Packaging/Themes/` to `Contents/Resources/Themes/`, `Packaging/AgentLogos/` to `Contents/Resources/AgentLogos/` and `fixtures/launch/` to `Contents/Resources/Demo/` (L17), signs the helper `Contents/Helpers/havooch` and then the bundle ad hoc, and verifies the signature. `make install` replaces `/Applications/Havooch.app` (quitting only this bundle's app first); with `HAVOOCH_SUPPORT_DIR` set it opens the app on that folder.
- A release is a `v<version>` tag; the tag must match `Version.app`. `.github/workflows/release.yml` reads the name, the command and the version through `make identity`, runs `make test` and `make bundle`, zips the bundle with `ditto -c -k --keepParent` as `<command>-<version>.zip` with `<command>-<version>.zip.sha256` beside it, and publishes both. Then the `tap` job writes the cask (`scripts/update-tap.sh`) and the `mate` job the skill's repository (`scripts/update-mate.sh`); both need the `TAP_TOKEN` secret and skip with a notice without it (`docs/decisions/release-publishing.md`). `scripts/install.sh` reads the app and command names from the zip, never from a constant; it finds an installed copy for `--uninstall` by the bundle id `com.<repository owner>.<command>`. The app is ad-hoc signed and not notarized, so the first launch needs Open Anyway.
- Owner tests, one per contract at its strongest boundary:

| Contract | Owner test |
|---|---|
| version refusal, wire round trips | `ReviewWireTests` |
| the lease rules, the holder key order | `ReviewLeaseTests` |
| CLI parsing, output, exit codes | `ReviewCommandTests` |
| joining, thread numbers, states, thread state, send, transcript kept, requeue, payload shape, outbox, context once per session | `ReviewCoreTests` |
| a project's review: adoption, anchors, per-version lookup, the payload's project block | `ReviewCoreTests` (`ProjectReviewTests`) |
| theme resolution: extends, fallback, overrides, loops, the defaults define every token; `accentFill` made from a nearer `accent`; white on every shipped theme's `accentFill` at 4.5:1 | `ReviewCoreTests`, `ReviewStoreTests` (`ThemeFilesTests`) |
| `config.toml`: reading, problems on their lines, warnings, the location, the writes keeping comments, the verdict, the schema equal to the reader | `ReviewConfigTests` |
| `config path`, `config check`, `project list` with no app | `ReviewCommandTests` (`ConfigCommandTests`, `ProjectCommandTests`) |
| live reload, the last valid settings kept, `config-status.json`, the move from `settings.json`, app state kept out | `ReviewAppTests` (`ConfigDeskTests`, `ThemeDeskTests`) |
| the probe, Link, the prompt per harness, the install | `ReviewSetupTests`; `ReviewAppTests` (`SetupDeskTests`, `SetupServerTests`) |
| the window cut, the source order | `ReviewTranscriptTests` |
| paths, round trips, the id-prefix index, moving a review into a project | `ReviewStoreTests` |
| popover close rules, frame time, the send through `WindowModel` | `ReviewAppTests` on the fixture |
| which window an open goes to, what each window keeps, the window commands, `--window` | `ReviewAppTests` (`WindowTests`, `OpenInFrontTests`), `ReviewCommandTests`, `ReviewWireTests` |
| a listener per review, binding, rekey, takeover | `ReviewAppTests` (`ListenerHubTests`, `ProjectTests`) |
| the server, the heartbeat, a gone client | `ReviewAppTests` over the real socket |
| the listener's round: ack, status, reply, ask and answer, a follow-up, a listener restart | `ReviewAppTests` over the real socket (`ListenerSocketTests`) |
| the Connect view, the tour, the first run | `ReviewAppTests` (`ConnectTests`, `TourTests`, `FirstRunTests`) |
| the thread list by version, the switcher, Compare | `ReviewAppTests` (`VersionTreeTests`, `VersionListTests`, `VersionSwitcherTests`, `CompareTests`) |
| region crops at several window sizes | `ReviewAppTests` (`RegionMessageTests`) |
| what a restart keeps | `ReviewAppTests`, a second `AppModel` on the same support folder |
| no raw colour in a view, every shipped theme's contrast as the window draws it, every agent logo | `ReviewAppTests` (`ThemeDeskTests`, `PaletteTests`, `AgentLogoTests`) |
| everything end to end | `scripts/acceptance.sh`, 20 steps against the installed app in demo mode: the 0.1.0 spec's 10, `havooch open` (11), the windows (12), a listener per window (13), the Connect view (14), the tour (15), projects (16), the first-run window (17), the thread list by version (18), the version switcher (19) and Compare (20) |

## 5. Extensibility

| Change | What you touch |
|---|---|
| A new CLI command | a case in `ControlRequest` (and its role), a parser in `ReviewCommand` registered in `CommandTable` (`onAWindow()` when it acts on one window), a branch in `ControlServer`, a method on `WindowModel` (and `WindowControlling`), `AppModel` (and `AppControlling`) or `ListenerQueue`. The compiler finds the `switch`es. A new command needs no new protocol version: an older app refuses it in words (L44). |
| A new UI action | a method on `WindowModel`, or on `AppModel` when it is the app's, then its CLI command and its part of `state --json` (ADR 0001). |
| A new colour token | one `ThemeToken` case and its value in the two default theme files; the test of the defaults fails until both have it. |
| A new built-in theme | one JSON file in `Packaging/Themes/`, with `accentFill` when it sets `accent`. |
| Fonts or spacing in themes | a second map in `ThemeFile` and `ResolvedTheme`; `Metrics` reads it as `Palette` reads colours. |
| A new `config.toml` key | `ConfigFile`, `ConfigReader`'s key lists, `schema/config.schema.json` (a test keeps them equal), the skill's Settings section. |
| A better transcription source | one `Transcriber`, one line in `TranscriptSources.standard`. |
| A new field in the payload | `SendPayload` and `assemble`, and the skill's "The send". |
| A new message state | `MessageState`, `canMove`, a `state…` token. |
| A new harness | one `HarnessCatalog` entry, its logo (`KnownAgent`, `Packaging/AgentLogos/`), a live check of its prompt form. |
| A harness's skill invocation changes | its `HarnessCatalog` prompt form. |
| A new setup step | `SetupProbe`, a step view in `UI/Connect/SetupSteps.swift`, the tour's steps (`TourStep`), Finish setup's count. |
| A new compare layout | a `CompareLayout` case, its drawing in `CompareStage`, the popover's segment. |
| A project rename | a `project rename` command: `ConfigWriter`, a `Library.move` of the project's folder, `ListenerHub.rekey` (not built). |
| A rule for a listener that never comes back | `Outbox.waitOpened` and a time check in `Outbox.presence`; nothing outside the outbox. |
| The popover redesign | `ThreadPopover`, `CommentPopover`'s placement and `StageView`'s; the close rules stay in `WindowModel`. |
| A database in place of JSON files | `Library` only. |

Refused for now: undo, an Allow button, system notifications, a plug-in registry of commands, branching versions.

## 6. Decisions

Each decision this design takes, with its reason. Spec and ticket numbers say where a decision came from.

Some code comments still cite P1 to P13, the numbers of the projects-and-onboarding design this document absorbed. Each is part of an L decision here: P1 → L52, L53; P2, P3, P4 → L59; P5 → L56; P6 → L51; P7 → L53; P8, P9 → L63; P10 → L52; P11 → L57, L58; P12 → L60; P13 → L54.

| # | Decision | Reason |
|---|---|---|
| L2 | A thread's key is the frame's start time from the nominal frame rate, raised to the next millisecond (`PlayerEngine.frameTime`). | "The exact frame" (D 3.8) must be one number for two moments inside one frame, from the UI and from `--at`. |
| L3 | The thread id carries its number: `t-<hash8>-<number>`, General `t-<hash8>-0`. Messages and sends count on their own (`m-<hash8>-<n>`, `s-<hash8>-<n>`). | The id a listener holds and the `#n` the person sees are the same thing. One counter per kind keeps ids short and deterministic. |
| L4 | A thread whose last message is deleted goes away; its number is not reused. | An empty thread has nothing to show. A reused number would make an old reference point at another frame. |
| L5 | `--thread`, `thread answer`, `thread choose`, `thread open`, `thread show`, `reply` and `ask` take a full thread id or a bare number of the window's review. | `--thread 0` for General is a number. Full ids keep listener commands working after another video opens (D A.5). |
| L6 | `comment add --thread <id> --at <time>` is refused when the time is another frame than the thread's. Without `--at`, `--thread` seeks to the thread's frame. | A message must never join a thread of another frame (D 3.1). The operator does what the person does: writing on a thread shows its frame. |
| L7 | `history[]` is every message of the thread that is not in this send's `messages[]` and not queued, in order, also agent messages written after an earlier delivery. | "The conversation so far" (D 2.15). A redelivery then includes the agent's own partial replies. |
| L8 | The payload's and the state's `video.title` is the file name with its extension. | One title everywhere, as the header shows it (D 4.1). |
| L9 | Store files start at `schemaVersion` 1. The prototypes' data is never migrated. | The prototypes used other support folders; no migration was asked for. |
| L10 | The agent-control icon shows in screenshots by default, as the person sees the window. `screenshot --hide-agent-indicator` leaves it out. | The maintainer's decision. |
| L11 | Theme resolution lives in `ReviewCore/Theme/`, theme files in `ReviewStore`, the watch and the `Palette` in the app. The built-in themes are JSON files in `Packaging/Themes/`, copied into the bundle's resources. | Resolution is unit-tested without the app, on Linux. Plain files in the bundle avoid SwiftPM resource bundles and are examples for user themes. |
| L13 | Thread state with no person message (General with only agent messages) is no state; General has no pin. | State is defined from person messages only (D 3.9). General has no keyframe to pin. |
| L14 | The popover's field answers at once when the thread has an open question, else it queues. | One field, with no second control (D 2.16, D 3.6). |
| L16 | A send is marked `taken` only after its reply was written; until then it is in flight and no other `wait` gets it. | Paired with the heartbeat (D A.8), a dead listener never loses a send. |
| L17 | "Try the Demo" opens the launch explainer (`fixtures/launch/`, bundled as `Contents/Resources/Demo/havooch-demo.mp4`) on the demo folder, `<temporary folder>/Havooch Demo`, in the same window (L27). The demo folder keeps its threads between demos. | The empty screen needs a demo with no command line (D 5.11), and demo data must never mix with the person's. |
| L18 | Notices for General say `General · <agent>` and show General's thread view on click. | General has no frame to open (D 4.10). |
| L19 | A message's pictures are written under a pending name in `frames/` and renamed to `frames/<thread-id>.png` and `crops/<message-id>.png` once the review gave the ids. | The ids come from the review's counters, and a listener's `reply` written while the frame is read takes the next message number. A rename on the main actor right after the write can't be overtaken. |
| L20 | `PlayerEngine` snaps the track's nominal frame rate to a whole rate or an NTSC rate (n × 1000 / 1001) when it is within 0.001 of one. | AVFoundation gives the rate as a `Float` a hair off (29.999998 for 30), which put 10.0 s in the frame before. |
| L21 | `--thread 0` with `--at` or `--region` is refused (`noFrame`); without `--thread` a message always has a frame time. | General has no keyframe, so a time or a region on it means nothing. |
| L22 | `comment open [<text>] [--region x,y,w,h]` opens the comment popover at the player's frame, as C or a drawn rectangle does. | The CLI cannot click or draw. Without it the popover, a drawn region and the close rules can't be shown, checked or screenshotted in the real app. |
| L23 | Pausing is no change of the moment: the popover stays open. | The popover only opens on a paused frame, so a pause changes no frame (D 2.3). |
| L24 | A drag on the frame with the popover open is a click outside it: the words are queued on their region, or an empty popover goes, and the new rectangle opens a new popover. | Every click outside is one rule (D 1.4). |
| L25 | The popover on a moment points at the playhead on the player bar's track, whose frame in the window the bar reports (`WindowModel.trackArea`). | The bar's track sits between its buttons, not under the stage's whole width. |
| L27 | `AppModel` holds the run's data as a `DataFolder` it can replace: the support folder, its `SupportLayout`, the `ReviewDesk`, the `ListenerHub` and the `TranscriptDesk`. `enterDemo` queues every window's popover words, closes its video and switches to a `DataFolder` on the demo folder, then opens the bundled video there; `leaveDemo()` closes the demo's video and switches back to `launchSupport`. The Open panel, a drop and `havooch open` leave an in-app demo first. The hub left behind ends its held `wait`s and `ask`s as `gone`, so their commands connect again; `ControlServer` asks for the current hub at each request and hands a send's `written` or `undelivered` back to the queue that handed it out. An open still under way when the data switches is refused, and a message being queued keeps its review and pictures on the data its video is on. The `ThemeDesk`, the `ConfigDesk` and the control socket stay on `launchSupport`, and no demo pointer is recorded. `isDemo` is true during an in-app demo and on a demo run: `app open --demo <folder>` launches the app with `HAVOOCH_DEMO_RUN=1` beside `HAVOOCH_SUPPORT_DIR`, and there "Try the Demo" opens on its own folder and never switches. A run with `HAVOOCH_SUPPORT_DIR` alone is a normal run on that folder. | A second copy of the app closed the window and changed the Dock icon. The theme is a preference, not review data. One socket keeps `havooch` on the same app all the time. |
| L28 | Every notice fades after 5 s, a question's too. The question stays open on its thread and in `state`. | A question that stayed over the video had no way to close but a click. |
| L29 | `thread open <thread> [--frame x,y,w,h]` opens a thread's popover on its frame, as a click on its pin or badge does; `--frame` first keeps the popover at that rectangle of the stage, as a drag and a resize leave it. | The CLI cannot click, drag or resize. Without it the thread popover, its kept frame and its persistence can't be checked in the real app. |
| L30 | Only a popover on an existing thread drags and resizes. A popover that will start a thread opens at its placement and gets the handles once its first message is queued. | The frame is kept per thread (D 2.10); before the first message there is no thread to keep it on. |
| L31 | Words in the popover on a thread with an open question are an answer however they leave it: Return, a click outside, a change of the moment, Cmd+Enter. | A click outside that queued the words instead would leave the agent's question waiting while the words sit in the queue. |
| L32 | The area of a `PopoverFrame` is the stage (the video with its letterbox). A kept frame is fitted on screen: at least 280 × 190 pt, at most the stage, 8 pt inside its edges. | Normalized to the stage, the popover lands in the same place at any window size and is never lost off screen or too small to use. |
| L35 | A thread with an open question draws its pin in the `question` token with a question mark, keeping its shape, and its hover line says `Question waiting`; the answer gives the pin its state colour back. Every built-in theme keeps `question` at least 10 apart (CIE76) from each state colour and at 3:1 on the `window` surface, which a test checks. | The person sees from the timeline alone that the agent waits for an answer. |
| L36 | The whole window is on one surface, `window`: the header, the stage, the player bar, the sidebar and its footer. A one-pixel `separator` hairline is on the sidebar's leading edge and above the footer, inside the footer's height. A sidebar row under the pointer takes `controlHover`; the row of the thread on the stage sits in a `well`. There are no per-part surface tokens. | Spec 0.2.0 (#36): colour bands made the window look like parts of different apps. |
| L37 | A theme may set a token of `ThemeToken.systemSurfaces` to `system`. `Palette` makes them: `window` is `windowBackgroundColor`, `field` is `textBackgroundColor`, `separator` is `separatorColor`; a popover and a notice are the ultra-thick material under `windowBackgroundColor` at 80%. With a `system` `window` the native toolbar shows. A native popover (Context, agent control) keeps the system's background in a native theme and takes `popover` in a painted one. Default Light and Default Dark set all five to `system`; Dimmed and the VS Code themes paint all five; a test checks that no shipped theme mixes them. A person's theme may mix them. | The default themes feel like a Mac app, and the VS Code themes keep their colours. A bare material over a dark video turned a light popover grey and its quiet words unreadable, so the window colour sits on it. |
| L38 | The sidebar shows the thread list or one thread's view (`WindowModel.shown`, nil for the list), apart from the pin's `selection`. A row click, Previous and Next, Up and Down, `thread show`, a pin, a badge and a notice show a thread's view, pause the player and move it to the thread's frame; a written message leaves the list as it is. Back, Escape and `thread list` show the list. A plain video's list groups the threads as Needs you (an open question), With agent (a message sent, acknowledged or working), Queued (a queued message), Done (the rest), each in the first group it matches, in time order with General first; Previous and Next go in that time order. | Spec 0.2.0 (#36), from variant 02 of the prototype: the keyframe in the sidebar repeated the stage, and the person reads first what waits for them. |
| L39 | `thread show <thread>` shows a thread's view, as a click on its row does, and answers once the player is on the thread's frame; `thread list` shows the list. `state` names the thread the sidebar shows in `sidebar.thread`, `null` for the list. | The CLI cannot click. Without them neither view can be shown, checked or screenshotted in the real app. |
| L40 | The conversation is a chat. An agent's message (`ack` text, `reply`, `ask`) keeps the name of the listener session it was written under (`Message.sessionName`) and shows that name and its logo; one kept before the field existed shows the current listener's. A right-click on a message offers Edit and Delete on a queued message and Copy on every message; on a row, Open, Show on Video (not General) and Delete Queued Messages (only with a queued message). The question card is headed `<agent> asks`; the region tag sits on the quiet line under the bubble. A bubble's words are not selectable, so the right-click reaches the message's menu. | A later listener renamed every old reply, so the conversation lied about who wrote what. The menus offer only what applies, as macOS does. |
| L41 | One composer at the sidebar's foot (`Composer`); the stage popover's view is `CommentPopover`. Its target (`ComposerTarget`): in a thread view a follow-up on the thread, or the answer to its open question; in the list the thread of the frame on the stage ("Reply on #3"), a new thread there ("New thread at 0:12"), or General with the General toggle, and the answer when the frame's thread has an open question. A drawn region opens the comment popover and is the composer's chip too; a chip turns an answer into a message on the frame, since an answer takes no region. One draft per target thread and one for a new thread, in memory, cleared when written and when another video opens. Clicking into the field pauses the player. Cmd+Return queues the words, or answers, then sends. `comment compose [<text>] [--region] [--general]` fills it; `state` reports it as `sidebar.composer`. | Spec 0.2.0 (#36), stories 36 to 46. The spec keeps the popover on a drawn region, so the region is offered to both. The CLI cannot type or draw. |
| L42 | Native parts. The empty first screen is a `ContentUnavailableView`, its drop target the whole stage with a dashed outline only while a file is over it. Symbol buttons are native `.borderless` buttons with a `textSecondary` label, so they dim on press and take the focus ring under keyboard navigation. `MessageField` and the composer draw the field colour with a `separator` hairline at rest and the system focus ring (`FocusRing`, 3 pt outside the edge in `Palette.focusRing`) while their text view has the focus in the key window; Tab and Shift+Tab move to the next and the previous control. A `Settings` scene (⌘,) holds the theme picker, as View › Theme does (`ThemePicker`). `screenshot --window settings` opens Settings as ⌘, does, captures it, and closes it when it was closed before. | Spec 0.2.0 (#36): the app feels like a Mac app. An `NSTextView` in a scroll view draws no focus ring of its own. Settings has to be checked and shown without a click. |
| L43 | Polish against the macOS conventions. A notice is a native `.borderless` button. "No Threads Yet" is the compact native empty state: a light symbol, a headline and a callout, centred. The thread view's Previous and Next name their keys in their help (↑, ↓). The timeline's pins keep `.plain`. A `ThreadRow` is a `Button` with `RowButtonStyle`, so keyboard navigation reaches it with the system focus ring around its rounded shape; a click, the keys, the menu and VoiceOver go through `WindowModel.perform(_:on:)`. | Spec 0.2.0 (#36). The large title was heavier than the thread list's own heading in a 340 pt sidebar. |
| L44 | The control protocol version is 6. A request of another version is refused before anything else, naming both versions. The version goes up when a request already in use changes shape; a new command keeps it, since an older app refuses an unknown command in words. | A CLI and an app that disagree on a request's shape are told to reinstall, not given a wrong answer. |
| L45 | Space and Return press the control with the keyboard focus. Under keyboard navigation every focusable control in the player's window reports its focus through `pressedByKeys(in:isFocused:action:)`. `WindowModel` keeps the focused controls as a stack (`focusControl`, `blurControl`, `pressFocusedControl`): the last to take the focus is pressed, and `blurControl` removes only its own entry. `Shortcuts` gives Space, Return and Enter with no modifier to it in place of play or a new message. An AppKit control that is the first responder takes those keys itself, only while keyboard navigation is on (`Shortcuts.isControlFocused`). A queued message's Edit and Delete also show while either has the keyboard focus. With no control focused, Space plays and pauses. | The player's key monitor sees every key before SwiftUI, so a focused button never got Space; one general rule serves every control. |
| L46 | Unread threads. `ReviewThread.lastSeen` is when the person last opened the thread's view, kept in the review file; `isUnread` is whether an agent message is newer than it, or there is one and it's `null`. `WindowModel.shown`'s `didSet` marks the thread seen, so every way into the thread view clears it; an agent message on the thread the sidebar shows is read as it comes. A review file from before the field has its agent messages read. `state --json` reports `unread` per thread. | Spec 0.2.0 (#36), ticket #48. The thread view is the one place the conversation shows in full. |
| L48 | The home screen. `StageContent` decides what the stage shows: the player with a video, the home screen with none and a recent video or a project, else the empty state; the sidebar shows beside the player only. A card's click calls `WindowModel.openRecent`, which does nothing for an entry whose file is gone; the trash button and "Remove from Recents" call `removeRecent`, which leaves the review on disk. A thumbnail is the frame at the entry's position, or at 1 second when the position is 0, at most 640 × 360 pixels, made when the card first shows by `Thumbnails` on `AppModel` and kept in memory for the run. The relative time moves on each minute. Cards show no thread counts or unread dots. | Spec 0.3.0 (#65). The frame where the person stopped costs no more than the first frame. In memory only, so the support folder holds no cache to clean. |
| L49 | Going home from the player: `WindowModel.goHome()` leaves an in-app demo, or else queues the popover's words on their review, saves the position and closes the video; the queue stays on the review. Its callers: the cat mark at the header's leading edge, File › Close Video (Shift+Cmd+W) and `havooch app home`. The header's "Open a Video…" leaves an in-app demo as the Open panel does. `havooch app demo` does what "Try the Demo" does. `state` reports `screen`: `player` with a video, else `home`. | Spec 0.3.0 (#65). Cmd+W is the window's Close, so Close Video takes Shift+Cmd+W. One `screen` word for every screen with no video keeps `state` simple; `recents` tells the home screen from the empty state. |
| L50 | Filled controls (ADR 0006). `ThemeToken.accentFill` is the fill of every prominent button; `accent` stays for lines, selections, rings and pins, and is still the window's tint. Views make a prominent button only through `View.filledButton(palette)` (`.borderedProminent` tinted `accentFill`); a source test fails on `.borderedProminent` anywhere else. A theme that sets `accent` nearer than `accentFill` gets `accent.filled()`. `state` reports the active fill as `theme.accentFill`. | White text read at about 1.9:1 on Default Dark's light accent (I4). A test checks white on every shipped theme's `accentFill` for 4.5:1, so a new theme cannot break it. |
| L51 | `havooch open <path> [--project]` is a **person** request: what a person's click would do, with no lease and no agent-control icon. It refuses a path with no file before anything else, asks the running app, and when none answers launches it in front, checks `app status` every 0.05 s (10 s at most), then asks for the open once. In the app, `openInFront` checks the file plays first, leaves an in-app demo, opens, plays and comes to the front; the reply carries the app's `pid`, which the command brings to the front (`AppLaunching.bringToFront(pid:)`), with a note on standard error when that fails. `ContentHashCache` keeps each content hash by path, size and modification time for the run. `player open` stays the operator's leased open, paused. | C1: opening a file never takes control from the person. C2: 1 s warm. macOS's cooperative activation keeps an app in the background from activating itself on a socket request, so the command activates it by process. Asking over the socket once the app answers gives the command the app's own refusal and exit code. |
| L52 | Setup detection and the skill install live in their own module, `ReviewSetup`, with the file system and processes behind seams, so its tests and the app's run on fakes and never touch the person's home or run `npx`. The app does the work and the CLI asks it: `setup status` (free; reads the disk again), `setup link`, `setup install` and `setup cancel` (operator), each with `--dry-run` where it changes the machine. `setup install` starts the install and answers; `setup status` and `state --json` follow its log. With no `--harness` it installs for the harnesses found without the skill. Link replaces only a link, and a failure gives the `ln -sf` line. `HOME` and `SHELL` come from the app's environment. Detection never polls: it runs at launch, when the app becomes active, after Link or an install, and on `setup status`. | ADR 0005; G3, G4, G9, G10. Detection is pure and testable on a fake file system. One way in for the person and the agent (ADR 0001). A start-and-follow install keeps every request short, as the lease and the heartbeat expect. |
| L53 | Settings are `config.toml` (ADR 0002, D1 to D3), read by its own module, `ReviewConfig`, with TOMLDecoder, so the CLI checks it with no app. A problem rejects the file with its line; an unknown key is a warning with the nearest known key; `schema/config.schema.json` is named on the file's `#:schema` line and kept equal to the reader by a test. The folder is `<support>/config/` when `HAVOOCH_SUPPORT_DIR` moves the support folder. `ConfigDesk` applies a save that reads at once, keeps the last valid settings for one that doesn't, writes the verdict to `config-status.json`, and shows new problems as a notice at the top of every window, never a modal alert. The app writes only targeted edits (the `theme` line, a project, a version), in place, under a lock, when the result reads back with only that change. On the first launch an older build's `settings.json` theme moves into the file once, its `Themes/` folder moves beside it, and token overrides are dropped with a note; `settings.json` keeps app state only. | ADR 0002. `HAVOOCH_SUPPORT_DIR` already isolates every check and test; without the moved folder, every `AppModel` in a test would write the person's `~/.config/havooch`. A modal alert would hold the main actor and the control socket until a click. |
| L54 | Any number of windows, each holding nothing, a plain video or a project (ADR 0003, F1). `HavoochApp` has `WindowGroup(for: WindowTarget.self)` with restoration off, so a launch shows one empty window on home and opens no video; the app runs on with no window, and the Dock icon with none makes an empty one. `WindowTarget` is equal by review key, so a moved or renamed copy is the same video. Everything about "the open video" is `WindowModel`'s, one per window, with an id (`w1`, `w2`…, never used twice in a run). No two windows hold one review. An open goes to the window that holds the review, which comes forward; else the key window when it holds nothing; else a new window. Every UI action has a CLI command: operator commands take `--window <id>` and act on the key window without it (the one with the keys, else the one that had them last, else the one made last); `player open`, `app home` and `app demo` make a window when there is none. `state` reports `window` and `windows[]`. Keys, clicks outside the popover and the menus act on the window they happen in. A notice goes to the window that holds its review. `config.toml` and setup are the app's: their commands take no `--window`. | ADR 0003: two agents work on two videos side by side. The scene value is the target, so SwiftUI's windows and ours agree on what each holds; the registry decides which window an open goes to, since an open must also reach a window already on screen. One data folder for every window keeps the demo apart from the person's reviews (L27). |
| L55 | Videos open from Finder's Open With, a drop on the Dock icon and `open -a Havooch <file>` (C3). `Info.plist` declares `public.movie` with role Viewer and rank Alternate, so Havooch shows in Open With but never asks to be the default player. `AppDelegate.application(_:open:)` hands the files to `AppModel.openFromFinder`, which opens each one as `havooch open` does. At a launch by Open With the files can arrive before the first scene appears, so they wait and `sceneAppeared` opens them in the launch's empty window. A file that doesn't play is the key window's `problem`. | One open path for the person, whoever starts it. A window made before any scene exists would have no scene to show it. |
| L56 | A listener per review (ADR 0003, F2, F3). `ListenerHub` keeps one `ListenerQueue`, each with its own `Outbox`, per `ReviewKey`, made lazily and kept for the run. `wait --video <path>` resolves the path as `open` would and binds to that review, open in a window or not; `wait --project <slug>` binds to the project; a bare `wait` binds to the key window's review. `ack`, `status`, `reply` and `ask` find their review by the id's prefix, with no flag. Each window's footer, activity, agent name and Connect view read its own review's queue; `windows[]` reports each window's `listener`. A `wait` from a new holder key while the last listener was present is a takeover: the older `wait` ends with exit 1, the window shows "<new> took over from <old>", and `state` reports `listener.tookOverFrom`. The outboxes live in `outboxes/<key>.json`; an older build's one `outbox.json` is split once into them. The skill passes its target on every `wait`. | ADR 0003. A listener of a video no window holds is still heard, and a window that opens it later shows it. A takeover only from a present listener, so a restarted agent is not announced as a new one. A bare `wait` keeps an older skill working. |
| L57 | The Connect view (G1 to G11, ADR 0005), from the lab's connect-flow V6 and connect-view V2. A window's sidebar shows the threads, a thread's view, or the Connect view (`WindowModel.connect`, a `ConnectEntry` with its reason, `pill`, `header` or `send`, and the sends it waits for). Three ways in: the presence pill, the header's Connect an Agent button, and a send made while nobody listens, which keeps the send in the outbox and opens the view on it. The outbox banner counts those sends' messages, then says "Delivered N messages to <agent>". The steps are the command line, the skill and your agent, with `Readiness` of the picked harness (`ready`, `skillNotDetected`, `harnessNotDetected`, never an error) and its prompt always shown. The listener phase is `connected`, `reconnecting` (a session the last run left, not heard from in this one, for 30 s after the data opened) or `none`; there is no other waiting state. Disconnect and Forget let the session go (`Outbox.letGo`): the open `wait` is refused with "the person disconnected you from this video or project", and the taken sends go back in line. An agent's first `wait` ever is kept in `settings.json` (`agentConnectedOnce`); the connect button's dot and Finish setup show while setup isn't fully detected and no agent has ever connected (`AppModel.showsConnectDot`). `connect show`, `pick`, `disconnect` and `forget` are its commands; Copy Prompt and Copy Path have none, since the text is in `state --json`. | Spec #79, stories 66 to 86. One view for every way in, so the person always finds the next step. A window speaks only of its own agent. Disconnect refuses the agent's `wait` in words, so an agent that loops on `wait` stops. A real connection proves setup works, so the dot goes once one happens. |
| L58 | The setup tour and Finish setup (H4, H5), from first-run V3's coach panel as connect-flow V6 draws it. Each window has a `TourState` (open or not, the step, the send made in it). Finish setup sits in the header in a capsule of its own with the count of setup items left; it shows beside a video by the connect button's dot rule (L57) and while the tour shows. It opens the tour at the step it was left on. Each step shows the sidebar it is about and rings parts of the window (`TourRing`): tools rings the Connect view's command line and skill steps, connect its agent step, write the stage and the composer, send rings Send, and reply the agent step while the tour's send waits, then the send's first thread once it is finished. A ring stands 9 points outside its part, 6 in the thread list. Steps move on by themselves: both tools detected (0.8 s later), an agent's `wait` on the window's review, a message queued, a send. `tour show`, `next`, `skip` and `close` are its commands; Write an Example is `comment compose`. | Spec #79, stories 91 to 93. The tour is per window, as the sidebar it drives is. One rule for Finish setup and the dot, so the two never disagree. The 9 point ring is the maintainer's change to first-run V3. |
| L59 | Projects (ADR 0004, C4, E1 to E8). A `Review` belongs to a plain video or a project (`ReviewKey`), and its id prefix `hash8` is stored and fixed when it is made, so ids stay valid when a plain video's review becomes a project's; listener commands find their review by it. A project's review lives in `projects/<slug>/`; a video's transcript stays in `videos/<hash>/`. Each thread on a frame has an `anchor`, the absolute path of the version it was raised on; General has none. Thread lookup by frame is per version; a follow-up joins its thread wherever it is anchored. The version's number comes from `config.toml` as it is now: a path that left the list is a removed version, and its thread stays and takes words on the whole frame. `project new` and `project add` go through the app as person requests (they move reviews and open windows); `project list` reads the file with no app. When no other project lists the video, `project new` moves its review in with its ids, anchored to v1, rekeys the listener's queue with its open `wait`, and the window holding the video holds the project; when another project lists it, the new project starts fresh with an id prefix of its own. `open` and `wait --video` resolve a path through `resolveTarget`: `--project`, else the most recently opened project that lists the path, else the plain video. A send keeps the version on screen, and its payload carries the project and each thread's version. Pins, marks and the composer's thread at the frame are the version on screen's; a click on a thread of another version opens that version first. A project's version is not a recent video; the home screen shows a Projects row. | ADR 0004. Anchors by path keep the file hand-editable: a person who removes a version loses no thread. Rekeying the queue in place keeps the agent's `wait` open, so the first change request needs no reconnect. One prefix per review keeps every id unambiguous when a plain video and a project share content. |
| L60 | The first-run window (H1 to H3), from first-run V1: an AppKit window of its own (`FirstRunWindow`, 760 by 540), not a scene, so the model shows and closes it and a command reaches it with no player window. Four steps: Welcome, Tools, Connect, Try it. Tools and Connect are the Connect view's step views on the `FirstRun` model: both it and `WindowModel` are a `SetupSteering`. The prompt is the harness's demo prompt. Open the Demo opens the bundled video with `openInFront` on the person's own data, then closes the window. It shows by itself at launch while `settings.json` reads and has no `firstRunDone`, no agent ever connected and no recent video, and never on a demo run; what counts as done is L65. A send on the demo video, known by its content hash (`DemoVideo`, checked against the fixture by a test), carries `video.demo: true`, and the skill reads `references/first-demo.md` only then. `first-run show`, `next`, `back`, `pick`, `demo` and `skip`, and `screenshot --window first-run`, are its commands. | Spec #79, stories 87 to 90 and 94. The person's own agent runs the demo, so the first send teaches the real loop (H3). The tour is the way back for a person who finished or skipped it. One set of step views keeps the Connect view and the first run from saying two things. |
| L61 | A project's thread list by version (E9), from thread-list V5. A plain video's list stays by group (L38). In a project, `VersionTree` (pure) lays the list out: General first, then the last three versions as sections, newest first, then an older version on screen, then each version picked from All versions (the latest pick first), then "Removed version" while a thread's version left the list (E6: nothing hides). The window keeps the picks (`pickedVersions`) and the menu's search (`versionMenu`) until its project changes. `thread versions [--search] [--close]` and `thread version <n> [--remove]` are its commands; `state` reports `sidebar.versions`. All versions uses `clock.arrow.circlepath`, not the lab's stacked symbol. | Spec #79, stories 49 to 56. The last three versions keep a long project short; the menu and the footer reach every older thread, so an open one never hides. The layout is a pure value, so the model, `state` and the view read one answer. |
| L62 | The version switcher (E10), from version-switcher V5. In a project the header's first line is the project's title with the switcher, and the line under it the version on screen, then the folder (`HeaderWords.Project`). The switcher shows the last three versions as segments; a project of more adds the `All N` field and its picker. The words and numbers are `VersionSwitch` and `VersionPicker`, pure, and the picker's state is the window's, so the CLI drives it. `switchVersion(to:)` keeps the playhead's time and plays on when it played. A switch keeps the sidebar's view, the composer's drafts, the General toggle, the Connect view and the notices; only the popover, the drawn region, the context popover and the picker go. `version show <n>`, `version pick [<query>]` and `version close` are its commands; `version pick` is refused on three versions or fewer. The lab's raw colours are theme tokens. | E10. Threads are the project's (E6), so the sidebar and the drafts stay on a switch. The picker's state in the model makes it reachable without a click (ADR 0001). Views take colours only from the palette. |
| L63 | Compare two versions (E11), from compare-control V4. The rules are `CompareSession` (pure): it opens on the previous version on the left and the one on screen on the right (v1 on screen: v1 and v2; a removed version on screen: the last two); picking the version on the other side swaps the sides, so a version is never compared with itself. Start loads the other side on a player of its own at the playhead's time and makes a `PlayerPair`: both start with `setRate(_:time:atHostTime:)` on one host time 0.1 s ahead, with `automaticallyWaitsToMinimizeStalling` off; pause pauses both and puts the other side on the lead's time; a seek and the speed are both sides'; on each periodic tick of the lead (the active side) the other side is put back in step when it drifted more than 0.04 s, at most every 0.5 s. Only the lead is heard. While comparing, `engine` and `video` are the active side's, so the player bar, the marks, the popover, the composer and `state` follow it. A click or a drag on the other side, a thread of its version, `version show` of its version and `compare set --side` make it active; the first click only picks the side, and a drag draws on it at once. Words in the popover are queued first on the version they were written on (`Showing`). The composer writes to the active side, the right one until the person picks the left; Flip's side showing is the active side. Exit Compare, Escape and `compare exit` make the right side active and retire the left side's player. Another version, a thread of a third version, another video and going home end the comparison first. `compare open`, `pick`, `set`, `swap`, `start` and `exit` are its commands; `state` reports `project.compare`. | Spec #79, stories 57 to 65. Keeping the active side's player as the window's `engine` lets every existing action act on the active side unchanged, and a side switch costs no reload. The composer has no side of its own, so it writes where a popover would. Flip's bar says "press to flip": a held key that flips back on release is not built. |
| L64 | The skill install command shows in a `RunBox`, from connect-view V3: the command on top, a footer bar with "Login shell", a copy icon and Run Command, which starts the install `setup install` starts. While it runs the box keeps its place, its command dims, and its footer holds a progress indicator, the last log line and Cancel. A step 3 box runs only while the running install includes its harness. Node missing keeps its `CopyBox` and Check Again, and a harness that isn't detected keeps its command in a `CopyBox`. | The person sees what runs in their login shell before it runs, and has the line to run alone if it fails. |
| L65 | The first run is done when the person uses the app, not when the first-run window shows (ticket #134; it changes decision H1's "only once"). `AppModel.markFirstRunDone()` runs on Get Started or any later step (`FirstRun.next()`, `FirstRun.go(to:)` past Welcome, `first-run next` and `first-run pick`), on Skip Setup (`FirstRun.skip()`, the button and `first-run skip`), on a video opened in any window (`WindowModel` after it records the open), and on an agent's `wait` opening (`AppModel.agentConnected`). `FirstRun.used` is the seam: the app sets it to `markFirstRunDone`. `showFirstRun`, the close button (`closedByPerson`) and a quit mark nothing, so the next launch shows the window again. The other conditions of `showFirstRunOnFirstLaunch` stay: never on demo data, only when `settings.json` reads, and not for a person with a recent video or a connected agent. `state` reports `firstRun.done` by the same rule. | The maintainer closed the window on the first launch of 0.4.1 and never saw it again. A person who closed the app without using it is still a new person. |
| L66 | The first-run window opens centered over the player window (ticket #133). The first time it shows in a run, `FirstRunWindow.place` lays out the hosting view and sets the window to its fitting size (760 by 572 points: the 540 of the view and the title bar's safe area), then sets its frame with `FirstRunWindow.frame(of:over:on:)`: centered over the key player window, else the first visible one, else the main screen, and moved in to stay inside that screen's visible frame. A later show in the same run keeps where the person moved it. | `center()` measured the size the window was made with, before the hosting view resized it, and centered on the screen, not over the empty window the person looks at. |
