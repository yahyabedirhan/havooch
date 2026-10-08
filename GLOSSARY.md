# Havooch

Havooch is a native macOS video player for giving feedback to agents. A person writes messages on frames of a video, sends them to a listening agent, and reads the agent's answers in the player.

## Language

### The review

**Video**:
A local video file the person opens. Its identity is its content, so a renamed or moved copy is the same video.
_Avoid_: file, clip

**Recent video**:
A video the person opened lately, kept with the path it was last opened at, when it was opened and where its playhead stopped. The app keeps the 10 newest. Removing one leaves its review on the disk.
_Avoid_: history, recent file

**Window**:
One Havooch window, holding either nothing, one plain video or one project. The person can open any number of them, and each has its own listener.
_Avoid_: tab, workspace, document

**Empty window**:
A window that holds nothing yet. It shows the home screen.
_Avoid_: new window (as a state), blank window

**Home screen**:
What an empty window shows: the cat mark, "Open a Video…", "Try the Demo" and the recent videos and projects as cards with thumbnails. With nothing recent it shows the empty state.
_Avoid_: start screen, welcome screen, launcher

**Plain video**:
A video opened in a window without a project.
_Avoid_: loose video, single video

**Project**:
A named line of versions of one video, set in the configuration file. The agent makes it when the person starts asking for changes.
_Avoid_: series, collection, folder, workspace

**Version**:
One video in a project, named by its full path and an optional label, and numbered by its place in the line: v1, v2.
_Avoid_: cut, revision, iteration, variant

**Version switcher**:
The control in the header of a project window that shows which version is on screen and switches to another, keeping the playhead time.
_Avoid_: version picker, version tabs

**Compare**:
Two versions of a project on one playhead, laid out side by side, as a flip between them or as a slider across them.
_Avoid_: diff, A/B view (flip is one layout of it)

**Review**:
Everything kept about one plain video or one project: its threads, its sends and its context note. A project has one review across all its versions.
_Avoid_: session

**Keyframe**:
The image of the exact frame a thread is about.
_Avoid_: screenshot, frame grab, thumbnail

**Region**:
A rectangle on a keyframe that a message points at, in coordinates from 0 to 1 of the frame.
_Avoid_: selection, area, box

**Crop**:
The image of a region, cut from its keyframe.
_Avoid_: snippet, cutout

**Context**:
What the agent is told about a video beside the messages: the context sidecar file and the in-app note.
_Avoid_: description, brief

### Threads and messages

**Thread**:
The whole conversation about one keyframe, with a number unique in its review.
_Avoid_: comment, topic, conversation, batch

**General thread**:
The thread with the number 0 and no keyframe, for conversation that is not about one frame.
_Avoid_: batch thread, main thread

**Thread list**:
The sidebar's view of every thread of a review, grouped by who must act next: Needs you, With agent, Queued, Done.
_Avoid_: inbox

**Thread view**:
The sidebar's view of one thread: its conversation, with Back to the thread list and Previous and Next. It has no keyframe, since the stage shows it.
_Avoid_: detail, expanded thread

**Unread**:
A thread with an agent message newer than the last time the person opened its thread view. Its row in the thread list shows a dot in the accent colour.
_Avoid_: new, unseen, badge

**Composer**:
The one field at the foot of the sidebar. In a thread view it follows up on that thread or answers its open question; in the thread list it writes at the playhead, to the thread of that frame or a new one. It keeps a draft per thread.
_Avoid_: reply box, thread field, input

