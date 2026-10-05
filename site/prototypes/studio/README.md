# studio

A calm, premium product page in the native-Mac tradition. The hero is the real app window with four callouts that explain what is on screen; the loop is five moves on one hairline; the rest is real screenshots with one paragraph each, the install lines and the name in first person.

## Design plan

- Colour: paper `#ffffff`, fog `#f3f4f6`, ink `#16181d`, slate `#5b6270`, carrot `#f37a1f` (the mark, the callout pins, the primary button on hover) and the app's own region blue `#4a6fb5` for code keys and focus. Dark mode mirrors it on `#101114`.
- Type: Instrument Sans alone, 400 to 600, a tight display scale and a 17 px body.
- Layout: left-aligned, 1120 px max. Hero copy, the annotated window, the five-step strip, the payload with its JSON, alternating screenshot features, three facts, install, the name.
- Principle: the screenshots are the design; the page adds hairlines, air and words.

## Assets

Screenshots are the shared `site/assets/shots/*.webp` (light and dark pairs). `logo.svg` is a copy of `assets/images/logo/v2-havuc/havooch-mark.svg`. Instrument Sans from Google Fonts.

## Method

Built following the `frontend-design` skill from [anthropics/skills](https://github.com/anthropics/skills) at commit `683bc88e56f3e09ba94f7055977f3d3aa499f202` (`skills/frontend-design/SKILL.md`). Checked with headless Chromium at 1440 and 390 px in light and dark: no horizontal scroll, no console errors. Previews in `preview/`.
