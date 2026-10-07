# Launch fixture

A 55 s narrated launch explainer of Havooch, made in the local explainer studio ([yahyabedirhan/explainer-studio](https://github.com/yahyabedirhan/explainer-studio)) with the Kokoro voice `af_heart`. "Try the Demo" opens it: `make bundle` copies this folder to `Contents/Resources/Demo`. The tests keep using `fixtures/sample`.

| File | What it is |
|---|---|
| `havooch-launch.mp4` | H.264 1920x1080 at 30 fps, yuv420p, AAC audio, 1651 frames, 55.033 s, 3.4 MB |
| `havooch-launch.srt` | the narration, one cue per scene |
| `havooch-launch.context.md` | topic, goal and source repo, which the app sends to the agent |
| `voiceover.json` | the studio's scene list: narration text, measured `durationSeconds` and `paddingSeconds` per scene |

## Refreshing it

The studio project is `havooch-launch`. Git doesn't track its render, so copy the files from the studio's checkout:

| File here | Studio source |
|---|---|
| `havooch-launch.mp4` | `out/havooch-launch/havooch-launch.mp4`, re-encoded (below) |
| `havooch-launch.srt` | `out/havooch-launch/havooch-launch.srt` |
| `havooch-launch.context.md` | `out/havooch-launch/havooch-launch.context.md` |
| `voiceover.json` | `videos/havooch-launch/voiceover.json` |

The studio's render is about 64 MB. Re-encode it before committing; the flat, code-drawn picture compresses well:

```sh
ffmpeg -i <studio>/out/havooch-launch/havooch-launch.mp4 \
  -vf "scale=in_range=pc:out_range=tv,format=yuv420p" \
  -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -c:v libx264 -preset veryslow -tune animation -crf 26 -r 30 \
  -c:a aac -b:a 128k -movflags +faststart fixtures/launch/havooch-launch.mp4
```

The studio renders full-range `yuvj420p`; the `scale` filter converts it to the limited-range `yuv420p` the other fixtures use. Check the frame count against the scene table, and compare a few frames with the render for damage to text, the logo and thin lines.

## Scenes

Each scene lasts `ceil((durationSeconds + paddingSeconds) x 30)` frames, as the studio's `src/lib/timing.ts` computes it. A scene starts where the previous one ends.

| Scene | Frames | Start (s) | End (s) | Narration |
|---|---|---|---|---|
| `mark` | 0 to 147 | 0.000 | 4.900 | Meet Havooch, named after an orange cat whose name means carrot. |
| `player` | 147 to 278 | 4.900 | 9.267 | It's a video player that carries your feedback to your coding agent. |
| `point` | 278 to 438 | 9.267 | 14.600 | Pause on any frame, drag a box around what you mean, and write what should change. |
| `threads` | 438 to 591 | 14.600 | 19.700 | Each frame you comment on becomes a numbered thread, and your notes wait in a queue. |
| `send` | 591 to 795 | 19.700 | 26.500 | Then send them all. One batch goes to your agent, with the time, the frame, the region, and the transcript. |
| `work` | 795 to 976 | 26.500 | 32.533 | Your agent knows the project behind the video. It does the work, and makes you a new version. |
| `replies` | 976 to 1153 | 32.533 | 38.433 | Answers land on the right threads, beside the video. When it's unsure, it asks you there. |
| `nosetup` | 1153 to 1324 | 38.433 | 44.133 | And there's nothing to set up. No API key, no account, no agents to connect. |
| `agents` | 1324 to 1510 | 44.133 | 50.333 | Havooch talks to the agent you already run. Claude Code, Codex, OpenCode, and more. |
| `close` | 1510 to 1651 | 50.333 | 55.033 | Havooch. Watch videos together with your agents. |
