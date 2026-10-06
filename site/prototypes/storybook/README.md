# storybook

Ink on paper: the Havooch landing site as a picture book. The pixel diorama is a tipped-in colour plate, set slightly askew on a white mat, and the four character scenes are the book's chapters. Light first; dark mode is the same book read by a lamp at night.

## Routes

| Route | Content |
|---|---|
| `storybook/` | The pixel-world narrative: title page, the plate (the diorama), four chapters with their sprites, the facts, install, the name. It has the floating contents list. |
| `storybook/studio/` | How the app works, with the real screenshots mounted as plates. Plain language, no sprites. |
| `storybook/cli/` | How the command line works: the terminal as a dark plate, both ends of the wire, the send, the commands. Plain language, no sprites. |

The header links only to pages (Home, Studio, CLI, GitHub) and marks the current one. In-page movement on the home page belongs to the contents list alone.

## Design plan

- Colour: paper `#eef0e6` (a cool ivory), mat `#fafbf5`, ink `#1b2a4b` (deep ink-blue, used for text, rules and button outlines), moss `#586a35` (chapter numerals, labels, fleurons), plum `#6f3b5c` (the pointing hand and focus rings), carrot `#f37a1f` (the primary button, callout pins, and the cat). Code plates are `#10182b`. Dark: paper `#23211e`, cream ink `#ece5d3`, moss `#adba7f`.
- Type: Young Serif for display, Source Serif 4 for all text at 18.5px with a 1.68 line-height. No sans; the system monospace only for code and keys. Italics carry captions, labels and asides.
- Layout: one reading column, 720px on the home page, like a book page. The title page is centred; everything after is left aligned. The plate is wider than the column (900px) and rotated 0.7 degrees. Chapters alternate the illustration from the left side to the right, with the sprites set straight on the paper, unboxed. Sub-pages widen the measure to 1040px so screenshots and the two-lane wire diagram have room.

```text
 wide (1380px and up)                     phone
+----------------------------------+     +-----------------+
| Havooch      Home Studio CLI Git |     | Havooch  H S C G|
+----------------------------------+     +-----------------+
| Contents |   Title, centred      |     |  Title          |
| I.  Start|   lede, two buttons   |     |  lede, buttons  |
| ☞  World |  +----------------+   |     | [    plate    ] |
| III. ... |  |  plate, askew  |   |     |  caption        |
|          |  +----------------+   |     |  sprite         |
|          |  sprite | Chapter I   |     |  Chapter I      |
|          |  Chapter II | sprite  |     |      (Contents) |
+----------------------------------+     +-----------------+
```

- Contents: fixed in the left margin from 1380px, where the margin is wide enough that it never meets the column or the plate. Roman numerals, and a pointing hand marks the section in view. Below 1380px it is a small "Contents" button at the bottom right that opens a sheet; Escape, a link or a tap outside closes it.
- Principles: the plate is the one memorable thing; the page around it is quiet paper and ink. Rules are borrowed from book setting (a double rule opens a table, a single rule separates entries). Chapter numerals are used because the scenes are a real sequence. The only motion is the diorama itself, the terminal replay and the packet on the wire; all stop under `prefers-reduced-motion`, and the smooth scroll turns off.

## Fonts and assets

Young Serif and Source Serif 4 from Google Fonts. `world.js` is an unchanged copy of `pixel-world/world.js`; it draws the diorama and paints the sprites and the portrait. `logo.svg` is a copy of `assets/images/logo/v2-havuc/havooch-mark.svg`. Screenshots come from `site/assets/shots/`. `script.js` holds the copy buttons, the contents list, the studio callouts, the terminal replay and the packet.

## Known copy issues, kept as they are

- The studio hero callouts describe the old `sample.mp4` shot; the screenshot is now the Halcyon teaser.
- The home page says the logo is "drawn from a photo".
- The pages say "signed but not notarized"; the build is ad hoc signed.

## Method

Built following the `frontend-design` skill from [anthropics/skills](https://github.com/anthropics/skills) at commit `683bc88e56f3e09ba94f7055977f3d3aa499f202` (`skills/frontend-design/SKILL.md`). Checked with headless Chrome at 1440 and 390 px in light and dark: no horizontal scroll, no console errors. Previews in `preview/`.
