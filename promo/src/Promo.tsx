import React from "react";
import { AbsoluteFill, Audio, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { COPY, Lang } from "./lib/copy";
import { Format, Provider, useCtx } from "./lib/ctx";
import { Q } from "./lib/cues";
import { C } from "./lib/theme";
import { Intro, introDot, introZoom } from "./scenes/Intro";
import { MacWorld } from "./scenes/MacShots";
import { PhoneScene, phoneFocus } from "./phone/Phone";
import { Bento } from "./scenes/Bento";
import { EndCard } from "./scenes/EndCard";
import { E, ramp } from "./lib/time";
import { Caption } from "./ui/Caption";
import { Grain } from "./ui/Grain";

export type PromoProps = { lang: Lang; format: Format };

/** The captions over the Mac shots. */
const MacCaptions: React.FC = () => {
  const { t, copy, format, W, H } = useCtx();
  const tall = format === "tall";
  const side = tall ? "top" : "left";
  const c = copy;
  return (
    <>
      <Caption lines={c.setup} sub={c.setupSub} t={t} inAt={Q.setup.start + 0.25} outAt={Q.setup.end - 0.3} place={side} />
      <Caption
        lines={c.arm}
        sub={c.armSub}
        t={t}
        inAt={Q.arm.start + 0.15}
        outAt={Q.arm.end - 0.3}
        place={tall ? "top" : "bottom"}
        maxWidth={W * 0.3}
        y={tall ? undefined : H * 0.08}
        scrim={1}
      />
      <Caption lines={c.guard} sub={c.guardSub} t={t} inAt={Q.guard.start + 0.2} outAt={Q.guard.end - 0.55} place={side} />
      <Caption lines={c.touch} sub={c.touchSub} t={t} inAt={Q.touch.flood + 0.05} outAt={Q.touch.end - 0.2} place={side} />
      <Caption lines={c.lift} sub={c.liftSub} t={t} inAt={Q.lift.up + 0.1} outAt={Q.lift.end - 0.2} place={side} />
      <Caption lines={c.phone} sub={c.phoneSub} t={t} inAt={Q.phone.start + 0.42} outAt={Q.phone.end - 0.5} place={side} />
      <Caption lines={c.putback} sub={c.putbackSub} t={t} inAt={Q.putback.thud + 0.06} outAt={Q.putback.end - 0.2} place={side} />
      <Caption
        lines={c.back}
        sub={c.backSub}
        t={t}
        inAt={Q.touchid.start + 0.1}
        outAt={Q.welcome.shrink - 0.15}
        place={tall ? "top" : "bottom"}
        y={tall ? undefined : H * 0.08}
        scrim={1}
      />
    </>
  );
};

const Film: React.FC = () => {
  const { t, W, H, format } = useCtx();
  const tall = format === "tall";
  const I = Q.intro;
  const dot = introDot(W, H, tall);
  const zoom = introZoom(t);
  const revealR = t >= I.toMenu - 0.07 ? dot.r * zoom : 0;
  // Out of the Mac: on into the menu-bar shield, then away.
  const macOut = ramp(t, Q.welcome.land + 0.05, Q.bento.start + 0.12, E.in);
  const macOn = t >= I.toMenu - 0.07 && t < Q.bento.start + 0.12;
  return (
    <AbsoluteFill style={{ background: C.night }}>
      {t < I.end + 0.05 && <Intro />}
      {macOn && (
        <div
          style={{
            position: "absolute",
            inset: 0,
            clipPath: t < I.end ? `circle(${revealR}px at ${dot.x}px ${dot.y}px)` : undefined,
            transform: macOut > 0 ? `scale(${1 + 0.3 * macOut})` : undefined,
            opacity: 1 - macOut,
            filter: macOut > 0 ? `blur(${macOut * 16 * (W / 1920)}px)` : undefined,
          }}
        >
          <MacWorld blur={phoneFocus(t) * 18 * (W / 1920)} dim={phoneFocus(t) * 0.42} />
          <PhoneScene />
          <MacCaptions />
        </div>
      )}
      <Bento />
      <EndCard />
      <Grain t={t} W={W} H={H} />
      {/* Music and sound, made from the same cue sheet by scripts/soundtrack.py. */}
      <Audio src={staticFile("audio/soundtrack.wav")} />
    </AbsoluteFill>
  );
};

export const Promo: React.FC<PromoProps> = ({ lang, format }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const t = frame / fps;
  return (
    <Provider value={{ lang, format, copy: COPY[lang], t, fps, W: width, H: height }}>
      <Film />
    </Provider>
  );
};
