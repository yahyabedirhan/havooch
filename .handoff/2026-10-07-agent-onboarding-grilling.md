# Handoff: grill the agent onboarding requirement

## The work

Start the **agent-onboarding** effort from its requirement, **Mate: Make opening a video and connecting any agent simple for new users** (#76, https://github.com/yahyabedirhan/havooch/issues/76). Read the issue body and its comment first. They hold the loop, the problems found, the harness list and the possible work. This handoff doesn't repeat them.

- Worktree: `/Users/yahyabedirhanpak/.treehouse/havooch-1247ba/2/havooch` (treehouse lease holder `agent-onboarding`).
- Branch: `spec/agent-onboarding`, cut from `main` at `ad17907` (after the General toggle merge, #75).
- Label: `effort:agent-onboarding` already exists. The issue carries it with `needs-triage`.
- Role: a **thinking** session. The maintainer is present and wants to be grilled before anything is written.

## What to do next

1. Grill the maintainer on #76 with the `grilling` skill, one question at a time. Start with the decisions the issue leaves to the spec, under "Possible work". Settle the scope too: which harnesses are in the first build, and which only get a QA ticket.
2. Check facts in the code instead of asking about them: `Sources/ReviewLease/Holder.swift`, `Packaging/Info.plist` (document types), the `havooch` command's usage, `.agents/skills/havooch-mate/SKILL.md` and `docs/adr/0001-agents-control-the-app-through-a-leased-cli.md`.
3. When the grilling settles, write the spec with `to-spec` (title `Spec: ...`), then the tickets with `to-tickets`. Give every ticket `effort:agent-onboarding`, and add one QA ticket for each harness for the maintainer's live QA, as #76 asks.
4. Record new terms in `GLOSSARY.md` and lasting decisions as ADRs (`domain-modeling`).

Don't build anything in this session. The build is a later handover to an orchestrator.

## What this session knows that the issue doesn't

- **Live QA works best when the agent prepares the app and the maintainer only looks and plays.** The maintainer said so: "you have control and you have access to the application... update the application state in a way that I can just look at, verify, and play around with it". Plan the effort's QA tickets this way, not as step lists the maintainer runs alone.
- The live session ran the app on a scratch data folder, `/Users/yahyabedirhanpak/Developer/yahyabedirhan/havooch/.scratch/qa-live` (main checkout, ignored). The app still runs on it, with the new launch video from the explainer studio open. That is how the `HAVOOCH_SUPPORT_DIR` problem in #76 showed up: each new agent had to be told the folder.
- The current listener is a Claude Code session in the explainer studio worktree (`/Users/yahyabedirhanpak/.treehouse/explainer-studio-404ae0/1/explainer-studio`). Its background `havooch wait` is still open. The first listener, the agent `mate` in the havooch workspace (pane `w2T:p5`), is idle and has no `wait`. Leave both alone. The maintainer ends them.
- The older QA tickets #34 and #45 are closed, because the live session replaced them. `QA: Check the 0.3.0 window and home screen by hand` (#73) stays open. Some of its checks (Open With, the Dock) overlap with "open a video in one step" in #76. Decide in the spec whether the effort takes them over.

## Suggested skills

- `grilling`: the first step.
- `domain-modeling`: terms and ADRs that come out of the grilling.
- `to-spec`, then `to-tickets`: when the grilling settles.
- `codebase-design`: if the grilling reaches the CLI or lease interfaces.
