// The Graphite look for this video: folded white paper on a dark granite tile.
// Only the one focal element of a scene folds white, with a shade dog-ear.
import { loadFont as loadTitle } from "@remotion/google-fonts/SpaceGrotesk";
import { loadFont as loadSans } from "@remotion/google-fonts/InterTight";
import { loadFont as loadMono } from "@remotion/google-fonts/IBMPlexMono";
import { Audio } from "@remotion/media";
import { AbsoluteFill, Easing, Sequence, interpolate, staticFile, useVideoConfig } from "remotion";
import {
  ACCENT,
  FOLD_MUTED,
  INK,
  LINE,
  LINK,
  MUTED,
  PAPER,
  PAPER_2,
  SHADE,
  SOFT,
  STORYBOARD,
} from "./config";

export const title = loadTitle("normal", { weights: ["600"], subsets: ["latin"] }).fontFamily;
export const sans = loadSans("normal", { weights: ["400", "600"], subsets: ["latin"] }).fontFamily;
export const mono = loadMono("normal", { weights: ["400"], subsets: ["latin"] }).fontFamily;

export const easeOut = Easing.bezier(0.22, 1, 0.36, 1);
export const easeInOut = Easing.bezier(0.65, 0, 0.35, 1);

// Clamped, eased interpolation. With STORYBOARD on it returns the end value, so a still shows the end pose.
export const tween = (
  frame: number,
  input: [number, number],
  output: [number, number] = [0, 1],
  easing = easeOut,
) =>
  STORYBOARD
    ? output[1]
    : interpolate(frame, input, output, { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing });

// The ground of every scene: the tile gradient with a double rim inside the frame's edge.
export const Tile: React.FC<{ children?: React.ReactNode }> = ({ children }) => (
  <AbsoluteFill style={{ background: `linear-gradient(180deg, ${PAPER_2} 0%, ${PAPER} 100%)`, overflow: "hidden" }}>
    <svg width={1920} height={1080} style={{ position: "absolute", inset: 0 }}>
      <defs>
        <linearGradient id="rim-outer" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#fff" stopOpacity="0.32" />
          <stop offset="1" stopColor="#fff" stopOpacity="0.08" />
        </linearGradient>
        <linearGradient id="rim-inner" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#fff" stopOpacity="0.14" />
          <stop offset="1" stopColor="#fff" stopOpacity="0.03" />
        </linearGradient>
      </defs>
      <rect x={14.5} y={14.5} width={1891} height={1051} rx={10} fill="none" stroke="url(#rim-outer)" strokeWidth={1} />
      <rect x={22.5} y={22.5} width={1875} height={1035} rx={2} fill="none" stroke="url(#rim-inner)" strokeWidth={1} />
    </svg>
    {children}
  </AbsoluteFill>
);

// A small uppercase mono label above a title or a group.
export const Eyebrow: React.FC<{ children: React.ReactNode; style?: React.CSSProperties }> = ({ children, style }) => (
  <div style={{ fontFamily: mono, fontSize: 22, letterSpacing: "0.18em", textTransform: "uppercase", color: MUTED, ...style }}>
    {children}
  </div>
);

// A type tag: square corners, mono, outlined.
export const TypeTag: React.FC<{ children: string; folded?: boolean; size?: number }> = ({ children, folded, size = 18 }) => (
  <span
    style={{
      display: "inline-block",
      fontFamily: mono,
      fontSize: size,
      letterSpacing: "0.12em",
      lineHeight: 1,
      padding: `${size * 0.35}px ${size * 0.5}px`,
      border: `1px solid ${folded ? "rgba(19,20,23,0.35)" : LINE}`,
      color: folded ? FOLD_MUTED : MUTED,
      borderRadius: 0,
    }}
  >
    {children}
  </span>
);

// The dog-ear: the top-right corner cut at 45 degrees, its folded face in shade.
export const DogEar: React.FC<{ size: number; bg?: string }> = ({ size, bg = "transparent" }) => (
  <svg width={size} height={size} style={{ position: "absolute", top: 0, right: 0 }}>
    <polygon points={`0,0 ${size},0 ${size},${size}`} fill={bg} />
    <polygon points={`0,0 0,${size} ${size},${size}`} fill={SHADE} />
  </svg>
);

// A card that flips about its horizontal axis from its dark face (p = 0) to its folded white face (p = 1).
export const Flip: React.FC<{
  p: number;
  dark: React.ReactNode;
  light: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ p, dark, light, style }) => {
  const angle = p * 180;
  const showLight = angle >= 90;
  return (
    <div style={{ position: "absolute", perspective: 1600, ...style }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          transform: `rotateX(${showLight ? angle - 180 : angle}deg)`,
        }}
      >
        {showLight ? light : dark}
      </div>
    </div>
  );
};

