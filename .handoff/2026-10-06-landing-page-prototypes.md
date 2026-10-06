# Handoff: five new landing page prototypes for Havooch

You build five new landing page prototypes for Havooch. Each one is a whole small site with three pages. Each one explores a new look and feel for the pixel-world home page. The maintainer reviews them in the browser and gives feedback in your tab. You are their contact for this work.

## Where things are

- **Worktree:** `/Users/yahyabedirhanpak/.treehouse/video-review-14a6ef/7/video-review`, detached at `a673701` (`main` after the launch PR #54). Another session shares this worktree. It has uncommitted edits to `AGENTS.md` and `docs/agents/issue-tracker.md`. Don't touch those two files.
- **Server:** `python3 -m http.server 8765` already serves `site/` from Herdr pane `w2M:p6`. Don't start another one. The prototypes are at `http://localhost:8765/prototypes/`.
- **Context:** read `AGENTS.md`, the landing page issue (#50, "Feature: Build a landing page for Video Review") with its comments, and PR #54's description (`gh pr view 54 --repo yahyabedirhan/havooch`). The repository is private. It was just renamed to `yahyabedirhan/havooch`.

## The reference prototypes

They live in `site/prototypes/`, beside `site/index.html` (the current landing page). Keep every one of them unchanged. They are references, not bases to edit.

- `pixel-world/`: **the starting point.** A lit isometric pixel diorama (`world.js`, drawn in code) of the loop, then "What happens in there": four scenes, each with a pixel sprite (Havuç sitting, Havuç walking with the satchel, the agent's robot, the envelope). Then "The unglamorous facts", install and the name. Dark blue night palette, Fraunces for display.
- `studio/`: a calm product page around the real screenshots in `site/assets/shots/`. It has an annotated hero window, "One loop, five moves" and features with screenshots.
- `wire/`: the developer-tool page. It has a terminal that plays one send, "Both ends of the wire", the send as JSON and the command line reference.
- `pixel-wire/`: a mix of the three. **The maintainer didn't like it. Ignore it.** Don't reuse its structure.
- `index.html`: the gallery of all prototypes with desktop and phone previews.

## What the maintainer said

These are their own words, condensed:

- "From Pixel World, I really, really like that animation, the pixel isometric animation that shows the cat, mate, and all the character explanations after." Keep the diorama and the four character scenes in every new prototype.
- "I want to explore the overall look and feel of the landing page itself. Currently it has a dark blueish background color and a font that shows the narration. I really like that version but I want to keep iterating... to show the same content but with a different look and feel."
- "Connect the other prototypes, the studio and Wire, using Wire as the CLI entry point now. Treat them as a whole single landing page application and it should work consistently and properly."
- Header inconsistency. In the earlier prototypes some header links smooth-scroll down the home page and others open another page. "That's creating inconsistency." Use a consistent flow: "a floating table of contents or sidebar-ish thing on the homepage", whose items scroll to the related section.
- Earlier in this conversation: "the other tabs will be more professional... same font we used in the pixel world, but instead of that pixel game analogy, they'll regularly explain how the terminal command line works, and on the other hand, how the studio works with screenshots." Page names: `/studio` and `/cli`.

## What to build

Build five prototypes in `site/prototypes/<name>/`. Give each a short, distinct name. Each prototype is one site:

| Route | Content | Source of the content |
|---|---|---|
| `<name>/` | The pixel-world narrative: hero, the diorama, the four character scenes, the facts, install, the name | `pixel-world/` |
| `<name>/studio/` | How the app works, with the real screenshots | `studio/` |
| `<name>/cli/` | How the command line works: the terminal, both ends of the wire, the send, the commands | `wire/` |

Follow these rules in every prototype:

1. **Navigation.**
   - The header links only to pages: Home, Studio, CLI, and GitHub, with an Install button if you want one. A header link never scrolls inside a page.
   - Mark the current page in the header.
   - The home page has a floating table of contents (a sticky sidebar or a floating panel) whose items smooth-scroll to its sections and highlight the section in view.
   - On phones the table of contents collapses into something reachable (a small floating button or a sheet). It never covers the content.
   - Respect `prefers-reduced-motion`.
2. **One look and feel per prototype.** All three pages of a prototype share it: palette, background, type, spacing, components. Each of the five explores a clearly different direction from pixel-world's dark-blue night with Fraunces, and from the others. Vary the background (paper, a light day scene, warm tones, ink on cream, and so on), the type pairing, the layout of the hero and scenes, and the framing of the diorama.
3. **Keep the diorama art and animation.** Copy `world.js` into each prototype. The scene and sprites stay as they are. Changing the frame, the background around the scene and the page palette is fine. Pages without the diorama still need the sprites only where you show them. `world.js` returns early when the page has no `#world` canvas. Keep the sprite painting working on such pages if you use sprites there.
4. **The home page keeps the game language.** `/studio` and `/cli` explain plainly. They use no pixel-game analogy, no robot and no workshop, but the same fonts and look as their home page.
5. **The content stays the same.** Take the text from the reference pages. The copy pass with the maintainer comes later. Don't rewrite claims. Keep these known copy issues as they are, and list them in your report:
   - The studio hero callouts describe the old `sample.mp4` shot, but the screenshot is now the Halcyon teaser.
   - Every page says the logo is "drawn from a photo", but PR #54 says the logo delegate never got the photo.
   - The prototypes say "signed but not notarized"; the build and `install.sh` are ad hoc signed.
6. **Static and self-contained.** Each prototype is plain HTML, CSS and JS with no build step. It uses relative paths. Screenshots come from `site/assets/shots/` (`../../assets/shots/` from `<name>/`, one more `../` from a sub-page). Fonts come from Google Fonts. Write a `README.md` with the design plan.
7. **Quality bar.**
   - The pages work at 1440 px and 390 px, in light and dark, with no horizontal page scroll and no console errors.
   - The links, copy buttons and the CLI terminal replay work.
   - The `frontend-design` skill from `anthropics/skills` is cloned at `~/Developer/open-source/skills` (commit `683bc88`, `skills/frontend-design/SKILL.md`). Follow it and cite it in each README, as the reference prototypes do.

## How to check your work

- Take screenshots with headless Chrome: `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --virtual-time-budget=6000 --window-size=1440,900 --screenshot=<file> <url>`.
- Headless Chrome won't lay out narrower than about 500 px. For 390 px, load the page in a 390 px wide iframe that sits in the centre of a 600 px window. Then crop the centre with `sips -c <h> 390`. `sips` ignores `--cropOffset`.
- Force light mode with `--blink-settings=preferredColorScheme=1`.
- Save `preview/desktop.png` (1440 × 900) and `preview/phone.png` (390 × 844) of each home page.
- Keep temporary files in your scratchpad, not in the repo.

## Keep the gallery current

The maintainer asked for `http://localhost:8765/prototypes/` to always list every prototype. Add each new prototype to `site/prototypes/index.html` as soon as it exists:
- its name and a one-line description of its look and feel;
- links to `/`, `/studio` and `/cli`;
- the desktop and phone previews.

Keep the four reference cards. pixel-wire stays last, marked "set aside".

## Deferred until the maintainer says so

- Committing.
- Enabling GitHub Pages and making the repository public.
- Replacing `site/index.html`.

## When you finish

- Report in your tab. Give the URL of each prototype and one or two sentences on its direction.
- Say which one you would pick and why. Let the maintainer decide.
- Then wait for their feedback and iterate on the prototypes they name.
