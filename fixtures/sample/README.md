# Sample fixture

A 21 s narrated explainer of Havooch, made in the local explainer studio with the Kokoro voice `af_heart`. Tests and demo mode use it.

| File | What it is |
|---|---|
| `sample.mp4` | H.264 1920x1080 at 30 fps, yuv420p, AAC audio, 637 frames, 21.233 s |
| `voiceover.json` | the studio's scene list: narration text, measured `durationSeconds` and `paddingSeconds` per scene |
| `sample.srt` | one cue per scene, made from `voiceover.json` |
| `sample.context.md` | topic, goal and source repo |

## Scenes

Each scene lasts `ceil((durationSeconds + paddingSeconds) x 30)` frames, as the studio's `src/lib/timing.ts` computes it. A scene starts where the previous one ends.

| Scene | Frames | Start (s) | End (s) | Narration |
|---|---|---|---|---|
| `pause` | 0 to 182 | 0.000 | 6.067 | This is Video Review. Pause any video, or draw a box on the frame, and write a comment. |
| `send` | 182 to 430 | 6.067 | 14.333 | Your comments queue up. Press command enter, and they go to your agent as one batch, with the time, the frame, and the transcript. |
| `answer` | 430 to 637 | 14.333 | 21.233 | The agent reads your notes and answers right inside the player. No copying, and no screenshots. |

The container reports 21.248 s because the AAC track runs a few milliseconds past the last video frame.

## Transcript windows to test

- A comment at 10.0 s falls in `send`. Its transcript window holds "Press command enter".
- A window of 5 s to 7 s spans the end of `pause` and the start of `send`.
