# Handoff: orchestrate the projects-and-onboarding effort

## The work

Build the effort **projects-and-onboarding** end to end and deliver one pull request into `main`.

- Spec: `Spec: Projects, windows and agent onboarding` (#79), https://github.com/yahyabedirhan/havooch/issues/79. Read the body; it is the final state.
- Tickets: #81 to #105, all sub-issues of #79, with GitHub's native "blocked by" edges. Label `effort:projects-and-onboarding`. Build tickets carry `ready-for-agent`; QA tickets (#96 to #105) carry `ready-for-human`.
- Worktree: `/Users/yahyabedirhanpak/.treehouse/havooch-1247ba/4/havooch`, branch `effort/projects-and-onboarding`, cut from `main` at `78cdcbe` (the merge of #80). Treehouse lease holder `projects-and-onboarding`, lease id `3d6a39a34ebf42cfe31a862c6c845d82`. The branch has no upstream until its first `git push -u`.
- The pull request targets `main`. Ask the maintainer before merging it (global rule).

## Read before delegating

Everything decided is in the repository on `main`. Do not re-decide it.

- `docs/prototypes/2026-10-08-decisions.md`: every decision, A1 to I6.
- `docs/low-level-design-projects-and-onboarding.md`: the target design, with its own decisions P1 to P13 and three traces. `docs/low-level-design.md` stays the design of the current code; each ticket updates it for what it builds (`AGENTS.md`, Design).
- `docs/prototypes/2026-10-08-lab/README.md`: **the final prototype variants to build from**, one per part, with the ticket each one feeds and the list of variants not to build from. Delegates copy that code into Havooch and build on it; screenshots alone are not enough. In Swift Lab (project `havooch`, sessions `project-versions` and `agent-onboarding`) the finals carry the keep pin and titles that start with "Final:".
- ADRs 0002 to 0006, `GLOSSARY.md`, and the look rules in `AGENTS.md` (no stacked-layers symbol, no em dash, en dash or spaced hyphen in app copy, no one-sided coloured edges).
- `docs/prototypes/2026-10-08-feedback-verbatim.md`: the maintainer's words, when a decision needs its reason.

## The frontier

Five build tickets start at once: #81 (accent fill), #82 (`havooch open`), #84 (`config.toml`), #85 (Codex and Pi sessions), #88 (setup detection). The longest chain is #82 → #86 (windows) → #87 (listener per window) → #92 (projects) → #93 (switcher) → #95 (compare). #89 (the Connect view) waits for #81, #85, #87 and #88.

- #86 is a wide change to the app's one-window model (ADR 0003 replaces #72's decision). Expect it to touch most of `ReviewApp`; give it a delegate with a fresh context and keep other `ReviewApp` tickets off it while it runs.
- #92 starts with the mechanical rename `VideoReview` to `Review` (P2).

## What this session knows that the repository doesn't

- **Live QA:** the maintainer wants the agent to prepare the app and then only look and play. For each QA ticket: install, set up the state on a scratch data folder (`HAVOOCH_SUPPORT_DIR`), assign the ticket to the maintainer with a comment on what to look at. Ping the maintainer through `shipyard ping` when a QA ticket is ready.
- **Blocking or not (decided by the maintainer, 2026-10-08):** the harness QA tickets (#97 to #104) and #96 do not block the merge. Reference them with `Refs`, prepare them once the PR is ready, and leave them open after the merge. #105 (projects and compare) is prepared before asking to merge.
- **Cursor's prompt form** (`/havooch-mate …`) is unverified; #101 and #102 confirm it.
- An older Havooch run may still use the scratch data folder `.scratch/qa-live` in the main checkout, with idle listener sessions from the earlier live QA. Leave them alone; the maintainer ends them.
- Swift Lab issue `Lab: Mark the variants that changed since the maintainer last looked` (yahyabedirhan/swift-lab#103) came out of this session; it is not part of this effort.
- Out-of-scope follow-ups to file as issues when the effort settles: a Raycast extension; the CLI following the running app's data folder; Havooch Studio (a new repository); the human-agent interaction mental-model document (the maintainer's notes hold it as HUMA-1).

## Reaching the thinking session

The thinking session runs in Herdr pane `w3M:p1` and can take a message there, but it may be settled by the time you ask. Decide open questions yourself from the documents above, and list each decision you take alone in the pull request's "Things to be aware of".

## Suggested skills

- `orchestrate-with-handoff` / `orchestrate-effort` and `orchestrating`: run the effort.
- `implement` and `tdd`: what each delegate follows for its ticket.
- `swift-lab`: "Apply a winner", to turn a final variant's code into Havooch code.
- `write-swift`: Swift 6 concurrency for the windows, listener hub and compare player pair.
- `low-level-design`: when a ticket updates `docs/low-level-design.md`.
- `to-pr`: the pull request. `shipyard`: pings for QA.
- `settle-effort`: after the maintainer approves the merge.

## Progress (paused 2026-10-08 by the maintainer)

The maintainer paused all agent work because video sound reached their meeting. Resume only when they say so.

- **Landed and pushed** on `effort/projects-and-onboarding` (tip `01596af`): #81, #82, #83, #84, #85, #86, #88. Closed: #81, #84, #85, #86, #88. Open with one unticked criterion each: #82 (cold start needs the installed app), #83 (real Finder, Dock and `open -a`, confirmed by QA #96).
- **Stopped mid-build:** #87. Its uncommitted work is in the worktree `/Users/yahyabedirhanpak/Developer/yahyabedirhan/havooch/.claude/worktrees/agent-a626acca04fa77664` (branch `worktree-agent-a626acca04fa77664`, base `e86cff8`). It had reached the CLI and wire tests. A resumed delegate continues from that worktree.
- **Next after #87:** #89 and #92 in parallel, then #90, #91, #93, #94, then #95.
- **Delegate brief:** `.scratch/orchestration/delegate-brief.md` in this worktree. Running PR notes (decisions, surprises, times per ticket): `.scratch/orchestration/pr-notes.md`. Both are ignored files; read them before delegating.
- **Silence rules (maintainer):** no agent launches, opens or plays a Havooch. Delegates verify with tests only. Treat `make test` as possibly audible, because app-model tests play the fixture videos: run it only when the maintainer allows sound. #106 tracks a muted mode; do not build it in this effort.
- **Installs (maintainer, decision D1):** no `make install` during the build. After every build ticket lands, run one final check: install, `scripts/acceptance.sh` end to end, and #82's cold start. That install quits the maintainer's running Havooch, which is accepted then.
- **Integration lessons:** delegate worktrees start from `main`, so each delegate first runs `git reset --keep origin/effort/projects-and-onboarding`. Design rows in `docs/low-level-design.md` are taken up to L55; renumber clashes at integration. `havooch app open` quits every running copy of the app, so no check uses it.
- A worktree from #81 (`agent-aa841231a4fdf5004`) is kept because a sourcekit-lsp process held it; `/settle-effort` releases it.
