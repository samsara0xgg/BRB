import React from "react";
import { SH, SW } from "./Desktop";

// A 14-inch MacBook Pro in CSS 3D, 1200 px wide. The world's origin is the middle of its footprint on
// the table; y points down (the table is y = 0), z toward the viewer.
export const BW = 1200;
export const BD = 840;
export const BT = 30;
export const LT = 11;
const BEZEL_X = 18;
const BEZEL_TOP = 16;
export const SCREEN_SCALE = (BW - BEZEL_X * 2) / SW;
const SCREEN_H = SH * SCREEN_SCALE;
export const LH = BEZEL_TOP + SCREEN_H + 34;
export const LID_ANGLE = 17; // degrees back from upright
const HINGE_Y = -BT - 1;
const HINGE_Z = -BD / 2 + 16;
const R_BASE = 34;
const R_LID = 30;

// Keyboard: rows of [legend, width in keys]; 14.5 keys wide.
const ROWS: [string, number][][] = [
  [
    ["esc", 1.5],
    ["", 1],
    ["", 1],
    ["", 1],
    ["", 1],
    ["", 1],
    ["", 1],
    ["", 1],
    ["", 1],
    ["", 1],
    ["", 1],
    ["", 1],
    ["", 1],
    ["TID", 1],
  ],
  [
    ["`", 1],
    ["1", 1],
    ["2", 1],
    ["3", 1],
    ["4", 1],
    ["5", 1],
    ["6", 1],
    ["7", 1],
    ["8", 1],
    ["9", 1],
    ["0", 1],
    ["-", 1],
    ["=", 1],
    ["delete", 1.5],
  ],
  [
    ["tab", 1.5],
    ["Q", 1],
    ["W", 1],
    ["E", 1],
    ["R", 1],
    ["T", 1],
    ["Y", 1],
    ["U", 1],
    ["I", 1],
    ["O", 1],
    ["P", 1],
    ["[", 1],
    ["]", 1],
    ["\\", 1],
  ],
  [
    ["caps lock", 1.75],
    ["A", 1],
    ["S", 1],
    ["D", 1],
    ["F", 1],
    ["G", 1],
    ["H", 1],
    ["J", 1],
    ["K", 1],
    ["L", 1],
    [";", 1],
    ["'", 1],
    ["return", 1.75],
  ],
  [
    ["shift", 2.25],
    ["Z", 1],
    ["X", 1],
    ["C", 1],
    ["V", 1],
    ["B", 1],
    ["N", 1],
    ["M", 1],
    [",", 1],
    [".", 1],
    ["/", 1],
    ["shift", 2.25],
  ],
  [
    ["fn", 1],
    ["control", 1],
    ["option", 1],
    ["command", 1.25],
    ["", 5],
    ["command", 1.25],
    ["option", 1],
    ["ARROWS", 3],
  ],
];
const KW = 960;
const U = KW / 14.5;
const KX = (BW - KW) / 2;
const KY = 40;
export const TP = { x: BW / 2 - 262, y: KY + U * 6 + 30, w: 524, h: 318 };
/** The Touch ID key's middle, on the deck (deck coordinates, from the back-left corner). */
export const TOUCH_ID = { x: KX + KW - U / 2, y: KY + U / 2 };

const keyStyle = (w: number, h: number, extra?: React.CSSProperties): React.CSSProperties => ({
  position: "absolute",
  width: w,
  height: h,
  borderRadius: 8,
  background: "linear-gradient(180deg, #17181b 0%, #0e0f11 100%)",
  boxShadow: "inset 0 1px 0 rgba(255,255,255,0.07), 0 1.5px 0 rgba(0,0,0,0.7), 0 0 0 1px rgba(0,0,0,0.5)",
  color: "rgba(255,255,255,0.78)",
  fontFamily: "Inter, sans-serif",
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
  ...extra,
});

