import React from "react";
import { Q } from "../lib/cues";
import { useCtx } from "../lib/ctx";
import { C, FONT } from "../lib/theme";
import { E, clamp, ramp, rand, springAt } from "../lib/time";
import { SH, SW } from "../mac/Desktop";
import { ScreenAt } from "../mac/Screen";
import { LiveView } from "../phone/LiveView";
import { ActivityCard, CARD } from "../phone/Phone";
import { Caption } from "../ui/Caption";

const B = Q.bento;

/** The frosted screen in miniature: the real veil at a moment while it guards. */
const MiniScreen: React.FC<{ w: number; h: number }> = ({ w, h }) => {
  const s = Math.min((w * 0.7) / SW, (h * 0.8) / SH);
  const sw = SW * s;
  const sh = SH * s;
  return (
    <div
      style={{
        position: "absolute",
        left: (w - sw) / 2 - 7,
        top: (h - sh) / 2 + 6,
        width: sw + 14,
        height: sh + 14,
        borderRadius: 14,
        background: "#08080a",
        boxShadow: "0 0 0 1.5px #3a3c42, 0 24px 50px rgba(0,0,0,0.5), 0 0 80px rgba(246,181,68,0.12)",
      }}
    >
      <div style={{ position: "absolute", left: 7, top: 7, width: sw, height: sh, borderRadius: 7, overflow: "hidden" }}>
        <div style={{ width: SW, height: SH, transform: `scale(${s})`, transformOrigin: "0 0" }}>
          <ScreenAt t={9.7} />
        </div>
      </div>
    </div>
  );
};

/** A sensor trace that jumps when the Mac moves, over the four things it feels. */
const Motion: React.FC<{ w: number; h: number; lt: number }> = ({ w, h, lt }) => {
  const n = 90;
  const tw = w - 70;
  const th = h * 0.42;
  const burst = 0.62;
  const grow = E.out(clamp((lt - 0.15) / 0.5));
  const pts = Array.from({ length: n + 1 }, (_, i) => {
    const x = (i / n) * tw;
    const d = Math.abs(i / n - burst);
    const env = Math.exp(-(d * d) / 0.004) * grow;
    const noise = (rand(i * 1.9 + Math.floor(lt * 12) * 0.37) - 0.5) * 0.12;
    const y = th / 2 + (Math.sin(i * 1.7 + lt * 9) * env * 0.85 + noise) * (th / 2);
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(" ");
  const icons = [
    // lift
    <path
      key="a"
      d="M12 18 V6 M7 10.5 L12 5.5 L17 10.5"
      stroke="currentColor"
      strokeWidth="2.2"
      fill="none"
      strokeLinecap="round"
      strokeLinejoin="round"
    />,
    // lid
    <g key="b" stroke="currentColor" strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 18 H20" />
      <path d="M6.5 16 L9.5 6.5 H18.5 L16 16" />
    </g>,
    // keys
    <g key="c" stroke="currentColor" strokeWidth="1.9" fill="none" strokeLinejoin="round">
      <rect x="3.5" y="6.5" width="17" height="11" rx="2.5" />
      <path d="M7 10 H8 M11.5 10 H12.5 M16 10 H17 M8 14 H16" strokeLinecap="round" />
    </g>,
    // charger
    <path key="d" d="M13.2 3 L6.5 13.2 H11.6 L10.6 21 L17.5 10.6 H12.4 Z" fill="currentColor" />,
  ];
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      <svg width={tw} height={th} style={{ position: "absolute", left: 35, top: h * 0.12, overflow: "visible" }}>
        <line x1="0" x2={tw} y1={th / 2} y2={th / 2} stroke="rgba(255,255,255,0.08)" strokeWidth="1.5" />
        <polyline
          points={pts}
          fill="none"
          stroke={C.amber}
          strokeWidth="3"
          strokeLinejoin="round"
          style={{ filter: "drop-shadow(0 0 6px rgba(246,181,68,0.6))" }}
        />
        <circle
          cx={tw * burst}
          cy={th / 2}
          r={7 + 3 * Math.sin(lt * 8)}
          fill={C.red}
          opacity={grow}
          style={{ filter: "drop-shadow(0 0 8px rgba(255,77,85,0.9))" }}
        />
      </svg>
      <div style={{ position: "absolute", left: 0, right: 0, top: h * 0.62, display: "flex", justifyContent: "center", gap: 16 }}>
        {icons.map((ic, i) => {
          const on = clamp((lt - 0.3 - i * 0.18) / 0.25);
          return (
            <div
              key={i}
              style={{
                width: 52,
                height: 52,
                borderRadius: 16,
                background: `rgba(246,181,68,${0.08 + 0.12 * on})`,
                boxShadow: `inset 0 0 0 1px rgba(246,181,68,${0.2 + 0.35 * on})`,
                color: on > 0.5 ? C.amberHi : "rgba(255,255,255,0.55)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <svg width="26" height="26" viewBox="0 0 24 24">
                {ic}
              </svg>
            </div>
          );
        })}
      </div>
    </div>
  );
};

/** A strip of frames: the ten seconds before the touch are kept too. */
const Rewind: React.FC<{ w: number; h: number; lt: number }> = ({ w, h, lt }) => {
  const { lang } = useCtx();
  const frames = 9;
  const fw = (w - 70) / frames;
  const fh = fw * 0.66;
  const y = h * 0.42;
  const mark = 6; // the touch happens after this many frames
  const sweep = E.inOut(clamp((lt - 0.2) / 1.6));
  const left = 35 + (mark - 4) * fw;
  return (
    <div style={{ position: "absolute", inset: 0 }}>
      {Array.from({ length: frames }, (_, i) => {
        const kept = i >= mark - 4 && i < mark;
        const after = i >= mark;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: 35 + i * fw + 2,
              top: y,
              width: fw - 4,
              height: fh,
              borderRadius: 6,
              background: after
                ? "linear-gradient(180deg, #7a1c26, #3a0d14)"
                : `linear-gradient(180deg, rgba(255,255,255,${kept ? 0.2 : 0.08}), rgba(255,255,255,${kept ? 0.08 : 0.03}))`,
              boxShadow: kept ? "inset 0 0 0 1px rgba(246,181,68,0.5)" : "inset 0 0 0 1px rgba(255,255,255,0.06)",
            }}
          />
        );
      })}
      {/* the kept stretch */}
      <div
        style={{
          position: "absolute",
          left: left + (mark * fw - (mark - 4) * fw) * (1 - sweep),
          top: y - 34,
          width: 4 * fw * sweep,
          height: 18,
          borderTop: `3px solid ${C.amber}`,
          borderLeft: sweep > 0.98 ? `3px solid ${C.amber}` : undefined,
          borderRight: `3px solid ${C.amber}`,
          borderRadius: "6px 6px 0 0",
          boxSizing: "border-box",
        }}
      />
      <div
        style={{
          position: "absolute",
          left,
          width: 4 * fw,
          top: y - 78,
          textAlign: "center",
          fontFamily: FONT.display,
          fontWeight: 800,
          fontSize: 34,
          color: C.amber,
          opacity: ramp(lt, 1.1, 1.5),
        }}
      >
        {lang === "zh" ? "−10 秒" : "−10 s"}
      </div>
      {/* the touch */}
      <div
        style={{
          position: "absolute",
          left: 35 + mark * fw - 1.5,
          top: y - 14,
          width: 3,
          height: fh + 28,
          borderRadius: 2,
          background: C.red,
          boxShadow: "0 0 12px rgba(255,77,85,0.9)",
        }}
      />
    </div>
  );
};

