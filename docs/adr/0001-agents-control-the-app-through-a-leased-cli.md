# Agents control the app through a leased CLI

Agents are users of Havooch from the first build, not only testers. Every action a person can take in the app, an agent can take through the `havooch` command line, and the app enforces that one agent at a time drives it. The design is Shipyard's app control (`yahyabedirhan/shipyard`, ADR 0006 and ADR 0007), adapted to a video player.

## The wire

- The app listens on a Unix stream socket, `control.sock` in `~/Library/Application Support/Havooch/`, mode 0600. It exists only while the app runs.
- One request per connection. The client writes one JSON object and shuts down its write side; the app answers with `{ok, output, error, lease?}`.
- Every request carries `version` and `holder`. A request of another version is refused, naming both versions, so a CLI from another build is told to reinstall.
- The CLI ships inside the app bundle at `Contents/Helpers/havooch`.

## Two roles

- An **operator** drives the UI: open a video, play, pause, seek, write a message on a frame, a region or a thread (what the person does in the comment popover or the sidebar's composer), show the thread list or a thread view, send the queue, answer a question, set the theme, take a screenshot. Every operator command needs the lease.
- A **listener** receives sends and answers on their threads: `wait`, `ack <send-id>`, `status <message-id> working|done|failed`, `reply <thread-id>` and `ask <thread-id>`. It needs no lease: a person watches and writes while a listener works, and the two must not fight. One listener at a time is enough. The listener's session name tells the app its agent harness ("Claude Code", "Codex CLI"), and the app shows that harness's logo on the agent's messages, the presence pill and the notices; no flag says it (0.2.0, #38).
- Free commands: `app status`, `state --json`, `control take`, `control release`, `theme list`, and the listener commands.

## The lease

Shipyard's rules, unchanged:

- The first operator command takes the lease and each later one renews it. It ends one minute after the holder's last command, and five minutes after it was taken at most.
- `control take --wait <seconds>` holds it for a longer run and queues agents first come, first served. `control release` ends it.
- The CLI works out the holder on every call: `CLAUDE_CODE_SESSION_ID` when exported, otherwise the nearest ancestor process that isn't a shell (pid plus start time). `HAVOOCH_CONTROL_KEY` overrides both.
- A command from another holder is refused with exit 1, naming the holder and when the lease ends.
- While an agent holds the lease the app shows the agent-control icon in the header, left of Context. Its popover names the agent, where it runs and the time left, and has Stop. The person's Stop ends the lease and bars that holder for five minutes. The person always wins.
- The lease rules are a pure value in an agent-side module, given the time on each call, so they test without the app.

## Demo mode and screenshots

- `app open --demo <folder>` runs the app on a separate support folder and writes a pointer so later commands reach the demo's socket. Plain `app open` removes the pointer and returns to the person's own data.
- `screenshot <abs.png> [--appearance light|dark]` captures only the app's own window through ScreenCaptureKit.
- Accessibility and System Events stay closed to agents. The CLI is the only way in.

## Beyond the spec

The 0.1.0 build added these to the commands the spec names, so an agent can reach every state of the UI for a check or a screenshot:

- `comment open [<text>] [--region x,y,w,h]` opens the popover at the player's frame, as C or a drawn rectangle does.
- `thread open <thread> [--frame x,y,w,h]` opens a thread's popover on its frame, first kept at `--frame` when given.
- `thread show <thread>` shows a thread's view in the sidebar and pauses the player on its frame, as a click on its row does. `thread list` shows the thread list, as Back does. The 0.2.0 build replaced 0.1.0's `thread expand <thread>` with them (#39). `state` names the thread the sidebar shows in `sidebar.thread`, or `null` for the list.
- `comment compose [<text>] [--region x,y,w,h] [--general]` puts words, a region chip on the player's frame and the General toggle in the composer at the sidebar's foot, as the person types, draws and clicks (#42). `state` reports the composer in `sidebar.composer`, its `target` the line it shows, such as "New thread at 0:12" or "Answer #1 · goes at once".
- `screenshot --hide-agent-indicator` leaves the agent-control icon out; by default it shows, as the person sees it.
- `screenshot --window settings` captures the Settings window: it opens it as ⌘, does and closes it again when it was closed before. The 0.2.0 build added it (#43).
- `theme set system` unpins the theme, so it follows the system appearance.
- A thread is named by its id or by its bare number on the open video (`3`, `0` for General).
- `wait` keeps reconnecting while the app is not running.
- Exit code 2 means a timeout ran out (`wait --timeout`, `ask --wait`), with nothing printed.

## Modules

The code splits by concern. The agent-side modules (command line, wire, lease, listener client) never link the app's rules, and build and test without the app. Only the app target is macOS UI code.

## Considered Options

- **Playwright on an Electron build.** Agents could drive a web UI, but the product is a native player; the CLI gives the same reach to the real app.
- **Accessibility scripting.** Fragile, needs a permission grant, and lets an agent click anything. The CLI exposes exactly the product's actions.
- **A plain lock.** A crashed agent would hold the app. A lease ends by itself.
- **The listener under the lease.** The listener runs for the whole session beside a person; leasing it would lock the person out.

## Consequences

- A new UI action is not done until its CLI command exists.
- Tests drive the installed app through the CLI with the fixture video in demo mode.
- An agent writing its own socket client could skip the lease. That's out of scope, as in Shipyard.
