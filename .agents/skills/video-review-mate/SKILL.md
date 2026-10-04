---
name: video-review-mate
description: Listen for feedback batches from the Video Review player and act on each comment in this repo, answering inside the player. Use when asked to listen for video feedback, or to be the video review mate.
---

# Video Review mate

You are the **listener** of the Video Review player. The person watches a video about this repo's project, comments on moments and on regions of the frame, and sends the comments as one **batch**. You act on every comment in this repo and answer inside the player. A comment is about the video's subject (the project, design or setup it shows), not about the video.

The person reads the player, not this chat: everything for them goes through `reply` and `ask`.

## Start

1. Make this run's key: `mate-` and the output of `openssl rand -hex 4`. One key for the whole run. A new key is a new listener session, so the app gives it the unfinished batches and the context again.
2. Every command below is `mate <arguments>`, which stands for `sh "<this skill's folder>/mate.sh" <key> <arguments>`, written out in full each time. `mate.sh` finds the CLI by itself (see "The CLI"): there is nothing to look up first.
3. Run `mate listen` as a background command. You are present in the player while it runs.

## A batch

`mate listen` is `wait`, then `ack <batch-id>`. It exits 0 when a batch came: its output is the payload, one JSON object, and the batch is already acknowledged.

1. Run `mate listen` in the background again, before anything else. It keeps you present and catches the next batch. Take batches in the order they came.
2. Read the payload. `context` is the video's topic and source repos: read it when it is not `null`, and keep it for the run. For each of `comments`, read `keyframePath` with the Read tool, `cropPath` too when `region` is not `null` (the crop is what the person pointed at), and the `transcript` lines (what the video said from 15 s before `time` to 15 s after).
3. Run `mate state --json` and find the batch's comments by `id`. A comment with messages in its `thread` is **redelivered**: the payload carries no thread history, so the thread is where you learn what was asked, answered and reported before. Go on from there. A comment whose work you finished in this run gets its `status` set again and nothing more.
4. Work each comment through its states, one comment at a time:
   1. Decide its intent: research, a design change, issues, a spec or an implementation. When the comment does not tell you what to do, `ask` (below) before you start.
   2. `mate status <comment-id> working`
   3. Do the work in this repo, by this repo's own instructions.
   4. When the work changed files, make one commit that holds this comment's changes and nothing else.
   5. `mate reply <comment-id> "<the result in a few lines; the commit's SHA when there is one>"`, then `mate status <comment-id> done`.
   6. Work you cannot do: `mate reply <comment-id> "<the reason>"`, then `mate status <comment-id> failed`.
5. The batch is finished when every comment has a reply and is `done` or `failed`. Then `mate reply <batch-id> "<one summary of the batch>"`.

`done` and `failed` are final. A text is one argument: quote it.

## A question

`mate ask <comment-id> "<question>" --wait 60` writes the question on the comment and waits for the person.

- Exit 0: the output is the answer. Go on with the comment.
- Exit 3: no answer yet, and the question stays open. Run the same `ask`, in the same words, as a background command with `--wait 86400`, and go on to the other comments. The same words wait on the same question; they don't ask twice. When that command exits 0, its output is the answer: come back to the comment. The batch's summary waits for it.

One open question per comment.

## Exit codes

| Code | Meaning | Do |
|---|---|---|
| 0 | Done. | Read the output. |
| 1 | Refused, or the app is not running. Standard error says which. | `isn't running`, `is quitting` or `went away` from `listen`: say so in the chat and listen again when the user says the app is open. `another listener took over`: stop, another session listens now. A refused `status` or `reply`: read the reason; a comment that is already final needs nothing more. |
| 2 | The command was written wrong. | Fix it by the usage printed, and run it again. |
| 3 | An `ask` ran out of time. | See "A question". |

## The CLI

`mate.sh` runs the `video-review` CLI at `$VIDEO_REVIEW_CLI` when set, else at `/Applications/Video Review.app/Contents/Helpers/video-review`, never from `PATH`. A prototype build lives at `/Applications/Video Review (proto-N).app/Contents/Helpers/video-review`: a path with spaces and parentheses, easiest to use through `VIDEO_REVIEW_CLI` or a symlink. When `mate.sh` says `No such file or directory`, tell the user to set `VIDEO_REVIEW_CLI`.

## Stop

When the user ends the listening, stop the background `listen` and every background `ask`.
