import { Audio } from "@remotion/media";
import { staticFile, useCurrentFrame } from "remotion";
import { getScene } from "@studio/lib/timing";
import { useWord } from "@studio/lib/words";
import { INK, MUTED } from "../config";
import { Mark, Rise, Sfx, Tile, sans, title, tween } from "../graphite";
import voiceover from "../voiceover.json";

// The reveal: the folded mark assembles, then the wordmark and the tagline.
export const Logo: React.FC = () => {
  const frame = useCurrentFrame();
  const meetAt = useWord(voiceover, "logo", "meet");
  const nameAt = useWord(voiceover, "logo", "lantern");
  const seeAt = useWord(voiceover, "logo", "see where the time goes");

  return (
    <Tile>
      <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", gap: 72 }}>
        <Mark size={220} p={tween(frame, [meetAt - 6, meetAt + 34], [0, 1], (t) => t)} />
        <div>
          <Rise p={tween(frame, [nameAt, nameAt + 18])}>
            <div style={{ fontFamily: title, fontWeight: 600, fontSize: 200, lineHeight: 1, letterSpacing: "-0.01em", color: INK }}>Lantern</div>
          </Rise>
          <Rise p={tween(frame, [seeAt, seeAt + 18])} style={{ marginTop: 26 }}>
            <div style={{ fontFamily: sans, fontWeight: 400, fontSize: 56, color: MUTED }}>See where the time goes.</div>
          </Rise>
        </div>
      </div>
      <Sfx at={0} name="whoosh" volume={0.12} />
      <Sfx at={nameAt} name="pop" volume={0.18} />
      <Audio src={staticFile(getScene(voiceover, "logo").audioFile)} />
    </Tile>
  );
};
