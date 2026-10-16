import React from "react";
import { FONT } from "../lib/theme";
import { useCtx } from "../lib/ctx";

// The Mac's logical screen: a 14-inch MacBook Pro "looks like" 1512 × 982.
export const SW = 1512;
export const SH = 982;
export const MENU_H = 37;

const wallpaper = [
  "radial-gradient(70% 55% at 88% 104%, rgba(246,181,68,0.42), rgba(246,181,68,0) 70%)",
  "radial-gradient(60% 60% at 6% -6%, rgba(92,108,230,0.55), rgba(92,108,230,0) 70%)",
  "radial-gradient(55% 50% at 64% 34%, rgba(156,86,206,0.32), rgba(156,86,206,0) 72%)",
  "linear-gradient(162deg, #1b2256 0%, #0d1130 55%, #160b26 100%)",
].join(", ");

/** Soft folds of light across the wallpaper, like the system's own. */
const Folds: React.FC = () => (
  <svg width={SW} height={SH} viewBox={`0 0 ${SW} ${SH}`} style={{ position: "absolute", inset: 0 }}>
    <defs>
      <linearGradient id="fold1" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stopColor="#8fa0ff" stopOpacity="0.22" />
        <stop offset="1" stopColor="#8fa0ff" stopOpacity="0" />
      </linearGradient>
      <linearGradient id="fold2" x1="1" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#ffcf6e" stopOpacity="0.2" />
        <stop offset="1" stopColor="#ff7a59" stopOpacity="0" />
      </linearGradient>
    </defs>
    <path d="M0 520 C 300 380, 620 640, 980 470 S 1400 330, 1512 420 L1512 982 L0 982 Z" fill="url(#fold1)" />
    <path d="M0 760 C 380 600, 760 860, 1100 700 S 1420 610, 1512 640 L1512 982 L0 982 Z" fill="url(#fold2)" />
    <path d="M0 300 C 420 180, 760 380, 1120 230 S 1440 160, 1512 200" stroke="#ffffff" strokeOpacity="0.06" strokeWidth="2" fill="none" />
  </svg>
);

const Lights: React.FC = () => (
  <div style={{ position: "absolute", left: 16, top: 18, display: "flex", gap: 8 }}>
    {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => (
      <div key={c} style={{ width: 12, height: 12, borderRadius: 6, background: c }} />
    ))}
  </div>
);

const Bar: React.FC<{ w: number | string; o?: number; h?: number; mb?: number }> = ({ w, o = 0.16, h = 9, mb = 13 }) => (
  <div style={{ width: w, height: h, borderRadius: h / 2, background: `rgba(255,255,255,${o})`, marginBottom: mb }} />
);

const NotesWindow: React.FC = () => {
  const { lang } = useCtx();
  const zh = lang === "zh";
  return (
    <div
      style={{
        position: "absolute",
        left: 112,
        top: 96,
        width: 730,
        height: 590,
        borderRadius: 14,
        background: "#1d1e23",
        boxShadow: "0 30px 70px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.09)",
        overflow: "hidden",
        fontFamily: FONT.text,
      }}
    >
      <div style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: 210, background: "#25262c" }}>
        <Lights />
        <div style={{ position: "absolute", top: 62, left: 14, right: 14 }}>
          {[zh ? "论文" : "Thesis", zh ? "阅读笔记" : "Reading", zh ? "待办" : "To do", zh ? "旅行" : "Travel"].map((n, i) => (
            <div
              key={n}
              style={{
                height: 30,
                borderRadius: 7,
                padding: "0 10px",
                display: "flex",
                alignItems: "center",
                gap: 8,
                color: i === 0 ? "#fff" : "rgba(255,255,255,0.7)",
                background: i === 0 ? "rgba(255,207,110,0.22)" : "transparent",
                fontSize: 13,
                fontWeight: 500,
                marginBottom: 3,
              }}
            >
              <div style={{ width: 13, height: 11, borderRadius: 2, border: "1.5px solid #ffcf6e" }} />
              {n}
            </div>
          ))}
        </div>
      </div>
      <div style={{ position: "absolute", left: 210, top: 0, right: 0, height: 52, borderBottom: "1px solid rgba(255,255,255,0.06)" }} />
      <div style={{ position: "absolute", left: 250, top: 80, right: 40 }}>
        <div style={{ color: "#fff", fontSize: 24, fontWeight: 700, marginBottom: 8, letterSpacing: zh ? 0 : -0.3 }}>
          {zh ? "第三章 · 田野笔记" : "Chapter 3 · Field notes"}
        </div>
        <div style={{ color: "rgba(255,255,255,0.4)", fontSize: 12, marginBottom: 26 }}>{zh ? "10月16日 15:12" : "October 16, 3:12 PM"}</div>
        <Bar w="96%" />
        <Bar w="88%" />
        <Bar w="92%" />
        <Bar w="60%" mb={28} />
        <Bar w="94%" />
        <Bar w="85%" />
        <Bar w="90%" />
        <Bar w="72%" mb={28} />
        <Bar w="93%" />
        <Bar w="81%" />
        <Bar w="40%" />
      </div>
    </div>
  );
};

