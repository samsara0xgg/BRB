import React from "react";
import { Q } from "../lib/cues";
import { useCtx } from "../lib/ctx";
import { C, FONT } from "../lib/theme";
import { E, clamp, map, ramp, springAt } from "../lib/time";
import { AppIcon } from "../ui/AppIcon";
import { Backdrop } from "../mac/Stage";

const I = Q.intro;

/** How far the intro has zoomed into the icon's watch light, 1 → about 80. */
export const introZoom = (t: number) => {
  const k = ramp(t, I.toMenu - 0.07, I.end, (n) => n * n * n * n);
  return Math.exp(Math.log(80) * k);
};

/** The icon's size and where its watch light sits, for the circular reveal of the next shot. */
export const introDot = (W: number, H: number, tall: boolean) => {
  const S = tall ? 300 : 236;
  const cx = W / 2;
  const iconTop = H / 2 - S * (tall ? 0.95 : 0.88);
  return { S, x: cx, y: iconTop + 0.4854 * S, r: 0.0699 * S };
};

// The rest of each word, roughly in em, so it can fold away.
const REST_EM = [0.62, 1.6, 2.02];

export const Intro: React.FC = () => {
  const { t, W, H, fps, lang, copy, format } = useCtx();
  if (t > I.end + 0.05) return null;
  const tall = format === "tall";
  const fs = tall ? 150 : 176;
  const words = [
    ["B", "e"],
    ["R", "ight"],
    ["B", "ack."],
  ];
  const fold = ramp(t, I.collapse, I.collapse + 0.46, E.inOut);
  const amber = ramp(t, I.collapse + 0.12, I.collapse + 0.5);
  const iconIn = springAt(t, I.shield, fps, { damping: 11, stiffness: 150 });
  const lift = ramp(t, I.shield - 0.06, I.shield + 0.4, E.out);
  const zoom = introZoom(t);
  const dot = introDot(W, H, tall);
  const wordY = H / 2 + (tall ? 40 : 30) + lift * (tall ? 150 : 120);

  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: C.night }}>
      <div style={{ position: "absolute", inset: 0, opacity: 0.55 * ramp(t, 0, 0.8) }}>
        <Backdrop W={W} H={H} yaw={-6 * t} t={t} alarm={0} tint="#000" />
        <div style={{ position: "absolute", inset: 0, background: "rgba(5,7,14,0.55)" }} />
      </div>
      <div
        style={{
          position: "absolute",
          inset: 0,
          transformOrigin: `${dot.x}px ${dot.y}px`,
          transform: `scale(${zoom})`,
        }}
      >
        {/* the icon */}
        <div
          style={{
            position: "absolute",
            left: dot.x - dot.S / 2,
            top: dot.y - 0.4854 * dot.S,
            width: dot.S,
            height: dot.S,
            opacity: clamp(iconIn * 1.6),
            transform: `scale(${0.55 + 0.45 * iconIn}) translateY(${(1 - iconIn) * 30}px)`,
            filter: iconIn < 1 ? `blur(${(1 - clamp(iconIn)) * 12}px)` : undefined,
          }}
        >
          <div
            style={{
              position: "absolute",
              inset: -dot.S * 0.5,
              background: "radial-gradient(closest-side, rgba(246,181,68,0.35), rgba(246,181,68,0) 70%)",
              opacity: iconIn,
            }}
          />
          <AppIcon
            size={dot.S}
            sheen={map(t, [I.shield + 0.15, I.shield + 0.9], [0, 1.4])}
            style={{ filter: "drop-shadow(0 18px 40px rgba(0,0,0,0.6))" }}
          />
        </div>

        {/* Be right back. → BRB */}
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            top: wordY,
            transform: "translateY(-50%)",
            display: "flex",
            justifyContent: "center",
            fontFamily: FONT.display,
            fontWeight: 800,
            fontSize: fs * (1 - 0.1 * fold),
            letterSpacing: "-0.04em",
            color: "#fff",
            whiteSpace: "nowrap",
          }}
        >
          {words.map(([initial, rest], i) => {
            const k = clamp((t - [I.w1, I.w2, I.w3][i]) / 0.55);
            const e = E.expoOut(k);
            const restW = REST_EM[i] * (1 - fold);
            return (
              <span
                key={i}
                style={{
                  display: "inline-flex",
                  opacity: e,
                  transform: `translateY(${(1 - e) * 46}px)`,
                  filter: k < 1 ? `blur(${(1 - e) * 16}px)` : undefined,
                  marginRight: i < 2 ? `${0.24 * (1 - fold) + 0.01}em` : 0,
                }}
              >
                <span style={{ position: "relative", display: "inline-block" }}>
                  {initial}
                  <span
                    style={{
                      position: "absolute",
                      left: 0,
                      top: 0,
                      backgroundImage: `linear-gradient(180deg, ${C.amberHi} 15%, ${C.amber} 60%, ${C.amberLow} 100%)`,
                      WebkitBackgroundClip: "text",
                      backgroundClip: "text",
                      color: "transparent",
                      opacity: amber,
                    }}
                  >
                    {initial}
                  </span>
                </span>
                <span
                  style={{
                    display: "inline-block",
                    overflow: "hidden",
                    maxWidth: `${restW}em`,
                    opacity: 1 - fold * 1.3,
                    filter: fold > 0 ? `blur(${fold * 10}px)` : undefined,
                  }}
                >
                  {rest}
                </span>
              </span>
            );
          })}
        </div>
        {lang === "zh" && (
          <div
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              top: wordY + fs * 0.62,
              textAlign: "center",
              fontFamily: FONT.zh,
              fontWeight: 600,
              fontSize: fs * 0.26,
              letterSpacing: "0.5em",
              paddingLeft: "0.5em",
              color: "rgba(255,255,255,0.72)",
              opacity: ramp(t, I.w3 + 0.2, I.w3 + 0.6) * (1 - ramp(t, I.collapse, I.collapse + 0.3)),
            }}
          >
            {copy.introSub}
          </div>
        )}
      </div>
    </div>
  );
};
