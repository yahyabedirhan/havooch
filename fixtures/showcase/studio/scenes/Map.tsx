import { Audio } from "@remotion/media";
import { staticFile, useCurrentFrame } from "remotion";
import { getScene } from "@studio/lib/timing";
import { useWord } from "@studio/lib/words";
import { ACCENT, INK, LINK, MUTED, PAPER } from "../config";
import { Arrow, Eyebrow, Node, Sfx, Tile, mono, pointAt, title, tween, type Pt } from "../graphite";
import voiceover from "../voiceover.json";

const W = 270;
const H = 150;
const COL = [110, 470, 830, 1190, 1550];
const ROW = { top: 320, mid: 495, bottom: 670 };
const mid = (y: number) => y + H / 2;

const NODES = [
  { id: "web", x: COL[0], y: ROW.mid, tag: "APP", name: "Web app", sub: "browser" },
  { id: "gw", x: COL[1], y: ROW.mid, tag: "API", name: "API gateway", sub: "edge · auth" },
  { id: "co", x: COL[2], y: ROW.mid, tag: "SVC", name: "Checkout", sub: "orders" },
  { id: "pay", x: COL[3], y: ROW.top, tag: "SVC", name: "Payments", sub: "charge card" },
  { id: "inv", x: COL[3], y: ROW.bottom, tag: "SVC", name: "Inventory", sub: "reserve stock" },
  { id: "pg", x: COL[4], y: ROW.top, tag: "DB", name: "Postgres", sub: "orders table" },
  { id: "redis", x: COL[4], y: ROW.bottom, tag: "CACHE", name: "Redis", sub: "sessions" },
] as const;

const EDGES: { id: string; pts: Pt[]; kind: "muted" | "link" | "focal" }[] = [
  { id: "web-gw", pts: [{ x: COL[0] + W, y: mid(ROW.mid) }, { x: COL[1], y: mid(ROW.mid) }], kind: "link" },
  { id: "gw-co", pts: [{ x: COL[1] + W, y: mid(ROW.mid) }, { x: COL[2], y: mid(ROW.mid) }], kind: "link" },
  {
    id: "co-pay",
    pts: [
      { x: COL[2] + W, y: mid(ROW.mid) - 20 },
      { x: COL[3] - 45, y: mid(ROW.mid) - 20 },
      { x: COL[3] - 45, y: mid(ROW.top) },
      { x: COL[3], y: mid(ROW.top) },
    ],
    kind: "focal",
  },
  {
    id: "co-inv",
    pts: [
      { x: COL[2] + W, y: mid(ROW.mid) + 20 },
      { x: COL[3] - 45, y: mid(ROW.mid) + 20 },
      { x: COL[3] - 45, y: mid(ROW.bottom) },
      { x: COL[3], y: mid(ROW.bottom) },
    ],
    kind: "muted",
  },
  { id: "pay-pg", pts: [{ x: COL[3] + W, y: mid(ROW.top) }, { x: COL[4], y: mid(ROW.top) }], kind: "link" },
  { id: "inv-redis", pts: [{ x: COL[3] + W, y: mid(ROW.bottom) }, { x: COL[4], y: mid(ROW.bottom) }], kind: "muted" },
];

// The service map: a pulse follows the request to Payments, which folds white where it waits.
export const ServiceMap: React.FC = () => {
  const frame = useCurrentFrame();
  const buildAt = useWord(voiceover, "map", "lantern");
  const requestAt = useWord(voiceover, "map", "one request");
  const throughAt = useWord(voiceover, "map", "through every service");
  const gwAt = useWord(voiceover, "map", "gateway");
  const coAt = useWord(voiceover, "map", "checkout");
  const payAt = useWord(voiceover, "map", "payments");
  const foldAt = useWord(voiceover, "map", "payments", 2);
  const waitAt = useWord(voiceover, "map", "waits");

  // The pulse crosses each gap and lands on the node as the voice names it.
  const legs: { edge: string; from: number; to: number }[] = [
    { edge: "web-gw", from: throughAt, to: gwAt },
    { edge: "gw-co", from: coAt - 14, to: coAt },
    { edge: "co-pay", from: payAt - 18, to: payAt },
  ];
  const leg = legs.find((l) => frame >= l.from && frame < l.to);
  const pulse = leg ? pointAt(EDGES.find((e) => e.id === leg.edge)!.pts, tween(frame, [leg.from, leg.to], [0, 1], (t) => t)) : null;

  const reached: Record<string, number> = { web: requestAt, gw: gwAt, co: coAt, pay: payAt };
  const wait = tween(frame, [waitAt, waitAt + 22], [0, 1.31], (t) => t);
  const ring = tween(frame, [foldAt + 10, foldAt + 34], [0, 1]);

  return (
    <Tile>
      <Eyebrow style={{ position: "absolute", left: 110, top: 104, opacity: tween(frame, [0, 10]) }}>trace 7f3a · GET /checkout</Eyebrow>
      <div style={{ position: "absolute", left: 110, top: 140, fontFamily: title, fontWeight: 600, fontSize: 64, letterSpacing: "-0.01em", color: INK, opacity: tween(frame, [0, 12]) }}>
        One request, every service
      </div>

      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
        {EDGES.map((e, i) => (
          <Arrow key={e.id} pts={e.pts} kind={e.kind} p={tween(frame, [buildAt + 10 + i * 3, buildAt + 30 + i * 3])} />
        ))}
      </svg>

      {NODES.map((n, i) => {
        const inP = tween(frame, [buildAt - 6 + i * 3, buildAt + 8 + i * 3]);
        const at = reached[n.id];
        return (
          <Node
            key={n.id}
            x={n.x}
            y={n.y + (1 - inP) * 24}
            w={W}
            h={H}
            tag={n.tag}
            name={n.name}
            sub={n.id === "pay" && wait > 0 ? `waits ${wait.toFixed(2)} s` : n.sub}
            opacity={inP}
            glow={at !== undefined ? tween(frame, [at, at + 8]) : 0}
            fold={n.id === "pay" ? tween(frame, [foldAt, foldAt + 16]) : 0}
          />
        );
      })}

      {/* A ring that spreads once from the folded Payments node. */}
      {ring > 0 && ring < 1 ? (
        <div
          style={{
            position: "absolute",
            left: COL[3] - 30 * ring,
            top: ROW.top - 30 * ring,
            width: W + 60 * ring,
            height: H + 60 * ring,
            border: `2px solid ${ACCENT}`,
            borderRadius: 4,
            opacity: (1 - ring) * 0.5,
          }}
        />
      ) : null}

      {/* The clock beside the folded node. */}
      <div
        style={{
          position: "absolute",
          left: COL[3],
          top: ROW.top + H + 22,
          width: W,
          textAlign: "center",
          fontFamily: mono,
          fontSize: 24,
          color: MUTED,
          opacity: tween(frame, [waitAt, waitAt + 10]),
        }}
      >
        slowest hop
      </div>

      {pulse ? (
        <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
          <circle cx={pulse.x} cy={pulse.y} r={20} fill={LINK} opacity={0.18} />
          <circle cx={pulse.x} cy={pulse.y} r={9} fill={ACCENT} stroke={PAPER} strokeWidth={2} />
        </svg>
      ) : null}

      <Sfx at={gwAt} name="tick" volume={0.15} />
      <Sfx at={coAt} name="tick" volume={0.15} />
      <Sfx at={payAt} name="tick" volume={0.15} />
      <Sfx at={foldAt} name="pop" volume={0.2} />
      <Audio src={staticFile(getScene(voiceover, "map").audioFile)} />
    </Tile>
  );
};
