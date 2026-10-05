# wire

The developer-tool direction, centred on the agent's side of the loop. The hero pairs the headline with a terminal that plays one send as the listener sees it (`havooch wait`, the JSON, `ack`, `status`, `reply`, `ask`). Then both ends of the wire side by side: what you do in the player on the left, the command the agent runs on the right, with a packet travelling the wire between them. Then the full send as JSON, the command line in two lists, install and the name.

## Design plan

- Colour: blueprint paper `#eef1f6` with a faint 32 px grid, ink navy `#15213a`, steel `#4b5873`, carrot `#f37a1f`, signal green `#2f9e6b` for the person's answer, and a terminal `#0f1626` that stays dark in both schemes. Dark mode is the same navy family on `#0b1020`.
- Type: IBM Plex Sans for people, JetBrains Mono for everything the machine says. The mono carries content (commands, JSON), not labels.
- Layout: a 11/13 hero split; a three-column lane grid (you, the wire, the agent) that collapses to one column on phones with the agent's command under each step; a 5/7 split for the send.
- Principle: show the real mechanism. Every claim on the page has a command next to it.

## Assets

`logo.svg` is a copy of `assets/images/logo/v2-havuc/havooch-mark.svg`. Fonts from Google Fonts. Command names and exit codes follow `Sources/ReviewCommand` and the mate skill; the page writes them as `havooch`, the command's name after the rename.

## Method

Built following the `frontend-design` skill from [anthropics/skills](https://github.com/anthropics/skills) at commit `683bc88e56f3e09ba94f7055977f3d3aa499f202` (`skills/frontend-design/SKILL.md`). Checked with headless Chromium at 1440 and 390 px in light and dark: no horizontal scroll, no console errors. Previews in `preview/`.
