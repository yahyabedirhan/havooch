# Showcase fixture

A 42.6 s narrated launch teaser for **Halcyon**, a made-up weather app that tells you how the day will feel in plain words. It is the kind of video a person makes with a coding agent and then reviews in the player. `scripts/showcase.sh` plays a review of it, and the landing page's screenshots show that review.

It was made in the local explainer studio ([yahyabedirhan/explainer-studio](https://github.com/yahyabedirhan/explainer-studio), Remotion for the picture and Kokoro for the voice `af_heart`), as the video `halcyon-teaser`. Everything in it is original: the scenes are drawn in code, the voice is generated, and there is no music, footage or third-party logo.

| File | What it is |
|---|---|
| `halcyon-teaser.mp4` | H.264 1920x1080 at 30 fps, yuv420p, AAC audio, 1279 frames, 42.633 s, 5.7 MB |
| `halcyon-teaser.srt` | the narration, one cue per sentence, timed from the pauses in the voice track |
| `halcyon-teaser.context.md` | topic, goal, source and note, which the app sends to the agent |
| `voiceover.json` | the studio's scene list: narration text, measured `durationSeconds` and `paddingSeconds` per scene |
| `studio/` | the scenes' source, as they are in the studio's `videos/halcyon-teaser/` (the voice files are not kept here) |

The container reports 42.645 s because the AAC track runs a few milliseconds past the last video frame.

## Scenes

Each scene lasts `ceil((durationSeconds + paddingSeconds) x 30)` frames, as the studio's `src/lib/timing.ts` computes it. A scene starts where the previous one ends.

| Scene | Frames | Start (s) | End (s) | What it shows |
|---|---|---|---|---|
| `numbers` | 0 to 250 | 0.000 | 8.333 | A cold open on a night sky: 17°, 62%, 14 km/h, then a field of readings and "Every forecast gives you numbers." |
| `reveal` | 250 to 414 | 8.333 | 13.800 | Dawn over the sea: the sun rises and the serif wordmark "Halcyon" with "How the day will feel." |
| `today` | 414 to 630 | 13.800 | 21.000 | Warm paper: "A crisp morning, a warm afternoon.", two chips and a phone with the day's temperature curve. The phone leaves at the end. |
| `rain` | 630 to 864 | 21.000 | 28.800 | Rain streaks on deep blue, a glass notification "Rain at 4:40 pm / Leave by 4:15 and you'll stay dry." and the next hour's rain bars. |
| `week` | 864 to 1099 | 28.800 | 36.633 | "Your week, in plain words.": seven coloured day tiles (Bright, Breezy, Mild, Soft rain, Clear, Golden, Still). Monday, Tuesday and Thursday lift as the voice names them. |
| `close` | 1099 to 1279 | 36.633 | 42.633 | The end card: the mark, "Halcyon", "Weather, in plain words." and "Coming to iPhone · Spring 2027" over a low sun. |

## Frames the showcase review uses

| Time (s) | Scene | What is on the frame |
|---|---|---|
| 1.5 | `numbers` | 17° in full |
| 12.0 | `reveal` | the wordmark and the tagline over the sunrise |
| 20.7 | `today` | the phone leaving the frame |
| 26.0 | `rain` | the notification, the rain bars and the "Leave by 4:15" marker |
| 34.8 | `week` | all seven tiles, Thursday lifted |
| 40.5 | `close` | the whole end card |
