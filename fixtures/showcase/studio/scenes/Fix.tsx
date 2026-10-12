import { Audio } from "@remotion/media";
import { staticFile, useCurrentFrame } from "remotion";
import { getScene } from "@studio/lib/timing";
import { useWord } from "@studio/lib/words";
import { ACCENT, FOLD_MUTED, INK, LINK, MUTED, PAPER, RULE, SOFT } from "../config";
import { DarkFace, Eyebrow, Flip, LightFace, PlainHead, Sfx, Tile, TypeTag, mono, pointAt, sans, title, tween, type Pt } from "../graphite";
import voiceover from "../voiceover.json";

// The chart: a week of p95 latency, two readings a day, 0 to 2.0 s.
const CX0 = 210;
const CX1 = 1110;
const CY0 = 300;
const CY1 = 820;
const X = (i: number) => CX0 + (i / 13) * (CX1 - CX0);
const Y = (s: number) => CY1 - (s / 2) * (CY1 - CY0);
const FIX_AT = 6.4;

const BEFORE: Pt[] = [1.76, 1.82, 1.79, 1.84, 1.8, 1.78, 1.81].map((s, i) => ({ x: X(i), y: Y(s) })).concat([{ x: X(FIX_AT), y: Y(1.8) }]);
const AFTER: Pt[] = [{ x: X(FIX_AT), y: Y(1.8) }].concat([0.26, 0.22, 0.21, 0.22, 0.21, 0.21, 0.21].map((s, i) => ({ x: X(7 + i), y: Y(s) })));
const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

const path = (pts: Pt[]) => pts.map((q, i) => `${i ? "L" : "M"} ${q.x.toFixed(1)} ${q.y.toFixed(1)}`).join(" ");
const length = (pts: Pt[]) => pts.slice(1).reduce((a, b, i) => a + Math.hypot(b.x - pts[i].x, b.y - pts[i].y), 0);

