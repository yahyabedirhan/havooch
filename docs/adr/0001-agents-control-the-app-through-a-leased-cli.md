# Agents control the app through a leased CLI

Agents are users of Video Review from the first build, not only testers. Every action a person can take in the app, an agent can take through the `video-review` command line, and the app enforces that one agent at a time drives it. The design is Shipyard's app control (`yahyabedirhan/shipyard`, ADR 0006 and ADR 0007), adapted to a video player.

## The wire

- The app listens on a Unix stream socket, `control.sock` in `~/Library/Application Support/Video Review/`, mode 0600. It exists only while the app runs.
- One request per connection. The client writes one JSON object and shuts down its write side; the app answers with `{ok, output, error, lease?}`.
- Every request carries `version` and `holder`. A request of another version is refused, naming both versions, so a CLI from another build is told to reinstall.
- The CLI ships inside the app bundle at `Contents/Helpers/video-review`.

## Two roles

- An **operator** drives the UI: open a video, play, pause, seek, draw a region, write a comment, send a batch, answer a question, take a screenshot. Every operator command needs the lease.
- A **listener** receives sent batches and answers them (`wait`, `ack`, `reply`, `ask`, `done`, `fail`). It needs no lease: a person watches and comments while a listener works, and the two must not fight. One listener at a time is enough for v1.
- Free commands: `app status`, `state --json`, `control take`, `control release`, and the listener commands.

## The lease

Shipyard's rules, unchanged:

- The first operator command takes the lease and each later one renews it. It ends one minute after the holder's last command, and five minutes after it was taken at most.
- `control take --wait <seconds>` holds it for a longer run and queues agents first come, first served. `control release` ends it.
- The CLI works out the holder on every call: `CLAUDE_CODE_SESSION_ID` when exported, otherwise the nearest ancestor process that isn't a shell (pid plus start time). `VIDEO_REVIEW_CONTROL_KEY` overrides both.
- A command from another holder is refused with exit 1, naming the holder and when the lease ends.
- While an agent holds the lease the app shows a banner. The person's Stop ends the lease and bars that holder for five minutes. The person always wins.
- The lease rules are a pure value in an agent-side module, given the time on each call, so they test without the app.

## Demo mode and screenshots

- `app open --demo <folder>` runs the app on a separate support folder and writes a pointer so later commands reach the demo's socket. Plain `app open` removes the pointer and returns to the person's own data.
- `screenshot <abs.png> [--appearance light|dark]` captures only the app's own window through ScreenCaptureKit.
- Accessibility and System Events stay closed to agents. The CLI is the only way in.

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
