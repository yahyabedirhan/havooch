import { Audio } from "@remotion/media";
import { AbsoluteFill, staticFile, useCurrentFrame } from "remotion";
import { getScene } from "../../../src/lib/timing";
import { ACCENT, INK, MUTED, PAPER } from "../config";
import { MaskLine, SunMark, easeInOut, sans, serif, tween, useSpring } from "../ui";
import voiceover from "../voiceover.json";

const scene = getScene(voiceover, "today");

const HOURS = ["7", "9", "11", "1", "3", "5", "7", "9"];
const TEMPS = [11, 12, 15, 18, 21, 22, 20, 17];

const Chip: React.FC<{ delay: number; label: string; icon: React.ReactNode }> = ({ delay, label, icon }) => {
  const p = useSpring(delay, 16);
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 18,
        padding: "20px 34px 20px 22px",
        borderRadius: 999,
        background: "#FFFFFF",
        boxShadow: "0 10px 30px rgba(60, 40, 20, 0.08), 0 1px 0 rgba(60, 40, 20, 0.06)",
        fontFamily: sans,
        fontSize: 38,
        fontWeight: 500,
        color: INK,
        opacity: Math.min(1, p * 1.5),
        transform: `translateY(${(1 - p) * 30}px) scale(${0.9 + p * 0.1})`,
      }}
    >
      <div style={{ width: 52, height: 52, borderRadius: 26, background: "#FBEDE2", display: "flex", alignItems: "center", justifyContent: "center" }}>{icon}</div>
      {label}
    </div>
  );
};

const Chart: React.FC = () => {
  const frame = useCurrentFrame();
  const w = 340;
  const h = 150;
  const pts = TEMPS.map((t, i) => [20 + (i * (w - 40)) / (TEMPS.length - 1), h - 20 - ((t - 10) / 13) * (h - 40)] as const);
  const d = pts.map(([x, y], i) => {
    if (i === 0) return `M ${x} ${y}`;
    const [px, py] = pts[i - 1];
    const cx = (px + x) / 2;
    return `C ${cx} ${py} ${cx} ${y} ${x} ${y}`;
  }).join(" ");
  const draw = tween(frame, [30, 110], [0, 1], easeInOut);
  return (
    <svg width={w} height={h + 34}>
      <defs>
        <linearGradient id="today-fill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#F2A07B" stopOpacity="0.35" />
          <stop offset="1" stopColor="#F2A07B" stopOpacity="0" />
        </linearGradient>
        <clipPath id="today-draw">
          <rect x="0" y="0" width={w * draw} height={h} />
        </clipPath>
      </defs>
      <path d={`${d} L ${w - 20} ${h} L 20 ${h} Z`} fill="url(#today-fill)" clipPath="url(#today-draw)" />
      <path d={d} fill="none" stroke="#F0B48F" strokeWidth={3} strokeLinecap="round" clipPath="url(#today-draw)" />
      {pts.map(([x, y], i) => (
        <circle key={i} cx={x} cy={y} r={4} fill="#FFFFFF" stroke="#F0B48F" strokeWidth={2} opacity={draw * (w - 40) + 20 >= x ? 1 : 0} />
      ))}
      {HOURS.map((hh, i) => (
        <text key={i} x={pts[i][0]} y={h + 26} textAnchor="middle" fontFamily={sans} fontSize={17} fill="#9C8E7C">
          {hh}
        </text>
      ))}
    </svg>
  );
};