/** "$0", and the "/month" that isn't there. */
const Price: React.FC<{ lt: number; tall: boolean }> = ({ lt, tall }) => {
  const { lang } = useCtx();
  const strike = E.out(clamp((lt - 0.45) / 0.35));
  return (
    <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", gap: 14 }}>
      <div
        style={{
          fontFamily: FONT.display,
          fontWeight: 800,
          fontSize: tall ? 168 : 150,
          letterSpacing: "-0.04em",
          lineHeight: 1,
          backgroundImage: `linear-gradient(180deg, ${C.amberHi} 10%, ${C.amber} 55%, ${C.amberLow} 100%)`,
          WebkitBackgroundClip: "text",
          backgroundClip: "text",
          color: "transparent",
          paddingBottom: 10,
          filter: "drop-shadow(0 10px 30px rgba(246,181,68,0.25))",
        }}
      >
        {lang === "zh" ? "¥0" : "$0"}
      </div>
      <div
        style={{
          position: "relative",
          fontFamily: FONT.text,
          fontWeight: 600,
          fontSize: tall ? 44 : 40,
          color: "rgba(255,255,255,0.45)",
          marginTop: tall ? 40 : 34,
        }}
      >
        {lang === "zh" ? "/月" : "/mo"}
        <div
          style={{ position: "absolute", left: -4, top: "52%", height: 4, width: `calc(${strike * 100}% + 8px)`, background: C.red, borderRadius: 2 }}
        />
      </div>
    </div>
  );
};