// The fix: the week's latency drops at "index added", beside the folded suggested-fix panel.
export const Fix: React.FC = () => {
  const frame = useCurrentFrame();
  const suggestAt = useWord(voiceover, "fix", "suggests");
  const addAt = useWord(voiceover, "fix", "add it");
  const dropAt = useWord(voiceover, "fix", "drops");
  const readAt = useWord(voiceover, "fix", "two hundred");

  const before = tween(frame, [2, suggestAt + 10], [0, 1], (t) => t);
  const after = tween(frame, [dropAt - 4, dropAt + 26], [0, 1]);
  const marker = tween(frame, [addAt, addAt + 14]);
  const panelIn = tween(frame, [suggestAt - 8, suggestAt]);
  const fold = tween(frame, [suggestAt, suggestAt + 16]);
  const read = tween(frame, [readAt, readAt + 14]);
  const tip = pointAt(AFTER, after);

  const panel = (folded: boolean) => {
    const fg = folded ? PAPER : INK;
    const sub = folded ? FOLD_MUTED : MUTED;
    return (
      <div style={{ position: "absolute", inset: 0, padding: "36px 40px" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
          <TypeTag folded={folded}>FIX</TypeTag>
          <span style={{ fontFamily: mono, fontSize: 20, letterSpacing: "0.16em", textTransform: "uppercase", color: sub }}>Suggested fix</span>
        </div>
        <div style={{ fontFamily: title, fontWeight: 600, fontSize: 46, lineHeight: 1.12, letterSpacing: "-0.01em", color: fg, marginTop: 28 }}>
          Add an index on orders(user_id)
        </div>
        <div style={{ marginTop: 30, padding: "18px 20px", background: folded ? "#eceef0" : "rgba(255,255,255,0.06)", fontFamily: mono, fontSize: 22, color: fg, borderRadius: 2 }}>
          CREATE INDEX ON orders (user_id);
        </div>
        <div style={{ marginTop: 28, fontFamily: sans, fontSize: 26, color: sub, lineHeight: 1.35 }}>
          The payments query scans every order. Found in 312 slow traces this week.
        </div>
      </div>
    );
  };

  return (
    <Tile>
      <Eyebrow style={{ position: "absolute", left: 110, top: 104 }}>p95 latency · GET /checkout · last 7 days</Eyebrow>
      <div style={{ position: "absolute", left: 110, top: 140, fontFamily: title, fontWeight: 600, fontSize: 64, letterSpacing: "-0.01em", color: INK }}>
        One index, one week
      </div>

      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
        {[0, 0.5, 1, 1.5, 2].map((s) => (
          <g key={s}>
            <line x1={CX0} y1={Y(s)} x2={CX1} y2={Y(s)} stroke={RULE} strokeWidth={1} />
            <text x={CX0 - 18} y={Y(s) + 7} fill={SOFT} fontFamily={mono} fontSize={20} textAnchor="end">
              {s.toFixed(1)} s
            </text>
          </g>
        ))}
        {DAYS.map((d, i) => (
          <text key={d} x={(X(2 * i) + X(2 * i + 1)) / 2} y={CY1 + 44} fill={SOFT} fontFamily={mono} fontSize={20} textAnchor="middle">
            {d}
          </text>
        ))}

        {/* The "index added" marker. */}
        <g opacity={marker}>
          <line x1={X(FIX_AT)} y1={CY0 - 6} x2={X(FIX_AT)} y2={CY1} stroke={ACCENT} strokeWidth={1.5} strokeDasharray="6 7" />
        </g>

        <path d={path(BEFORE)} fill="none" stroke={MUTED} strokeWidth={4} strokeLinejoin="round" strokeDasharray={`${before * length(BEFORE)} 9999`} />
        {after > 0 ? (
          <path d={path(AFTER)} fill="none" stroke={ACCENT} strokeWidth={4} strokeLinejoin="round" strokeDasharray={`${after * length(AFTER)} 9999`} />
        ) : null}
        {after > 0 ? <circle cx={tip.x} cy={tip.y} r={8} fill={ACCENT} /> : null}

        {/* The drop, marked with a link arrow. */}
        <g opacity={tween(frame, [dropAt + 10, dropAt + 22])}>
          <line x1={X(FIX_AT) + 48} y1={Y(1.8)} x2={X(FIX_AT) + 48} y2={Y(0.26) - 14} stroke={LINK} strokeWidth={2} />
          <PlainHead x={X(FIX_AT) + 48} y={Y(0.26) - 12} angle={90} color={LINK} />
          <text x={X(FIX_AT) + 70} y={(Y(1.8) + Y(0.26)) / 2 + 8} fill={LINK} fontFamily={mono} fontSize={26}>
            1.80 s to 0.21 s
          </text>
        </g>
      </svg>

      <div
        style={{
          position: "absolute",
          left: X(FIX_AT) - 110,
          top: CY0 - 58,
          width: 220,
          textAlign: "center",
          fontFamily: mono,
          fontSize: 22,
          color: INK,
          opacity: marker,
        }}
      >
        index added
      </div>

      <div
        style={{
          position: "absolute",
          left: X(13) - 70,
          top: Y(0.21) - 64,
          fontFamily: mono,
          fontSize: 36,
          color: INK,
          opacity: read,
          translate: `0 ${(1 - read) * 10}px`,
        }}
      >
        0.21 s
      </div>

      <div style={{ position: "absolute", left: 1230, top: 330, width: 580, height: 440, opacity: panelIn }}>
        <Flip p={fold} style={{ inset: 0 }} dark={<DarkFace>{panel(false)}</DarkFace>} light={<LightFace ear={30}>{panel(true)}</LightFace>} />
      </div>

      <Sfx at={suggestAt} name="pop" volume={0.2} />
      <Sfx at={addAt} name="click" volume={0.18} />
      <Sfx at={dropAt} name="whoosh" volume={0.12} />
      <Audio src={staticFile(getScene(voiceover, "fix").audioFile)} />
    </Tile>
  );
};
