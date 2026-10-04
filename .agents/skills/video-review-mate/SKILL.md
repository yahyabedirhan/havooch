---
name: video-review-mate
description: Listen for feedback batches from the Video Review app and act on each comment in this repository, answering inside the player. Use when asked to listen for video feedback or to be the video review mate.
---

# Video Review Mate

You are the **listener** of the Video Review app. A person watches a video there, pauses, and comments on a moment or on a region of the frame. Cmd+Enter sends their comments to you as one **batch**. You do what each **comment** asks in this repository and answer in the player, where each answer shows next to its comment.

The feedback is about the **subject** of the video: the project, design or setup the video explains. "This is wrong" at 0:42 means the thing shown at 0:42 is wrong in the repository. Change the video itself only when a comment plainly asks for that.

`vr` below stands for `scripts/vr.sh` in this skill's folder, called by its absolute path. It finds the app's own command line (never one on `PATH`) and passes every command through with its output and exit code. `vr help` lists the commands.

The app knows its one listener by this session's id. A listener command from another session takes your place and gets your unfinished comments again, so sub-agents do work and report to you, and only you run `vr`.

## Start

1. Run `vr which` and tell the user which app you listen to. When it refuses, give the user its message and stop: it names what to install or set.
2. Run `vr listen` as a background command, and tell the user you are listening. The app shows you as present while it is open.

## Loop

`vr listen` exits when a batch arrives, which wakes you. It has already acknowledged the batch, so the person knows you have it. Then:

1. **Listen again first.** Start a new background `vr listen` before anything else. A batch sent while you work is then acknowledged at once and waits its turn behind the current one.
2. **Read the batch**, as [The batch](#the-batch) says: the context, then every comment with its images.
3. **Work the comments** one after another, in the batch's order, each as [One comment](#one-comment) says. A comment that waits for an answer steps aside while you go on with the next.
4. **Close the batch.** Once every comment is `done` or `failed`, run `vr reply <batch-id> '<summary>'`: what changed across the comments, what failed, in a few plain lines.

The loop is complete for a batch when each of its comments has a reply and a final status, and the batch has its summary.

## The batch

`vr listen` prints one JSON object, and its last line on standard error names a file with the same object.

- `batch.id` names the batch for `reply`.
- `video` is what the person watched: `title`, `path`, `duration`, `contentHash`.
- `context` is the video's topic, its source repositories and the person's note. It comes with the first batch of a video and again only when it changed. `null` means the context you already have for this `video.contentHash` still holds, so keep it for the session.
- `comments[]`, each with:
  - `id`, which names the comment for `status`, `reply` and `ask`.
  - `text`, what the person said, and `time`, the moment in seconds.
  - `keyframePath`, the frame they saw. Read the image.
  - `cropPath`, the part of the frame they drew a rectangle on, or `null`. Read it too: it is what "this" and "here" point at. `region` is its place in the frame (`x`, `y`, `w`, `h` from 0 to 1, origin top left).
  - `transcript`, the narration from 15 s before to 15 s after `time`, as lines with `start`, `end` and `text`. The line that spans `time` is what they heard. It is `[]` when the video has no transcript yet.

A batch can be one that an earlier listener session took and left unfinished. It then carries only the unfinished comments, so look in `git log` for work that session already committed before you redo it.

## One comment

1. **Decide the intent** from the text, the images, the transcript and the context:

   | Intent | The work | The reply gives |
   |---|---|---|
   | a question, or research | find the answer; write it into the repository only when the comment asks for that | the answer, with its sources |
   | a design change | change the design document or decision record | what changed, and the commit |
   | issues | file them in the repository's issue tracker | each issue's link |
   | a spec | write or change the spec where this repository keeps specs | its link or path, and the commit when a file changed |
   | an implementation | change the code and run its tests | what changed, the test result, and the commit |

   Follow this repository's own instructions for each kind of work. Changes land in this repository only: a comment whose subject lives elsewhere is `failed`, with a reply that names where.
2. **Ask when the intent or the target is unclear**, as [A question](#a-question) says, and go on with the next comment.
3. Run `vr status <comment-id> working`, then do the work.
4. **Commit** once for this comment when it changed files: only its own files, by this repository's commit rules.
5. **Reply, then set the status.** `vr reply <comment-id> '<text>'`, then `vr status <comment-id> done`. The reply is the person's only view of what happened: lead with the result in plain words, and give the short commit SHA when there is a commit.
6. When the work can't be done, `vr reply <comment-id> '<the reason>'`, then `vr status <comment-id> failed`.

`done` and `failed` are final. A correction afterwards is another `reply`.

Write each text as one single-quoted argument, so the shell leaves its backticks and `$` alone.

## A question

Run `vr ask <comment-id> '<question>'` as a background command. The person answers in the comment's thread, and the command then exits 0 and prints the answer, which wakes you. Put the choices in the question, so a few words answer it.

- Go on with the other comments meanwhile. The batch's summary waits until the answer came and that comment is final.
- An `ask` that ended without an answer is asked again with the same question, word for word: it attaches to the question already in the thread and returns the answer when one is there.
- A new question on a comment ends the `ask` that waited on its earlier one.

## Exit codes

| Code | Meaning | Then |
|---|---|---|
| 0 | done; `listen` printed a batch, `ask` an answer | go on |
| 3 | a `listen --timeout` ran out with no batch, or an `ask --wait` with no answer | run the same command again |
| 2 | the command line doesn't parse | correct it from the usage line it printed |
| 1 | refused; standard error says why in one line | see below |

- **`… is already listening; one listener at a time`**: another session is the listener. Tell the user who it names, and stop.
- **`video-review is quitting`**: the app closed. Run `vr listen` again: it waits for the app to start, and a batch sent meanwhile is kept for you. An `ask` that ended this way is asked again, word for word, once `listen` is open.
- **The app isn't running**: `vr listen` waits for it by itself. Starting the app is the person's move.
- **A refused `status`, `reply` or `ask`** names the comment's state. Read it and act on that state; the same command again is refused again.

## End

When the user ends the session, stop the background `vr listen` and every open `vr ask`, and tell the user which comments are unfinished. The app gives those to the next listener session.
