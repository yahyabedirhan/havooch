# A window holds one video or one project, with one listener

The person can open any number of windows, as in VS Code. A new window starts empty and shows the home screen; the person opens a video or a project in it. Each window has its own listener, so two agents can work on two projects at the same time. This replaces the 0.3.0 decision to keep one window with a home screen (#72).

## Decision

- **Any number of windows.** ⌘N opens an empty window. Opening a video or a project that is already open in a window brings that window forward instead of opening it twice.
- **One thing per window**: either one plain video or one project (ADR 0004), never both and never two.
- **One listener per window.** A listener waits for the sends of one window: `havooch wait --video <path>` or `havooch wait --project <slug>`. A newer `wait` for the same window replaces the older one, as before.
- **The copied prompt names the window's video or project**, so the agent that pastes it listens to the right window: `/havooch-mate listen for my feedback on launch.mp4`.
- **The listener card, the presence pill and the outbox are per window.**

## Considered Options

- **One window, switching between videos (0.3.0).** One agent for everything; the maintainer wants parallel agents on parallel projects.
- **One window per project, plus one shared window for every plain video.** Two rules where one is enough.
- **One listener for the whole app.** Simple, but every video's feedback would reach the same agent.

## Consequences

- The listener protocol changes: `wait` and the send payload name their window's video or project. The `havooch-mate` skill changes with it.
- Window restoration, the home screen and the recent list must work with several windows.
- An agent that listens with no `--video` or `--project` needs a defined meaning in the spec.
