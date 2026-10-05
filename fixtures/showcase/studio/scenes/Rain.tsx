import { Audio } from "@remotion/media";
import { AbsoluteFill, staticFile, useCurrentFrame } from "remotion";
import { getScene } from "../../../src/lib/timing";
import { CREAM, RAIN } from "../config";
import { SunMark, easeInOut, rand, sans, serif, tween, useSpring } from "../ui";
import voiceover from "../voiceover.json";

const scene = getScene(voiceover, "rain");

// Minute-by-minute rain over the next hour, 0..1.
const BARS = Array.from({ length: 36 }, (_, i) => {
  if (i < 14) return 0.03 + rand(i) * 0.03;
  const rise = Math.min(1, (i - 13) / 7);
  return 0.18 + rise * 0.7 + rand(i + 40) * 0.12;
});
const LEAVE = 9; // 4:15
const START = 14; // 4:40

const Streaks: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <>
      {Array.from({ length: 160 }).map((_, i) => {
        const speed = 22 + rand(i + 1) * 18;
        const len = 40 + rand(i + 2) * 70;
        const y = ((rand(i + 3) * 1300 + frame * speed) % 1300) - 140;
        const x = rand(i + 4) * 2100 - 60 - y * 0.14;
        const near = rand(i + 5);
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: x,
              top: y,
              width: near > 0.8 ? 3 : 2,
              height: len,
              borderRadius: 2,
              background: `linear-gradient(180deg, rgba(156,195,232,0) 0%, ${RAIN} 100%)`,
              opacity: 0.12 + near * 0.35,
              transform: "rotate(8deg)",
            }}
          />
        );
      })}
    </>
  );
};

export const Rain: React.FC = () => {
  const frame = useCurrentFrame();
  const card = useSpring(24, 18);
  const chart = tween(frame, [70, 120], [0, 1], easeInOut);
  const leave = useSpring(118, 14);

  return (
    <AbsoluteFill style={{ background: "linear-gradient(180deg, #0B1A2E 0%, #12304F 60%, #1A3D60 100%)", overflow: "hidden" }}>
      <div style={{ position: "absolute", right: -30, bottom: -120, fontFamily: sans, fontWeight: 700, fontSize: 560, color: "rgba(255, 255, 255, 0.045)", letterSpacing: "-0.05em", lineHeight: 1 }}>4:15</div>
      <Streaks />

      <div style={{ position: "absolute", left: 160, top: 150, fontFamily: serif, fontWeight: 300, fontSize: 92, lineHeight: 1.05, color: CREAM, letterSpacing: "-0.01em", opacity: tween(frame, [0, 20], [0, 1]) }}>
        Rain is on <span style={{ fontStyle: "italic" }}>its way.</span>
      </div>

      {/* The notification. */}
      <div
        style={{
          position: "absolute",
          left: 160,
          top: 330,
          width: 880,
          padding: "34px 40px 38px",
          borderRadius: 44,
          background: "rgba(255, 255, 255, 0.13)",
          border: "1px solid rgba(255, 255, 255, 0.22)",
          backdropFilter: "blur(30px)",
          boxShadow: "0 40px 80px rgba(0, 10, 30, 0.35)",
          fontFamily: sans,
          color: "#FFFFFF",
          opacity: Math.min(1, card * 1.4),
          transform: `translateY(${(1 - card) * -60}px) scale(${0.96 + card * 0.04})`,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
          <div style={{ width: 64, height: 64, borderRadius: 16, background: "linear-gradient(180deg, #26306A 0%, #F6A57C 100%)", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <SunMark size={48} />
          </div>
          <span style={{ fontSize: 26, fontWeight: 600, letterSpacing: "0.14em", opacity: 0.8 }}>HALCYON</span>
          <span style={{ marginLeft: "auto", fontSize: 26, opacity: 0.6 }}>now</span>
        </div>
        <div style={{ fontSize: 62, fontWeight: 600, marginTop: 26, letterSpacing: "-0.01em" }}>Rain at 4:40 pm</div>
        <div style={{ fontSize: 42, fontWeight: 400, marginTop: 10, opacity: 0.85 }}>Leave by 4:15 and you'll stay dry.</div>
      </div>

      {/* The next hour, minute by minute. */}
      <div style={{ position: "absolute", left: 160, top: 760, width: 880, fontFamily: sans, color: "rgba(255, 255, 255, 0.7)", opacity: tween(frame, [60, 80], [0, 1]) }}>
        <div style={{ display: "flex", alignItems: "flex-end", gap: 8, height: 150, position: "relative" }}>
          {BARS.map((b, i) => (
            <div
              key={i}
              style={{
                flex: 1,
                height: `${Math.max(3, b * 100 * tween(chart, [i / 60, i / 60 + 0.45], [0, 1]))}%`,
                borderRadius: 6,
                background: i >= START ? "linear-gradient(180deg, #8EC5F5 0%, #4F8FD0 100%)" : "rgba(255, 255, 255, 0.25)",
              }}
            />
          ))}
          <div
            style={{
              position: "absolute",
              left: `${(LEAVE / BARS.length) * 100}%`,
              bottom: -14,
              height: 190,
              width: 3,
              borderRadius: 2,
              background: "#FFC069",
              opacity: leave,
              transform: `scaleY(${leave})`,
              transformOrigin: "bottom",
            }}
          />
          <div style={{ position: "absolute", left: `calc(${(LEAVE / BARS.length) * 100}% + 14px)`, top: -44, fontSize: 28, fontWeight: 600, color: "#FFC069", opacity: leave }}>Leave by 4:15</div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", marginTop: 18, fontSize: 24 }}>
          <span>4:00</span>
          <span>4:30</span>
          <span>5:00</span>
        </div>
      </div>
      <Audio src={staticFile(scene.audioFile)} />
    </AbsoluteFill>
  );
};
