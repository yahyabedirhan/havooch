# Handoff: make the General toggle look like a button

## The work

Build ticket **Thread: Make the General toggle look like a button and show a hover state** (#74, https://github.com/yahyabedirhan/havooch/issues/74), then open a pull request. The ticket holds the problem, the steps and the acceptance criteria. This is not an effort, so there is no spec beyond the ticket.

- Worktree: `/Users/yahyabedirhanpak/.treehouse/havooch-1247ba/1/havooch` (treehouse lease holder `general-toggle`).
- Branch: `fix/general-toggle-affordance`, cut from `main` at `7e21419`. It is pushed with this handoff.
- The maintainer's screenshot of the problem: `.scratch/01-general-toggle.png` in this worktree (ignored, not committed).

## Where it came from

The maintainer used Havooch 0.3.0 in a real review and gave live UX feedback. The General toggle (globe + "General", at the right of the composer header at the foot of the sidebar) has no background when off and no hover state, so they could not tell that it is clickable. The code is `GeneralToggle` in `Sources/ReviewApp/UI/Sidebar/Composer.swift`. The sidebar's hover pattern lives in `ThreadRow.swift`, `MessageBubble.swift` and `QuickReplies.swift` (`@State isHovered`, `.onHover`, `palette[.controlHover]`, `.smooth(duration: 0.12)`).

## How to work

- Work autonomously. The maintainer asked for a delivered pull request, not questions. Decide open design questions yourself, and list them in the pull request's reviewer notes.
- You can't reach the session that handed over. Don't wait for it.
- Follow `AGENTS.md`: build and test through the `Makefile`, check the visual change through app control (`make install`, the `havooch` CLI, `screenshot`), and take the lease before `make install` and release it at the end.
- Set `HAVOOCH_SUPPORT_DIR` to a folder in this worktree's `.scratch/` for `make install` and every command. **Another QA session is live** on `/Users/yahyabedirhanpak/Developer/yahyabedirhan/havooch/.scratch/qa-live`, with a listener agent attached. `make install` replaces `/Applications/Havooch.app` and relaunches it. Wait for the lease (`havooch control take --wait`). After your checks, reopen the app on the QA folder with `HAVOOCH_SUPPORT_DIR=/Users/yahyabedirhanpak/Developer/yahyabedirhan/havooch/.scratch/qa-live havooch app open`, then `havooch player open` on `.scratch/qa-live/videos/halcyon-teaser.mp4` in that folder. That way the maintainer gets their session back.
- Take screenshots with the toggle off and on, in Default Light, Default Dark and Tokyo Night. Keep the ones worth showing in `assets/screenshots/general-toggle/` and link them from the pull request.
- Leave the hover check to the maintainer (it needs a real pointer), and say so in the pull request.
- Update `docs/low-level-design.md` only if the code moves away from it.
- Commit message: `fix(comment): ...` or `fix(thread): ...`, lowercase, in the repo's convention, with `Closes #74` in the pull request.
- Open the pull request with the `to-pr` skill. Don't merge it.

## Suggested skills

- `implement`: build the ticket.
- `write-swift`: SwiftUI changes.
- `apple-design`: hover feedback and affordance that feels native.
- `to-pr`: open the pull request.
