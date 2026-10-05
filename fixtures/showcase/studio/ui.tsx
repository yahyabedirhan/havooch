import { loadFont as loadSerif } from "@remotion/google-fonts/Fraunces";
import { loadFont as loadSans } from "@remotion/google-fonts/InterTight";
import { Easing, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";

export const serif = loadSerif("normal", { weights: ["300", "400", "500"], subsets: ["latin"] }).fontFamily;
loadSerif("italic", { weights: ["300", "400"], subsets: ["latin"] });
export const sans = loadSans("normal", { weights: ["300", "400", "500", "600", "700"], subsets: ["latin"] }).fontFamily;

export const easeOut = Easing.bezier(0.22, 1, 0.36, 1);
export const easeInOut = Easing.bezier(0.65, 0, 0.35, 1);

// Clamped, eased interpolation: the one curve every scene moves on.
export const tween = (frame: number, input: [number, number], output: [number, number], easing = easeOut) =>
  interpolate(frame, input, output, { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing });

export const useSpring = (delay: number, damping = 200) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - delay, fps, config: { damping } });
};

// A deterministic random number in 0..1 for a seed.
export const rand = (seed: number) => {
  const x = Math.sin(seed * 12.9898) * 43758.5453;
  return x - Math.floor(x);
};

// A line of text that rises out of a mask.
export const MaskLine: React.FC<{ delay: number; children: React.ReactNode; style?: React.CSSProperties; duration?: number }> = ({
  delay,
  children,
  style,
  duration = 22,
}) => {
  const frame = useCurrentFrame();
  const p = tween(frame, [delay, delay + duration], [0, 1]);
  return (
    <div style={{ overflow: "hidden", paddingBottom: "0.12em", marginBottom: "-0.12em", ...style }}>
      <div style={{ transform: `translateY(${(1 - p) * 105}%)` }}>{children}</div>
    </div>
  );
};

// The Halcyon mark: a sun on the horizon and its reflection.
export const SunMark: React.FC<{ size: number; color?: string }> = ({ size, color = "#FFF8EE" }) => (
  <svg width={size} height={size} viewBox="0 0 100 100">
    <defs>
      <linearGradient id="hal-sun" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#FFE9C2" />
        <stop offset="1" stopColor="#F59A5A" />
      </linearGradient>
      <clipPath id="hal-above">
        <rect x="0" y="0" width="100" height="62" />
      </clipPath>
    </defs>
    <circle cx="50" cy="62" r="28" fill="url(#hal-sun)" clipPath="url(#hal-above)" />
    <rect x="12" y="67" width="76" height="5" rx="2.5" fill={color} />
    <rect x="26" y="78" width="48" height="5" rx="2.5" fill={color} opacity="0.7" />
    <rect x="38" y="89" width="24" height="5" rx="2.5" fill={color} opacity="0.4" />
  </svg>
);
