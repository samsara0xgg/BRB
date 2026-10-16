import React from "react";
import { Img, staticFile } from "remotion";
import { C, FONT } from "../lib/theme";
import { useCtx } from "../lib/ctx";
import { Shield } from "../ui/Shield";
import { Desktop, SH, SW } from "./Desktop";

export const SIGN_CX = SW / 2;
export const SIGN_CY = 404;

/** The frosted glass over every screen: it spreads from the middle and clears from the bottom-right. */
export const Frost: React.FC<{ r: number; clearR: number; tint: string }> = ({ r, clearR, tint }) => {
  if (r <= 0) return null;
  const spread = `radial-gradient(circle at 50% 50%, #000 ${Math.max(0, r - 140)}px, transparent ${r}px)`;
  const clear = `radial-gradient(circle at 100% 100%, transparent ${Math.max(0, clearR - 160)}px, #000 ${clearR}px)`;
  const mask = clearR > 0 ? `${spread}, ${clear}` : spread;
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        top: 0,
        width: SW,
        height: SH,
        overflow: "hidden",
        WebkitMaskImage: mask,
        maskImage: mask,
        WebkitMaskComposite: clearR > 0 ? "source-in" : undefined,
        maskComposite: clearR > 0 ? "intersect" : undefined,
      }}
    >
      {/* the desktop, a little larger so the blur never pulls in black from past the edges */}
      <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, transform: "scale(1.12)", filter: "blur(44px) saturate(1.3)" }}>
        <Desktop />
      </div>
      <div style={{ position: "absolute", inset: 0, background: tint }} />
      <Img
        src={staticFile("img/film-grain.png")}
        style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, objectFit: "cover", opacity: 0.5 }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: "radial-gradient(80% 70% at 50% 40%, rgba(255,255,255,0.10), rgba(255,255,255,0) 70%)",
        }}
      />
    </div>
  );
};

/** The red that spreads from where the Mac was touched. */
export const Flood: React.FC<{ x: number; y: number; r: number; calm: number; clearR: number }> = ({ x, y, r, calm, clearR }) => {
  if (r <= 0) return null;
  const edge = `radial-gradient(circle at ${x}px ${y}px, #000 ${Math.max(0, r - 40)}px, transparent ${r}px)`;
  const clear = `radial-gradient(circle at 100% 100%, transparent ${Math.max(0, clearR - 160)}px, #000 ${clearR}px)`;
  const mask = clearR > 0 ? `${edge}, ${clear}` : edge;
  // Once it's back in place the red deepens and calms; it stays opaque so the frost doesn't muddy it.
  const mixc = (a: number[], b: number[]) => a.map((v, i) => Math.round(v + (b[i] - v) * calm)).join(",");
  const c0 = mixc([240, 52, 64], [178, 24, 40]);
  const c1 = mixc([205, 28, 44], [140, 16, 32]);
  const c2 = mixc([140, 12, 28], [92, 8, 22]);
  return (
    <>
      <div
        style={{
          position: "absolute",
          left: 0,
          top: 0,
          width: SW,
          height: SH,
          background: `radial-gradient(circle at ${x}px ${y}px, rgba(${c0},0.94) 0%, rgba(${c1},0.95) 45%, rgba(${c2},0.97) 100%)`,
          WebkitMaskImage: mask,
          maskImage: mask,
          WebkitMaskComposite: clearR > 0 ? "source-in" : undefined,
          maskComposite: clearR > 0 ? "intersect" : undefined,
        }}
      />
      {r < 2200 && (
        <div
          style={{
            position: "absolute",
            left: x - r,
            top: y - r,
            width: r * 2,
            height: r * 2,
            borderRadius: "50%",
            boxShadow: `0 0 60px 18px rgba(255,120,120,${0.55 * (1 - r / 2200)}), inset 0 0 40px 10px rgba(255,160,160,${0.4 * (1 - r / 2200)})`,
          }}
        />
      )}
    </>
  );
};