// The faces a node or panel can show.
export const DarkFace: React.FC<{ children?: React.ReactNode; glow?: number; style?: React.CSSProperties }> = ({
  children,
  glow = 0,
  style,
}) => (
  <div
    style={{
      position: "absolute",
      inset: 0,
      background: PAPER_2,
      borderRadius: 2,
      boxShadow: `inset 0 0 0 ${1 + glow}px ${glow > 0 ? mix(LINE_RGB, LINK_RGB, glow) : LINE}`,
      ...style,
    }}
  >
    {children}
  </div>
);

export const LightFace: React.FC<{ children?: React.ReactNode; ear?: number; style?: React.CSSProperties }> = ({
  children,
  ear = 26,
  style,
}) => (
  <div
    style={{
      position: "absolute",
      inset: 0,
      background: ACCENT,
      borderRadius: 2,
      clipPath: `polygon(0 0, calc(100% - ${ear}px) 0, 100% ${ear}px, 100% 100%, 0 100%)`,
      ...style,
    }}
  >
    <svg width={ear} height={ear} style={{ position: "absolute", top: 0, right: 0 }}>
      <polygon points={`0,0 0,${ear} ${ear},${ear}`} fill={SHADE} />
    </svg>
    {children}
  </div>
);

const LINE_RGB: [number, number, number, number] = [255, 255, 255, 0.16];
const LINK_RGB: [number, number, number, number] = [157, 179, 200, 1];
const mix = (a: number[], b: number[], t: number) =>
  `rgba(${a.map((v, i) => (i < 3 ? Math.round(v + (b[i] - v) * t) : (v + (b[i] - v) * t).toFixed(3))).join(",")})`;

// A service node: type tag, name and sublabel. `fold` flips it to the folded white focal face.
export const Node: React.FC<{
  x: number;
  y: number;
  w?: number;
  h?: number;
  tag: string;
  name: string;
  sub: string;
  fold?: number;
  glow?: number;
  opacity?: number;
  lift?: number;
}> = ({ x, y, w = 280, h = 150, tag, name, sub, fold = 0, glow = 0, opacity = 1, lift = 0 }) => {
  const content = (folded: boolean) => (
    <div style={{ position: "absolute", left: 24, top: 20, right: 24 }}>
      <TypeTag folded={folded}>{tag}</TypeTag>
      <div style={{ fontFamily: sans, fontWeight: 600, fontSize: 34, color: folded ? PAPER : INK, marginTop: 14, lineHeight: 1.05 }}>
        {name}
      </div>
      <div style={{ fontFamily: mono, fontSize: 20, color: folded ? FOLD_MUTED : MUTED, marginTop: 8 }}>{sub}</div>
    </div>
  );
  return (
    <Flip
      p={fold}
      style={{ left: x, top: y - lift, width: w, height: h, opacity }}
      dark={<DarkFace glow={glow}>{content(false)}</DarkFace>}
      light={<LightFace>{content(true)}</LightFace>}
    />
  );
};

// A folded arrowhead: a triangle split along its axis, one half shade and one half white.
export const FoldedHead: React.FC<{ x: number; y: number; angle: number; len?: number; half?: number }> = ({
  x,
  y,
  angle,
  len = 32,
  half = 14,
}) => (
  <g transform={`translate(${x} ${y}) rotate(${angle})`}>
    <polygon points={`0,0 ${-len},${-half} ${-len * 0.72},0`} fill={SHADE} />
    <polygon points={`0,0 ${-len * 0.72},0 ${-len},${half}`} fill={ACCENT} />
  </g>
);

// A plain arrowhead in the line's colour.
export const PlainHead: React.FC<{ x: number; y: number; angle: number; color: string }> = ({ x, y, angle, color }) => (
  <g transform={`translate(${x} ${y}) rotate(${angle})`}>
    <polygon points="0,0 -16,-7 -16,7" fill={color} />
  </g>
);

export type Pt = { x: number; y: number };