export const Today: React.FC = () => {
  const frame = useCurrentFrame();
  const phoneIn = useSpring(0, 22);
  const phoneOut = tween(frame, [200, 216], [0, 1], easeInOut);

  return (
    <AbsoluteFill style={{ background: PAPER, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 160, top: 170, fontFamily: sans, fontSize: 28, fontWeight: 600, letterSpacing: "0.2em", color: MUTED, opacity: tween(frame, [0, 16], [0, 1]) }}>
        TUESDAY · 14 OCTOBER
      </div>
      <div style={{ position: "absolute", left: 152, top: 240, fontFamily: serif, fontWeight: 400, fontSize: 132, lineHeight: 1.04, color: INK, letterSpacing: "-0.02em" }}>
        <MaskLine delay={4}>A crisp morning,</MaskLine>
        <MaskLine delay={40}>
          a <span style={{ fontStyle: "italic", color: ACCENT }}>warm</span> afternoon.
        </MaskLine>
      </div>
      <div style={{ position: "absolute", left: 160, top: 640, display: "flex", gap: 24 }}>
        <Chip
          delay={98}
          label="Bring a light jacket"
          icon={<div style={{ width: 22, height: 26, borderRadius: "8px 8px 4px 4px", background: ACCENT }} />}
        />
        <Chip
          delay={138}
          label="No umbrella"
          icon={<div style={{ width: 26, height: 14, borderRadius: "14px 14px 0 0", background: "#7FA7D4", opacity: 0.45 }} />}
        />
      </div>

      {/* The phone. */}
      <div
        style={{
          position: "absolute",
          left: 1230,
          top: 80,
          width: 470,
          height: 940,
          borderRadius: 72,
          background: "#141210",
          padding: 14,
          boxShadow: "0 60px 120px rgba(60, 40, 20, 0.25), 0 20px 40px rgba(60, 40, 20, 0.15)",
          transform: `translateY(${(1 - phoneIn) * 700 - phoneOut * 1100}px) rotate(${(1 - phoneIn) * 6}deg)`,
        }}
      >
        <div style={{ width: "100%", height: "100%", borderRadius: 58, overflow: "hidden", background: "linear-gradient(180deg, #FFDDB5 0%, #FFEBD3 45%, #FFF8EE 100%)", position: "relative", fontFamily: sans, color: INK }}>
          <div style={{ display: "flex", justifyContent: "space-between", padding: "26px 40px 0", fontSize: 22, fontWeight: 600 }}>
            <span>9:41</span>
            <span style={{ width: 120, height: 34, borderRadius: 17, background: "#141210", marginTop: -4 }} />
            <span>100%</span>
          </div>
          <div style={{ padding: "44px 40px 0" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
              <SunMark size={40} color={INK} />
              <span style={{ fontSize: 26, fontWeight: 600 }}>Lisbon</span>
            </div>
            <div style={{ fontSize: 168, fontWeight: 200, letterSpacing: "-0.05em", lineHeight: 1, marginTop: 18 }}>17°</div>
            <div style={{ fontFamily: serif, fontStyle: "italic", fontSize: 42, marginTop: 6, lineHeight: 1.15 }}>Crisp now, warm by two.</div>
          </div>
          <div style={{ margin: "34px 24px 0", padding: "22px 20px 14px", borderRadius: 32, background: "rgba(255, 255, 255, 0.75)" }}>
            <div style={{ fontSize: 19, fontWeight: 600, letterSpacing: "0.14em", color: "#9C8E7C", marginLeft: 6, marginBottom: 6 }}>TODAY</div>
            <Chart />
          </div>
          <div style={{ display: "flex", gap: 14, margin: "18px 24px 0" }}>
            {[
              ["Feels", "Fresh"],
              ["Wind", "Light"],
              ["Rain", "None"],
            ].map(([k, v]) => (
              <div key={k} style={{ flex: 1, padding: "18px 18px", borderRadius: 26, background: "rgba(255, 255, 255, 0.75)" }}>
                <div style={{ fontSize: 18, color: "#9C8E7C", fontWeight: 600 }}>{k}</div>
                <div style={{ fontSize: 30, fontWeight: 600, marginTop: 4 }}>{v}</div>
              </div>
            ))}
          </div>
        </div>
      </div>
      <Audio src={staticFile(scene.audioFile)} />
    </AbsoluteFill>
  );
};