/** The 5 s ring. `k` is how far it has stretched into the notice. */
export const Ring: React.FC<{ progress: number; n: number; nAge: number; k: number; opacity: number }> = ({ progress, n, nAge, k, opacity }) => {
  const { copy } = useCtx();
  if (opacity <= 0) return null;
  const R = 66;
  const circ = 2 * Math.PI * R;
  const pop = Math.min(1, nAge / 0.18);
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, opacity, fontFamily: FONT.text, color: "#fff" }}>
      <div style={{ position: "absolute", left: SIGN_CX - 75, top: SIGN_CY - 75, width: 150, height: 150, opacity: 1 - k }}>
        <svg width="150" height="150" viewBox="0 0 150 150" style={{ position: "absolute", inset: 0 }}>
          <circle cx="75" cy="75" r={R} stroke="rgba(255,255,255,0.14)" strokeWidth="7" fill="rgba(10,12,24,0.28)" />
          <circle
            cx="75"
            cy="75"
            r={R}
            stroke={C.amber}
            strokeWidth="7"
            fill="none"
            strokeLinecap="round"
            strokeDasharray={circ}
            strokeDashoffset={circ * (1 - progress)}
            transform="rotate(-90 75 75)"
            style={{ filter: "drop-shadow(0 0 8px rgba(246,181,68,0.6))" }}
          />
        </svg>
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontFamily: FONT.display,
            fontWeight: 500,
            fontSize: 70,
            transform: `scale(${0.82 + 0.18 * pop})`,
            filter: `blur(${(1 - pop) * 6}px)`,
            opacity: 0.4 + 0.6 * pop,
          }}
        >
          {n}
        </div>
      </div>
      <div style={{ position: "absolute", left: 0, width: SW, top: SIGN_CY + 100, textAlign: "center", opacity: 1 - k * 2 }}>
        <div style={{ fontSize: 19, fontWeight: 700 }}>{copy.mac.leave}</div>
        <div
          style={{
            display: "flex",
            justifyContent: "center",
            alignItems: "center",
            gap: 8,
            marginTop: 12,
            fontSize: 13,
            color: "rgba(255,255,255,0.7)",
          }}
        >
          <Key>esc</Key>
          <span>{copy.mac.cancels}</span>
          <span style={{ opacity: 0.4, margin: "0 4px" }}>·</span>
          <Key>
            <div style={{ width: 11, height: 11, borderRadius: 6, border: "1.5px solid rgba(255,255,255,0.85)" }} />
          </Key>
          <span>{copy.mac.touchId}</span>
        </div>
      </div>
    </div>
  );
};

const Key: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div
    style={{
      minWidth: 30,
      height: 24,
      padding: "0 7px",
      borderRadius: 6,
      background: "rgba(255,255,255,0.16)",
      boxShadow: "inset 0 0 0 0.5px rgba(255,255,255,0.32), 0 1px 0 rgba(0,0,0,0.25)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: 11.5,
      fontWeight: 600,
      color: "#fff",
    }}
  >
    {children}
  </div>
);

export type SignState = "guard" | "alarm" | "off" | "welcome";

type SignContent = { icon: React.ReactNode; iconBg: string; title: string; sub: string; chips: React.ReactNode[]; w: number };

const Dot: React.FC<{ color: string; glow?: number }> = ({ color, glow = 0.6 }) => (
  <div style={{ width: 7, height: 7, borderRadius: 4, background: color, boxShadow: `0 0 ${6 * glow}px ${color}` }} />
);

export const Chip: React.FC<{ children: React.ReactNode; strong?: boolean }> = ({ children, strong }) => (
  <div
    style={{
      height: 30,
      padding: "0 13px",
      borderRadius: 15,
      background: strong ? "rgba(255,255,255,0.18)" : "rgba(255,255,255,0.1)",
      boxShadow: "inset 0 0 0 0.5px rgba(255,255,255,0.16)",
      display: "flex",
      alignItems: "center",
      gap: 7,
      fontSize: 12.5,
      fontWeight: 600,
      color: "#fff",
      whiteSpace: "nowrap",
    }}
  >
    {children}
  </div>
);

