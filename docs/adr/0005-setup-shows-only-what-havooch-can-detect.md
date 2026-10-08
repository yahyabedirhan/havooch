# Setup shows only what Havooch can detect, and stays optimistic about the rest

To connect an agent, the person needs the `havooch` command and the `havooch-mate` skill in their agent harness, then pastes a prompt into it. Havooch cannot see the person's whole environment: a skill can be installed inside a repository, a harness can live anywhere. The maintainer's rule: state only what Havooch knows for certain, and never present an unknown as a failure.

## Decision

- **A positive sign only for what is detected.** Anything not detected reads **Not detected**, in a neutral style: never a cross, never "Not installed", never a warning colour.
- **Command line: Linked** means the link file exists in `~/.local/bin`. Havooch does not claim the agent's PATH reaches it.
- **Skill: Installed** means the skill folder exists in that harness's user skills folder (a global install). A skill installed in a repository cannot be detected; the view says so once, and says it still works there.
- **Harness found** is a best guess. A harness that is not detected can still be chosen.
- **Connected** is known only when an agent actually waits.
- **The prompt stays primary.** When something is not detected, the view still shows the prompt at full size: "If it's installed another way, paste the prompt and your agent will take it from there. If not, install it first."
- **Each harness gets its own prompt**, in its own skill invocation: Claude Code and Cursor `/havooch-mate listen for my feedback on <video>`, Codex `$havooch-mate …`, Pi `/skill:havooch-mate …`, OpenCode "Use the havooch-mate skill to listen for my feedback on <video>". Cursor's form is not verified yet; its live QA confirms it.
- **"Finish setup" leaves once an agent has connected** in the window, even when the skill was not detected: a real connection proves setup works. The maintainer confirmed it.
- **Installing the skill**: one click installs it globally for every harness found (`npx skills add https://github.com/yahyabedirhan/havooch/releases/download/v<version>/havooch-mate.tar.gz --skill havooch-mate -g`, the skill's archive in the app's own release); a per-repository install is a command to copy.

## Considered Options

- **Report not-detected as missing.** It would tell a person with a repository install that their working setup is broken.
- **Hide undetectable states.** It would leave the person without the next step.

## Consequences

- Every setup and listener state in the spec names how it is detected.
- The `havooch-mate` skill must handle a person who pastes the prompt with the skill missing in that harness: the agent then knows nothing of Havooch, which is the person's to fix.
