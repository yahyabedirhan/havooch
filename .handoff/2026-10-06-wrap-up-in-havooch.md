# Handoff: wrap up Havooch from one session

This handoff adds to `.handoff/2026-10-06-wrap-up.md`. Read that one first. Everything in it still holds, except where this file changes it.

## Where you are

- **Checkout:** `~/Developer/yahyabedirhan/havooch`, a fresh clone of `yahyabedirhan/havooch`, on branch `chore/wrap-up`. This is the maintainer's main checkout of the renamed repository. Make worktrees with `treehouse` when you need them, so this checkout stays usable.
- **Herdr:** your workspace is the new `havooch` workspace. The maintainer made it to group all the wrap-up work in one place.
- **Old clone:** `~/Developer/yahyabedirhan/video-review` is the clone under the old name. Its worktrees under `.claude/worktrees/`, and the treehouse pool `~/.treehouse/video-review-*`, hold the earlier sessions' work. Inspect them from disk.
- **The session that handed over** ran in `~/.treehouse/video-review-1247ba/1/video-review`, treehouse lease holder `havooch-wrap-up`, lease id `d55cec3989cc41bcf142809eca4259c2`, on `chore/wrap-up`. It stopped after the handover and made no other changes. Its worktree is clean and pushed, so return that lease once you no longer need it. Don't message that session.

## What the maintainer added

The project started as `video-review`. The maintainer worked on it on their Mac and on their Netcup VPS, then renamed it Havooch (from Turkish "havuç", carrot). They want one session, this one, to finish everything.

1. **Leave the old Herdr workspaces as they are.** Workspaces that still show the `video-review` name stay open, with their names unchanged. Don't close or rename them, and don't type into their panes.
2. **Don't wake or wait for the other sessions.** Their conversations are no longer cached, so every message to them costs the maintainer a lot of tokens. Don't send them prompts, questions or `herdr` input, and don't wait for them to finish. Work out what each one did from git, the worktrees on disk, `.handoff/`, `.scratch/`, issues and pull requests. This replaces the earlier handoff's step "find out whether that session is still live (Herdr pane `w2M`)": treat every other session as finished.
3. **Make sure no unfinished work is left in the other sessions.** For each worktree and branch, on the Mac and on the VPS: find work that `main` lacks. Then merge it, carry it into this branch, record it as an issue, or confirm that it is not needed. Uncommitted edits from another session, such as the `AGENTS.md` and `docs/agents/issue-tracker.md` diff in `~/.treehouse/video-review-14a6ef/7/video-review`, are yours to judge from the diff. Ask the maintainer before you commit or drop them.
4. **Settle everything at the end.** Free the worktrees and leases that are proven merged or empty, after the maintainer says yes to the list. Then settle this session.

## The VPS

Earlier sessions also worked on the Netcup VPS. Global instructions say: ask before SSH, and reach the remote machines through their saved Herdr machine, in a new Herdr workspace of their own, never plain SSH. Ask the maintainer once before you inspect the VPS, and look there only for `video-review` or `havooch` clones, worktrees, branches and handoffs that hold unpushed or unmerged work.

## Open decisions for the maintainer

Ask these early in your tab, each with your recommendation. The maintainer can reach you there.

- Promote the storybook prototype to the public `site/` page (earlier handoff, "The landing page").
- Keep or remove the `.handoff/` files before the repository goes public. They hold local paths.
- The other session's uncommitted `AGENTS.md` and `issue-tracker.md` edits.
- The list of branches, worktrees and pull requests to close or delete.
- Merging your wrap-up pull request.

## Suggested skills

- `herdr` for the new VPS workspace. Use it only to read, never to type into old panes.
- `treehouse` before you return or destroy any worktree, including the lease above.
- `to-pr` for the wrap-up pull request, and `code-review` before you ask for its merge.
- `set-up-project` to audit the project's agent setup.
- `settle-session` at the end, after the maintainer approves the merge.
