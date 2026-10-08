---
name: havooch-mate
description: Listen for the feedback the person sends from the Havooch player - take each send, do what each message on each thread asks in this repo, and answer on its thread in the player. Use when asked to listen for Havooch or video feedback, or to be the Havooch mate or listener.
---

# Havooch Mate

The person watches a video in the Havooch app and writes messages on its frames. All messages about one keyframe form one **thread**, numbered from 1; the **General thread** (#0) holds what is about no single frame. A message is about the **subject** the video shows (a project, a design, a setup), not about the video file. Cmd+Enter sends every queued message at once: one **send**, grouped by thread.

You are the **listener**: you take each send, do what each message asks in this repo, and answer on its thread, where the person reads it beside the video. Only sends drive this loop; what the person says in the chat is ordinary conversation.

While you listen, the person reads the player, not this chat. Everything you have to say about a send goes on its thread in the player, through `reply`, `ask` and `status`. Write in the chat only to answer what the person writes there, or when you stop listening.

## The command

`havooch` below stands for the CLI inside the app bundle. Write it as a quoted absolute path in every command. Find it once, at the start:

1. `$HAVOOCH_CLI`, when it is set.
2. Else `/Applications/Havooch.app/Contents/Helpers/havooch`.
3. Else the one match of `/Applications/Havooch*.app/Contents/Helpers/havooch`. With several matches, ask the person which app they review in.

Every text argument is one quoted argument, and it must not start with `--`: the command would read it as an option. Exit codes: `0` done; `1` refused, with the reason as one line on standard error; `2` a wait ran out, with nothing printed; `64` wrong usage (`havooch --help` prints the usage).

You run only the listener commands `wait`, `ack`, `status`, `reply` and `ask`, the project commands `project new` and `project add` (see [Projects](#projects)), the free `state --json`, `window list --json` and `app status`, `config path`, `config check` and `project list`, which need no app, and `open <path>`, which opens a video for the person. Every other command drives the player and takes control of the app from the person.

The app knows you by your holder key: `$HAVOOCH_CONTROL_KEY` when set, else your harness's session: `$CLAUDE_CODE_SESSION_ID` (Claude Code), `$CODEX_THREAD_ID` (Codex) or `$PI_SESSION_ID` (Pi). Any other harness is known by its process. A `wait` under another key is a new listener, and the app gives it your unfinished sends again. So run every `havooch` command from this session with this environment: a sub-agent may do a message's work, and you send the commands.

## The video you listen to

Each player window holds one plain video or one project, and has its own listener. You listen to one window: the one the person names, as in "listen for my feedback on launch.mp4" or "listen for my feedback on project launch-video". Find your **target** once, at the start:

1. When the person names a project, the target is `--project <slug>`.
2. When the person gives a path, the target is `--video <path>`.
3. When the person asks you to open the demo video, the path is `Contents/Resources/Demo/havooch-demo.mp4` in the app bundle that holds the command. Run `havooch open <path>`, then listen to it with `--video <path>`.
4. Else run `havooch window list --json` and find the window whose `video.title` is that file name. When its `video.project` is set, the target is `--project <that slug>`; else it is `--video <its video.path>`.
5. Else, with no name or no match, ask the person which video to listen to.

Pass your target on every `wait`. Another agent can listen to another window at the same time.

## The loop

1. **Listen.** Run `havooch wait <target>` as a background command, so that its exit wakes you. The player shows the person a listening agent only while a `wait` is open, so keep exactly one open at all times. `wait` keeps connecting while the app is closed, so start it whether or not the app runs.
   - Exit `0`: the send is on standard output, as JSON.
   - Exit `2`: a `--timeout` ran out with no send. Run `wait` again.
   - Exit `1`: see [Refusals](#refusals).
2. **Acknowledge, then listen again.** The moment a send wakes you, before you study it:
   1. `havooch ack <send id>`, with no text. Every message of the send turns `acknowledged`, which the player shows.
   2. Start a new background `havooch wait <target>`.

   A send that arrives while you work gets the same two commands at once. Its work starts when the send before it is finished.
3. **Work each thread**, in the order of `threads[]`. Read the thread first: see [The send](#the-send). Then work each of its `messages[]`, in order:
   1. `havooch status <message id> working "<what you do now>"`
   2. Decide its [intent](#intent) and do the work. When you cannot tell what it asks, [ask](#ask). When the work renders a new version of the video, see [Projects](#projects). Each time the work moves to a new step, send `status <message id> working "<the step>"` again: see [Activity](#activity).
   3. When the work changed files in this repo, commit: one commit per message, with only that message's files staged, in this repo's commit convention, and the line `Havooch-Message: <message id>` at the end of the body.
   4. `havooch reply <thread id> "<the result>"`, then `havooch status <message id> done`.

   When the message cannot be done: `havooch reply <thread id> "<why, and what would unblock it>"`, then `havooch status <message id> failed`. `done` and `failed` carry no text, so the reply is the reason.
A send is finished when every message in it is `done` or `failed` and has a reply on its thread. `done` and `failed` are final. The player shows each message's state, so post no summary of the send.

The reply is the person's only view of what you did, read in a narrow column beside the video. Write one to three plain sentences: what changed and where, or the answer, or the issue's link. Give the commit's short SHA whenever you committed. When a thread has several messages in the send, open each reply with the start of the message it answers, so the person can pair them.

## Activity

The text of `status <message id> working "<text>"` is the **activity**, a live line. The player shows it under the thread's conversation and in the footer, beside the presence pill, until the message is `done` or `failed`. The newest text replaces the one before; an empty text clears the line.

- Write what you do now, not what you did: `"Reading the intro scene"`, `"Rendering 0:14 to 0:21"`, `"Running the tests"`.
- Keep it to one short line, at most about 40 characters. Start with a verb in the `-ing` form, with no agent name and no full stop.
- Send a new text when the work moves to a new step, not more often than every few seconds.
- The line is not a result. The result goes in the `reply`.

## The send

```json
{
  "send":    { "id": "s-f92cbb2a-2", "sentAt": "…" },
  "video":   { "path": "/abs/….mp4", "contentHash": "…", "duration": 21.233, "title": "sample.mp4", "demo": false },
  "project": { "slug": "launch-video", "title": "Launch video", "onScreen": 2,
               "versions": [ { "number": 1, "path": "/abs/cut1.mp4", "label": null }, … ] },
  "context": "…",
  "threads": [
    { "id": "t-f92cbb2a-1", "number": 1, "time": 10.017, "keyframePath": "/abs/….png",
      "version": { "number": 1, "path": "/abs/cut1.mp4", "label": null },
      "transcript": [ { "start": 6.067, "end": 14.333, "text": "…" } ],
      "history":    [ { "id": "m-f92cbb2a-1", "author": "person", "kind": "message", "text": "…",
                        "region": null, "cropPath": null } ],
      "messages":   [ { "id": "m-f92cbb2a-9", "text": "…",
                        "region": { "x": 0.25, "y": 0.2, "w": 0.3, "h": 0.25 }, "cropPath": "/abs/….png" } ] }
  ]
}
```

- `threads[]` holds only the threads with a message in this send. The General thread has `number` 0, `time` and `keyframePath` `null` and an empty `transcript`; work its messages from the text, the history and the context.
- `keyframePath` is a PNG of the thread's frame, at `time`. Open it as an image for every thread: it is what "this" and "here" in the text point at.
- `messages[]` is the work of this send. `text` is what the person wrote or dictated; dictation mishears names, so read a strange word against the transcript and the context. `region` and `cropPath` are `null` unless the person drew a rectangle, in 0..1 frame coordinates. With a crop, open the crop first (what they point at), then the keyframe (where it sits).
- `history[]` is the thread's conversation before this send, oldest first: the person's earlier messages and your own replies, questions (`kind` `question`) and the person's answers (`kind` `answer`). A message with history is a **follow-up**: read the history before you decide what it asks. "Still wrong" or "the other one" points at your last reply on the thread; the commit named there is where to start.
- `transcript[]` holds the narration from 15 s before to 15 s after `time`, cut when the person sent. It says what the video claimed at that moment. It can be empty.
- `project` is `null` for a plain video. In a project, `video` is the version on screen when the person sent (`onScreen`), and `versions[]` lists every version, v1 first. Each thread's `version` is the version it was raised on: its `keyframePath`, `time` and `transcript` are of that version's file. A `number` of `null` means its path left the project's list. "Still wrong" on a thread of an older version points at what that version showed.
- `video.demo` is `true` only on the demo video bundled in the app. Then the person is new to Havooch: read [references/first-demo.md](references/first-demo.md) before you work the send, and follow it for every send on that video.
- `context` is the video's topic, its source repos and the person's own note. It comes on the first send of your session, and again when it changes. `null` means that what you got earlier in this session for this `video.contentHash` still holds.

A send can come a second time: when a new listener session starts, the app sends again each send the last session took and did not finish, with its unfinished messages only. Run `git log --grep "<message id>"` before you work a message; when a commit already did it, reply with that commit and mark it `done`.

## Intent

Decide from all parts together: the text, the crop, the keyframe, the transcript, the history and the context. This repo's own instructions say how each kind of work is done here; where they name a skill for it, use that skill.

| Intent | The message | You | The reply carries |
|---|---|---|---|
| Research | asks a question, or wants something looked into | find the answer in the code, the docs or the web | the answer; for long findings, the file you wrote and its commit |
| Design change | wants what the frame shows to look, read or be laid out another way | change the design, the document or the asset that the frame shows | what changed, and the commit |
| Issues | reports a problem or a wish to track, not to solve now | file it in this repo's issue tracker | the issue's link |
| Spec | describes a feature or a change to plan first | write or change the spec, as this repo does | the spec's link or file, and the commit |
| Implementation | wants the code or the setup changed now | make the change and check it with this repo's tests | what changed, and the commit |

A remark that asks for nothing ("nice", "this part is clear") gets a one-line reply and `done`, with no commit.

## Ask

Ask when a message has two readings that lead to different work and the frame, the transcript, the history and the context do not settle it. Put the readings in the question, so that a short answer is enough.

Run `havooch ask <thread id> "<question>"` as a background command, like `wait`: the question shows on the thread, the person answers in the player, and the command then exits `0` with the answer on standard output. Leave the message `working` and go on with the next one meanwhile; come back to it when the answer wakes you.

When the answer is one of a few short readings, give each one as a choice: `havooch ask <thread id> "<question>" --choice "<reading 1>" --choice "<reading 2>"`. Give two to four choices of a few words each, in the order of the question. The player shows each choice as a button under the question, and one click answers with its words. The person can still type another answer, so the answer is not always one of the choices. Leave out `--choice` when the answer needs the person's own words.

A thread holds one open question: a second `ask` on it is refused until the person answers the first. A `reply` does not close a question.

Exit `2` means an `--wait` ran out with no answer; an `ask` that the app's quitting cut off with exit `1` is the same case. The question stays open in the player, and an answer that comes later stays on the thread. Do not run `ask` on that thread again: it is refused until the person answers the open question. When the rest of the send is finished, run `havooch state --json`, find the thread by its id, and read its `messages`: one of `kind` `answer` after your `question` is the answer. `state` lists the threads of the key window's video or project only. With no answer there, reply with what you still need to know and mark the message `failed`.

## Projects

A project groups the versions of one video, v1 to vN, in `config.toml`. You make it on the person's behalf; a send that only asks questions never needs one.

1. **Make the project the first time a send asks for a change to the video itself** (a [Design change](#intent) or an [Implementation](#intent) whose result is a new render). Before the work, while you listen to a plain video:
   1. `havooch project new <slug> --from <video path> --title "<title>"`. The slug is lowercase letters, digits and single hyphens, from the video's subject: `launch-video`. The video becomes v1, and its threads move into the project with their ids, so every id you have stays valid.
   2. Your open `wait` keeps listening, now to the project. Use `--project <slug>` as your target for every `wait` from now on.
   - Refused because the slug is in use: run `havooch project list` and pick another slug, or use that project when it lists the video.
2. **Add each new render as the next version**: `havooch project add <slug> <render path> --label "<what changed, a few words>"`. The player shows the new version and comes to the front. Then reply on each thread the render answers, and name the version: `"Done in v2: slower intro, commit abc1234."`
3. A thread stays on the version it was raised on. The person can still write on a thread of an older version; work it like any other.

`havooch project list` prints every project with its versions, and `--json` the same as JSON; it needs no app. Never edit a project's `versions` by hand while the app runs: `project add` writes the file and shows the version.

## Settings

When the person asks you to change a Havooch setting, edit `config.toml` yourself: `havooch config path` prints where it is. Change only the lines you mean to change, and keep every comment. The file's `#:schema` line names its JSON Schema, which `taplo check` applies.

| Key | What it sets |
|---|---|
| `version` | The format version: `1`. A file that sets any key needs it. |
| `theme` | The pinned theme by name, as `havooch theme list` prints it. Leave it out to follow the Mac's appearance. The person's own themes are files in `themes/` beside `config.toml`. |
| `[[projects]]` | A project: `slug`, an optional `title`, and `versions`, a list of `{ path, label }` tables, v1 first. `project new` and `project add` write it; see [Projects](#projects). |

The app applies each save at once. After a save, run `havooch config check`: exit `0` means the file reads, and exit `1` lists each problem with its line. The app keeps the last valid settings while the file has a problem. Its own verdict on the last save is in `config-status.json`, whose path `state --json` gives as `config.status`. App state (recent videos, playheads, the sidebar width, reviews) is not in the file.

## Refusals

Exit `1` prints why. Read the line; the same command sent again gets the same answer.

- **A newer `wait` took this one's place.** You had two open. The newer one is the listener; nothing to do.
- **Another agent took over listening to this review.** The person connected another agent to it. Do not run `wait` again: finish or fail the messages you have, then tell the person in the chat that you stopped listening.
- **The person disconnected you from this video or project.** They pressed Disconnect in the player. Do not run `wait` again. Tell the person in the chat that you stopped listening. The sends you had and did not finish wait for the next agent.
- **No window holds a video to listen to**, **no video file** at the path, or **no project** with the slug. Ask the person which video or project to listen to.
- **The app is quitting**, on `wait` or `ask`: a new `wait` reconnects once the app is back; treat an `ask` as in [Ask](#ask).
- **The app isn't running**, on any other command: the person quit the player. Finish and commit the work, keep each result, and check `havooch app status` before the next command. When the app runs again, send the replies and statuses you kept. Tell the person in the chat when the session ends first.
- **No such send, message or thread.** Take the ids from the payload, never from memory.
- **Nothing was sent on the thread yet.** Use the thread id from the payload.
- **A message can't move.** It is already `done` or `failed`, or the state is behind its current one. Leave it.
- **A question is open.** See [Ask](#ask).

## End

When the person says the session is over: finish each open message or mark it `failed` with a reply on its thread, then stop the background `wait` and any open `ask`. The player then shows that no agent listens, and a send that comes later waits for the next listener.
