# Handoff: effort agent-loop

From a havooch session on `main` in `~/Developer/yahyabedirhan/havooch`, 2026-10-06. That session settles right after this handover and cannot answer questions. Decide open questions yourself, within the tickets, and list them in the pull request.

## Where

- Worktree: `~/.treehouse/havooch-1247ba/1/havooch`, leased with treehouse (holder `agent-loop`, lease id `308f99a8e360dbb0cc02cd689e6dcc02`).
- Branch: `effort/agent-loop`, cut from `main` at c9ba6d2.
- Herdr: a linked workspace `agent-loop` under the `havooch` workspace.
- Effort label: `effort:agent-loop`.

## What to build

Three features of the agent loop. The maintainer wants them in the launch. There is no spec issue: each ticket is complete and names its parent, `Spec: Havooch 0.2.0` (#36).

| Ticket | What |
|---|---|
| #46 Mate: Offer quick-reply choices on an agent question | `ask` choices in the listener, chip buttons on the question, the `havooch-mate` skill |
| #47 Mate: Show what the agent does now | text on `status working`, a live line in the thread view and the footer, the skill |
| #48 Thread: Mark new agent replies as unread | a per-thread last-seen time, an accent dot on the row, kept across restarts |

None blocks another. #46 and #47 both change the listener protocol and the `havooch-mate` skill, so expect conflicts there at integration.

## Decisions already made by the maintainer

- These three tickets ship with the launch. #56 step 11 (the `v0.2.0` tag) waits for this effort to merge.
- The prototype branch `prototype/thread-ux` is deleted. #46 and #48 describe the design in their own text; follow it.
- Keyboard users are not a requirement. Space must still play and pause the video while watching (#52). Do not break it.
- Do not do the launch steps in #56: no public repository, no Pages, no tap, no tag.
- Deliver a pull request. Ask the maintainer before merging.

## Not in scope

- #49, #50, #56, #60, #61 (the maintainer's launch work), #34, #45 and #52 (hand QA).

## Suggested skills

- `orchestrate-effort`, `orchestrating`, `implement` for delegates.
- `write-swift` and `tdd` for the app and the listener.
- `writing-for-agents` for the `havooch-mate` skill changes.
- `treehouse` for worktrees, `code-review` and `to-pr` at delivery.