// Width of the notice in each state, tuned to its words.
const WIDTHS: Record<string, Record<SignState, number>> = {
  en: { guard: 560, alarm: 540, off: 470, welcome: 520 },
  zh: { guard: 430, alarm: 420, off: 370, welcome: 380 },
};

const SpeakerOff: React.FC = () => (
  <svg width="26" height="26" viewBox="0 0 26 26">
    <path d="M4 10 H8 L13 5.5 V20.5 L8 16 H4 Z" fill="#fff" />
    <path d="M17 9.5 L23 16.5 M23 9.5 L17 16.5" stroke="#fff" strokeWidth="2.2" strokeLinecap="round" />
  </svg>
);

/** The glass notice, in whichever state; words swap in place with a little blur. */
export const Sign: React.FC<{
  from: SignState;
  to: SignState;
  k: number; // 0 → 1 between the two states
  appear: number; // the ring stretching into it, 0 → 1
  scale?: number;
  dx?: number;
  dy?: number;
  opacity?: number;
  pulse: number;
}> = ({ from, to, k, appear, scale = 1, dx = 0, dy = 0, opacity = 1, pulse }) => {
  const { copy, lang } = useCtx();
  const m = copy.mac;
  if (appear <= 0 || opacity <= 0) return null;
  const content = (s: SignState): SignContent => {
    switch (s) {
      case "guard":
        return {
          icon: <Shield look="armed" size={34} />,
          iconBg: "rgba(10,14,30,0.55)",
          title: m.dontTouch,
          sub: m.guarded,
          chips: [
            <Chip key="a">
              <Dot color={C.camera} />
              {m.walkBy}
            </Chip>,
            <Chip key="b">{m.noteChip}</Chip>,
          ],
          w: WIDTHS[lang].guard,
        };
      case "alarm":
        return {
          icon: (
            <svg width="30" height="30" viewBox="0 0 24 24">
              <rect x="10.6" y="4" width="2.8" height="10.5" rx="1.4" fill="#fff" />
              <circle cx="12" cy="18.6" r="1.7" fill="#fff" />
            </svg>
          ),
          iconBg: C.red,
          title: m.alarm,
          sub: m.onCamera,
          chips: [
            <Chip key="a" strong>
              <Dot color="#fff" glow={pulse} />
              <span style={{ opacity: 0.95 }}>{m.recording}</span>
            </Chip>,
          ],
          w: WIDTHS[lang].alarm,
        };
      case "off":
        return {
          icon: <SpeakerOff />,
          iconBg: "rgba(255,255,255,0.22)",
          title: m.sirenOff,
          sub: m.sirenOffSub,
          chips: [
            <Chip key="a" strong>
              <Dot color="#fff" glow={pulse} />
              {m.recording}
            </Chip>,
          ],
          w: WIDTHS[lang].off,
        };
      case "welcome":
        return {
          icon: (
            <svg width="30" height="30" viewBox="0 0 24 24">
              <path d="M6.5 12.4 L10.4 16.2 L17.8 8.4" stroke="#fff" strokeWidth="2.8" fill="none" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          ),
          iconBg: C.green,
          title: m.welcome,
          sub: m.welcomeSub,
          chips: [<Chip key="a">{m.photos}</Chip>, <Chip key="b">{m.sirenFor}</Chip>],
          w: WIDTHS[lang].welcome,
        };
    }
  };
  const a = content(from);
  const b = content(to);
  const ease = k * k * (3 - 2 * k);
  const w = a.w + (b.w - a.w) * ease;
  const h = 104;
  // The ring (150 round) stretching into the capsule.
  const ap = Math.min(1, Math.max(0, appear));
  const W = 150 + (w - 150) * ap;
  const Hh = 150 + (h - 150) * ap;
  const inner = Math.min(1, Math.max(0, (ap - 0.45) / 0.55));

  const layer = (c: SignContent, o: number, dir: number) => (
    <div
      style={{
        position: "absolute",
        inset: 0,
        display: "flex",
        alignItems: "center",
        padding: "0 24px",
        gap: 18,
        opacity: o * inner,
        filter: o < 1 ? `blur(${(1 - o) * 4}px)` : undefined,
        transform: `translateY(${(1 - o) * 8 * dir}px)`,
      }}
    >
      <div
        style={{
          width: 58,
          height: 58,
          flex: "0 0 58px",
          borderRadius: 29,
          background: c.iconBg,
          boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.18), 0 4px 14px rgba(0,0,0,0.25)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {c.icon}
      </div>
      <div style={{ whiteSpace: "nowrap" }}>
        <div style={{ fontFamily: FONT.display, fontWeight: 700, fontSize: 34, letterSpacing: lang === "zh" ? 1 : -0.6, lineHeight: 1.1 }}>
          {c.title}
        </div>
        <div style={{ fontSize: 14.5, fontWeight: 500, color: "rgba(255,255,255,0.8)", marginTop: 5 }}>{c.sub}</div>
      </div>
    </div>
  );

  const chipsA = (
    <div
      style={{
        display: "flex",
        gap: 10,
        justifyContent: "center",
        opacity: (1 - ease) * inner,
        filter: ease > 0 ? `blur(${ease * 4}px)` : undefined,
      }}
    >
      {a.chips}
    </div>
  );
  const chipsB = (
    <div
      style={{
        display: "flex",
        gap: 10,
        justifyContent: "center",
        opacity: ease * inner,
        filter: ease < 1 ? `blur(${(1 - ease) * 4}px)` : undefined,
      }}
    >
      {b.chips}
    </div>
  );

  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        top: 0,
        width: SW,
        height: SH,
        transform: `translate(${dx}px, ${dy}px) scale(${scale})`,
        transformOrigin: `${SIGN_CX}px ${SIGN_CY}px`,
        opacity,
        fontFamily: FONT.text,
        color: "#fff",
      }}
    >
      <div
        style={{
          position: "absolute",
          left: SIGN_CX - W / 2,
          top: SIGN_CY - Hh / 2,
          width: W,
          height: Hh,
          borderRadius: Hh / 2,
          background: "linear-gradient(180deg, rgba(255,255,255,0.17), rgba(255,255,255,0.07))",
          backdropFilter: "blur(26px) saturate(1.4)",
          boxShadow: "inset 0 1px 0 rgba(255,255,255,0.35), inset 0 0 0 1px rgba(255,255,255,0.16), 0 20px 50px rgba(0,0,0,0.28)",
          overflow: "hidden",
        }}
      >
        {k < 1 && layer(a, 1 - ease, -1)}
        {k > 0 && layer(b, ease, 1)}
      </div>
      <div style={{ position: "absolute", left: 0, width: SW, top: SIGN_CY + h / 2 + 18 }}>
        <div style={{ position: "relative", height: 30 }}>
          <div style={{ position: "absolute", left: 0, right: 0 }}>{k < 1 && chipsA}</div>
          <div style={{ position: "absolute", left: 0, right: 0 }}>{k > 0 && chipsB}</div>
        </div>
      </div>
    </div>
  );
};

export const Footer: React.FC<{ opacity: number }> = ({ opacity }) => {
  const { copy } = useCtx();
  if (opacity <= 0) return null;
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        width: SW,
        top: SH - 118,
        textAlign: "center",
        fontFamily: FONT.text,
        fontSize: 11.5,
        fontWeight: 600,
        letterSpacing: "0.24em",
        color: "rgba(255,255,255,0.45)",
        opacity,
      }}
    >
      {copy.mac.footer}
    </div>
  );
};
