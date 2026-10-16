import React from "react";
import { C, FONT } from "../lib/theme";
import { useCtx } from "../lib/ctx";
import { Shield } from "../ui/Shield";
import { ICON_X, MENU_H, SW } from "./Desktop";

export const PANEL_W = 340;
export const PANEL_X = Math.min(ICON_X - PANEL_W / 2, SW - PANEL_W - 10);
export const PANEL_Y = MENU_H + 8;
/** The start button's middle, in screen coordinates (for the pointer). */
export const START_X = PANEL_X + PANEL_W / 2;
export const START_Y = PANEL_Y + 14 + 30 + 12 + 34;

const ink = C.ink;

const PlaceIcon: React.FC<{ kind: number; color: string }> = ({ kind, color }) => {
  if (kind === 0)
    return (
      <svg width="18" height="18" viewBox="0 0 18 18">
        <rect x="2" y="3" width="3" height="12" rx="0.8" stroke={color} strokeWidth="1.6" fill="none" />
        <rect x="6.5" y="3" width="3" height="12" rx="0.8" stroke={color} strokeWidth="1.6" fill="none" />
        <path d="M11 4.2 L13.6 3.4 L16.4 14.2 L13.8 15 Z" stroke={color} strokeWidth="1.6" fill="none" strokeLinejoin="round" />
      </svg>
    );
  if (kind === 1)
    return (
      <svg width="18" height="18" viewBox="0 0 18 18">
        <path d="M3 7 H13 V10.5 A4.5 4.5 0 0 1 8.5 15 H7.5 A4.5 4.5 0 0 1 3 10.5 Z" stroke={color} strokeWidth="1.6" fill="none" />
        <path d="M13 8.2 H14.2 A1.9 1.9 0 0 1 14.2 12 H12.6" stroke={color} strokeWidth="1.6" fill="none" />
        <path
          d="M6 2.5 C 5.2 3.6 6.8 4.2 6 5.3 M9.2 2.5 C 8.4 3.6 10 4.2 9.2 5.3"
          stroke={color}
          strokeWidth="1.3"
          fill="none"
          strokeLinecap="round"
        />
      </svg>
    );
  return (
    <svg width="18" height="18" viewBox="0 0 18 18">
      <rect x="3.5" y="2" width="11" height="11.5" rx="3" stroke={color} strokeWidth="1.6" fill="none" />
      <path d="M3.5 8 H14.5" stroke={color} strokeWidth="1.4" />
      <circle cx="6.5" cy="10.8" r="0.9" fill={color} />
      <circle cx="11.5" cy="10.8" r="0.9" fill={color} />
      <path d="M5.5 13.5 L4 16 M12.5 13.5 L14 16" stroke={color} strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
};

const Check: React.FC<{ color: string }> = ({ color }) => (
  <svg width="14" height="14" viewBox="0 0 14 14">
    <path d="M3 7.4 L5.9 10.2 L11.2 4.2" stroke={color} strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

export const Panel: React.FC<{ open: number; press: number; fade: number }> = ({ open, press, fade }) => {
  const { copy, lang } = useCtx();
  const zh = lang === "zh";
  const m = copy.mac;
  if (open <= 0.001 || fade >= 0.999) return null;
  const scale = (0.9 + 0.1 * open) * (1 - 0.03 * fade);
  return (
    <div
      style={{
        position: "absolute",
        left: PANEL_X,
        top: PANEL_Y,
        width: PANEL_W,
        transformOrigin: `${ICON_X - PANEL_X}px 0px`,
        transform: `translateY(${(1 - open) * -10}px) scale(${scale})`,
        opacity: Math.min(1, open * 1.4) * (1 - fade),
        fontFamily: FONT.text,
        color: "#fff",
      }}
    >
      {/* the little arrow toward the shield */}
      <div
        style={{
          position: "absolute",
          left: ICON_X - PANEL_X - 9,
          top: -7,
          width: 18,
          height: 18,
          transform: "rotate(45deg)",
          background: "#2c2e3c",
          borderTop: "1px solid rgba(255,255,255,0.14)",
          borderLeft: "1px solid rgba(255,255,255,0.14)",
          borderTopLeftRadius: 4,
        }}
      />
      <div
        style={{
          position: "relative",
          borderRadius: 16,
          padding: 14,
          background: "linear-gradient(180deg, rgba(44,46,60,0.97), rgba(27,29,39,0.98))",
          boxShadow: "0 26px 70px rgba(0,0,0,0.6), inset 0 0 0 1px rgba(255,255,255,0.12)",
        }}
      >
        {/* header */}
        <div style={{ display: "flex", alignItems: "center", height: 30, gap: 9 }}>
          <div
            style={{
              width: 28,
              height: 28,
              borderRadius: 8,
              background: `linear-gradient(135deg, #2B3A6B, #131A33)`,
              boxShadow: "inset 0 0 0 0.5px rgba(255,255,255,0.22)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <Shield look="outline" size={18} stroke={2.1} />
          </div>
          <div style={{ fontWeight: 600, fontSize: 15 }}>BRB</div>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 6,
              height: 22,
              padding: "0 9px",
              borderRadius: 11,
              background: "rgba(255,255,255,0.08)",
              fontSize: 12,
              color: "rgba(255,255,255,0.75)",
              fontWeight: 500,
            }}
          >
            <div style={{ width: 7, height: 7, borderRadius: 4, background: C.green, boxShadow: `0 0 6px ${C.green}` }} />
            {m.ready}
          </div>
        </div>

        {/* start button, with its warm glow */}
        <div style={{ position: "relative", marginTop: 12 }}>
          <div
            style={{
              position: "absolute",
              left: -30,
              right: -30,
              top: -20,
              bottom: -30,
              background: "radial-gradient(50% 50% at 50% 55%, rgba(246,181,68,0.32), rgba(246,181,68,0) 70%)",
            }}
          />
          <div
            style={{
              position: "relative",
              height: 68,
              borderRadius: 14,
              background: `linear-gradient(180deg, #FFD47E 0%, ${C.amber} 58%, #EFA236 100%)`,
              boxShadow: `0 ${10 - 6 * press}px ${30 - 12 * press}px rgba(220,140,20,${0.45 - 0.15 * press}), inset 0 1px 0 rgba(255,255,255,0.55)`,
              transform: `scale(${1 - 0.035 * press})`,
              filter: `brightness(${1 + 0.08 * press})`,
              display: "flex",
              alignItems: "center",
              padding: "0 12px",
              gap: 12,
            }}
          >
            <div
              style={{
                width: 42,
                height: 42,
                borderRadius: 11,
                background: "rgba(43,26,0,0.12)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <Shield look="ink" size={26} />
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ color: ink, fontWeight: 600, fontSize: 16.5, letterSpacing: zh ? 0.5 : -0.1 }}>{m.start}</div>
              <div style={{ color: "rgba(43,26,0,0.72)", fontSize: 12.5, marginTop: 2, fontWeight: 500 }}>{m.startSub}</div>
            </div>
            <div
              style={{
                width: 34,
                height: 24,
                borderRadius: 6,
                background: "rgba(43,26,0,0.12)",
                boxShadow: "inset 0 0 0 0.5px rgba(43,26,0,0.2)",
                color: ink,
                fontSize: 15,
                fontWeight: 700,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              ↩
            </div>
          </div>
        </div>

        {/* places */}
        <div style={{ display: "flex", gap: 8, marginTop: 10 }}>
          {m.places.map((p, i) => {
            const on = i === 1;
            return (
              <div
                key={p}
                style={{
                  flex: 1,
                  height: 82,
                  borderRadius: 12,
                  background: on ? "rgba(246,181,68,0.13)" : "rgba(255,255,255,0.05)",
                  boxShadow: on ? "inset 0 0 0 1px rgba(246,181,68,0.38)" : "inset 0 0 0 1px rgba(255,255,255,0.06)",
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  justifyContent: "center",
                  gap: 8,
                }}
              >
                <div
                  style={{
                    width: 34,
                    height: 34,
                    borderRadius: 17,
                    background: on ? `linear-gradient(180deg, ${C.amberHi}, ${C.amberLow})` : "rgba(255,255,255,0.1)",
                    boxShadow: on ? "0 4px 14px rgba(246,181,68,0.45)" : "none",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                  }}
                >
                  <PlaceIcon kind={i} color={on ? ink : "rgba(255,255,255,0.7)"} />
                </div>
                <div style={{ fontSize: 12.5, fontWeight: on ? 600 : 500, color: on ? "#fff" : "rgba(255,255,255,0.62)" }}>{p}</div>
              </div>
            );
          })}
        </div>
        <div style={{ fontSize: 12.5, color: "rgba(255,255,255,0.6)", marginTop: 10, paddingLeft: 2 }}>{m.hint}</div>

        {/* note */}
        <div
          style={{
            marginTop: 10,
            height: 40,
            borderRadius: 10,
            background: "rgba(255,255,255,0.06)",
            display: "flex",
            alignItems: "center",
            gap: 10,
            padding: "0 12px",
            fontSize: 14,
          }}
        >
          <svg width="16" height="15" viewBox="0 0 16 15">
            <path
              d="M3 1.5 H13 A2 2 0 0 1 15 3.5 V9 A2 2 0 0 1 13 11 H7 L3.8 13.6 V11 H3 A2 2 0 0 1 1 9 V3.5 A2 2 0 0 1 3 1.5 Z"
              stroke="rgba(255,255,255,0.55)"
              strokeWidth="1.4"
              fill="none"
            />
          </svg>
          <div style={{ flex: 1 }}>{m.note}</div>
          <div
            style={{
              width: 15,
              height: 15,
              borderRadius: 8,
              background: "rgba(255,255,255,0.3)",
              color: "#1b1d26",
              fontSize: 11,
              fontWeight: 800,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            ×
          </div>
        </div>

        {/* recent */}
        <div style={{ fontSize: 11.5, fontWeight: 600, color: "rgba(255,255,255,0.45)", marginTop: 16, marginBottom: 6, paddingLeft: 2 }}>
          {m.recent}
        </div>
        {m.recents.map((r) => (
          <div key={r.title} style={{ display: "flex", alignItems: "center", gap: 11, height: 46 }}>
            <div
              style={{
                width: 28,
                height: 28,
                borderRadius: 8,
                background: r.kind === "ok" ? "rgba(70,212,131,0.17)" : "rgba(255,77,85,0.2)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: C.red,
                fontWeight: 800,
                fontSize: 15,
              }}
            >
              {r.kind === "ok" ? <Check color={C.green} /> : "!"}
            </div>
            <div style={{ minWidth: 0 }}>
              <div style={{ fontSize: 14, fontWeight: 600, color: r.kind === "ok" ? "#fff" : C.warn, whiteSpace: "nowrap" }}>{r.title}</div>
              <div style={{ fontSize: 12, color: "rgba(255,255,255,0.45)", marginTop: 1, whiteSpace: "nowrap" }}>{r.sub}</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
