import { Audio } from "@remotion/media";
import { AbsoluteFill, interpolateColors, staticFile, useCurrentFrame } from "remotion";
import { getScene } from "../../../src/lib/timing";
import { CREAM, NIGHT } from "../config";
import { easeInOut, sans, serif, tween } from "../ui";
import voiceover from "../voiceover.json";

const scene = getScene(voiceover, "reveal");
const HORIZON = 780;

export const Reveal: React.FC = () => {
  const frame = useCurrentFrame();
  const dawn = tween(frame, [0, 110], [0, 1], easeInOut);
  const top = interpolateColors(dawn, [0, 1], [NIGHT, "#26306A"]);
  const mid = interpolateColors(dawn, [0, 1], ["#141A3E", "#8A6A9E"]);
  const low = interpolateColors(dawn, [0, 1], ["#1E2552", "#F6A57C"]);
  const sunY = tween(frame, [0, 150], [HORIZON + 220, HORIZON - 120], easeInOut);
  const letters = "Halcyon".split("");

  return (
    <AbsoluteFill style={{ background: `linear-gradient(180deg, ${top} 0%, ${mid} 52%, ${low} ${(HORIZON / 1080) * 100}%)`, overflow: "hidden" }}>
      {/* The sun, with its glow, rising behind the horizon. */}
      <div
        style={{
          position: "absolute",
          left: 1480 - 700,
          top: sunY - 700,
          width: 1400,
          height: 1400,
          borderRadius: "50%",
          background: `radial-gradient(circle, rgba(255, 196, 130, ${0.2 + dawn * 0.4}) 0%, rgba(255, 170, 120, ${0.1 + dawn * 0.2}) 30%, rgba(255, 170, 120, 0) 62%)`,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 1290,
          top: sunY - 190,
          width: 380,
          height: 380,
          borderRadius: "50%",
          background: "radial-gradient(circle at 50% 40%, #FFF6DF 0%, #FFD08A 55%, #F59A5A 100%)",
        }}
      />
      {/* The sea below the horizon, with the sun's reflection. */}
      <div style={{ position: "absolute", left: 0, right: 0, top: HORIZON, bottom: 0, background: `linear-gradient(180deg, ${interpolateColors(dawn, [0, 1], ["#151A3A", "#3A2F5E"])} 0%, ${NIGHT} 100%)` }}>
        {Array.from({ length: 9 }).map((_, i) => {
          const w = 320 - i * 30 + Math.sin(frame / 9 + i) * 24;
          return (
            <div
              key={i}
              style={{
                position: "absolute",
                left: 1480 - w / 2,
                top: 18 + i * 30,
                width: w,
                height: 6,
                borderRadius: 3,
                background: "#FFC98F",
                opacity: dawn * (0.55 - i * 0.05),
              }}
            />
          );
        })}
      </div>

      <div style={{ position: "absolute", left: 150, top: 300, display: "flex", fontFamily: serif, fontWeight: 400, fontSize: 250, color: CREAM, letterSpacing: "-0.02em", lineHeight: 1 }}>
        {letters.map((ch, i) => {
          const p = tween(frame, [14 + i * 3, 40 + i * 3], [0, 1]);
          return (
            <div key={i} style={{ overflow: "hidden", paddingBottom: 30, marginBottom: -30 }}>
              <div style={{ transform: `translateY(${(1 - p) * 110}%)` }}>{ch}</div>
            </div>
          );
        })}
      </div>
      <div
        style={{
          position: "absolute",
          left: 160,
          top: 600,
          fontFamily: sans,
          fontWeight: 500,
          fontSize: 50,
          color: "rgba(255, 248, 238, 0.9)",
          opacity: tween(frame, [58, 80], [0, 1]),
          transform: `translateY(${tween(frame, [58, 80], [20, 0])}px)`,
        }}
      >
        How the day will <span style={{ fontFamily: serif, fontStyle: "italic", fontWeight: 400, color: "#FFD8A8" }}>feel</span>.
      </div>
      <Audio src={staticFile(scene.audioFile)} />
    </AbsoluteFill>
  );
};
