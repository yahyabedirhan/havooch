# Video Review

A native macOS video player for giving feedback to agents. A person writes messages on frames of a video, sends them to a listening agent, and reads the agent's answers in the player.

## Language

### The review

**Video**:
A local video file the person opens. Its identity is its content, so a renamed or moved copy is the same video.
_Avoid_: file, clip

**Review**:
Everything kept about one video: its threads, its sends and its context note.
_Avoid_: session, project

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

**Message**:
One piece of text that the person or the agent writes on a thread, of the kind message, question or answer.
_Avoid_: comment, note, item

**Question**:
A message by the agent that waits for the person's answer.
_Avoid_: ask (as a noun), prompt

**Answer**:
A message by the person to an open question. It goes to the agent at once and never into the queue.
_Avoid_: response, reply (reply is what the agent writes)

**Reply**:
A message by the agent on a thread that waits for nothing.
_Avoid_: response, answer

**State**:
Where a person's message is in its life: queued, sent, acknowledged, working, done or failed. A thread's state is that of its latest open person message.
_Avoid_: status (except as the CLI command's name), progress

### Sending

**Queue**:
The person's messages of the open video that are written but not yet sent.
_Avoid_: drafts, pending list

**Send**:
Every queued message of the open video, delivered to the agent at once by Cmd+Enter.
_Avoid_: batch, submission, round

**Outbox**:
The line of sends that wait for a listener or that a listener has taken and not finished.
_Avoid_: delivery queue, inbox

### Agents and control

**Person**:
The human at the Mac who watches the video and writes messages.
_Avoid_: user, reviewer

**Listener**:
The agent session that receives sends and answers on their threads. It needs no lease.
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

**Agent-control icon**:
The icon in the header that shows while an agent holds the lease, with a popover that names it and stops it.
_Avoid_: banner, lease banner, indicator

### Look

**Theme**:
A named set of colours of one kind, light or dark, that can extend another theme.
_Avoid_: skin, colour scheme, appearance (the appearance is the system's light or dark mode)

**Token**:
One semantic colour name, such as the background of the sidebar or the colour of the done state, that a theme gives a value.
_Avoid_: colour variable, swatch
