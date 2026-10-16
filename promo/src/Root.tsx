import { Composition } from "remotion";
import { Promo } from "./Promo";
import { Q } from "./lib/cues";
import { loadFonts } from "./fonts/load";

loadFonts();

const FPS = Q.fps;
const FRAMES = Math.round(Q.duration * FPS);

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="BRB-EN-16x9"
        component={Promo}
        durationInFrames={FRAMES}
        fps={FPS}
        width={1920}
        height={1080}
        defaultProps={{ lang: "en" as const, format: "wide" as const }}
      />
      <Composition
        id="BRB-ZH-16x9"
        component={Promo}
        durationInFrames={FRAMES}
        fps={FPS}
        width={1920}
        height={1080}
        defaultProps={{ lang: "zh" as const, format: "wide" as const }}
      />
      <Composition
        id="BRB-EN-9x16"
        component={Promo}
        durationInFrames={FRAMES}
        fps={FPS}
        width={1080}
        height={1920}
        defaultProps={{ lang: "en" as const, format: "tall" as const }}
      />
      <Composition
        id="BRB-ZH-9x16"
        component={Promo}
        durationInFrames={FRAMES}
        fps={FPS}
        width={1080}
        height={1920}
        defaultProps={{ lang: "zh" as const, format: "tall" as const }}
      />
    </>
  );
};
