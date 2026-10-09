# Handoff: follow-ups after Havooch 0.5.1

## Where you are

- Worktree: `/Users/yahyabedirhanpak/.treehouse/havooch-1247ba/2/havooch`, leased with treehouse.
- Branch: `chore/followups-0.5.1`, cut from `main` at b92ed82. It holds only this handoff.
- Main checkout: `/Users/yahyabedirhanpak/Developer/yahyabedirhan/havooch`. Don't build or commit there. Its `.scratch/` folder holds the files named below.
- This isn't an effort: there's no spec and no tickets. The work is three open issues.
- Nothing can reach you, and you can't reach the session that wrote this. Decide open questions yourself and list them in each pull request.

Read `AGENTS.md` before you start. Pay particular attention to these rules:

- Build and test only through the `Makefile`.
- For a visual check: take the lease, then set `HAVOOCH_SUPPORT_DIR` to a scratch folder and `HAVOOCH_MUTED=1` for `make install` and every `havooch` command.
- Commit messages are lowercase Conventional Commits and end with a `Co-Authored-By:` line. Never add a `Claude-Session:` line or a session link.
- Never use an em dash, an en dash or a spaced hyphen in app copy.

## State after 0.5.1

Havooch 0.5.1 is released and verified. `main` is clean at b92ed82. Treehouse slot 1 belongs to another session (`feat/run-command-box`). Leave it alone. Also leave alone the local branches `feat/launch-demo-video` and `fix/skill-install-progress`.

## What to do, in this order

### 1. Finish #161: retake two Swift Lab screenshots

#161 is "Chore: Pin a current-app variant of every stale Swift Lab component". Every component in the `havooch` Swift Lab project now has a pinned variant that matches `main` at b92ed82. Screenshots are in `.scratch/lab-161/` in the main checkout, `<session>-<component>-<label>-{light,dark}.png`.

Two screenshot pairs are wrong:

- `project-versions` › `version-switcher` › `V6`: the picker popover shows twice, with a second copy offset behind it. The light shot is also cut off on its left edge, and its size differs from the dark one.
- `project-versions` › `compare-control` › `V5`: the Compare popover shows twice in the same way.

The other five that were retaken on 2026-10-09 look right: connect-view V4, connect-flow V7, first-run V4, thread-list V6 and player-window V2.

Steps:

1. Read the script `.scratch/lab-161-kit/isoshot.sh` in the main checkout.
   - It shoots a variant from an isolated copy of the lab at `.scratch/lab-161-iso`, so the maintainer's open Swift Lab windows are never driven.
   - Usage: `zsh <main checkout>/.scratch/lab-161-kit/isoshot.sh <session> <component> <label>`.
2. Find the cause of the doubled popover.
   - It may be a capture problem: a real popover window captured together with the inline copy, or a runner window left over from an earlier shot.
   - It may also be in the variant's own code: look in `~/.local/share/swift-lab/projects/havooch/sessions/project-versions/components/<component>/<label>/`.
   - Use the `swift-lab` skill for the `swiftlab` CLI.
3. Fix the variant or the capture, then retake both pairs. Look at each PNG yourself.
4. If you change a variant, make sure it still matches `main` and stays kept (pinned).
5. Close every runner of the isolated lab when you finish: `scripts/isolate.sh <iso> -- swiftlab session close <session> --project iso`, from the swift-lab checkout at `~/Developer/yahyabedirhan/swift-lab`.
6. Comment on #161 with the result, then close it.

Don't touch the maintainer's own Swift Lab sessions or windows. Only the isolated lab copy may be driven.

A known flaw in the lab copy, not the app: connect-view V4's "Reconnecting" state shows "62.300.633.316 s", because the sample data uses a far-past date. Fix the sample date if it is quick. Otherwise leave it.

### 2. Build #164 and open a pull request

#164 is "Chore: Keep decision numbers out of code comments". A subagent of the closed session was given this, but no branch or pull request exists. Treat it as not started.

1. Cut a branch from `origin/main` in this worktree, for example `chore/no-decision-numbers-in-comments`.
2. Do the steps in the issue: add the project instruction to `AGENTS.md`, say decisions live in `docs/decisions/`, and remove decision numbers from code comments.
3. Keep the meaning of each comment. Say in words what the decision was.
4. Run `make test`.
5. Open the pull request with the `to-pr` skill. Don't merge it.

### 3. Build #159 and open a pull request

#159 is "Player: Keep the stage and the sidebar whole in a narrow window" (`bug`, `ready-for-agent`). The window's minimum width is 760 pt, but the stage needs 480 pt plus the sidebar's 300 to 460 pt. Between those widths, both columns are clipped.

1. Cut a branch from `origin/main`, for example `fix/narrow-window`.
2. Pick one fix as the issue asks: the sidebar shrinks to its minimum, or it hides by itself, like macOS split views. Record the pick as a new L decision in `docs/low-level-design.md`.
3. Test what you can with `make test`. Check the result through app control (`make install`, `havooch app open --demo`, resize, `screenshot`), with the lease, the scratch support folder and muted sound.
4. Open the pull request with the `to-pr` skill, with before and after screenshots. Don't merge it.

## Not yours

These need the maintainer. Don't start them:

- #160 "QA: Check the 0.5.x controls by hand".
- Choosing among #158 (crowded header), #156 (screenshot badge), #144 (transcript in the sidebar), #50 and #56 (landing page and launch).
- #162, #163 and #165 are newer issues, and nobody has picked them yet.

## When you finish

1. Push each branch.
2. Return the treehouse slot with `treehouse return /Users/yahyabedirhanpak/.treehouse/havooch-1247ba/2/havooch` once its branches are pushed and it is clean.
3. Notify the maintainer: `shipyard notify "<what is ready>" --from codex`.
4. Name the two pull requests and say whether #161 is closed.
5. List the choices you made and anything only the maintainer can do.
