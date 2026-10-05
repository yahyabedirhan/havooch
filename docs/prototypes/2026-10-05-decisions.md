# Decisions from the prototype round

The itemized decisions for Video Review 0.1.0, taken from the maintainer's feedback in [round 1](2026-10-05-feedback-round-1-screenshots.md) and [round 2](2026-10-05-feedback-round-2-ux.md). The spec `Spec: Video Review 0.1.0` holds the same decisions in structured form. Where an item says *default*, the agent chose it and the maintainer did not object.

Prototype branches, kept for reference: `proto-1` (PR #17), `proto-2` (PR #18), `proto-3` (PR #19). The code assessment of each is in [assessments.md](assessments.md).

## 0. Version and base

| # | Decision |
|---|---|
| 0.1 | The next build is **0.1.0**, under semantic versioning. Not "v1". |
| 0.2 | Build on a new branch `0.1.0` from `main`. Take the code from the prototype branches; don't merge them. |
| 0.3 | proto-3 is out of the comparison. proto-1 and proto-2 are combined; a few UX pieces come from proto-3. |
| 0.4 | The v1 spec and its tickets are closed as done. The prototype branches stay. |

## A. Architecture (the agent's picks, delegated by the maintainer)

| # | Topic | Pick |
|---|---|---|
| A.1 | Base codebase | **proto-2**. |
| A.2 | Concurrency | proto-2's: main-actor default isolation, `@concurrent` workers, `Mutex`. Remove the leftover explicit `@MainActor` marks. |
| A.3 | App folders | proto-2's: the app's logic at the module root, views under `UI/`. |
| A.4 | Transcript capture | proto-1's: cut the transcript window at send time and keep it with the sent message, so redelivery needs no transcriber. |
| A.5 | Ids | proto-1's: ids carry the video's content-hash prefix, so listener commands work after another video opens. |
| A.6 | Disk paths | proto-1's: one `SupportLayout` owns every path; `Library` keeps only load and save. |
| A.7 | Lease and Wire | proto-1's: `Holder` lives in Lease, which depends on nothing. Wire depends on Lease. |
| A.8 | Control server | proto-1's split: socket and hang-up handling in a `SocketListener`; `ControlServer` only dispatches. |
| A.9 | Linux | Keep proto-2's `#if canImport` guards, so every module except the app builds on Linux. |
| A.10 | Identity | No prototype suffix: `Video Review.app`, its own bundle id, `~/Library/Application Support/Video Review/`. |
| A.11 | Stuck work | Both prototypes requeue unfinished work only for a new listener key. Kept as is for 0.1.0; a follow-up decides the rule for a listener that never comes back. |

## 1. The player bar

| # | Decision |
|---|---|
| 1.1 | proto-1's bottom bar: play/pause, time / duration, speed, timeline with ticks and time labels, small status pins. |
| 1.2 | proto-2's comment popover. The bar's Comment button, the C key and a region selection open the same component. |
| 1.3 | Not proto-2's numbered pins with status badges, and not its extra transport row. |
| 1.4 | The popover closes three ways. Click outside: typed text is queued. The × or Escape: discard. Empty: every close only closes. No new draft state. |
| 1.5 | Queued messages stay editable until they are sent. |
| 1.6 | A thread's pin is a rounded square when the thread has any region, a circle otherwise. Hover shows the details, e.g. "#3 · 0:12 · 2 regions · Working". The colour is the thread's state. |
| 1.7 | The popover shows time like the bar (`1:25`, not `1:25.945`), and its key hints are quieter. |
| 1.8 | The popover has too much padding around a small field. For 0.1.0, tighten it. A focused redesign comes after 0.1.0. |

## 2. Commenting on the video

| # | Decision |
|---|---|
| 2.1 | proto-2's region selection and popover, showing the number of the thread being written to. |
| 2.2 | Bug in the prototypes: the popover stays open when the moment changes. Fix it. |
| 2.3 | When the moment changes with the popover open (seek, scrub, play, timeline click, frame step): with text, queue it at its original time and region; empty, discard it and its region. |
| 2.4 | proto-1's size label on the region while drawing (e.g. `412 × 236`). |
| 2.5 | Every keyframe is a **thread**, with its own number. |
| 2.6 | On the frame, each region shows its outline, and the thread's number badge sits on the frame. The badge or the thread's pin opens the thread popover. |
| 2.7 | The thread popover is the comment popover with the conversation above the field. A thread continues in the popover or in the sidebar; it is one thread. |
| 2.8 | The thread popover is a widget: drag and resize it anywhere on the video. |
| 2.9 | Moment-only messages (C or the Comment button) get the thread popover too. |
| 2.10 | *Default:* the popover's position and size are kept per thread, with the review. |
| 2.11 | *Default:* during playback the frame shows only badges and outlines; nothing opens by itself. Rule 2.3 applies to the thread popover. |
| 2.12 | *Default:* a new message on a thread whose messages are all done or failed makes the thread active again. |
| 2.13 | Follow-ups are **queued** like first messages. Cmd+Enter sends everything queued, on any threads, at once. |
| 2.14 | Each sent message carries its thread; a new keyframe starts a new thread. |
| 2.15 | *Default:* each thread in a send carries its context: time, keyframe, regions and crops, and its conversation so far. |
| 2.16 | Answers to an agent's question are sent at once, because the agent waits for them. |
| 2.17 | Work is asynchronous: send, keep watching or close the app, find the replies in their threads later. |

## 3. The right sidebar

| # | Decision |
|---|---|
| 3.1 | One thread per keyframe. A moment message and every region message on the same frame are messages in that thread. |
| 3.2 | No batches in the UI. Cmd+Enter still sends the queue at once. |
| 3.3 | Threads are collapsed by default: number, keyframe thumbnail, state, the start of the last message. A click expands one. |
| 3.4 | proto-2's message style: avatar, name ("Claude Code" / you), time, bubble. |
| 3.5 | The conversation reads in order. Each region message shows its own crop as an attachment at that point. The keyframe image is in the thread's header. |
| 3.6 | An expanded thread has a field at its bottom. Follow-ups queue (2.13); answers go at once (2.16). |
| 3.7 | A **General** thread at the top, with no keyframe, for open conversation. The agent's messages about a whole send go there. |
| 3.8 | *Default:* the same keyframe means the exact same frame. A message on that frame joins its thread; one frame later starts a new thread. |
| 3.9 | *Default:* each person message has its own state. The thread shows the state of its latest open message. |

## 4. The header and agent presence

| # | Decision |
|---|---|
| 4.1 | The title is the full file name with its extension, with a video icon before it. |
| 4.2 | The subtitle is the folder, with a folder icon; a long path is shortened in the middle, the full path on hover; "Demo" in demo mode. |
| 4.3 | proto-1's floating button group at the top right. |
| 4.4 | proto-2's Context popover content. |
| 4.5 | proto-1's sidebar open and close animation. |
| 4.6 | Nothing from proto-3 in the header. |
| 4.7 | proto-2's agent-control indicator: its icon, left of the Context icon, its popover with who, where, time left and Stop. Shown only while an agent holds control. |
| 4.8 | proto-3's sidebar footer: presence pill ("Listening" / "Working" / "No listener"), the queued count, Send. Hover on the pill names the agent. |
| 4.9 | The sidebar footer has the same height as the player bar. |
| 4.10 | *Default:* a notice names the thread ("#3 · Claude Code: …"), opens it on click, and fades after a few seconds. |

## 5. The overall look and layout

| # | Decision |
|---|---|
| 5.1 | Every colour is a semantic token. Views never use a raw colour. |
| 5.2 | Themes are JSON files with a `kind` (light or dark). Built-in themes ship with the app; user themes go in the support folder's `Themes/`. A theme can extend another. |
| 5.3 | People pick a theme in the app; agents pick one with `video-review theme list` and `theme set <name>`. |
| 5.4 | By default the app follows the system appearance with a light and a dark theme; a person can pin one theme. |
| 5.5 | Per-token overrides in the settings, on top of the active theme. |
| 5.6 | Theme files reload when they change on disk. |
| 5.7 | Built-in themes for 0.1.0: Default Light, Default Dark (natural backgrounds, pastel state colours, no pink) and Dimmed (proto-2's softer background). |
| 5.8 | Themes cover colours only in 0.1.0. |
| 5.9 | proto-3's structure: background colour segments the UI, not bordered cards. Bubbles only for messages. |
| 5.10 | *Default:* the sidebar is resizable within limits, keeps its width, and collapses with the toggle. |
| 5.11 | *Default:* the empty first screen is a drop target with "Open a video" and "Try the demo". It is reviewed after 0.1.0 runs. |
