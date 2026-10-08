# A project groups versions of one video, created lazily by the agent

A video's identity is its content (its hash), so a new render is a new video with an empty review, unrelated to the one before. To review how a video changes over time, a **project** groups its versions. Havooch stays a player: opening a video never asks for a project, and a review that only asks questions never gets one.

## Decision

- **Projects live in `config.toml`** (ADR 0002): `[[projects]]` with `slug`, `title` and `versions = [{ path = "...", label = "..." }]`. The list order is the version order, v1 first. A version is a full path and an optional label. The videos stay wherever they are.
- **The agent makes the project, on the person's behalf, when iterating starts**: the first time a send asks for a change to the video, the `havooch-mate` skill runs `havooch project new <slug> --from <video>`, which makes that video v1. Each new render is `havooch project add <slug> <video> [--label <l>]`, which opens it and brings the window forward. `havooch project list` lists them.
- **Threads belong to the project**, not to one version. Each thread is anchored to the version it was raised on, by that version's path, and shows its tag (v1, v2) from the current list. Old and new threads stay usable side by side. Nothing closes or hides a thread by a rule; a thread whose path left the list still shows, tagged as a removed version.
- **A plain video's threads move into the project** when `project new` makes it v1. Opening that video again opens it in its project.
- **Havooch enforces nothing.** A video may be in several projects; agents keep the file right. When a video is already in a project, a second project that adds it starts with fresh threads. Opening a video that two projects list opens the project used most recently; `--project <slug>` chooses.
- **The content hash of each version is app state**, not configuration, so a person can edit the file by hand without computing anything.
- **Comparing two versions**: side by side, flip (A/B) and slider (wipe), on one playhead, with a swap of the two sides. The prototypes chose the layouts (`docs/prototypes/`).

## Considered Options

- **A project created up front.** It would slow the first open, which must stay instant.
- **Versions only, linked pairwise, with no container.** No name, no single place to list the line of versions.
- **Folder-based grouping.** Breaks as soon as one folder holds two different videos.
- **Threads per version, carried over by timestamp.** Timing moves between cuts, so a carried thread would point at the wrong frame.

## Consequences

- The review store gains a project review beside the per-video review keyed by content hash.
- The send payload carries the project, the version on screen and every version's path and label.
- Versions are a straight line in the player. Alternatives and a video's parts belong to Havooch Studio, a separate project.
