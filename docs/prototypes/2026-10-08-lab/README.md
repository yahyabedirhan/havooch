# The final prototypes to build from

These are the Swift Lab variants the maintainer chose for `Spec: Projects, windows and agent onboarding` (#79). Build from their **code**, not only from the screenshots: copy it into Havooch, rename it to Havooch's names, wire it to the real models, and add the logic. Change it as much as the build needs. The maintainer liked these UIs; keep their look and behaviour unless a ticket says otherwise.

The code here is a copy from Swift Lab (`yahyabedirhan/swift-lab` at `ccb82cb`), so it is in the repository for every agent. The live sessions are on the maintainer's Mac under the lab root, project `havooch`: run `swiftlab show <session> <component> <variant> --project havooch` to see one running.

## The finals

In Swift Lab each final has the keep pin and a title that starts with "Final:".

| Builds | Session | Component | Final variant | Code here | Ticket |
|---|---|---|---|---|---|
| Project thread list | `project-versions` | `thread-list` | **V5** "Final: Jump menu" | `project-versions/thread-list-V5/` | #94 Thread: Group threads by version in the thread list |
| Version switcher | `project-versions` | `version-switcher` | **V5** "Final: Recent plus picker" | `project-versions/version-switcher-V5/` | #93 Player: Switch versions from the header |
| Compare control and compare stage | `project-versions` | `compare-control` | **V4** "Final: Live search picker" | `project-versions/compare-control-V4/` | #95 Player: Compare two versions side by side, with a flip or a slider |
| Connect view: the whole flow in a window (entry points, header buttons, tour button, outbox banner, connected, reconnecting) | `agent-onboarding` | `connect-flow` | **V6** "Final: Step timeline, optimistic copy" | `agent-onboarding/connect-flow-V6/` | #89 Mate: Connect an agent from one view, from the pill, Send and the header |
| Connect view: every state of the sidebar view, side by side | `agent-onboarding` | `connect-view` | **V2** "Final: Every state" | `agent-onboarding/connect-view-V2/` | #89 (the same view as connect-flow V6, drawn per state) |
| First-run window (first launch) | `agent-onboarding` | `first-run` | **V1** "Final: Step wizard (first launch)" | `agent-onboarding/first-run-V1/` | #90 Mate: Show a first-run window and guide the first demo |
| Tour (coach panel and rings) | `agent-onboarding` | `first-run` | **V3** "Final: Learn by doing (the tour)" | `agent-onboarding/first-run-V3/` | #91 Mate: Offer the setup tour from Finish setup |

Changes the maintainer asked for after a final was built, which the code may not show everywhere:

- first-run V3: use it only as the tour, opened from "Finish setup"; take the ring padding (about 9 pt) and the step-timeline look from connect-flow V6.
- connect-flow V6 is the reference for every look rule: `accentFill` buttons, no one-sided edges, "Not detected" in place of ✕, copy boxes with Copy in a footer, the prompt per harness, no dashes in copy.

## Not to build from

Everything else in the two sessions is history. Do not build from it.

| Session | Component or variants | Why |
|---|---|---|
| `agent-onboarding` | `listener-area` (all) | Replaced by connect-flow: one Connect view in the sidebar, not a popover or footer panel. |
| `agent-onboarding` | `send-without-listener` (all) | Replaced by connect-flow: Send with no listener opens the Connect view with the outbox banner. |
| `agent-onboarding` | `setup-view` (all) | Replaced by connect-flow: setup is part of the Connect view, not separate menu items or a window. |
| `agent-onboarding` | `first-run` V2 | Rejected (one-page checklist). |
| `agent-onboarding` | `connect-flow` V1 to V5 | Earlier rounds; V6 carries their chosen experience (V1) and look (V4). |
| `agent-onboarding` | `connect-view` V1 | Replaced by V2. |
| `project-versions` | `thread-list` V1 to V4, `version-switcher` V1 to V4, `compare-control` V1 to V3 | Earlier rounds; the finals carry their chosen parts. |

## Turning lab code into Havooch code

Follow the swift-lab skill's "Apply a winner":

1. Read the final's folder here, and its `context/` sources in the Swift Lab session for the Havooch commit it started from.
2. Copy the view code into Havooch's own structure and names, as the low-level design (`docs/low-level-design.md`) places it.
3. Remove the lab parts: `import LabHost`, the `public let variant = LabVariant …` line, `LabWindow`, `.labID` (use Havooch's own identifiers), and the "Lab fixture" strips and simulate buttons.
4. Replace fixtures with Havooch's models: `Review`, `ProjectEntry`, `SetupReport`, the window's `ListenerQueue`.
5. Replace hard-coded colours with Havooch's `Palette` tokens, including `accentFill`.
6. Build and test with `make test`, and name the session, component, variant and lab commit in the commit message.
