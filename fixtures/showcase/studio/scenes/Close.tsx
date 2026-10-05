import { Audio } from "@remotion/media";
import { AbsoluteFill, staticFile, useCurrentFrame } from "remotion";
import { getScene } from "../../../src/lib/timing";
import { CREAM, GLOW, NIGHT } from "../config";
import { MaskLine, SunMark, easeInOut, sans, serif, tween, useSpring } from "../ui";
import voiceover from "../voiceover.json";

const scene = getScene(voiceover, "close");

export const Close: React.FC = () => {
  const frame = useCurrentFrame();
  const mark = useSpring(0, 20);
  const rise = tween(frame, [0, 170], [0, 1], easeInOut);
  return (
    <AbsoluteFill style={{ background: `linear-gradient(180deg, ${NIGHT} 0%, #1B2350 55%, #4A3A6E 100%)`, overflow: "hidden" }}>
      {/* A low sun, cut by the bottom edge. */}
      <div
        style={{
          position: "absolute",
          left: 1060,
          top: 760 - rise * 90,
          width: 900,
          height: 900,
          borderRadius: "50%",
          background: "radial-gradient(circle at 50% 35%, #FFF1D6 0%, #FFC27A 40%, #F2A07B 70%, rgba(242,160,123,0) 72%)",
          filter: "blur(2px)",
          opacity: 0.95,
        }}
      />
      <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 200, background: `linear-gradient(180deg, rgba(10,13,26,0) 0%, ${NIGHT} 100%)` }} />

      <div style={{ position: "absolute", left: 160, top: 250, opacity: mark, transform: `translateY(${(1 - mark) * 30}px)` }}>
        <SunMark size={150} />
      </div>
      <div style={{ position: "absolute", left: 150, top: 410, fontFamily: serif, fontWeight: 400, fontSize: 210, color: CREAM, letterSpacing: "-0.02em", lineHeight: 1 }}>
        <MaskLine delay={6} duration={26}>Halcyon</MaskLine>
      </div>
      <div style={{ position: "absolute", left: 160, top: 650, fontFamily: serif, fontStyle: "italic", fontWeight: 300, fontSize: 72, color: GLOW }}>
        <MaskLine delay={40}>Weather, in plain words.</MaskLine>
      </div>
      <div
        style={{
          position: "absolute",
          left: 160,
          top: 830,
          display: "flex",
          alignItems: "center",
          gap: 22,
          fontFamily: sans,
          fontSize: 28,
          fontWeight: 600,
          letterSpacing: "0.24em",
          color: "rgba(255, 248, 238, 0.75)",
          opacity: tween(frame, [84, 104], [0, 1]),
        }}
      >
        <span>COMING TO IPHONE</span>
        <span style={{ width: 8, height: 8, borderRadius: 4, background: GLOW }} />
        <span>SPRING 2027</span>
      </div>
      <Audio src={staticFile(scene.audioFile)} />
    </AbsoluteFill>
  );
};
