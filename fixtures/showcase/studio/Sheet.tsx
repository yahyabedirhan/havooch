import { AbsoluteFill } from "remotion";
import { ACCENT, FOLD_MUTED, INK, LINE, LINK, MUTED, PAPER, PAPER_2, SHADE, SOFT } from "./config";
import { Arrow, DarkFace, Eyebrow, Flip, LightFace, Mark, Node, Tile, TypeTag, mono, sans, title } from "./graphite";

const SWATCHES = [
  ["paper", PAPER],
  ["paper-2", PAPER_2],
  ["ink", INK],
  ["muted", MUTED],
  ["soft", SOFT],
  ["accent", ACCENT],
  ["shade", SHADE],
  ["fold-muted", FOLD_MUTED],
  ["link", LINK],
];

// The asset sheet: palette, type, the mark, nodes, arrows, spans, chips and the panel.
export const LanternSheet: React.FC = () => (
  <Tile>
    <AbsoluteFill>
      <Eyebrow style={{ position: "absolute", left: 80, top: 60 }}>lantern teaser · asset sheet</Eyebrow>
      <div style={{ position: "absolute", left: 80, top: 100, display: "flex", gap: 14 }}>
        {SWATCHES.map(([n, c]) => (
          <div key={n} style={{ width: 120 }}>
            <div style={{ height: 56, background: c, boxShadow: `inset 0 0 0 1px ${LINE}` }} />
            <div style={{ fontFamily: mono, fontSize: 15, color: MUTED, marginTop: 6 }}>{n}</div>
          </div>
        ))}
      </div>
      <div style={{ position: "absolute", left: 80, top: 210 }}>
        <div style={{ fontFamily: title, fontWeight: 600, fontSize: 64, color: INK, letterSpacing: "-0.01em" }}>Space Grotesk 600</div>
        <div style={{ fontFamily: sans, fontWeight: 600, fontSize: 34, color: INK }}>Inter Tight 600 node name</div>
        <div style={{ fontFamily: sans, fontWeight: 400, fontSize: 34, color: MUTED }}>Inter Tight 400 callout line</div>
        <div style={{ fontFamily: mono, fontSize: 26, color: MUTED }}>IBM Plex Mono 400 · SELECT … FROM orders  1.12 s</div>
      </div>
      <div style={{ position: "absolute", left: 1290, top: 60, display: "flex", alignItems: "center", gap: 36 }}>
        <Mark size={130} />
        <div>
          <div style={{ fontFamily: title, fontWeight: 600, fontSize: 110, color: INK, lineHeight: 1 }}>Lantern</div>
          <div style={{ fontFamily: sans, fontSize: 32, color: MUTED, marginTop: 10 }}>See where the time goes.</div>
        </div>
      </div>
      <div style={{ position: "absolute", left: 80, top: 440, display: "flex", gap: 10 }}>
        {["APP", "API", "SVC", "DB", "CACHE"].map((t) => (
          <TypeTag key={t}>{t}</TypeTag>
        ))}
      </div>
      <Node x={80} y={500} tag="SVC" name="Checkout" sub="orders" w={270} glow={0} />
      <Node x={380} y={500} tag="SVC" name="Checkout" sub="orders" w={270} glow={1} />
      <Node x={680} y={500} tag="SVC" name="Payments" sub="waits 1.31 s" w={270} fold={1} />
      <Node x={980} y={500} tag="SVC" name="Payments" sub="flip midway" w={270} fold={0.35} />
      <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
        <Arrow pts={[{ x: 1300, y: 520 }, { x: 1500, y: 520 }]} p={1} kind="muted" />
        <Arrow pts={[{ x: 1300, y: 570 }, { x: 1500, y: 570 }]} p={1} kind="link" />
        <Arrow pts={[{ x: 1300, y: 620 }, { x: 1500, y: 620 }]} p={1} kind="focal" />
        <circle cx={1600} cy={570} r={20} fill={LINK} opacity={0.18} />
        <circle cx={1600} cy={570} r={9} fill={ACCENT} stroke={PAPER} strokeWidth={2} />
      </svg>
      <div style={{ position: "absolute", left: 80, top: 690, width: 600, height: 46 }}>
        <DarkFace />
      </div>
      <div style={{ position: "absolute", left: 80, top: 760, width: 600, height: 46 }}>
        <DarkFace glow={1} />
      </div>
      <div style={{ position: "absolute", left: 80, top: 830, width: 600, height: 46 }}>
        <LightFace ear={18} />
      </div>
      <div style={{ position: "absolute", left: 760, top: 690, width: 400, height: 140 }}>
        <Flip p={1} style={{ inset: 0 }} dark={<DarkFace />} light={<LightFace ear={34}><div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", fontFamily: mono, fontSize: 90, color: PAPER }}>1.84 s</div></LightFace>} />
      </div>
      <div style={{ position: "absolute", left: 1230, top: 690, width: 580, height: 300 }}>
        <LightFace ear={30}>
          <div style={{ padding: "30px 36px" }}>
            <TypeTag folded>FIX</TypeTag>
            <div style={{ fontFamily: title, fontWeight: 600, fontSize: 40, color: PAPER, marginTop: 18 }}>Add an index on orders(user_id)</div>
            <div style={{ marginTop: 18, padding: "14px 18px", background: "#eceef0", fontFamily: mono, fontSize: 22, color: PAPER }}>CREATE INDEX ON orders (user_id);</div>
          </div>
        </LightFace>
      </div>
      <div style={{ position: "absolute", left: 760, top: 880, fontFamily: mono, fontSize: 26, letterSpacing: "0.16em", color: SOFT }}>PRIVATE BETA · SPRING 2027</div>
    </AbsoluteFill>
  </Tile>
);

export default LanternSheet;
