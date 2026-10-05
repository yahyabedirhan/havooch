import { Audio } from "@remotion/media";
import { AbsoluteFill, staticFile, useCurrentFrame } from "remotion";
import { getScene } from "../../../src/lib/timing";
import { CREAM, NIGHT } from "../config";
import { MaskLine, rand, sans, serif, tween } from "../ui";
import voiceover from "../voiceover.json";

const scene = getScene(voiceover, "numbers");

// Each reading holds while the voice says it.
const READINGS = [
  { from: 0, to: 46, label: "Temperature", value: "17", unit: "°" },
  { from: 46, to: 94, label: "Humidity", value: "62", unit: "%" },
  { from: 94, to: 158, label: "Wind", value: "14", unit: "km/h" },
];

const NOISE = ["18.4", "0.62", "1012", "SW 14", "UV 4", "9.8 km", "61%", "06:42", "12°", "0.0 mm", "NNE", "1009", "21°", "47%", "3 m/s", "88%"];

const Reading: React.FC<{ from: number; to: number; label: string; value: string; unit: string }> = ({ from, to, label, value, unit }) => {
  const frame = useCurrentFrame();
  if (frame < from - 2 || frame > to + 8) return null;
  const inP = tween(frame, [from, from + 10], [0, 1]);
  const outP = tween(frame, [to, to + 8], [0, 1]);
  return (
    <div
      style={{
        position: "absolute",
        left: 160,
        top: 250,
        opacity: inP * (1 - outP),
        transform: `translateY(${(1 - inP) * 50 - outP * 40}px)`,
        filter: `blur(${(1 - inP) * 14 + outP * 10}px)`,
      }}
    >
      <div style={{ fontFamily: sans, fontSize: 30, fontWeight: 500, letterSpacing: "0.22em", textTransform: "uppercase", color: "#7E8AB8" }}>{label}</div>
      <div style={{ fontFamily: sans, fontSize: 380, fontWeight: 300, color: CREAM, letterSpacing: "-0.04em", lineHeight: 1, marginTop: 24, fontVariantNumeric: "tabular-nums" }}>
        {value}
        <span style={{ fontSize: unit.length > 1 ? 120 : 380, fontWeight: 300, color: "#9AA6D6", marginLeft: unit.length > 1 ? 28 : 0, letterSpacing: 0 }}>{unit}</span>
      </div>
    </div>
  );
};

export const Numbers: React.FC = () => {
  const frame = useCurrentFrame();
  const noise = tween(frame, [140, 190], [0.035, 0.2]);
  return (
    <AbsoluteFill style={{ background: `radial-gradient(1200px 800px at 75% 30%, #18204A 0%, ${NIGHT} 70%)`, overflow: "hidden" }}>
      {/* A field of readings that fills in as the voice says "numbers". */}
      {Array.from({ length: 72 }).map((_, i) => {
        const col = i % 12;
        const row = Math.floor(i / 12);
        const drift = (frame * (0.25 + rand(i) * 0.35)) % 40;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: 40 + col * 160 + rand(i + 3) * 40,
              top: 60 + row * 170 + rand(i + 7) * 60 - drift,
              fontFamily: sans,
              fontSize: 26 + rand(i + 1) * 18,
              fontWeight: 400,
              color: "#AEB8E6",
              opacity: noise * (0.4 + rand(i + 5) * 0.6),
              fontVariantNumeric: "tabular-nums",
            }}
          >
            {NOISE[i % NOISE.length]}
          </div>
        );
      })}

      {/* A shade that keeps the readings and the line clear of the field. */}
      <div style={{ position: "absolute", inset: 0, background: "radial-gradient(1100px 700px at 22% 62%, rgba(10,13,26,0.92) 0%, rgba(10,13,26,0.6) 55%, rgba(10,13,26,0) 100%)" }} />
      {READINGS.map((r) => (
        <Reading key={r.label} {...r} />
      ))}

      <div style={{ position: "absolute", left: 160, top: 690, fontFamily: serif, fontStyle: "italic", fontWeight: 300, fontSize: 108, color: CREAM, lineHeight: 1.05, letterSpacing: "-0.01em" }}>
        <MaskLine delay={162}>Every forecast</MaskLine>
        <MaskLine delay={172}>gives you numbers.</MaskLine>
      </div>

      <div style={{ position: "absolute", right: 120, top: 90, padding: "10px 18px", borderRadius: 999, background: "rgba(10,13,26,0.85)", fontFamily: sans, fontSize: 26, fontWeight: 500, color: "#6D78A6", letterSpacing: "0.12em", opacity: tween(frame, [4, 24], [0, 1]) }}>
        06:42 · LISBON
      </div>
      <Audio src={staticFile(scene.audioFile)} />
    </AbsoluteFill>
  );
};
