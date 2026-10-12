import { Audio } from "@remotion/media";
import { staticFile, useCurrentFrame } from "remotion";
import { getScene } from "@studio/lib/timing";
import { useWord } from "@studio/lib/words";
import { FOLD_MUTED, INK, MUTED, RULE, SOFT } from "../config";
import { DarkFace, Eyebrow, Flip, LightFace, Sfx, Tile, TypeTag, mono, sans, title, tween } from "../graphite";
import voiceover from "../voiceover.json";

// The time ruler: 0 s at X0, 2.0 s at X1.
const X0 = 660;
const X1 = 1780;
const PX = (X1 - X0) / 2;
const TOP = 300;
const ROW_H = 80;
const BAR_H = 46;

const SPANS = [
  { id: "gw", tag: "API", name: "API gateway", op: "GET /checkout", start: 0, end: 1.84 },
  { id: "co", tag: "SVC", name: "Checkout", op: "create order", start: 0.04, end: 1.8 },
  { id: "redis", tag: "CACHE", name: "Redis", op: "GET session", start: 0.06, end: 0.09 },
  { id: "inv", tag: "SVC", name: "Inventory", op: "reserve stock", start: 0.1, end: 0.33 },
  { id: "pay", tag: "SVC", name: "Payments", op: "charge card", start: 0.36, end: 1.67 },
  { id: "pg", tag: "DB", name: "Postgres", op: "query orders", start: 0.42, end: 1.54 },
] as const;

// The trace waterfall: spans line up on a ruler, and the slow query lifts and folds white.
export const Trace: React.FC = () => {
  const frame = useCurrentFrame();
  const traceAt = useWord(voiceover, "trace", "trace");
  const linedAt = useWord(voiceover, "trace", "lines up");
  const payAt = useWord(voiceover, "trace", "payments");
  const secondAt = useWord(voiceover, "trace", "second");
  const dbAt = useWord(voiceover, "trace", "database");
  const queryAt = useWord(voiceover, "trace", "query");

  const fold = tween(frame, [dbAt, dbAt + 16]);
  const lift = tween(frame, [dbAt, dbAt + 16], [0, 10]);
  const sql = tween(frame, [queryAt, queryAt + 14]);
  const pgRowY = TOP + 5 * ROW_H;

  return (
    <Tile>
      <Eyebrow style={{ position: "absolute", left: 110, top: 104 }}>trace 7f3a · GET /checkout · 1.84 s</Eyebrow>
      <div style={{ position: "absolute", left: 110, top: 140, fontFamily: title, fontWeight: 600, fontSize: 64, letterSpacing: "-0.01em", color: INK }}>
        The time, lined up
      </div>

      {/* Ruler and gridlines. */}
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0, opacity: tween(frame, [traceAt - 6, traceAt + 8]) }}>
        {[0, 0.5, 1, 1.5, 2].map((s) => (
          <g key={s}>
            <line x1={X0 + s * PX} y1={262} x2={X0 + s * PX} y2={TOP + 6 * ROW_H - 10} stroke={RULE} strokeWidth={1} />
            <text x={X0 + s * PX} y={250} fill={SOFT} fontFamily={mono} fontSize={22} textAnchor="middle">
              {s.toFixed(1)} s
            </text>
          </g>
        ))}
      </svg>

      {SPANS.map((s, i) => {
        const y = TOP + i * ROW_H;
        const grow = tween(frame, [traceAt + i * 5, linedAt + i * 3], [0, 1]);
        const labelIn = tween(frame, [traceAt - 4 + i * 4, traceAt + 8 + i * 4]);
        const x = X0 + s.start * PX;
        const w = Math.max(6, (s.end - s.start) * PX);
        const isPay = s.id === "pay";
        const isPg = s.id === "pg";
        const dur = (s.end - s.start).toFixed(2);
        const glow = isPay ? tween(frame, [payAt, payAt + 8]) : 0;
        const big = isPay ? tween(frame, [secondAt, secondAt + 10]) : 0;
        return (
          <div key={s.id}>
            <div style={{ position: "absolute", left: 110, top: y - 4, width: 520, display: "flex", alignItems: "center", gap: 18, opacity: labelIn }}>
              <div style={{ width: 96 }}>
                <TypeTag>{s.tag}</TypeTag>
              </div>
              <div>
                <div style={{ fontFamily: sans, fontWeight: 600, fontSize: 28, color: INK, lineHeight: 1.1 }}>{s.name}</div>
                <div style={{ fontFamily: mono, fontSize: 19, color: MUTED, marginTop: 4 }}>{s.op}</div>
              </div>
            </div>
            <div style={{ position: "absolute", left: x, top: y, width: w, height: BAR_H, opacity: grow > 0 ? 1 : 0, clipPath: `inset(-20px ${(1 - grow) * 100}% -20px 0)` }}>
              {isPg ? (
                <Flip
                  p={fold}
                  style={{ left: 0, top: -lift, width: w, height: BAR_H }}
                  dark={<DarkFace />}
                  light={<LightFace ear={18} style={{ boxShadow: `0 ${lift}px ${lift * 2}px rgba(0,0,0,0.45)` }} />}
                />
              ) : (
                <DarkFace glow={glow} />
              )}
            </div>
            <div
              style={{
                position: "absolute",
                left: x + w + 16,
                top: y + BAR_H / 2 - 16 - (isPg ? lift : 0),
                fontFamily: mono,
                fontSize: 24 + big * 6,
                lineHeight: "32px",
                color: isPay && big > 0 ? INK : MUTED,
                opacity: tween(frame, [linedAt + i * 3, linedAt + i * 3 + 10]),
              }}
            >
              {dur} s
            </div>
          </div>
        );
      })}

      {/* The query label under the folded span, joined by a dashed leader. */}
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0, opacity: sql }}>
        <line x1={X0 + 0.42 * PX + 30} y1={pgRowY + BAR_H + 4} x2={X0 + 0.42 * PX + 30} y2={pgRowY + 112} stroke={MUTED} strokeWidth={1.5} strokeDasharray="5 6" />
        <circle cx={X0 + 0.42 * PX + 30} cy={pgRowY + BAR_H + 4} r={4} fill={MUTED} />
      </svg>
      <div
        style={{
          position: "absolute",
          left: X0 + 0.42 * PX,
          top: pgRowY + 116,
          padding: "14px 22px",
          background: "rgba(19,20,23,0.7)",
          boxShadow: `inset 0 0 0 1px rgba(255,255,255,0.16)`,
          borderRadius: 2,
          fontFamily: mono,
          fontSize: 34,
          color: INK,
          whiteSpace: "pre",
          opacity: sql,
          translate: `0 ${(1 - sql) * 14}px`,
        }}
      >
        SELECT … FROM orders  <span style={{ color: fold > 0.5 ? INK : FOLD_MUTED }}>1.12 s</span>
      </div>

      <Sfx at={traceAt} name="whoosh" volume={0.1} />
      <Sfx at={dbAt} name="pop" volume={0.2} />
      <Sfx at={queryAt} name="click" volume={0.18} />
      <Audio src={staticFile(getScene(voiceover, "trace").audioFile)} />
    </Tile>
  );
};

