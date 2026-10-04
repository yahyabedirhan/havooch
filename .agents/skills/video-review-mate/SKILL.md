---
name: video-review-mate
description: Listen for the feedback the user sends from the Video Review player - take each batch of comments, do what each comment asks in this repo, and answer in the player. Use when the user asks you to listen for video review feedback or to be their video review mate.
---

# Video Review Mate

The user watches a video in the Video Review app, pauses, and comments on a moment, or on a rectangle they draw on the frame. A comment is about the **subject** the video shows (a project, a design, a setup), not about the video file. They send their comments together as one **batch**.

You are the **listener**: you take each batch, do what each comment asks in this repo, and answer in the player, where every answer shows on its comment. Only batches drive this loop; what the user says in the chat is ordinary conversation.

## The command

`video-review` below stands for the CLI inside the app bundle. Write it as a quoted absolute path in every command. Find it once, at the start:

1. `$VIDEO_REVIEW_CLI`, when it is set.
2. Else `/Applications/Video Review.app/Contents/Helpers/video-review`.
3. Else the one match of `/Applications/Video Review*.app/Contents/Helpers/video-review`. With several matches, ask the user which app they review in.

Every text argument is one quoted argument. Exit codes: `0` done; `1` refused, with the reason as one line on standard error; `2` a wait ran out, with nothing printed; `64` wrong usage (`video-review --help` prints the usage).

You run only `wait`, `ack`, `status`, `reply`, `ask`, `state` and `app status`. The other commands drive the player and take control of the app from the user.

The app knows you by your session id (`CLAUDE_CODE_SESSION_ID`). A `wait` under another id is a new listener, and the app gives it your unfinished batches again. So every `video-review` command runs in this session: a sub-agent may do a comment's work, and you send the commands.

## The loop

1. **Listen.** Run `video-review wait` as a background command, so that its exit wakes you. The player shows the user a listening agent only while a `wait` is open, so keep exactly one open at all times.
   - Exit `0`: the batch is on standard output, as JSON.
   - Exit `2`: no batch came in time. Run `wait` again.
   - Exit `1`: see [Refusals](#refusals).
2. **Acknowledge, then listen again.** The moment a batch wakes you, before you study it:
   1. `video-review ack <batch id> "<one short line>"`, for example `"Got your 3 comments, starting."`
   2. Start a new background `video-review wait`.

   A batch that arrives while you work gets the same two commands at once. Its work starts when the batch before it is finished.
3. **Work each comment**, one at a time, in the order of the payload:
   1. Read it: see [The batch](#the-batch).
   2. `video-review status <comment id> working`
   3. Decide its [intent](#intent) and do the work. When you cannot tell what it asks, [ask](#ask).
   4. When the work changed files, commit: one commit per comment, with only that comment's files staged, in this repo's commit convention.
   5. `video-review reply <comment id> "<the result>"`, then `video-review status <comment id> done`.

   When the comment cannot be done: `video-review reply <comment id> "<why, and what would unblock it>"`, then `video-review status <comment id> failed`. `status` carries no text, so the reply is the reason.
4. **Close the batch.** `video-review reply <batch id> "<one line for the whole batch>"`: how many comments are done, and which failed.

A batch is finished when every comment in it has a reply and is `done` or `failed`, and the batch has its own reply. `done` and `failed` are final.

The reply is the user's only view of what you did, read in a narrow column beside the video. Write one to three plain sentences: what changed and where, or the answer, or the issue's link. Give the commit's short SHA whenever you committed.

## The batch

```json
{
  "batch":    { "id": "b-…", "sentAt": "…" },
  "video":    { "path": "/abs/….mp4", "contentHash": "…", "duration": 21.2, "title": "…" },
  "context":  "…" ,
  "comments": [
    { "id": "c-…", "time": 12.5, "text": "…",
      "keyframePath": "/abs/….png",
      "region": { … }, "cropPath": "/abs/….png",
      "transcript": [ … ] }
  ]
}
```

- `text` is what the user wrote or dictated. Dictation mishears names: read a strange word against the transcript and the context.
- `keyframePath` is a PNG of the frame the user saw at `time`. Open it as an image for every comment: it is what "this" and "here" in the text point at.
- `region` and `cropPath` are `null` unless the user drew a rectangle. With a crop, open the crop first (what they point at), then the keyframe (where it sits).
- `transcript` holds the narration from 15 s before to 15 s after `time`, as timed lines. It says what the video claimed at that moment. It can be empty.
- `context` is the video's topic, its source repos and the user's own note. The app sends it once per session for a video, and again when it changes. `null` means that what you got earlier for this `video.contentHash` still holds.

A batch can come a second time: when a new listener session starts, the app sends again each batch the last session took and did not finish, with its unfinished comments only. Look in `git log` for a commit that already did a comment before you do it again; then reply with that commit and mark it `done`.

## Intent

Decide from all five parts together: the text, the crop, the keyframe, the transcript and the context. This repo's own instructions say how each kind of work is done here; where they name a skill for it, use that skill.

| Intent | The comment | You | The reply carries |
|---|---|---|---|
| Research | asks a question, or wants something looked into | find the answer in the code, the docs or the web | the answer; for long findings, the file you wrote and its commit |
| Design change | wants what the frame shows to look, read or be laid out another way | change the design, the document or the asset that the frame shows | what changed, and the commit |
| Issues | reports a problem or a wish to track, not to solve now | file it in this repo's issue tracker | the issue's link |
| Spec | describes a feature or a change to plan first | write or change the spec, as this repo does | the spec's link or file, and the commit |
| Implementation | wants the code or the setup changed now | make the change and check it with this repo's tests | what changed, and the commit |

A remark that asks for nothing ("nice", "this part is clear") gets a one-line reply and `done`, with no commit.

## Ask

Ask when a comment has two readings that lead to different work and the frame, the transcript and the context do not settle it. Put the readings in the question, so that a short answer is enough.

Run `video-review ask <comment id> "<question>"` as a background command, like `wait`: the user answers in the player, and the command then exits `0` with the answer on standard output. Go on with the next comment meanwhile, and come back to this one when the answer wakes you.

A comment holds one open question: a second `ask` on it is refused until the user answers the first.

Exit `2` means the wait ran out with no answer; an `ask` that the app's quitting cut off with exit `1` is the same case. The question stays open in the player, and an answer that comes later stays in the comment's thread. When the rest of the batch is finished, run `video-review state --json`, find the comment by its id, and read its thread: a message of kind `answer` after your `question` is the answer. `state` lists the comments of the open video only. With no answer there, reply with what you still need to know and mark the comment `failed`.

## Refusals

Exit `1` prints why. Read the line; the same command sent again gets the same answer.

- **A newer `wait` took this one's place.** You had two open. The newer one is the listener; nothing to do.
- **The app isn't running**, on `wait`: tell the user in the chat, and listen again when they say it is open.
- **The app isn't running**, on any other command: the user quit the player. Finish and commit the work, keep each result, and check `video-review app status` before the next command. When the app runs again, send the replies and statuses you kept. Tell the user in the chat when the session ends first.
- **No such comment or batch.** Take the ids from the payload, never from memory.
- **A status that cannot move.** The comment is already `done` or `failed`. Leave it.
- **A question is open.** See [Ask](#ask).

## End

When the user says the session is over: finish each open comment or mark it `failed` with a reply, close each batch, then stop the background `wait` and any open `ask`. The player then shows that no agent listens, and a batch sent later waits for the next listener.
