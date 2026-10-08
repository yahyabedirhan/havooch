# Decisions: projects, windows and agent onboarding

Every decision from the grilling and prototype session of 7 and 8 October 2026, which started from `Mate: Make opening a video and connecting any agent simple for new users` (#76). The maintainer's own words are in [2026-10-08-feedback-verbatim.md](2026-10-08-feedback-verbatim.md). The lasting ones are also ADRs 0002 to 0006, and `Spec: Projects, windows and agent onboarding` (#79) holds them in structured form. A later build that departs from one of these updates this file.

The winning prototype code is in [2026-10-08-lab/](2026-10-08-lab/), copied from Swift Lab (`yahyabedirhan/swift-lab` at `ccb82cb`, project `havooch`, sessions `project-versions` and `agent-onboarding`). Screenshots are in `assets/screenshots/projects-and-onboarding/`.

## A. Direction

| # | Decision |
|---|---|
| A1 | Havooch is an interface for the agent the person already uses, in the harness they already use, with their own repos and skills. It is never an agent itself, and no third-party agent sits between the person and their agent. |
| A2 | Havooch stays a **player**: it does not care how a video was made. Making videos (components, variants, composition) belongs to a separate later project, Havooch Studio, which uses Havooch as its review surface. |
| A3 | The human-agent interaction pattern is written down as a mental model, not extracted as a shared library. Havooch and Swift Lab each build on it on their own, and the domains may diverge. |
| A4 | Connecting must be too obvious to need explaining: the person's existing agent starts listening in one step. |

## B. Work and delivery

| # | Decision |
|---|---|
| B1 | One effort holds all of this work: projects, versions, compare, windows, the configuration file and agent onboarding. Its spec describes the final state; its tickets form a dependency graph (a DAG) ordered for the most parallel work, so an orchestrator can delegate them. |
| B2 | Efforts are defined by meaning, not one per release. A release comes after one or more efforts land. |
| B3 | Every decision is written in the repository (this file, the ADRs, the glossary, the spec, the low-level design). Nothing stays only in a session. |
| B4 | Each tier-1 harness gets a live QA ticket for the maintainer. In live QA the agent prepares the app and the maintainer looks and plays. |
| B5 | The effort takes over the Open With and Dock checks of `QA: Check the 0.3.0 window and home screen by hand` (#73). |
| B6 | Out of the effort, as their own issues: a Raycast extension to open a video in Havooch; the CLI following the data folder of the running app (the `HAVOOCH_SUPPORT_DIR` case); Havooch Studio; the mental-model document. |

## C. Opening a video

| # | Decision |
|---|---|
| C1 | `havooch open <path>` opens a video for a person or an agent. It starts the app when needed, takes no lease, never shows the agent-control icon, and always brings the window to the front. `player open` stays the leased operator command. |
| C2 | `havooch open` is fast: the video is visible and playing within 1 s when Havooch runs and 2 s from cold. The spec holds this as a measured requirement. |
| C3 | Havooch declares video document types (`public.movie`, role Viewer, rank Alternate): Finder's Open With, a drop on the Dock icon and `open -a Havooch` work. Havooch never asks to be the default player. |
| C4 | When a video belongs to a project, `open` opens it in that project. When it belongs to several, the most recently used project wins, and `--project <slug>` chooses another. |

## D. The configuration file

| # | Decision |
|---|---|
| D1 | Settings move to one TOML file, `~/.config/havooch/config.toml` (or under `$XDG_CONFIG_HOME`), following Shipyard and Swift Lab (Swift Lab ADR 0016): `#:schema` and a JSON Schema, `version = 1`, kebab-case keys, live reload, the last valid file kept on an error, a verdict in `config-status.json`, `havooch config check`, and only targeted writes by the app. Built in #84 with two additions: the `theme` line is one more targeted write, for the theme picker and `theme set`; with `HAVOOCH_SUPPORT_DIR` set, the file and `themes/` are in that folder's `config/`. |
| D2 | `theme` moves into the file. Theme colours stay in their own files, in `~/.config/havooch/themes/`, and the file names one. Token overrides leave settings: a person writes a theme that extends another. |
| D3 | App state stays in the support folder, never in the file: recent videos, playheads, the sidebar width, reviews, content hashes, the last listener. |

## E. Projects and versions

| # | Decision |
|---|---|
| E1 | A plain video needs no project. A project appears only when iterating starts, and the agent creates it through the CLI on the person's behalf, never the app on its own. |
| E2 | `[[projects]]` in `config.toml` holds `slug`, `title` and `versions`, a list of `{ path, label }` in version order. Videos stay wherever they are. |
| E3 | Commands: `havooch project new <slug> --from <video> [--title]` (v1 is that video), `havooch project add <slug> <video> [--label]` (appends the next version, opens it and brings the window forward), `havooch project list`. The skill tells the agent to make a project the first time a send asks for a change to the video. |
| E4 | The file stays hand-editable, and agents fix it. Havooch enforces nothing: a video may be in several projects. |
| E5 | Versions are a straight line, v1 to vN. Branching alternatives belong to Havooch Studio. |
| E6 | Threads belong to the project, not to a version. Each thread is anchored to a version by its path, plus time and keyframe, and is tagged with that version's number. Nothing hides, drops or closes a thread because of a version: old and new threads stay usable side by side. A thread whose path left the list stays, tagged as a removed version. |
| E7 | `project new --from <video>` moves the plain video's threads into the project as v1 threads. After that, opening that video opens it in the project. Another project that lists the same video starts with fresh threads. |
| E8 | A send for a project video carries the project, the version on screen, and every version's path and label. |
| E9 | Thread list: the version tree (thread-list V5, "Jump menu"). General first, then the last three versions as sections, newest first, the one on screen marked. An "All versions" menu with search lists every version, with open threads on older versions grouped; picking an old version adds its section. |
| E10 | Version switcher: version-switcher V5, "Recent plus picker". The last three versions as segments, plus a field that names an older version when it's on screen and opens a searchable picker. A plain video shows no switcher. |
| E11 | Compare: compare-control V4, "Live search picker". A Compare button opens a popover with a two-pane mini window. A click on a side opens a search picker for that side; picking the version on the other side swaps them. It opens on the previous version and the one on screen. Three layouts: Side by side, Flip (A/B with a key) and Slider (wipe), and a swap button. The result plays both versions on one playhead, labelled, with Exit Compare (esc). |

## F. Windows and listeners

| # | Decision |
|---|---|
| F1 | Any number of windows, like VS Code. A new window starts empty and opens a video or a project. Opening something that is already open brings its window forward. This replaces the 0.3.0 one-window decision (#72). |
| F2 | One listener per window. A window holds one project or one plain video. `wait` names what it listens for (`--video` or `--project`), and the copied prompt names it. |
| F3 | A new listener on a window replaces the old one, and the player says so ("Codex took over from Claude Code"). |

## G. Connecting an agent

| # | Decision |
|---|---|
| G1 | One **Connect an agent** view in the right sidebar, replacing the thread list, with Back. Three entry points open it: the "No agent" pill, Send with no listener, and a header button. Command line and skill are parts of it, not separate menu items. |
| G2 | Its look is the step timeline (connect-flow V6, connect-view V2): steps 1 "`havooch` command line", 2 "`/havooch-mate` skill", 3 "Your agent", joined by a thin line; done steps fold to one line; the code names in monospace on a soft chip. |
| G3 | Command line: Link puts the command in `~/.local/bin`; done reads "Linked". A failed link shows the `ln -sf` command to copy. |
| G4 | Skill: one row per harness. One click installs it globally for every harness that lacks it (`npx skills add yahyabedirhan/havooch --skill havooch-mate -g`), with a live log and Cancel. "Install in one repo instead" shows the command to copy. Without `npx`, the view says Node is needed and shows the command. |
| G5 | Your agent: a harness picker and the prompt to copy. The prompt uses each harness's skill invocation: Claude Code `/havooch-mate listen for my feedback on <video>`, Codex `$havooch-mate …`, Pi `/skill:havooch-mate …`, Cursor `/havooch-mate …` (unverified, checked in Cursor's live QA), OpenCode `Use the havooch-mate skill to listen for my feedback on <video>`. |
| G6 | Copying the prompt is not an app state: there is no "paste it now" or "waiting for you" state. The only waiting state is a real connection state: "Reconnecting to Claude Code…" for about 30 s after a relaunch, with Forget. |
| G7 | Connected: the listener card shows the logo, the harness, where it runs (folder or Herdr pane), since when, Copy path, Disconnect, and "To listen again later, paste this in <harness>:" with its prompt. Setup folds to one "Set up" line. |
| G8 | Send with no listener: the send waits in the outbox, nothing is lost, and the Connect view opens with "3 messages wait for an agent. They'll be delivered when one connects." After connecting: "Delivered 3 messages to Claude Code". |
| G9 | Detection is honest and optimistic (ADR 0005). A ✓ shows only for what Havooch detects. Anything else reads a neutral "Not detected", never ✕ or "Not installed": a skill installed in a repo can't be seen and still works. When the picked harness's skill isn't detected, the view says so, offers the install, and keeps the prompt primary: "If it's installed another way, paste the prompt and your agent will take it from there." |
| G10 | Installing the skill is the person's job; showing that it isn't detected is Havooch's. The prompt stays short and assumes the skill. |
| G11 | No harness-specific plumbing: the skill teaches each agent how to listen in its harness, including harnesses that can't wake on a background command. |
| G12 | The Holder knows the session variables of Codex (`CODEX_THREAD_ID`) and Pi (`PI_SESSION_ID`) beside Claude Code's, and the harness markers name the rest. |

## H. First run and the tour

| # | Decision |
|---|---|
| H1 | The first launch shows a dedicated onboarding window (first-run V1, step wizard): Welcome, Tools, Connect, Try it. Every step can be skipped. |
| H2 | The first-run prompt is "Use Havooch to open the demo video and listen for my feedback" in the picked harness's invocation form. |
| H3 | The demo uses the person's real agent. The `havooch-mate` skill gets a demo reference for beginners, read only when a send comes from the bundled demo video (recognised by its content), never in daily use. |
| H4 | An optional tour (first-run V3's coach panel) walks tools, connect, write on a frame, send and the reply, with a ring around each part (about 9 pt of padding). A header button "Finish setup · N" opens it, separate from the connect button. |
| H5 | "Finish setup" and the connect button's dot go away once an agent has connected in the window, since a real connection proves setup works. (Confirmed by the maintainer.) |

## I. Look and copy rules

| # | Decision |
|---|---|
| I1 | Never use the stacked-layers symbol (`square.stack.3d.up` and its variants). |
| I2 | No em dash, en dash or spaced hyphen as punctuation in app copy. A range reads "v1 to v47". |
| I3 | No one-sided coloured edge on a box: not left, right, top or bottom. Use a full soft fill, an icon, or text weight and colour. |
| I4 | Filled controls use an `accentFill` token that white text reads on at 4.5:1 or more, in every bundled theme, checked by a test. Native prominent buttons drew white text on the light accent (about 1.9:1 in Default Dark). |
| I5 | Copy boxes put the text on top at full width and the Copy action in a footer bar under it. |
| I6 | Don't overuse cards. Prefer the native integrated look of a popover or a timeline. |
