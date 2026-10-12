import { Audio } from "@remotion/media";
import { staticFile, useCurrentFrame } from "remotion";
import { Typewriter } from "@studio/components/Typewriter";
import { getScene } from "@studio/lib/timing";
import { useWord, wordEndFrame } from "@studio/lib/words";
import { useVideoConfig } from "remotion";
import { INK, MUTED, PAPER, SOFT, RULE, FOLD_MUTED } from "../config";
import { DarkFace, Eyebrow, Flip, LightFace, Rise, Sfx, Tile, mono, title, tween } from "../graphite";
import voiceover from "../voiceover.json";

const LOG = [
  ["14:02:27", "GET", "/cart", "0.08 s"],
  ["14:02:28", "GET", "/search?q=lamp", "0.12 s"],
  ["14:02:29", "POST", "/login", "0.09 s"],
  ["14:02:30", "GET", "/products/42", "0.06 s"],
];

// Cold open: one request line types in, and its 1.84 s folds white and pulses.
export const Cold: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const scene = getScene(voiceover, "cold");
  const typeAt = useWord(voiceover, "cold", "one checkout request");
  const typeEnd = wordEndFrame(scene, "request", fps);
  const numAt = useWord(voiceover, "cold", "one point eight four");
  const secsAt = useWord(voiceover, "cold", "seconds");
  const someAt = useWord(voiceover, "cold", "somewhere");

  const chipIn = tween(frame, [numAt - 4, numAt + 6]);
  const count = tween(frame, [numAt, secsAt], [0, 1.84]);
  const fold = tween(frame, [secsAt, secsAt + 14], [0, 1]);
  // Two calm pulses after the fold.
  const pulse =
    Math.sin(Math.max(0, Math.min(1, (frame - (secsAt + 16)) / 14)) * Math.PI) * 0.05 +
    Math.sin(Math.max(0, Math.min(1, (frame - (secsAt + 34)) / 14)) * Math.PI) * 0.05;

  const chipText = (folded: boolean) => (
    <div
      style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        fontFamily: mono,
        fontSize: 112,
        color: folded ? PAPER : INK,
        fontVariantNumeric: "tabular-nums",
      }}
    >
      {count.toFixed(2)} s
    </div>
  );

  return (
    <Tile>
      <Eyebrow style={{ position: "absolute", left: 140, top: 120, opacity: tween(frame, [0, 10]) }}>
        production · request log
      </Eyebrow>
      <div style={{ position: "absolute", left: 140, top: 176, fontFamily: mono, fontSize: 26, lineHeight: "44px", color: SOFT }}>
        {LOG.map((row, i) => (
          <div key={i} style={{ display: "flex", gap: 40, opacity: tween(frame, [i * 2, i * 2 + 10]) * 0.8 }}>
            <span style={{ width: 150 }}>{row[0]}</span>
            <span style={{ width: 80 }}>{row[1]}</span>
            <span style={{ width: 330 }}>{row[2]}</span>
            <span>{row[3]}</span>
          </div>
        ))}
      </div>
      <div style={{ position: "absolute", left: 140, right: 140, top: 384, height: 1, background: RULE }} />

      <div style={{ position: "absolute", left: 140, top: 418, fontFamily: mono, fontSize: 26, color: MUTED, opacity: tween(frame, [typeAt - 4, typeAt + 6]) }}>
        14:02:31
      </div>
      <div style={{ position: "absolute", left: 140, top: 470, height: 170, display: "flex", alignItems: "center", fontFamily: mono, fontSize: 112, color: INK }}>
        <Typewriter text="GET /checkout" from={typeAt} to={typeEnd} caret={frame < numAt} caretColor={INK} />
      </div>

      <div style={{ position: "absolute", left: 1080, top: 470, width: 500, height: 170, opacity: chipIn, scale: String(1 + pulse) }}>
        <Flip
          p={fold}
          style={{ inset: 0 }}
          dark={<DarkFace>{chipText(false)}</DarkFace>}
          light={<LightFace ear={34}>{chipText(true)}</LightFace>}
        />
      </div>
      <div style={{ position: "absolute", left: 1080, top: 656, width: 500, textAlign: "center", fontFamily: mono, fontSize: 24, color: fold > 0.5 ? MUTED : FOLD_MUTED, opacity: tween(frame, [secsAt + 8, secsAt + 20]) }}>
        200 OK · trace 7f3a
      </div>

      <Rise p={tween(frame, [someAt, someAt + 18])} style={{ position: "absolute", left: 140, top: 770 }}>
        <div style={{ fontFamily: title, fontWeight: 600, fontSize: 96, letterSpacing: "-0.01em", color: INK }}>
          Somewhere, this got slow.
        </div>
      </Rise>

      <Sfx at={typeAt} name="tick" volume={0.15} />
      <Sfx at={numAt} name="click" volume={0.2} />
      <Sfx at={secsAt} name="pop" volume={0.2} />
      <Audio src={staticFile(scene.audioFile)} />
    </Tile>
  );
};