const Keyboard: React.FC<{ touchId: React.ReactNode }> = ({ touchId }) => {
  const keys: React.ReactNode[] = [];
  ROWS.forEach((row, r) => {
    let x = 0;
    row.forEach(([label, w], i) => {
      const kw = w * U - 7;
      const left = KX + x + 3.5;
      const top = KY + r * U + 3.5;
      const kh = U - 7;
      const key = `${r}-${i}`;
      if (label === "ARROWS") {
        const aw = U - 7;
        const half = (kh - 4) / 2;
        keys.push(
          <div key={`${key}l`} style={keyStyle(aw, half, { left, top: top + half + 4, fontSize: 11 })}>
            ◀
          </div>,
        );
        keys.push(
          <div key={`${key}u`} style={keyStyle(aw, half, { left: left + U, top, fontSize: 11 })}>
            ▲
          </div>,
        );
        keys.push(
          <div key={`${key}d`} style={keyStyle(aw, half, { left: left + U, top: top + half + 4, fontSize: 11 })}>
            ▼
          </div>,
        );
        keys.push(
          <div key={`${key}r`} style={keyStyle(aw, half, { left: left + 2 * U, top: top + half + 4, fontSize: 11 })}>
            ▶
          </div>,
        );
      } else if (label === "TID") {
        keys.push(
          <div key={key} style={keyStyle(kw, kh, { left, top, background: "linear-gradient(180deg, #121316, #0b0c0e)" })}>
            <div style={{ position: "absolute", inset: 5, borderRadius: 6, boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.07)" }} />
            {touchId}
          </div>,
        );
      } else {
        const small = label.length > 1;
        keys.push(
          <div
            key={key}
            style={keyStyle(kw, kh, {
              left,
              top,
              fontSize: small ? 11 : 17,
              fontWeight: 500,
              alignItems: small ? "flex-end" : "center",
              justifyContent: small ? (i === 0 ? "flex-start" : "flex-end") : "center",
              padding: small ? "0 8px 8px" : 0,
            })}
          >
            {label}
          </div>,
        );
      }
      x += w * U;
    });
  });
  return <>{keys}</>;
};

const Grille: React.FC<{ x: number }> = ({ x }) => (
  <div
    style={{
      position: "absolute",
      left: x,
      top: KY + 4,
      width: 70,
      height: U * 6 - 8,
      borderRadius: 6,
      backgroundImage: "radial-gradient(circle, rgba(0,0,0,0.75) 1.4px, transparent 1.9px)",
      backgroundSize: "7px 7px",
      opacity: 0.9,
    }}
  />
);

/** The deck: what you see looking down at the base. */
const Deck: React.FC<{ touchId: React.ReactNode; trackpad: React.ReactNode }> = ({ touchId, trackpad }) => (
  <div
    style={{
      position: "absolute",
      inset: 0,
      borderRadius: R_BASE,
      background: "linear-gradient(180deg, #2b2d33 0%, #26272c 45%, #222327 100%)",
      boxShadow: "inset 0 0 0 1.5px rgba(255,255,255,0.09), inset 0 -2px 0 rgba(0,0,0,0.3)",
      overflow: "hidden",
    }}
  >
    {/* keyboard well */}
    <div
      style={{
        position: "absolute",
        left: KX - 6,
        top: KY - 6,
        width: KW + 12,
        height: U * 6 + 12,
        borderRadius: 12,
        background: "rgba(0,0,0,0.28)",
      }}
    />
    <Keyboard touchId={touchId} />
    <Grille x={KX - 92} />
    <Grille x={KX + KW + 22} />
    {/* trackpad */}
    <div
      style={{
        position: "absolute",
        left: TP.x,
        top: TP.y,
        width: TP.w,
        height: TP.h,
        borderRadius: 16,
        background: "linear-gradient(180deg, #2f3137 0%, #2a2b30 100%)",
        boxShadow: "inset 0 0 0 1.5px rgba(0,0,0,0.45), inset 0 2px 0 rgba(255,255,255,0.05)",
        overflow: "hidden",
      }}
    >
      {trackpad}
    </div>
    {/* the thumb notch at the front */}
    <div
      style={{
        position: "absolute",
        left: BW / 2 - 70,
        top: BD - 9,
        width: 140,
        height: 18,
        borderRadius: "50%",
        background: "rgba(0,0,0,0.35)",
      }}
    />
    {/* a soft sheen across the aluminium */}
    <div
      style={{
        position: "absolute",
        inset: 0,
        background:
          "linear-gradient(115deg, rgba(255,255,255,0.05) 0%, rgba(255,255,255,0) 40%, rgba(255,255,255,0.03) 70%, rgba(255,255,255,0) 100%)",
      }}
    />
  </div>
);

const slab = (key: string, w: number, h: number, r: number, transform: string, style: React.CSSProperties, children?: React.ReactNode) => (
  <div
    key={key}
    style={{
      position: "absolute",
      left: -w / 2,
      top: -h / 2,
      width: w,
      height: h,
      borderRadius: r,
      transform,
      backfaceVisibility: "hidden",
      ...style,
    }}
  >
    {children}
  </div>
);

export type Pose = { x: number; y: number; z: number; rx: number; ry: number; rz: number };
export const REST: Pose = { x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0 };

/**
 * The laptop. `screen` is drawn at the Mac's logical 1512 × 982 and scaled into the lid; `glow` is
 * the colour the screen throws on the room.
 */
export const Laptop: React.FC<{
  pose: Pose;
  screen: React.ReactNode;
  touchId?: React.ReactNode;
  trackpad?: React.ReactNode;
  screenGlow?: string;
  lidAngle?: number;
}> = ({ pose, screen, touchId, trackpad, screenGlow = "rgba(120,140,255,0.25)", lidAngle = LID_ANGLE }) => {
  const N = 10; // slices of the base's thickness
  const slices: React.ReactNode[] = [];
  for (let i = 0; i < N; i++) {
    const y = -(i / N) * BT;
    // Darker toward the table, with a polished chamfer catching the light at the top.
    const top = i === N - 1;
    const shade = top ? 74 : 20 + Math.round((i / N) * 14);
    slices.push(
      slab(`s${i}`, BW, BD, R_BASE, `translate3d(0px, ${y}px, 0px) rotateX(90deg)`, {
        background: `rgb(${shade},${shade + 2},${shade + 6})`,
      }),
    );
  }
  const NL = 5;
  const lidSlices: React.ReactNode[] = [];
  for (let j = 1; j < NL; j++) {
    const z = -(j / NL) * LT;
    lidSlices.push(
      <div
        key={j}
        style={{
          position: "absolute",
          left: -BW / 2,
          top: -LH,
          width: BW,
          height: LH,
          borderRadius: R_LID,
          transform: `translateZ(${z}px)`,
          background: j === NL - 1 ? "linear-gradient(180deg, #34363c, #2a2b30)" : "#202125",
        }}
      />,
    );
  }
  return (
    <div
      style={{
        position: "absolute",
        transformStyle: "preserve-3d",
        transform: `translate3d(${pose.x}px, ${pose.y}px, ${pose.z}px) rotateX(${pose.rx}deg) rotateY(${pose.ry}deg) rotateZ(${pose.rz}deg)`,
      }}
    >
      {/* base */}
      {slab("bottom", BW, BD, R_BASE, "translate3d(0px, 0.5px, 0px) rotateX(-90deg)", { background: "#151619" })}
      {slices}
      {slab("deck", BW, BD, R_BASE, `translate3d(0px, ${-BT}px, 0px) rotateX(90deg)`, {}, <Deck touchId={touchId} trackpad={trackpad} />)}
      {/* lid, hinged at the back of the deck */}
      <div
        style={{
          position: "absolute",
          transformStyle: "preserve-3d",
          // The hinge sits a hair above the deck so the lid never cuts through the base's slices:
          // Chrome splits intersecting 3D planes and can drop the pieces.
          transform: `translate3d(0px, ${HINGE_Y}px, ${HINGE_Z}px) rotateX(${lidAngle}deg)`,
        }}
      >
        {lidSlices.reverse()}
        {/* the screen side */}
        <div
          style={{
            position: "absolute",
            left: -BW / 2,
            top: -LH,
            width: BW,
            height: LH,
            borderRadius: R_LID,
            background: "#060607",
            boxShadow: "inset 0 0 0 2px #50535b, inset 0 0 0 3.5px #0a0a0b",
            overflow: "hidden",
            backfaceVisibility: "hidden",
          }}
        >
          <div
            style={{
              position: "absolute",
              left: BEZEL_X,
              top: BEZEL_TOP,
              width: SW,
              height: SH,
              transformOrigin: "0 0",
              transform: `scale(${SCREEN_SCALE})`,
              borderRadius: 14 / SCREEN_SCALE,
              overflow: "hidden",
            }}
          >
            {screen}
          </div>
          {/* glass */}
          <div
            style={{
              position: "absolute",
              inset: 0,
              background: "linear-gradient(128deg, rgba(255,255,255,0.08) 0%, rgba(255,255,255,0.02) 32%, rgba(255,255,255,0) 52%)",
              pointerEvents: "none",
            }}
          />
          {/* the chin */}
          <div
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              bottom: 0,
              height: 34,
              background: "linear-gradient(180deg, #08080a, #111214)",
            }}
          />
        </div>
      </div>
      {/* light the screen throws onto the deck */}
      {slab("spill", BW, BD, R_BASE, `translate3d(0px, ${-BT - 0.6}px, 0px) rotateX(90deg)`, {
        // No mix-blend-mode here: blending isolates the parent and flattens the whole laptop.
        background: `radial-gradient(90% 60% at 50% 0%, ${screenGlow}, transparent 70%)`,
        opacity: 0.45,
      })}
    </div>
  );
};

/** Where a point of the screen (in the Mac's 1512 × 982 pixels) sits in the world, lid at rest. */
export const screenPoint = (sx: number, sy: number) => {
  const a = (LID_ANGLE * Math.PI) / 180;
  const lx = -BW / 2 + BEZEL_X + sx * SCREEN_SCALE;
  const ly = -LH + BEZEL_TOP + sy * SCREEN_SCALE;
  return { x: lx, y: HINGE_Y + ly * Math.cos(a), z: HINGE_Z + ly * Math.sin(a) };
};

/** A point on the deck (from its back-left corner) in the world. */
export const deckPoint = (dx: number, dz: number) => ({ x: dx - BW / 2, y: -BT, z: dz - BD / 2 });
