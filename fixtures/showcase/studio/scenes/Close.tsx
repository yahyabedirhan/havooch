import { Audio } from "@remotion/media";
import { staticFile, useCurrentFrame } from "remotion";
import { getScene } from "@studio/lib/timing";
import { useWord } from "@studio/lib/words";
import { INK, MUTED, SOFT } from "../config";
import { Mark, Rise, Sfx, Tile, mono, sans, title, tween } from "../graphite";
import voiceover from "../voiceover.json";

// The end card: the mark, the name, the tagline and the beta line.
export const Close: React.FC = () => {
  const frame = useCurrentFrame();
  const nameAt = useWord(voiceover, "close", "lantern");
  const seeAt = useWord(voiceover, "close", "see where the time goes");
  const betaAt = useWord(voiceover, "close", "private beta");

  return (
    <Tile>
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center" }}>
        <Mark size={150} p={tween(frame, [0, nameAt + 20], [0, 1], (t) => t)} />
        <Rise p={tween(frame, [nameAt, nameAt + 18])} style={{ marginTop: 44 }}>
          <div style={{ fontFamily: title, fontWeight: 600, fontSize: 150, lineHeight: 1, letterSpacing: "-0.01em", color: INK }}>Lantern</div>
        </Rise>
        <Rise p={tween(frame, [seeAt, seeAt + 18])} style={{ marginTop: 22 }}>
          <div style={{ fontFamily: sans, fontWeight: 400, fontSize: 52, color: MUTED }}>See where the time goes.</div>
        </Rise>
        <div
          style={{
            marginTop: 84,
            fontFamily: mono,
            fontSize: 28,
            letterSpacing: "0.16em",
            textTransform: "uppercase",
            color: SOFT,
            opacity: tween(frame, [betaAt, betaAt + 14]),
            translate: `0 ${tween(frame, [betaAt, betaAt + 14], [16, 0])}px`,
          }}
        >
          Private beta · Spring 2027
        </div>
      </div>
      <Sfx at={0} name="whoosh" volume={0.12} />
      <Audio src={staticFile(getScene(voiceover, "close").audioFile)} />
    </Tile>
  );
};
