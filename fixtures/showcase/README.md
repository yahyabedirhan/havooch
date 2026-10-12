# Showcase fixture

A 39.6 s narrated launch teaser for **Lantern**, a made-up developer tool that traces how one request moves through your services and shows where the time goes. It is a review fixture: every scene holds one strong, legible visual worth a comment, in the Graphite look of folded white paper on a dark granite tile. `scripts/showcase.sh` plays a review of it, and the README's and the guide's screenshots show that review.

It was made in the local explainer studio ([yahyabedirhan/explainer-studio](https://github.com/yahyabedirhan/explainer-studio), Remotion for the picture and Kokoro for the voice `af_heart`), as the video `lantern-teaser`. Everything in it is original: the scenes are drawn in code, the voice and the quiet synth bed are generated, and there is no footage or third-party logo.

| File | What it is |
|---|---|
| `lantern-teaser.mp4` | H.264 1920x1080 at 30 fps, yuv420p, AAC audio, 1189 frames, 39.633 s, 1.8 MB |
| `lantern-teaser.srt` | the narration, one cue per sentence, timed from the voice's word timings |
| `lantern-teaser.context.md` | topic, goal, source and note, which the app sends to the agent |
| `voiceover.json` | the studio's scene list: narration text, measured `durationSeconds` and `paddingSeconds` per scene |
| `studio/` | the scenes' source, as they are in the studio's `videos/lantern-teaser/`: `Video.tsx`, `config.ts`, `graphite.tsx` (the look's components), `Sheet.tsx` (the asset sheet) and `scenes/` (the voice and sound files are not kept here) |

The container reports 39.637 s because the AAC track runs a few milliseconds past the last video frame.

## Scenes

Each scene lasts `ceil((durationSeconds + paddingSeconds) x 30)` frames, as the studio's `src/lib/timing.ts` computes it. A scene starts where the previous one ends.

| Scene | Frames | Start (s) | End (s) | What it shows |
|---|---|---|---|---|
| `cold` | 0 to 183 | 0.000 | 6.100 | A request log; "GET /checkout" types in, its time counts up to 1.84 s and the chip folds white with a dog-ear and pulses. "Somewhere, this got slow." |
| `logo` | 183 to 327 | 6.100 | 10.900 | The Lantern mark, a folded paper diamond, assembles facet by facet, then the wordmark "Lantern" and "See where the time goes." |
| `map` | 327 to 582 | 10.900 | 19.400 | "One request, every service": Web app, API gateway, Checkout, Payments, Inventory, Postgres and Redis with type tags. A pulse follows the request; Payments folds white, counts up "waits 1.31 s" and is marked "slowest hop". |
| `trace` | 582 to 803 | 19.400 | 26.767 | "The time, lined up": a trace waterfall on a 0 to 2.0 s ruler. Payments lights at 1.31 s; the Postgres span lifts and folds white, labelled "SELECT … FROM orders  1.12 s". |
| `fix` | 803 to 1013 | 26.767 | 33.767 | "One index, one week": p95 latency Monday to Sunday, about 1.8 s until the "index added" marker on Thursday, then 0.21 s, with the drop marked "1.80 s to 0.21 s". Beside it the folded "Suggested fix" panel: "Add an index on orders(user_id)". |
| `close` | 1013 to 1189 | 33.767 | 39.633 | The end card: the mark, "Lantern", "See where the time goes." and "Private beta · Spring 2027". |

## Frames worth commenting on

| Time (s) | Scene | What is on the frame |
|---|---|---|
| 5.5 | `cold` | "GET /checkout" with the folded "1.84 s" chip, "200 OK · trace 7f3a" and "Somewhere, this got slow." |
| 9.5 | `logo` | the folded mark beside the wordmark and the tagline |
| 18.5 | `map` | the whole service map, Payments folded white with "waits 1.31 s" and "slowest hop", the folded arrowhead into it |
| 26.0 | `trace` | all six spans, Payments at 1.31 s, the lifted white Postgres span and the "SELECT … FROM orders  1.12 s" label |
| 33.0 | `fix` | the full week's line with the drop, "index added", "1.80 s to 0.21 s", "0.21 s" and the suggested fix panel |
| 38.5 | `close` | the whole end card |