**Comment popover**:
The popover on the stage where the person writes a message on the frame or a region, and continues a thread beside its keyframe.
_Avoid_: composer (the composer is the sidebar's field), comment box

**Message**:
One piece of text that the person or the agent writes on a thread, of the kind message, question or answer.
_Avoid_: comment, note, item

**Question**:
A message by the agent that waits for the person's answer.
_Avoid_: ask (as a noun), prompt

**Answer**:
A message by the person to an open question. It goes to the agent at once and never into the queue.
_Avoid_: response, reply (reply is what the agent writes)

**Choice**:
A short answer the agent offers with a question. The thread view shows each one as a button under the open question, after the label "Quick reply"; a click on it sends it as the answer at once.
_Avoid_: option (an option is a command's `--flag`), suggestion

**Reply**:
A message by the agent on a thread that waits for nothing.
_Avoid_: response, answer

**State**:
Where a person's message is in its life: queued, sent, acknowledged, working, done or failed. A thread's state is that of its latest open person message.
_Avoid_: status (except as the CLI command's name), progress

**Activity**:
What the agent says it does now on a thread, given as the text of `status <message> working`. It shows as a live line under the thread view's conversation and in the footer, until the message is done or failed.
_Avoid_: progress, status text

### Sending

**Queue**:
The person's messages of one window that are written but not yet sent.
_Avoid_: drafts, pending list

**Send**:
Every queued message of one window, delivered to its listener at once by Cmd+Enter.
_Avoid_: batch, submission, round

**Outbox**:
The line of sends that wait for a listener or that a listener has taken and not finished.
_Avoid_: delivery queue, inbox

**Outbox banner**:
The line at the top of the connect view that says how many messages wait for an agent and that they will be delivered when one connects.
_Avoid_: warning, error, no-agent alert

### Agents and control

**Person**:
The human at the Mac who watches the video and writes messages.
_Avoid_: user, reviewer

**Listener**:
The agent session that receives the sends of one window and answers on their threads. Each window has at most one. It needs no lease.
_Avoid_: mate, worker, consumer

**Operator**:
An agent that drives the app through the CLI as a person would. It needs the lease.
_Avoid_: controller, driver, tester

**Holder**:
Who sends a control request, named by a key.
_Avoid_: client, caller, owner

**Lease**:
A holder's right to drive the app, which ends by itself.
_Avoid_: lock, control session

**Agent harness**:
The program an agent runs in, such as Claude Code or Codex. The listener's session name says which one it is.
_Avoid_: client, tool, model

**Agent logo**:
The logo of the agent harness, shown as the agent's avatar on its messages, in the thread list's previews, on the presence pill and on notices. An unknown harness shows a sparkle symbol.
_Avoid_: avatar (the avatar is where the logo shows), icon

**Agent-control icon**:
The icon in the header that shows while an agent holds the lease, with a popover that names it and stops it.
_Avoid_: banner, lease banner, indicator

### Setup

**Connect view**:
The sidebar view that guides the person to connect an agent to a window: the setup steps, the choice of harness with its prompt, and, once connected, the listener. The presence pill, Send with no listener and a header button all open it.
_Avoid_: setup screen, onboarding panel, settings

**Setup step**:
One thing an agent needs before it can listen: the **command line** (the `havooch` command linked into the person's PATH folder) or the **skill** (the `havooch-mate` skill installed for a harness).
_Avoid_: requirement, prerequisite, check

**Not detected**:
The state of a setup step or harness that Havooch could not find. It does not mean missing: the thing may be set up in a way Havooch cannot see.
_Avoid_: missing, not installed, failed

**Prompt**:
The one line the person pastes into their harness to make an agent listen to a window, written in that harness's skill invocation and naming the window's video or project.
_Avoid_: command, snippet, instruction

**First run**:
The step-by-step setup a person sees the first time they open Havooch: welcome, setup steps, connect, then the demo.
_Avoid_: onboarding (as a screen name), wizard, welcome flow

**Tour**:
The optional guided walk through setup, writing a message, sending and reading the reply, shown over the real window.
_Avoid_: walkthrough, coach marks, tutorial

**Finish setup**:
The header button that opens the tour, shown only until an agent has connected.
_Avoid_: setup badge, onboarding button

**Demo reference**:
The part of the `havooch-mate` skill that an agent reads only when a send comes from the bundled demo video, to guide a beginner through the first loop.
_Avoid_: demo agent, tutorial mode

### Look

**Theme**:
A named set of colours of one kind, light or dark, that can extend another theme.
_Avoid_: skin, colour scheme, appearance (the appearance is the system's light or dark mode)

**Token**:
One semantic colour name, such as the surface of the window or the colour of the done state, that a theme gives a value: a colour, or `system` on a surface.
_Avoid_: colour variable, swatch

**Surface**:
A token that a part of the window is drawn on: the window, a popover, a notice, a field or a separator. The whole window is on one surface, with hairlines between its parts. A surface set to `system` is the native macOS one, as in Default Light and Default Dark.
_Avoid_: background, panel colour, sidebar colour

**Accent fill**:
The token that filled controls such as Send are drawn on, dark enough for white text in every theme. The accent itself stays for lines, rings and selections.
_Avoid_: button colour, primary colour
