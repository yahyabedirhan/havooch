# pixel-world

A landing page whose hero is a lit isometric pixel diorama of the loop. Havuç sits in the screening room in front of a glowing screen with a paused video and an orange region drawn on it, three notes float beside him, he carries the notes down a lantern-lit path to the agent's workshop, and the replies fly back as glowing envelopes. Dark first; light mode is dusk around the same night-time diorama.

## How the art is made

No images and no third-party art. `world.js` is a small software renderer:

- A 320 × 180 pixel buffer (`Float32Array` albedo plus an emissive mask), scaled up with `image-rendering: pixelated`.
- Isometric projection with 16 × 8 tiles. A box is three fills: a scanline diamond for the top and two "column fills" for the faces, where a shading function receives face-local coordinates. The screen on the brick wall and the terminal on the bench are shading functions on a face, so the video content is skewed with the wall.
- Textures (bricks, planks, flagstones, cliff) come from a deterministic hash per pixel.
- Sprites (Havuç sitting, Havuç walking with two leg frames, the satchel, the notes, the envelopes, the robot) are string maps, one letter per palette colour.
- A lighting pass shades every non-emissive pixel from the scene's lights (the screen in teal, the workshop lamp in gold, the standing lamp, two lanterns, the moon, the terminal, and the flying replies) with squared falloff, then quantises the light into eight steps with a 4 × 4 Bayer dither so shading reads as bands of pixels. Emissive pixels skip lighting and feed a separable box-blur bloom that is added back on top.
- Animation at 24 fps: the region outline pulses, the terminal scrolls, the paw waves, the notes bob, Havuç walks, the envelopes arc back with a trail, stars twinkle. The loop runs only while the canvas is on screen and the tab is visible, and with `prefers-reduced-motion` a single still frame is drawn.

The sprites are reused on the page: the four story icons and the portrait in the name section are the same string maps drawn big into small canvases.

## Design plan

- Colour: night `#0a0c1c`, plum `#1a1633`, bone `#f3e9dc`, carrot `#f37a1f`, teal `#39d7dc`, gold `#ffc566`. The warm-cool contrast of the diorama (teal screen, gold workshop) is the page's palette.
- Type: Fraunces (soft, large optical size) for display, the system sans for text.
- Layout: centred hero copy, then the diorama at full width with a glow that bleeds the scene's colours into the page, then a left-aligned storyline with sprite icons, plain facts, install, the name.
- Principle: one memorable thing, the diorama; everything else quiet.

## Fonts and assets

Fraunces from Google Fonts. `logo.svg` is a copy of `assets/images/logo/v2-havuc/havooch-mark.svg`.

## Method

Built following the `frontend-design` skill from [anthropics/skills](https://github.com/anthropics/skills) at commit `683bc88e56f3e09ba94f7055977f3d3aa499f202` (`skills/frontend-design/SKILL.md`). Checked with headless Chromium at 1440 and 390 px in light and dark: no horizontal scroll, no console errors. Previews in `preview/`.
