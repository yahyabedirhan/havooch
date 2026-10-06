# Handoff: Video Review v1 prototypes

Three orchestrators build the same spec on their own, at the same time, on `proto-1`, `proto-2` and `proto-3`. A fourth session researches transcription on `research/transcription`. The maintainer compares the three draft pull requests later; nothing merges into `main` from this round without them.

## Read first

- Spec: #1 `Spec: Video Review v1`. Tickets: every issue labelled `effort:v1`. Start with #15 (the low-level design), then follow the blocking links.
- `AGENTS.md` and `docs/adr/0001-agents-control-the-app-through-a-leased-cli.md`.
- Shipyard (`~/Developer/yahyabedirhan/shipyard`) is the working example for the build, the CLI, the socket, the lease, demo mode and screenshots: its `Package.swift`, `Makefile`, `Sources/ShipyardControl/`, `Sources/ShipyardApp/Control/`, ADR 0006, ADR 0007 and the Testing section of its `AGENTS.md`. Copy its patterns; don't link its code.
- ReviewMate, a review loop in one of the maintainer's private repositories, is the working example for the listener loop. Read it for the principles only. Never copy its code or name its private details in this repo.
- The fixture video is in `fixtures/sample/`.

## Why this exists

The maintainer watches explainer videos that agents made about their projects, and wants to give feedback on the material as fast as pointing at the screen. The agent gets the moment, the frame, the region and the words around it, and answers inside the player. Agents also drive the app through the CLI, both as a product feature and to test the real app.

## Rules for this round

- **The GitHub issues are shared by three runs. Treat them as read-only.** Don't tick, close, comment on, label or assign any issue. Record each ticket's status and its evidence for every acceptance criterion in your pull request's description instead.
- **Your prototype is your own.** Choose the UX, layout and look and feel freely. Similarities with the other runs are fine. Keep the CLI contract, the batch payload and the item states exactly as the spec says.
- **Write `docs/low-level-design.md` first** with the `low-level-design` skill (#15), accept it yourself and keep it current with every ticket. It is documentation for the maintainer, not a review gate.
- **Keep a decision log** of every choice the spec left open, with its reason, and put it in the pull request.
- **Don't ask the maintainer design questions.** Decide within the spec and log it.

## Running three builds on one Mac

The installed app is shared with the other two runs. Give your build its own identity so the builds never replace or reach each other, without changing the CLI contract:

- App name `Video Review (proto-N).app` in `/Applications`, bundle id ending in `.proto-N`.
- Support folder `~/Library/Application Support/Video Review (proto-N)/`, so the socket, the demo pointer and the data are separate.
- The CLI keeps its name and commands. Run it from your own bundle's `Contents/Helpers/video-review`, never from `PATH`.
- Write this in one build setting, so the real product can drop the suffix later.

`N` is the number in your branch name.

## When something needs the maintainer

macOS may ask for Screen Recording or Speech Recognition permission for your app. An agent can't grant it. When a permission prompt or a click blocks you, ping the maintainer with `shipyard ping "<what to grant>" --body "<where and why>" --from proto-N --herdr`, which brings them back to your pane, and work on another ticket meanwhile. Ping also when the run is done or truly blocked.

## Delivery

Open a **draft** pull request from your branch to `main` with `to-pr`, with the decision log, the ticket status and evidence, the acceptance test output and the light and dark screenshots. Don't merge and don't run `settle-effort`. Leave your worktree and session open.
