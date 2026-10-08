# Projects, windows and agent onboarding: target low-level design

Written 2026-10-08, before the first build ticket of `effort:projects-and-onboarding`, from `Spec: Projects, windows and agent onboarding` (#79), the decisions in `docs/prototypes/2026-10-08-decisions.md` (cited as A1 to I6), ADRs 0002 to 0006 and `GLOSSARY.md`. The UI comes from the final prototypes listed in `docs/prototypes/2026-10-08-lab/README.md`: copy their code and build on it.

This is the **target**: the design the effort builds toward. `docs/low-level-design.md` stays the design of the code as it is (0.2.0 and later, cited there as L1 to L49). Each ticket moves code from that design to this one. When a ticket lands, update `docs/low-level-design.md` for what it built; when the effort ends, this file folds into it. When the build departs from this file, change this file in the same change.

The decisions this design takes on its own, which the spec left open, are numbered **P1, P2…** under [Decisions](#6-decisions-this-design-takes).

## For a newcomer, in one screen

The package keeps its eight modules and gains two:

```diff
 agent side (no app rules, no UI)
   ReviewLease       Holder: + CODEX_THREAD_ID, PI_SESSION_ID
   ReviewWire        + the window and project requests; protocol version + 1
   ReviewCommand     + open, window, project, version, compare, connect, setup, tour, config
   ReviewCLI
+  ReviewConfig      config.toml: read, verdict, schema, targeted writes; [[projects]]
+  ReviewSetup       what Havooch can detect: the command link, the skill per harness,
+                    the harnesses; the skill install; the prompt per harness

 app side
   ReviewCore        VideoReview → Review (a plain video's or a project's); threads anchored
                     to a version; the payload's project block; ThemeToken.accentFill
   ReviewTranscript
   ReviewStore       + projects/<slug>/; outboxes per review; app state moves out of settings.json
   ReviewApp         one AppModel, many WindowModels; ListenerHub; SetupDesk; Connect view,
                     first run, tour, version switcher, version-tree list, compare
```

How a request finds its window:

```text
person ──▶ a window's UI ─────────────────────────────▶ WindowModel ──▶ PlayerEngine (one, or a pair when comparing)
                                                            │
operator ──▶ havooch ──▶ ControlServer ── --window or the ──┤        └──▶ ReviewDesk ──▶ Review ──▶ Library
                         (lease)          key window        │
person/agent ──▶ havooch open | project ──▶ ControlServer ──▶ AppModel ──▶ WindowRegistry ──▶ the window that holds the target
                 (no lease)                                       └──▶ ConfigDesk ──▶ ReviewConfig (config.toml)
listener ──▶ havooch wait --video|--project ──▶ ControlServer ──▶ ListenerHub ──▶ the ListenerQueue of that review
```

| You want to | Open |
|---|---|
| see what a window holds and how one opens | `ReviewApp/Windows/` (`WindowRegistry`, `WindowModel`, `WindowTarget`) |
| change how `havooch open` finds or makes a window | `AppModel.open(_:)`, `WindowRegistry` |
| change a `config.toml` key | `ReviewConfig/` and `schema/config.schema.json` |
| change a project rule (versions, thread anchors, moving a video's threads) | `ReviewCore/Review.swift`, `ReviewCore/VersionAnchor.swift` |
| change what Havooch says it detected | `ReviewSetup/SetupProbe.swift`, `HarnessCatalog.swift` |
| change the prompt for a harness | `ReviewSetup/HarnessCatalog.swift` |
| change the Connect view | `ReviewApp/UI/Connect/` |
| change which listener a send goes to | `ReviewApp/ListenerHub.swift` |
| follow `havooch open` from the shell to a window | [Trace 1](#trace-1-havooch-open-from-the-shell-to-a-window) |
| follow a project from its first change to v2 | [Trace 2](#trace-2-a-plain-video-becomes-a-project-and-gets-v2) |
| follow a send with no listener | [Trace 3](#trace-3-send-with-no-listener-then-an-agent-connects) |

## 1. Requirements

The 99 user stories of #79 are the requirements. They group like this (story numbers in brackets, decisions in braces).

### Capabilities

1. **Open in one step**: `havooch open`, Open With, a Dock drop and `open -a`; no lease; the window comes forward; 1 s warm, 2 s cold. (1 to 9) {C1 to C4}
2. **Windows**: any number; a new one is empty and shows the home screen; one target per window; an open target brings its window forward. (10 to 14) {F1}
3. **Listener per window**: `wait --video|--project`; takeover notice; Codex and Pi sessions. (15 to 21) {F2, F3, G12}
4. **Settings file**: `config.toml` with schema, verdict, check, live reload, last valid kept, targeted writes; theme by name; app state out of it. (22 to 30) {D1 to D3}
5. **Projects**: lazy, made by the agent; `project new|add|list`; threads move in; threads anchored by version path and tagged; never hidden; payload carries versions; most recent project wins, `--project` chooses. (31 to 48) {E1 to E8}
6. **Version switcher and version-tree list**. (49 to 56) {E9, E10}
7. **Compare**: popover with mini window, pickers per side, swap, three layouts, one playhead. (57 to 65) {E11}
8. **Connect view**: three entry points; setup steps; honest detection; prompt per harness; outbox banner; listener card; reconnecting. (66 to 86) {G1 to G11}
9. **First run, tour, demo reference**. (87 to 94) {H1 to H5}
10. **Look**: `accentFill`; copy and border rules. (95 to 97) {I1 to I6}
11. **Agent control**: every new UI action has a CLI command and shows in `state --json`. (ADR 0001)

### Rules and completion

- A window holds at most one **target**: a plain video (by content hash) or a project (by slug). No two windows hold the same target.
- A **review** belongs to one target. A plain video's review is keyed by content hash; a project's by slug. A review's id prefix (`hash8`) is fixed when it is made and never changes, so ids stay valid when a plain video's review becomes a project's (P3).
- A project's versions are its `versions` list in `config.toml`, in order. Version number = position + 1. A thread's version is found by its anchor path; a path no longer listed shows as "removed version" and the thread stays.
- One **listener session** per review. A new holder key on that review's `wait` replaces the old one (today's rule, now per review).
- **Detection** has three answers: detected, not detected, cannot know. Only detected shows ✓ (ADR 0005).
- "Finish setup" shows while setup is not fully detected **and** no agent has connected yet (P11).

### Error handling

- `open` of a file AVPlayer cannot play: refused; nothing opens.
- `project add` on an unknown slug, or of a path that does not exist: refused with the reason. `project new` with a slug in use: refused.
- `wait --project` on an unknown slug: refused. `wait --video` on a file that does not exist: refused.
- An operator command with no `--window` and no key window: refused, listing the windows.
- A `config.toml` that does not read: the last valid configuration stays; the verdict holds each problem with its line; nothing writes the file over.
- A skill install that fails: the log shows the failure; nothing else changes. No `npx`: the view says Node is needed.

### Scope

In: the above. Out (#79): Havooch Studio, a Raycast extension, the CLI following the running app's data folder, harness wake plugins, starting agent sessions from Havooch, branching versions, the mental-model document.

## 2. Entities and relationships

New and changed entities:

| Entity | Owns | Lives in |
|---|---|---|
| `AppModel` (orchestrator, app-wide) | the windows, the data folder, the config, the theme, setup, the first run; routes `open` and `project` to a window | ReviewApp |
| `WindowRegistry` | which window holds which target; making, finding and closing windows | ReviewApp |
| `WindowModel` (per window) | the target, the player (or pair), the popover and draft, the sidebar mode (threads, a thread, connect), notices, compare, the tour | ReviewApp |
| `Review` (was `VideoReview`) | one target's threads, messages and sends, every rule about them, and version anchors | ReviewCore |
| `ReviewDesk` | the one path for changing any review: change, save, publish; moving a video's review into a project | ReviewApp |
| `ListenerHub` | one `ListenerQueue` per review; which review a `wait` binds to | ReviewApp |
| `ListenerQueue` + `Outbox` | as today, now one per review | ReviewApp, ReviewCore |
| `ConfigFile` | the parsed `config.toml`, its verdict, the last valid copy | ReviewConfig |
| `ConfigDesk` | watching the file, applying a valid save, writing the verdict, the targeted writes | ReviewApp |
| `SetupProbe` | what is on disk: the command link, each harness's skills folder, each harness's presence | ReviewSetup |
| `SkillInstall` | one running `npx skills add`, its log lines, Cancel | ReviewSetup |
| `SetupDesk` | the latest probe, the running install, the link action, re-probe on window focus | ReviewApp |
| `CompareSession` | the two versions, the layout, the slider position | ReviewApp (per window) |
| `PlayerPair` | two `PlayerEngine`s on one clock | ReviewApp |
| `TourState` | the step, dismissed or not | ReviewApp (per window) |

Fields, not entities: `WindowTarget`, `VersionAnchor`, `Version`, `ProjectEntry`, `HarnessSetup`, `Detection`, `CompareLayout`, `SetupStep`, `AppState`.

```text
AppModel ──owns──▶ WindowRegistry ──holds──▶ WindowModel* ──holds──▶ WindowTarget (video hash | project slug)
AppModel ──owns──▶ DataFolder ──holds──▶ ReviewDesk ──holds──▶ Review* ──contains──▶ ReviewThread ──anchored by──▶ VersionAnchor (path)
                              ├──holds──▶ ListenerHub ──holds──▶ ListenerQueue* (one per review) ──holds──▶ Outbox
                              └──holds──▶ TranscriptDesk
AppModel ──owns──▶ ConfigDesk ──reads/writes──▶ ConfigFile (ReviewConfig) ──lists──▶ ProjectEntry* ──lists──▶ Version*
AppModel ──owns──▶ ThemeDesk ──reads theme name from──▶ ConfigDesk
AppModel ──owns──▶ SetupDesk ──uses──▶ SetupProbe, SkillInstall, HarnessCatalog (ReviewSetup)
WindowModel ──reads──▶ ReviewDesk (its review), ListenerHub (its queue), ConfigDesk (its project), SetupDesk
WindowModel ──owns──▶ PlayerEngine | PlayerPair (while comparing), CompareSession?, TourState
ControlServer ──calls──▶ AppModel (open, project, window, config, setup), a WindowModel (operator commands), ListenerHub (listener)
```

Where each rule lives:

- "Which window holds this target? Is it open already?" → `WindowRegistry`.
- "Which review does this video open into?" → `AppModel.resolveTarget`: the most recently used project that lists the path, else the plain video (C4).
- "Which version is this thread on?" → `Review` with the window's `ProjectEntry` (anchor path → number, or removed).
- "Which listener gets this send?" → `ListenerHub`, by the send's review.
- "Is this detected?" → `SetupProbe`. "What prompt does this harness take?" → `HarnessCatalog`.
- "Is this config valid?" → `ConfigFile.read`.
- "Show Finish setup?" → `SetupDesk.needsTour` (P11).

Module dependencies stay one way:

```text
ReviewConfig  ← Foundation, TOMLDecoder (first package dependency, as Swift Lab ADR 0016)
ReviewSetup   ← Foundation, ReviewCore (KnownAgent)
ReviewCommand ← ReviewWire, ReviewLease, ReviewConfig (config check, project list run without the app)
ReviewApp     ← everything
```

## 3. Class design

### Folder tree

What changes, in short:

```diff
 Package.swift                          + ReviewConfig, ReviewSetup; + TOMLDecoder
+schema/config.schema.json              the JSON Schema config.toml names on its #:schema line
 Packaging/Info.plist                   + CFBundleDocumentTypes: public.movie, Viewer, Alternate (C3)
 Packaging/Themes/*.json                + accentFill in every bundled theme (ADR 0006)
 .agents/skills/havooch-mate/SKILL.md   + wait --video|--project; projects; prompt forms; detection honesty
+.agents/skills/havooch-mate/references/first-demo.md   the beginner demo, read only for the bundled sample (H3)
 Sources/
+  ReviewConfig/
+    ConfigLocation.swift               <support>/config with HAVOOCH_SUPPORT_DIR, else $XDG_CONFIG_HOME/havooch or ~/.config/havooch; config.toml, themes/
+    ConfigFile.swift                   the decoded file: version, theme, [[projects]]; read → (config | problems with lines)
+    ProjectEntry.swift                 slug, title, versions [{path, label}]; versionNumber(of path)
+    ConfigWriter.swift                 targeted writes: header for a missing file, the theme line, append [[projects]], append a version
+    ConfigVerdict.swift                {accepted, checked, configModified, problems, warnings} as config-status.json
+  ReviewSetup/
+    HarnessCatalog.swift               per harness: skills folders, presence hints, the -a name, the prompt form
+    SetupProbe.swift                   Detection per step and per harness; the FileSystem seam
+    SkillInstall.swift                 npx skills add …: the command, log lines, cancel; the ProcessRunner seam
+    CommandLink.swift                  the link in ~/.local/bin: state, make, the ln -sf fallback line
   ReviewLease/Holder.swift             + CODEX_THREAD_ID, PI_SESSION_ID; harness markers name others (G12)
   ReviewWire/ControlRequest.swift      + open, window*, project*, version, compare*, connect, setup*, tour*, firstRun*;
                                          wait(target:); operator requests carry window: String?
   ReviewWire/Version.swift             protocol version + 1
   ReviewCommand/
+    OpenCommand.swift                  open <path> [--project] [--new-window]; launches the app with the file when it isn't running
+    WindowCommands.swift               window list | new | close
+    ProjectCommands.swift              project new | add | list
+    CompareCommands.swift              version show <n>; compare open | set | swap | exit
+    SetupCommands.swift                connect show; setup status | link | install; tour show | next | skip; first-run show | skip
+    ConfigCommands.swift               config path | check (no app needed)
     ListenerCommands.swift             wait [--video <path> | --project <slug>]
   ReviewCore/
-    VideoReview.swift
+    Review.swift                       one target's review (renamed, P2); key: .video(hash) | .project(slug); hash8 fixed at birth
+    VersionAnchor.swift                a thread's version: the path; resolved against a ProjectEntry to number | removed
     ReviewThread.swift                 + anchor: VersionAnchor?
     SendPayload.swift                  + project {slug, title, onScreen, versions[]}; thread.version; video.demo (H3)
     Theme/ThemeToken.swift             + accentFill
   ReviewStore/
     SupportLayout.swift                + projects/<slug>/{review.json,frames,crops}; outboxes/<review key>.json;
                                          appstate.json (recents, last listener per review, first run done, agent connected once)
     Settings.swift                     shrinks to the sidebar width; theme moves to config (one-time migration, P7)
   ReviewApp/
     HavoochApp.swift                   WindowGroup(for: WindowTarget) in place of the one Window; first-run window; Open With
     AppModel.swift                     app-wide: open, resolveTarget, project new/add, config, theme, setup, first run
+    Windows/
+      WindowTarget.swift               .video(hash, path) | .project(slug); Codable, Hashable (the scene value)
+      WindowRegistry.swift             target → window; focus, make, close; the key window
+      WindowModel.swift                per window: everything AppModel held for "the open video" today
     ReviewDesk.swift                   many reviews; adopt(videoReview, into: slug)
+    ListenerHub.swift                  review key → ListenerQueue; bind wait; route ack/status/reply/ask by id prefix
     ListenerQueue.swift                one review's waits and asks (unchanged inside)
+    ConfigDesk.swift                   watch, apply, verdict, writes
+    SetupDesk.swift                    probe, link, install, needsTour
     Player/
+      PlayerPair.swift                 two PlayerEngines on one clock: play, pause, seek, rate together
     Control/StateReport.swift          + windows[], each with target, sidebar, compare, tour; setup; config verdict
     UI/
       RootView.swift                   per window; empty window → HomeScreen
       Home/HomeScreen.swift            + projects row (latest version thumbnail, vN)
       Header/FloatingControls.swift    + Connect button (dot), Finish setup button, Compare button
+      Header/VersionSwitcher.swift     last three segments + picker (E10, version-switcher V5)
+      Compare/CompareControl.swift     popover, mini window, side pickers, swap, layouts (E11, compare-control V4)
+      Compare/CompareStage.swift       side by side, flip, slider over the PlayerPair
       Sidebar/ThreadList.swift         + version sections and All versions menu for a project (E9, thread-list V5)
+      Connect/ConnectView.swift        the step timeline (G2, connect-flow V6, connect-view V2)
+      Connect/SetupSteps.swift         command line and skill steps
+      Connect/HarnessPicker.swift      the logos, the readiness line, the prompt box
+      Connect/ListenerCard.swift       connected and reconnecting
+      Connect/OutboxBanner.swift       "N messages wait for an agent…"
+      Connect/CopyBox.swift            text on top, Copy in a footer bar (I5)
+      Tour/TourPanel.swift             coach panel and rings with padding (H4)
+      FirstRun/FirstRunWindow.swift    Welcome, Tools, Connect, Try it (H1)
```

### ReviewConfig

- `ConfigFile.read(data) -> Result<ConfigFile, [Problem]>`. A problem has a line and a message. Unknown keys are warnings, not problems (Swift Lab's rule).
- `ConfigWriter` never rewrites the whole file: it inserts text at a position, so comments survive. Operations: `header()` for a missing file; `settingTheme(name)` (the one `theme` line, built in #84); `appendProject(slug, title, firstVersion)`; `appendVersion(slug, path, label)` (rewrites only that project's `versions` array).
- `ProjectEntry.versionNumber(of path) -> Int?` (position + 1). `projects(listing path) -> [ProjectEntry]`.

### ReviewSetup

- `Detection`: `.detected`, `.notDetected`, `.cannotKnow`. There is no "missing".
- `HarnessCatalog` entries (from the harness research in this session; sources in ADR 0005):

| Harness | Skills folders checked (user level) | `-a` name | Prompt form |
|---|---|---|---|
| Claude Code (CLI, Desktop) | `~/.claude/skills` | `claude-code` | `/havooch-mate listen for my feedback on <target>` |
| Codex (CLI, Desktop) | `~/.agents/skills`, `~/.codex/skills` | `codex` | `$havooch-mate listen for my feedback on <target>` |
| Cursor (CLI, Desktop) | `~/.agents/skills`, `~/.cursor/skills` | `cursor` | `/havooch-mate …` (unverified) |
| Pi | `~/.pi/agent/skills`, `~/.agents/skills` | `pi` | `/skill:havooch-mate …` |
| OpenCode | `~/.config/opencode/skills`, `~/.claude/skills`, `~/.agents/skills` | `opencode` | `Use the havooch-mate skill to listen for my feedback on <target>` |

- `<target>` is the window's video file name, or `project <slug>`.
- `SetupProbe.probe(fs) -> SetupReport`: command link (detected when the link file exists and points into a Havooch bundle), skill per harness (detected when `havooch-mate/SKILL.md` exists in one of its folders, else not detected), harness presence (detected from known app and binary locations, else not detected). Repo installs are never looked for.
- `SkillInstall.start(harnesses)` runs `npx skills add yahyabedirhan/havooch --skill havooch-mate -g -y -a …` through the login shell, streams lines, supports cancel, and ends with exit status. Missing `npx` ends as `.noNode` before running.

### ReviewCore: the review and anchors

- `Review` keeps today's rules. New: `key`, `hash8` (stored, not derived), and on each thread an optional `anchor`. A plain video's threads have no anchor. `adoptedIntoProject(slug, versionPath)` returns the same review with key `.project(slug)` and every unanchored thread anchored to `versionPath`.
- A new message on a project review anchors its new thread to the version on screen. A follow-up joins its thread wherever that thread is anchored.
- Thread lookup by frame time is per version: two versions may each have a thread at 0:12.

### ReviewApp: windows

- `WindowGroup(for: WindowTarget.self)` gives one scene per value; its binding is nil for the empty window. `WindowRegistry` keeps target → `WindowModel` and opens or focuses through SwiftUI's `openWindow(value:)`.
- `AppModel.open(url, project:)`: resolve the target (C4), then `WindowRegistry.show(target)`: focus the window that holds it, else reuse the key window if it is empty, else make a new one. Then `NSApp.activate`.
- Operator commands take `--window <id>` (from `window list`); without it they act on the key window.

### ReviewApp: listeners

- `ListenerHub.queue(for review key)` makes queues lazily and keeps them for the run.
- `wait --video <path>` resolves the path as `open` would (C4) and binds to that review; `wait --project <slug>` binds to the project. `wait` with neither binds to the key window's review (P5).
- `ack`, `status`, `reply`, `ask` find their review by the id's `hash8` (P3), so they need no flag.
- Outboxes persist per review key. The 0.3.0 `outbox.json` migrates once into the review of its sends.

### ReviewApp: setup and the Connect view

- `SetupDesk` probes on launch, when any window becomes key, and after Link or Install ends. It never polls.
- Sidebar mode per window: `.threads | .thread(id) | .connect(reason)`, `reason` is `.pill`, `.send(waiting: n)` or `.header`. Send with no listener queues the send in the outbox and sets `.connect(.send(n))` (G8).
- Connected state: from that window's `ListenerQueue` presence. Reconnecting: the last listener of the review from app state, for 30 s after launch (G6).

## 4. Implementation

### The methods that carry the logic

```text
AppModel.open(url, project?)                       (ReviewApp/AppModel.swift)
  hash = ContentHash(url)                          (cached by path + mtime, P6)
  target = project.map(.project) ?? resolveTarget(url, hash)
      resolveTarget: projects listing url.path in config, most recently used first → .project(slug)
                     else → .video(hash, url.path)
  window = WindowRegistry.show(target)             focus | reuse empty key window | new
  window.load(target)                              review from ReviewDesk; player opens url (or the project's version on screen)
  NSApp.activate()
  reject: unplayable file → refused, nothing opened

AppModel.projectNew(slug, from url, title?)
  reject slug in config
  ConfigWriter.appendProject(slug, title, url.path) → ConfigDesk applies the new file
  ReviewDesk.adopt(.video(hash) → .project(slug), anchor url.path)   moves review folder, keeps hash8
  ListenerHub.rekey(.video(hash) → .project(slug))                   the listener keeps listening
  WindowModel.moveIntoProject(slug)                                  the window holding the video now holds the project
  (another project lists the video already → the new project starts fresh, nothing moves; E4)

AppModel.projectAdd(slug, url, label?)
  reject unknown slug, missing file
  ConfigWriter.appendVersion(slug, url.path, label)
  window = WindowRegistry.show(.project(slug)); window.showVersion(last); NSApp.activate()

WindowModel.send()
  if no queued messages → nothing
  send = review.makeSend(...)                      (today's rules)
  hub.queue(review.key).enqueue(send)
  if !hub.queue(review.key).isPresent → sidebar = .connect(.send(waiting: outbox.pendingCount))

SetupProbe.probe(fs)                               (ReviewSetup)
  link  = fs.isSymlink(~/.local/bin/havooch) && target in a Havooch bundle ? .detected : .notDetected
  skill = per harness: any folder has havooch-mate/SKILL.md ? .detected : .notDetected
  harness presence = any hint path exists ? .detected : .notDetected
```

### Trace 1: `havooch open` from the shell to a window

```text
$ havooch open ~/Movies/cut2.mp4
OpenCommand.run                                    (ReviewCommand/OpenCommand.swift)
  app running? ── no ──▶ AppLauncher.open(file: cut2.mp4)   Launch Services open-document event → cold path
              └─ yes ─▶ ControlClient.send(.open(path, project: nil))   no lease
ControlServer.dispatch(.open)                      (ReviewApp/Control/ControlServer.swift)
  AppModel.open(url)
    resolveTarget → .project("launch-video")       cut2.mp4 is v2 of launch-video in config.toml
    WindowRegistry.show(.project("launch-video"))  no window holds it; key window is empty → reuse it
    window.load → ReviewDesk.review(.project("launch-video")); player opens cut2.mp4 (v2)
    NSApp.activate
  reply ok: "opened cut2.mp4 in project launch-video (v2) in window w2"
state after: windows = [w1: .video(abc…), w2: .project(launch-video) v2]
rejection: `havooch open notes.txt` → "can't play notes.txt" exit 1, windows unchanged
```

### Trace 2: a plain video becomes a project and gets v2

```text
person writes 2 messages on cut1.mp4 (plain video, window w1), ⌘↩
listener (Claude Code, wait --video cut1.mp4) gets the send; message asks to tighten the intro
skill: first change request → havooch project new launch-video --from cut1.mp4
  AppModel.projectNew
    config.toml += [[projects]] slug launch-video, versions = [{ path = ".../cut1.mp4" }]
    ReviewDesk.adopt: videos/<hash>/ → projects/launch-video/ (the transcript stays); threads anchored to cut1.mp4 (v1); hash8 kept
    ListenerHub.rekey: the listener's queue is now launch-video's; its open wait stays open
    w1 retargeted → header shows "v1"
agent renders cut2.mp4 → havooch project add launch-video cut2.mp4 --label "tighter intro"
  config.toml versions += { path = ".../cut2.mp4", label = "tighter intro" }
  w1 shows v2, comes forward; thread list: v2 (empty), v1 (2 threads, still open)
agent: reply t-<hash8>-1 "Done in v2 at 0:02" (finds the review by hash8)
state after: one review, threads tagged v1, the switcher shows v1 v2
rejection: project add launch-videoo … → "no project launch-videoo; projects: launch-video" exit 1
```

### Trace 3: Send with no listener, then an agent connects

```text
w1 holds onboarding-cut-v3.mp4, 3 queued, no listener
⌘↩ → WindowModel.send: outbox(.video(h)) pending = 1 send (3 messages); not present
     sidebar = .connect(.send(waiting: 3)) → OutboxBanner "3 messages wait for an agent. They'll be delivered when one connects."
SetupDesk report: link .detected, skill: claude .detected, codex .notDetected
person picks Claude Code → readiness "Ready. The skill is installed for Claude Code."; prompt
  "/havooch-mate listen for my feedback on onboarding-cut-v3.mp4" → Copy
agent runs havooch wait --video …/onboarding-cut-v3.mp4 → ListenerHub binds → delivers the pending send
w1: banner → "Delivered 3 messages to Claude Code"; ListenerCard; Finish setup hidden (agent connected once, P11)
rejection: Codex picked → "Havooch couldn't detect the skill for Codex. If it's installed another way,
  paste the prompt and your agent will take it from there. If not, install it first:" + Install for Codex; prompt stays
```

### Build and tests

- **Seam 1**: `scripts/acceptance.sh` gains steps for `open`, windows, projects, versions, compare, the Connect view and per-window listeners, read through `state --json`.
- **Seam 2**: ReviewAppTests: `WindowRegistry`, `AppModel.open` resolution, `projectNew` adoption, `ListenerHub` binding and rekey, the outbox banner, sidebar modes, tour visibility.
- **Seam 3**: ReviewConfigTests (read, problems with lines, writer keeps comments), ReviewSetupTests (probe on a fake file system, prompt per harness, install with a fake runner), ReviewCoreTests (anchors, adoption, per-version thread lookup, payload project block), ReviewLeaseTests (Codex, Pi), a theme test for `accentFill` contrast in every bundled theme.

## 5. Extensibility

| Change | What you touch |
|---|---|
| A new harness | one `HarnessCatalog` entry, its logo (`KnownAgent`), a live QA ticket |
| A harness's skill invocation changes | its `HarnessCatalog` prompt form |
| A new `config.toml` key | `ConfigFile`, the schema, the skill's key table |
| A new compare layout | `CompareLayout` case, `CompareStage` drawing, the popover's segment |
| Rename a project | a `project rename` command: `ConfigWriter`, `ReviewDesk` move, `ListenerHub.rekey` (not built now) |
| Branching versions (Studio) | out of the player; `ProjectEntry` stays a line |
| A new setup step | `SetupProbe` step, one `SetupSteps` row, the tour's step list |

## 6. Decisions this design takes

| # | Decision |
|---|---|
| P1 | Two new agent-side modules: `ReviewConfig` (the CLI needs `config check` and `project list` without the app) and `ReviewSetup` (detection is pure and testable on a fake file system). |
| P2 | `VideoReview` becomes `Review`, since a review now belongs to a plain video or a project (glossary). It is a mechanical rename inside one module plus its callers, done first in the projects ticket. |
| P3 | A review's `hash8` is stored and fixed at birth, so thread, message and send ids stay valid when a plain video's review becomes a project's; listener commands find their review by it. |
| P4 | `project new` and `project add` go through the app (they move reviews and open windows) and take no lease, like `open`. `project list` and `config check` read the file directly. |
| P5 | `wait` without `--video` or `--project` binds to the key window's review, so the current skill keeps working; the updated skill always passes a flag. |
| P6 | The content hash of a path is cached by path and modification time, so `open` stays inside 1 s warm. |
| P7 | `settings.json`'s `theme` moves into `config.toml` once, on the first launch of this build; `overrides` are dropped with a one-line notice; `sidebarWidth` stays app state. |
| P8 | Compare plays two `AVPlayer`s started together with `setRate(_:time:atHostTime:)` on one host time, with drift corrected on each periodic tick. |
| P9 | While comparing, a new message goes to the version on the side the person draws or clicks on; the composer writes to the right side. Flip writes to the version showing. Exit Compare returns to the right side's version. |
| P10 | Detection never polls: probe on launch, on window focus, and after Link or Install. |
| P11 | "Finish setup" and the connect button's dot show while setup is not fully detected and no agent has ever connected (app state, kept across launches). |
| P12 | The send payload marks `video.demo: true` when the content hash is the bundled sample's; the skill reads its demo reference only then. |
| P13 | Every new UI action has a CLI command (ADR 0001); operator commands take `--window`, and `state --json` lists `windows[]`. |
