# Code assessments of the three prototypes

Three read-only agents assessed the prototypes on 2026-10-05, on the same rubric, after the round-1 rework was built and tested on the Mac. This is a summary of their reports. The branch tips assessed: `proto-1` at 69cb3c8, `proto-2` at af82f05, `proto-3` at b0ccd72.

| | proto-1 (#17) | proto-2 (#18) | proto-3 (#19) |
|---|---|---|---|
| Spec coverage | Nearly full. Gap: requeue only for a new listener key; no guard against a second listener session. | Fullest: requeue, presence, lease queue and Stop. | Nearly full. Gap: a comment sent before speech transcription ends gets no transcript lines. |
| Concurrency | Explicit `@MainActor`; 3 `@unchecked Sendable`; no `Mutex`. | Main-actor default isolation; 5 `@concurrent`; 2 `Mutex`; 2 `@unchecked Sendable`. | No default isolation; 2 `@unchecked Sendable` with NSLock and GCD; a blocking socket write; poll-based loading. |
| App layer | `AppModel` 581 lines, `ControlServer` 432, logic split into `ReviewDesk` and `ListenerQueue`. | `AppModel` 675, `ControlServer` 617 (the most fragile file), logic split into `ReviewDesk`, `ListenerQueue`, `TranscriptDesk`. | One `ReviewModel` of 957 lines and about 60 methods. |
| `make test` on the Mac | 322 tests, all pass, about 31 s. | 320 tests, all pass, about 27 s. | 416 tests, all pass, about 4 s. |
| Acceptance | 8 of 8 against the installed app. | Passes, per its PR. | 8 of 8 against the installed app. |
| Lease and ADR 0001 | Faithful; fixed the ADR's listener command names. | Faithful. | Faithful; `make install` refuses while another agent holds the lease. |
| Linux build | `VRCommand` does not build (AppKit launcher). | Every module except the app builds. | The agent-side modules build from a separate package. |

## What each design does better

- **proto-1:** the transcript window is cut at send time and kept on the batch; ids carry the video's hash prefix; `SupportLayout` owns every path; `Holder` lives in the lease module; `SocketListener` is apart from `ControlServer`; region-crop tests at several window sizes.
- **proto-2:** the Swift 6 concurrency model; logic and views in separate folders; Linux guards; the end-to-end acceptance script and a screenshot script.
- **proto-3:** the fastest and largest test suite; delivery-aware replies; `make install` checks the lease.

## The pick

proto-2 is the base for 0.1.0, with proto-1's design details ported into it. See [2026-10-05-decisions.md](2026-10-05-decisions.md), section A.