// A polyline arrow that draws on from 0 to 1. `kind` sets its colour and head.
export const Arrow: React.FC<{ pts: Pt[]; p: number; kind: "muted" | "link" | "focal"; dashed?: boolean }> = ({
  pts,
  p,
  kind,
  dashed,
}) => {
  if (p <= 0) return null;
  const segs = pts.slice(1).map((b, i) => Math.hypot(b.x - pts[i].x, b.y - pts[i].y));
  const total = segs.reduce((a, b) => a + b, 0);
  const tip = pointAt(pts, p);
  const color = kind === "link" ? LINK : kind === "focal" ? ACCENT : MUTED;
  const headLen = kind === "focal" ? 32 : 16;
  const d = pts.map((q, i) => `${i ? "L" : "M"} ${q.x} ${q.y}`).join(" ");
  // Stop the line short of the tip so the head covers its end.
  const shown = Math.max(0, p * total - headLen * 0.7);
  return (
    <g>
      <path
        d={d}
        fill="none"
        stroke={color}
        strokeWidth={kind === "focal" ? 2.4 : 2}
        strokeDasharray={dashed ? `8 8` : `${shown} ${total}`}
        opacity={dashed ? Math.min(1, p * 3) : 1}
      />
      {p > 0.02 ? (
        kind === "focal" ? (
          <FoldedHead x={tip.x} y={tip.y} angle={tip.angle} />
        ) : (
          <PlainHead x={tip.x} y={tip.y} angle={tip.angle} color={color} />
        )
      ) : null}
    </g>
  );
};

// The point at fraction t along a polyline, with the direction of travel in degrees.
export const pointAt = (pts: Pt[], t: number) => {
  const segs = pts.slice(1).map((b, i) => Math.hypot(b.x - pts[i].x, b.y - pts[i].y));
  const total = segs.reduce((a, b) => a + b, 0);
  let d = Math.max(0, Math.min(1, t)) * total;
  for (let i = 0; i < segs.length; i++) {
    const a = pts[i];
    const b = pts[i + 1];
    if (d <= segs[i] || i === segs.length - 1) {
      const k = segs[i] ? Math.min(1, d / segs[i]) : 0;
      return { x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k, angle: (Math.atan2(b.y - a.y, b.x - a.x) * 180) / Math.PI };
    }
    d -= segs[i];
  }
  return { x: pts[0].x, y: pts[0].y, angle: 0 };
};

// The Lantern mark: a folded paper diamond with a cap above and below.
// `p` runs 0 to 1 as the facets unfold one after another; at 1 the mark is whole.
export const Mark: React.FC<{ size: number; p?: number }> = ({ size, p = 1 }) => {
  const step = (i: number) => Math.max(0, Math.min(1, (p - i * 0.16) / 0.36));
  const e = (i: number) => easeOut(step(i));
  const facets = [
    { pts: "50,22 10,72 50,72", fill: ACCENT, ox: 50, sx: true },
    { pts: "50,22 90,72 50,72", fill: SHADE, ox: 50, sx: true },
    { pts: "10,72 50,122 50,72", fill: SHADE, ox: 50, sx: true },
    { pts: "90,72 50,122 50,72", fill: ACCENT, ox: 50, sx: true },
  ];
  const cap = e(4);
  return (
    <svg width={size} height={size * 1.44} viewBox="0 0 100 144" style={{ overflow: "visible" }}>
      {facets.map((f, i) => (
        <polygon
          key={i}
          points={f.pts}
          fill={f.fill}
          opacity={step(i) > 0 ? 1 : 0}
          transform={`translate(50 72) scale(${e(i)} 1) translate(-50 -72)`}
        />
      ))}
      <rect x={50 - 13 * cap} y={8} width={26 * cap} height={6} fill={ACCENT} />
      <rect x={50 - 13 * cap} y={130} width={26 * cap} height={6} fill={SHADE} />
    </svg>
  );
};

// A line of text that rises out of a mask.
export const Rise: React.FC<{ p: number; children: React.ReactNode; style?: React.CSSProperties }> = ({ p, children, style }) => (
  <div style={{ overflow: "hidden", paddingBottom: "0.14em", marginBottom: "-0.14em", ...style }}>
    <div style={{ transform: `translateY(${(1 - p) * 110}%)` }}>{children}</div>
  </div>
);

export const palette = { PAPER, PAPER_2, INK, MUTED, SOFT, LINE, LINK, SHADE, FOLD_MUTED, ACCENT };

// A quiet synth sound effect from this video's assets, played from a cue frame.
export const Sfx: React.FC<{ at: number; name: "pop" | "click" | "tick" | "whoosh"; volume?: number }> = ({ at, name, volume = 0.22 }) => {
  const { fps } = useVideoConfig();
  return (
    <Sequence from={Math.max(0, at)} durationInFrames={fps} premountFor={fps}>
      <Audio src={staticFile(`lantern-teaser/assets/sound/${name}.wav`)} volume={volume} />
    </Sequence>
  );
};
