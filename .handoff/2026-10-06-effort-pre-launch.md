# Handoff: effort pre-launch

From a havooch session on `main` in `~/Developer/yahyabedirhan/havooch`, 2026-10-06. That session runs in Herdr workspace `w2T`, tab `CC #2`, pane `w2T:p2`. It can be reached with `herdr agent prompt` while it lives, but decide open questions yourself and list them in the pull request.

## Where

- Worktree: `~/.treehouse/havooch-1247ba/1/havooch`, leased with treehouse (holder `pre-launch`, lease id `958aefe721dc71f099cd050990ecd411`).
- Branch: `effort/pre-launch`, cut from `main` at 7e9b9d2.
- Effort label: `effort:pre-launch`.

## What to build

Agent work that can land before the public launch. There is no spec issue: the tickets are complete on their own, and each one names its parent.

| Ticket | What |
|---|---|
| #52 Player: Let Space press a focused button | key handling in the player |
| #59 Chore: Record the sample video again with the name Havooch | new `fixtures/sample/` and the tests that quote it |
| #62 Launch: Fix the image sizes, unused shots and alt text of the landing page | leftovers from #58 in `site/` |

None blocks another. #59 and #52 both run `make test`; #59 also needs the explainer studio (`make-explainer` skill).

The branch also carries one commit from this session: the new `Launch` title prefix in `docs/agents/issue-tracker.md`.

## Decisions already made by the maintainer

- The launch steps in #56 (`Launch: Launch Havooch publicly`) are the maintainer's. Do not make the repository public, touch Pages, create the tap or push a tag. #49, #50 and #56 stay `ready-for-human`.
- The home page keeps the pixel isometric drawing. The demo video is later work in #60, on the studio page. Do not do it here.
- Developer ID signing is later work in #61. Do not do it here.
- The copy of the site stays as it is; the maintainer does the copy pass (#56 step 3). #62 changes no copy except alt text.
- The git history stays; no squash.
- Ask the maintainer before merging the pull request.

## Not in scope

- #46, #47, #48 (`needs-triage`), #34 and #45 (hand QA), and the claude-mods session in Herdr workspace `w23`.

## Suggested skills

- `orchestrate-effort`, `orchestrating`, `implement` for delegates.
- `make-explainer` for #59.
- `write-swift` and `tdd` for #52.
- `treehouse` for delegate worktrees, `code-review` and `to-pr` at delivery.