const Tile: React.FC<{
  x: number;
  y: number;
  w: number;
  h: number;
  at: number;
  title: string;
  sub: string;
  children: (w: number, h: number, lt: number) => React.ReactNode;
}> = ({ x, y, w, h, at, title, sub, children }) => {
  const { t, fps, format, lang } = useCtx();
  const tall = format === "tall";
  const zh = lang === "zh";
  const sp = springAt(t, at, fps, { damping: 15, stiffness: 140 });
  if (sp <= 0) return null;
  const textH = tall ? 128 : 112;
  const ih = h - textH;
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: w,
        height: h,
        borderRadius: 30,
        overflow: "hidden",
        background: "linear-gradient(180deg, rgba(255,255,255,0.075), rgba(255,255,255,0.03))",
        boxShadow: "inset 0 1px 0 rgba(255,255,255,0.14), inset 0 0 0 1px rgba(255,255,255,0.08), 0 30px 60px rgba(0,0,0,0.35)",
        opacity: clamp(sp * 1.5),
        transform: `translateY(${(1 - sp) * 70}px) scale(${0.9 + 0.1 * sp})`,
        filter: sp < 0.98 ? `blur(${(1 - clamp(sp)) * 10}px)` : undefined,
      }}
    >
      <div style={{ position: "absolute", left: 0, top: 0, width: w, height: ih }}>{children(w, ih, t - at)}</div>
      <div style={{ position: "absolute", left: 30, right: 24, bottom: tall ? 30 : 26, color: "#fff" }}>
        <div
          style={{
            fontFamily: zh ? FONT.zh : FONT.display,
            fontWeight: 700,
            fontSize: tall ? 38 : 34,
            letterSpacing: zh ? "0.02em" : "-0.02em",
            lineHeight: 1.15,
          }}
        >
          {title}
        </div>
        <div
          style={{
            fontFamily: zh ? FONT.zh : FONT.text,
            fontWeight: 500,
            fontSize: tall ? 24 : 21,
            color: "rgba(255,255,255,0.58)",
            marginTop: 6,
            whiteSpace: "nowrap",
          }}
        >
          {sub}
        </div>
      </div>
    </div>
  );
};

/** Six tiles: everything it does, and what it costs. */
export const Bento: React.FC = () => {
  const { t, W, H, format, copy } = useCtx();
  if (t < B.start - 0.2 || t > B.end + 0.1) return null;
  const tall = format === "tall";
  const cols = tall ? 2 : 3;
  const gap = tall ? 22 : 24;
  const gx = tall ? 64 : 150;
  const gy = tall ? H * 0.2 : H * 0.215;
  const gw = W - gx * 2;
  const gh = tall ? H * 0.72 : H * 0.72;
  const rows = 6 / cols;
  const tw = (gw - gap * (cols - 1)) / cols;
  const th = (gh - gap * (rows - 1)) / rows;
  const out = ramp(t, B.end - 0.28, B.end + 0.05, E.in);
  const drift = 1 + 0.025 * ramp(t, B.start, B.end, (n) => n);
  const bg = ramp(t, B.start - 0.25, B.start + 0.2);

  const art: ((w: number, h: number, lt: number) => React.ReactNode)[] = [
    (w, h) => <MiniScreen w={w} h={h} />,
    (w, h, lt) => <Motion w={w} h={h} lt={lt} />,
    (w, h, lt) => <Rewind w={w} h={h} lt={lt} />,
    (w, h, lt) => (
      <div
        style={{
          position: "absolute",
          left: 24,
          top: 24,
          width: w - 48,
          height: h - 24,
          borderRadius: 18,
          overflow: "hidden",
          boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.1)",
        }}
      >
        <LiveView t={15.4 + lt * 0.6} w={w - 48} h={h - 24} />
      </div>
    ),
    (w, h) => {
      const s = Math.min((w - 50) / CARD.w, (h - 30) / CARD.h);
      return (
        <div
          style={{
            position: "absolute",
            left: (w - CARD.w * s) / 2 - CARD.x * s,
            top: (h - CARD.h * s) / 2 + 8 - CARD.y * s,
            width: 393,
            height: 852,
            transform: `scale(${s})`,
            transformOrigin: "0 0",
          }}
        >
          <ActivityCard t={15.1} press={0} />
        </div>
      );
    },
    (_w, _h, lt) => <Price lt={lt} tall={tall} />,
  ];

  return (
    <div style={{ position: "absolute", inset: 0, opacity: bg }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: [
            "radial-gradient(60% 50% at 8% 0%, rgba(92,108,230,0.22), rgba(92,108,230,0) 70%)",
            "radial-gradient(60% 50% at 96% 100%, rgba(246,181,68,0.16), rgba(246,181,68,0) 70%)",
            `linear-gradient(180deg, ${C.night2}, ${C.night})`,
          ].join(", "),
        }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          transform: `scale(${drift * (1 - 0.04 * out)})`,
          opacity: 1 - out,
          filter: out > 0 ? `blur(${out * 10}px)` : undefined,
        }}
      >
        <Caption
          lines={[copy.bentoTitle]}
          t={t}
          inAt={B.start - 0.05}
          outAt={B.end + 1}
          place="top"
          y={tall ? H * 0.085 : H * 0.075}
          size={tall ? 84 : 72}
        />
        {copy.bento.map((b, i) => {
          const c = i % cols;
          const r = Math.floor(i / cols);
          return (
            <Tile key={i} x={gx + c * (tw + gap)} y={gy + r * (th + gap)} w={tw} h={th} at={B.start + 0.2 + i * 0.16} title={b.title} sub={b.sub}>
              {art[i]}
            </Tile>
          );
        })}
      </div>
    </div>
  );
};
