import { Series, useVideoConfig } from "remotion";
import { sceneFrames } from "../../src/lib/timing";
import { Close } from "./scenes/Close";
import { Numbers } from "./scenes/Numbers";
import { Rain } from "./scenes/Rain";
import { Reveal } from "./scenes/Reveal";
import { Today } from "./scenes/Today";
import { Week } from "./scenes/Week";
import voiceover from "./voiceover.json";

export const HalcyonTeaser: React.FC = () => {
  const { fps } = useVideoConfig();
  const len = (id: string) => sceneFrames(voiceover, id, fps);

  return (
    <Series>
      <Series.Sequence name="Numbers" durationInFrames={len("numbers")} premountFor={fps}>
        <Numbers />
      </Series.Sequence>
      <Series.Sequence name="Reveal" durationInFrames={len("reveal")} premountFor={fps}>
        <Reveal />
      </Series.Sequence>
      <Series.Sequence name="Today" durationInFrames={len("today")} premountFor={fps}>
        <Today />
      </Series.Sequence>
      <Series.Sequence name="Rain" durationInFrames={len("rain")} premountFor={fps}>
        <Rain />
      </Series.Sequence>
      <Series.Sequence name="Week" durationInFrames={len("week")} premountFor={fps}>
        <Week />
      </Series.Sequence>
      <Series.Sequence name="Close" durationInFrames={len("close")} premountFor={fps}>
        <Close />
      </Series.Sequence>
    </Series>
  );
};

export default HalcyonTeaser;
