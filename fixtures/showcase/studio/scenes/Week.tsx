import { Audio } from "@remotion/media";
import { AbsoluteFill, staticFile, useCurrentFrame } from "remotion";
import { getScene } from "../../../src/lib/timing";
import { INK, MUTED } from "../config";
import { MaskLine, sans, serif, tween, useSpring } from "../ui";
import voiceover from "../voiceover.json";

const scene = getScene(voiceover, "week");

type Icon = "sun" | "breeze" | "cloud" | "rain" | "clear" | "golden" | "still";

const DAYS: { day: string; word: string; hi: number; lo: number; from: string; to: string; icon: Icon; say?: number }[] = [
  { day: "MON", word: "Bright", hi: 21, lo: 12, from: "#FFE3A0", to: "#FFB547", icon: "sun", say: 76 },
  { day: "TUE", word: "Breezy", hi: 19, lo: 12, from: "#D3F1EC", to: "#7CCFC4", icon: "breeze", say: 116 },
  { day: "WED", word: "Mild", hi: 18, lo: 13, from: "#E4EED8", to: "#A9C99A", icon: "cloud" },
  { day: "THU", word: "Soft rain", hi: 16, lo: 12, from: "#DCE6F6", to: "#8FAEDD", icon: "rain", say: 158 },
  { day: "FRI", word: "Clear", hi: 18, lo: 10, from: "#DDEEFC", to: "#9DCBF2", icon: "clear" },
  { day: "SAT", word: "Golden", hi: 22, lo: 13, from: "#FFD9BF", to: "#F59A6A", icon: "golden" },
  { day: "SUN", word: "Still", hi: 20, lo: 12, from: "#E8E2F7", to: "#B6A6E3", icon: "still" },
];

const Glyph: React.FC<{ icon: Icon }> = ({ icon }) => {
  const frame = useCurrentFrame();
  const ink = "rgba(29, 26, 22, 0.78)";
  switch (icon) {
    case "sun":
    case "golden":
      return (
        <svg width="96" height="96" viewBox="0 0 96 96">
          <g transform={`rotate(${frame * 0.6} 48 48)`}>
            {Array.from({ length: 8 }).map((_, i) => (
              <rect key={i} x="46" y="6" width="4" height="14" rx="2" fill={ink} transform={`rotate(${i * 45} 48 48)`} />
            ))}
          </g>
          <circle cx="48" cy="48" r={icon === "sun" ? 20 : 17} fill={ink} />
        </svg>
      );
    case "breeze":
      return (
        <svg width="96" height="96" viewBox="0 0 96 96" fill="none" stroke={ink} strokeWidth="5" strokeLinecap="round">
          <path d={`M ${10 + Math.sin(frame / 8) * 4} 34 H 62 a 10 10 0 1 0 -10 -10`} />
          <path d={`M ${6 + Math.sin(frame / 7) * 4} 52 H 74 a 10 10 0 1 1 -10 10`} />
          <path d={`M ${16 + Math.sin(frame / 9) * 4} 70 H 48`} />
        </svg>
      );
    case "cloud":
      return (
        <svg width="96" height="96" viewBox="0 0 96 96">
          <path d="M26 66 a16 16 0 0 1 2-32 a22 22 0 0 1 42 6 a13 13 0 0 1 0 26 Z" fill={ink} />
        </svg>
      );
    case "rain":
      return (
        <svg width="96" height="96" viewBox="0 0 96 96">
          <path d="M26 54 a16 16 0 0 1 2-32 a22 22 0 0 1 42 6 a13 13 0 0 1 0 26 Z" fill={ink} />
          {[30, 48, 66].map((x, i) => (
            <rect key={x} x={x - 2} y={62 + ((frame * 1.2 + i * 7) % 18)} width="4" height="12" rx="2" fill={ink} opacity={0.8} />
          ))}
        </svg>
      );
    case "clear":
      return (
        <svg width="96" height="96" viewBox="0 0 96 96">
          <circle cx="48" cy="48" r="22" fill="none" stroke={ink} strokeWidth="5" />
        </svg>
      );
    case "still":
      return (
        <svg width="96" height="96" viewBox="0 0 96 96">
          <path d="M60 22 a26 26 0 1 0 16 40 a22 22 0 0 1 -16 -40 Z" fill={ink} />
        </svg>
      );
  }
};

const Tile: React.FC<{ i: number }> = ({ i }) => {
  const frame = useCurrentFrame();
  const d = DAYS[i];
  const p = useSpring(30 + i * 7, 18);
  const lift = d.say ? tween(frame, [d.say, d.say + 12], [0, 1]) * (1 - tween(frame, [d.say + 40, d.say + 56], [0, 1]) * (d.day === "THU" ? 0 : 1)) : 0;
  return (
    <div
      style={{
        width: 222,
        height: 540,
        borderRadius: 40,
        background: `linear-gradient(180deg, ${d.from} 0%, ${d.to} 100%)`,
        padding: "30px 26px",
        display: "flex",
        flexDirection: "column",
        fontFamily: sans,
        color: INK,
        opacity: Math.min(1, p * 1.4),
        transform: `translateY(${(1 - p) * 120 - lift * 28}px) scale(${1 + lift * 0.04})`,
        boxShadow: `0 ${20 + lift * 30}px ${40 + lift * 40}px rgba(60, 40, 20, ${0.08 + lift * 0.1})`,
      }}
    >
      <div style={{ fontSize: 26, fontWeight: 600, letterSpacing: "0.16em", opacity: 0.6 }}>{d.day}</div>
      <div style={{ marginTop: 40 }}>
        <Glyph icon={d.icon} />
      </div>
      <div style={{ marginTop: "auto", fontFamily: serif, fontWeight: 400, fontSize: d.word.length > 6 ? 46 : 52, lineHeight: 1.02, letterSpacing: "-0.01em" }}>{d.word}</div>
      <div style={{ marginTop: 14, fontSize: 28, fontWeight: 500, opacity: 0.7 }}>
        {d.hi}° <span style={{ opacity: 0.6 }}>/ {d.lo}°</span>
      </div>
    </div>
  );
};

export const Week: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: "#F7F4EE", overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 120, top: 96, fontFamily: sans, fontSize: 28, fontWeight: 600, letterSpacing: "0.2em", color: MUTED, opacity: tween(frame, [0, 16], [0, 1]) }}>
        THE NEXT SEVEN DAYS
      </div>
      <div style={{ position: "absolute", left: 114, top: 140, fontFamily: serif, fontWeight: 400, fontSize: 110, color: INK, letterSpacing: "-0.02em" }}>
        <MaskLine delay={2}>
          Your week, in <span style={{ fontStyle: "italic" }}>plain words.</span>
        </MaskLine>
      </div>
      <div style={{ position: "absolute", left: 120, top: 400, display: "flex", gap: 24 }}>
        {DAYS.map((_, i) => (
          <Tile key={i} i={i} />
        ))}
      </div>
      <Audio src={staticFile(scene.audioFile)} />
    </AbsoluteFill>
  );
};
