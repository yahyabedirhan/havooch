import { Audio } from "@remotion/media";
import { Sequence, Series, interpolate, staticFile, useVideoConfig } from "remotion";
import { sceneFrames, totalFrames } from "@studio/lib/timing";
import { Close } from "./scenes/Close";
import { Cold } from "./scenes/Cold";
import { Fix } from "./scenes/Fix";
import { Logo } from "./scenes/Logo";
import { ServiceMap } from "./scenes/Map";
import { Trace } from "./scenes/Trace";
import voiceover from "./voiceover.json";

export const LanternTeaser: React.FC = () => {
  const { fps } = useVideoConfig();
  const total = totalFrames(voiceover, fps);

  return (
    <>
      <Series>
        <Series.Sequence name="Cold" durationInFrames={sceneFrames(voiceover, "cold", fps)} premountFor={fps}>
          <Cold />
        </Series.Sequence>
        <Series.Sequence name="Logo" durationInFrames={sceneFrames(voiceover, "logo", fps)} premountFor={fps}>
          <Logo />
        </Series.Sequence>
        <Series.Sequence name="Map" durationInFrames={sceneFrames(voiceover, "map", fps)} premountFor={fps}>
          <ServiceMap />
        </Series.Sequence>
        <Series.Sequence name="Trace" durationInFrames={sceneFrames(voiceover, "trace", fps)} premountFor={fps}>
          <Trace />
        </Series.Sequence>
        <Series.Sequence name="Fix" durationInFrames={sceneFrames(voiceover, "fix", fps)} premountFor={fps}>
          <Fix />
        </Series.Sequence>
        <Series.Sequence name="Close" durationInFrames={sceneFrames(voiceover, "close", fps)} premountFor={fps}>
          <Close />
        </Series.Sequence>
      </Series>
      {/* A quiet synth bed under the whole video, and the sting at the end. */}
      <Audio
        src={staticFile("lantern-teaser/assets/sound/bed.wav")}
        volume={(f) => interpolate(f, [0, fps, total - 2 * fps, total], [0, 0.07, 0.07, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })}
      />
      <Sequence from={total - Math.round(3.2 * fps)} premountFor={fps}>
        <Audio src={staticFile("lantern-teaser/assets/sound/sting.wav")} volume={0.22} />
      </Sequence>
    </>
  );
};

export default LanternTeaser;
