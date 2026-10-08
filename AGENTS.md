# Havooch

Havooch is a native macOS video player for giving feedback to agents. You pause any video, or draw a region on its frame, and comment. Comments queue up and Cmd+Enter sends them as one batch to a listening agent session, with the timestamp, the keyframe, the region and the transcript around that point. The agent answers inside the player.

Each build has its spec as a GitHub issue titled `Spec: ...`. The app follows `Spec: Havooch v1` (#1), then `Spec: Havooch 0.1.0` (#20) and `Spec: Havooch 0.2.0` (#36), each one changing the one before. Read them, and the decisions in `docs/prototypes/`, before building anything.

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
.scratch/                      ignored   notes, logs, temp files and pull request description sources
.claude/worktrees/             ignored   sub-agent worktrees
```

## Design

Agent control follows Shipyard's design (`yahyabedirhan/shipyard`, ADR 0006 and ADR 0007), adapted here in `docs/adr/0001-agents-control-the-app-through-a-leased-cli.md`. Read it before touching the CLI, the socket or the lease.

`docs/low-level-design.md` is the design of this build, written with the `low-level-design` skill before the first build ticket. It is documentation for the maintainer to read later, not a review gate. Read it before adding or moving a module, and update it in the same change whenever the code moves away from it.

Never use the stacked-layers symbol (`square.stack.3d.up` and its variants) anywhere in the app or its prototypes. The maintainer rejected it.

Never use an em dash, an en dash or a spaced hyphen as punctuation in app copy. Write a full stop, a comma, a colon or two sentences instead, and "v1 to v47" for a range.

Never emphasise a box with a one-sided coloured edge: no left stripe, and no right, top or bottom stripe either. Use a full soft fill, an icon, or text weight and colour.

## Testing

Build and test with SwiftPM through the `Makefile` only; there is no Xcode project. `make test` runs the tests without driving the Mac. Check a visual change through app control: `make install`, then the `havooch` CLI (`app open --demo`, player and comment commands, `screenshot`). Take the lease before `make install` and release it at the end. Set `HAVOOCH_SUPPORT_DIR` to a scratch folder for `make install` and every command, so a check never opens the maintainer's data. Accessibility and System Events are not a way in; a check that needs a real click goes to the maintainer.

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues in `yahyabedirhan/havooch`, handled with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels, each named after its role (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