const BrowserWindow: React.FC = () => (
  <div
    style={{
      position: "absolute",
      left: 650,
      top: 214,
      width: 770,
      height: 610,
      borderRadius: 14,
      background: "#18191d",
      boxShadow: "0 40px 90px rgba(0,0,0,0.55), 0 0 0 1px rgba(255,255,255,0.09)",
      overflow: "hidden",
    }}
  >
    <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: 52, background: "#26272d" }}>
      <Lights />
      <div
        style={{
          position: "absolute",
          left: 200,
          right: 200,
          top: 12,
          height: 28,
          borderRadius: 8,
          background: "rgba(255,255,255,0.08)",
        }}
      />
    </div>
    <div
      style={{
        position: "absolute",
        left: 28,
        right: 28,
        top: 80,
        height: 250,
        borderRadius: 12,
        background: "linear-gradient(135deg, #3a4a9a 0%, #6b3fa0 50%, #f0a53a 120%)",
        opacity: 0.85,
      }}
    />
    <div style={{ position: "absolute", left: 28, right: 28, top: 356 }}>
      <Bar w="55%" o={0.32} h={14} mb={18} />
      <Bar w="95%" />
      <Bar w="90%" />
      <Bar w="84%" />
      <Bar w="66%" />
    </div>
  </div>
);

const Wifi: React.FC = () => (
  <svg width="17" height="13" viewBox="0 0 17 13">
    <path d="M8.5 12.2 L5.9 9.4 A3.8 3.8 0 0 1 11.1 9.4 Z" fill="#fff" />
    <path d="M3.5 7 A7.2 7.2 0 0 1 13.5 7" stroke="#fff" strokeWidth="1.7" fill="none" strokeLinecap="round" />
    <path d="M1.1 4.4 A10.6 10.6 0 0 1 15.9 4.4" stroke="#fff" strokeWidth="1.7" fill="none" strokeLinecap="round" />
  </svg>
);

const Battery: React.FC = () => (
  <svg width="27" height="13" viewBox="0 0 27 13">
    <rect x="0.75" y="0.75" width="22.5" height="11.5" rx="3.2" stroke="#fff" strokeOpacity="0.5" strokeWidth="1.5" fill="none" />
    <rect x="2.6" y="2.6" width="15" height="7.8" rx="1.6" fill="#fff" />
    <path d="M24.8 4.3 C26 4.6 26 8.4 24.8 8.7 Z" fill="#fff" fillOpacity="0.5" />
  </svg>
);

const Toggles: React.FC = () => (
  <svg width="16" height="14" viewBox="0 0 16 14">
    <rect x="0.8" y="0.8" width="14.4" height="5" rx="2.5" stroke="#fff" strokeWidth="1.5" fill="none" />
    <circle cx="11.7" cy="3.3" r="1.6" fill="#fff" />
    <rect x="0.8" y="8.2" width="14.4" height="5" rx="2.5" stroke="#fff" strokeWidth="1.5" fill="none" />
    <circle cx="4.3" cy="10.7" r="1.6" fill="#fff" />
  </svg>
);

/** Where the BRB shield sits in the menu bar (its center). */
export const ICON_X = 1222;
export const ICON_Y = MENU_H / 2;

export const MenuBar: React.FC<{ icon: React.ReactNode; dim?: number; clock?: string }> = ({ icon, dim = 0, clock }) => {
  const { copy, lang } = useCtx();
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        top: 0,
        width: SW,
        height: MENU_H,
        background: `rgba(10,12,30,${0.28 + dim})`,
        display: "flex",
        alignItems: "center",
        color: "#fff",
        fontFamily: FONT.text,
        fontSize: 14,
      }}
    >
      <div style={{ display: "flex", gap: lang === "zh" ? 20 : 22, paddingLeft: 22, alignItems: "center" }}>
        <span style={{ fontWeight: 700 }}>{copy.mac.menuApp}</span>
        {copy.mac.menus.map((m) => (
          <span key={m} style={{ fontWeight: 500, opacity: 0.92 }}>
            {m}
          </span>
        ))}
      </div>
      <div style={{ position: "absolute", left: ICON_X - 13, top: (MENU_H - 26) / 2, width: 26, height: 26 }}>{icon}</div>
      <div style={{ position: "absolute", left: 1262, top: 0, height: MENU_H, display: "flex", alignItems: "center", gap: 18 }}>
        <Wifi />
        <Battery />
        <Toggles />
        <span style={{ fontWeight: 500, whiteSpace: "nowrap" }}>{clock ?? copy.mac.clock}</span>
      </div>
    </div>
  );
};

/** The notch, with the camera and its green light (on whenever BRB keeps the 10 s buffer). */
export const Notch: React.FC<{ light?: number }> = ({ light = 0 }) => (
  <div
    style={{
      position: "absolute",
      left: SW / 2 - 92,
      top: 0,
      width: 184,
      height: MENU_H - 2,
      background: "#000",
      borderBottomLeftRadius: 12,
      borderBottomRightRadius: 12,
    }}
  >
    <div
      style={{
        position: "absolute",
        left: 92 - 6,
        top: 11,
        width: 12,
        height: 12,
        borderRadius: 6,
        background: "radial-gradient(circle at 40% 35%, #2a3550, #07080c 70%)",
      }}
    />
    {light > 0 && (
      <div
        style={{
          position: "absolute",
          left: 92 + 13,
          top: 15,
          width: 5,
          height: 5,
          borderRadius: 3,
          background: "#3EF07A",
          opacity: light,
          boxShadow: `0 0 ${6 * light}px 2px rgba(62,240,122,${0.7 * light})`,
        }}
      />
    )}
  </div>
);

/** Wallpaper and windows: what the frost blurs. */
export const Desktop: React.FC = () => (
  <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, background: wallpaper, overflow: "hidden" }}>
    <Folds />
    <NotesWindow />
    <BrowserWindow />
  </div>
);
