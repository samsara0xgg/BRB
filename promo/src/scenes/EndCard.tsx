import React from "react";
import { Q } from "../lib/cues";
import { useCtx } from "../lib/ctx";
import { C, FONT } from "../lib/theme";
import { E, clamp, map, ramp, springAt } from "../lib/time";
import { Backdrop } from "../mac/Stage";
import { AppIcon } from "../ui/AppIcon";

const N = Q.end;

/** One line of the end card rising into place. */
const Rise: React.FC<{ at: number; children: React.ReactNode; style?: React.CSSProperties }> = ({ at, children, style }) => {
  const { t } = useCtx();
  const k = clamp((t - at) / 0.6);
  const e = E.expoOut(k);
  return (
    <div style={{ opacity: e, transform: `translateY(${(1 - e) * 26}px)`, filter: k < 1 ? `blur(${(1 - e) * 10}px)` : undefined, ...style }}>
      {children}
    </div>
  );
};

/** The app icon, the name, one line, and where to get it. */
export const EndCard: React.FC = () => {
  const { t, W, H, format, fps, copy, lang } = useCtx();
  if (t < N.start - 0.3) return null;
  const tall = format === "tall";
  const zh = lang === "zh";
  const S = tall ? 300 : 232;
  const icon = springAt(t, N.icon, fps, { damping: 12, stiffness: 140 });
  const fade = ramp(t, N.fade, Q.duration, E.inOut);
  const glow = ramp(t, N.icon, N.icon + 0.8) * (0.85 + 0.15 * Math.sin((t - N.icon) * 2.2));
  const bg = ramp(t, N.start - 0.25, N.start + 0.15);

  return (
    <div style={{ position: "absolute", inset: 0, background: C.night, opacity: bg }}>
      <div style={{ position: "absolute", inset: 0, opacity: 0.4 }}>
        <Backdrop W={W} H={H} yaw={-4 * (t - N.start)} t={t} alarm={0} tint="#000" />
        <div style={{ position: "absolute", inset: 0, background: "rgba(5,7,14,0.6)" }} />
      </div>
      <div
        style={{
          position: "absolute",
          left: W / 2 - S * 2,
          top: H * (tall ? 0.38 : 0.33) - S * 2,
          width: S * 4,
          height: S * 4,
          background: "radial-gradient(closest-side, rgba(246,181,68,0.26), rgba(246,181,68,0) 70%)",
          opacity: glow,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: H * (tall ? 0.38 : 0.33) - S / 2,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          color: "#fff",
          textAlign: "center",
        }}
      >
        <div
          style={{
            width: S,
            height: S,
            opacity: clamp(icon * 1.6),
            transform: `scale(${0.6 + 0.4 * icon}) translateY(${(1 - icon) * 30}px)`,
            filter: icon < 0.98 ? `blur(${(1 - clamp(icon)) * 12}px)` : undefined,
          }}
        >
          <AppIcon size={S} sheen={map(t, [N.icon + 0.25, N.icon + 1.1], [0, 1.4])} style={{ filter: "drop-shadow(0 24px 50px rgba(0,0,0,0.65))" }} />
        </div>
        <Rise at={N.word} style={{ marginTop: tall ? 46 : 34 }}>
          <div style={{ fontFamily: FONT.display, fontWeight: 800, fontSize: tall ? 150 : 128, letterSpacing: "-0.045em", lineHeight: 1 }}>BRB</div>
        </Rise>
        <Rise at={N.tag} style={{ marginTop: tall ? 26 : 20 }}>
          <div
            style={{
              fontFamily: zh ? FONT.zh : FONT.text,
              fontWeight: 500,
              fontSize: tall ? 44 : 36,
              color: "rgba(255,255,255,0.72)",
              letterSpacing: zh ? "0.04em" : "-0.01em",
              maxWidth: tall ? W * 0.82 : undefined,
            }}
          >
            {copy.endLine}
          </div>
        </Rise>
        <Rise at={N.cta} style={{ marginTop: tall ? 64 : 48 }}>
          <div
            style={{
              padding: tall ? "24px 56px" : "20px 48px",
              borderRadius: 999,
              backgroundImage: `linear-gradient(180deg, ${C.amberHi}, ${C.amber} 60%, ${C.amberLow})`,
              color: C.ink,
              fontFamily: zh ? FONT.zh : FONT.display,
              fontWeight: 700,
              fontSize: tall ? 44 : 36,
              letterSpacing: zh ? "0.04em" : "-0.01em",
              boxShadow: "inset 0 1px 0 rgba(255,255,255,0.5), 0 14px 40px rgba(246,181,68,0.32)",
            }}
          >
            {copy.endCta}
          </div>
        </Rise>
        <Rise at={N.cta + 0.2} style={{ marginTop: tall ? 30 : 24 }}>
          <div
            style={{
              fontFamily: zh ? FONT.zh : FONT.text,
              fontWeight: 500,
              fontSize: tall ? 28 : 22,
              color: "rgba(255,255,255,0.42)",
              letterSpacing: zh ? "0.06em" : "0.01em",
            }}
          >
            {copy.endFine}
          </div>
        </Rise>
      </div>
      <div style={{ position: "absolute", inset: 0, background: "#000", opacity: fade }} />
    </div>
  );
};
