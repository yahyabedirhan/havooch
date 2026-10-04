# video-review

A native macOS video player for giving feedback to agents. You pause any video, or draw a region on its frame, and comment. Comments queue up and Cmd+Enter sends them as one batch to a listening agent session, with the timestamp, the keyframe, the region and the transcript around that point. The agent answers inside the player.

The v1 spec is a GitHub issue titled `Spec: Video Review v1`. Read it before building anything.

## Git, Commits, And Pull Requests

- Opening a pull request, or changing an existing one's description, goes through the **to-pr** skill.
- Issue and pull request numbers belong in commit messages, pull requests and docs. Code, comments and test names say what they mean in words.

Use lowercase multi-line commit messages with a Conventional Commits type on the subject line:

```text
type(scope): what changed

- explanation 1
- explanation 2
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`. Scope is optional and names the area (`player`, `comment`, `mate`, `control`, `transcript`, `adr`, `skill`).

## Folder Layout

```text
.handoff/<date>-<topic>.md     tracked   handoffs between sessions
assets/images/<topic>/         tracked   images the project uses
assets/screenshots/<topic>/    tracked   screenshots worth keeping, linked from issues, pull requests and docs
fixtures/                      tracked   the sample video and its sidecars for tests and demo mode
.agents/skills/<name>/         tracked   the project's skills; `.claude/skills/<name>` is a link to each, for Claude Code
.scratch/                      ignored   notes, logs, temp files and pull request description sources
.claude/worktrees/             ignored   sub-agent worktrees
```

## Design

Agent control follows Shipyard's design (`yahyabedirhan/shipyard`, ADR 0006 and ADR 0007), adapted here in `docs/adr/0001-agents-control-the-app-through-a-leased-cli.md`. Read it before touching the CLI, the socket or the lease.

`docs/low-level-design.md` is the design of this build, written with the `low-level-design` skill before the first build ticket. It is documentation for the maintainer to read later, not a review gate. Read it before adding or moving a module, and update it in the same change whenever the code moves away from it.

## Testing

Build and test with SwiftPM through the `Makefile` only; there is no Xcode project. `make test` runs the tests without driving the Mac. Check a visual change through app control: `make install`, then the `video-review` CLI (`app open --demo`, player and comment commands, `screenshot`). Take the lease before `make install` and release it at the end. Accessibility and System Events are not a way in; a check that needs a real click goes to the maintainer.

## Agent skills

### The listener skill

`.agents/skills/video-review-mate/` is the skill a Claude Code session in any repository uses to listen for batches and act on them. It is part of the product: it speaks only the CLI contract of the spec. Change it with the `writing-for-agents` skill, and keep `docs/low-level-design.md`'s section on it true.

### Issue tracker

Issues and specs live as GitHub issues in `yahyabedirhan/video-review`, handled with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels, each named after its role (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
