import React from "react";
import { rand } from "../lib/time";
import { BD, BW, Laptop, Pose } from "./Laptop";

export type Cam = {
  yaw: number; // degrees, + turns the laptop to show its right side
  pitch: number; // degrees looking down
  dist: number; // px pushed away from the lens (negative = closer)
  tx: number;
  ty: number;
  tz: number;
  fov: number; // CSS perspective, px
  ox?: number; // where the target lands on screen, as a fraction of the frame
  oy?: number;
};

export const lerpCam = (a: Cam, b: Cam, k: number): Cam => ({
  yaw: a.yaw + (b.yaw - a.yaw) * k,
  pitch: a.pitch + (b.pitch - a.pitch) * k,
  dist: a.dist + (b.dist - a.dist) * k,
  tx: a.tx + (b.tx - a.tx) * k,
  ty: a.ty + (b.ty - a.ty) * k,
  tz: a.tz + (b.tz - a.tz) * k,
  fov: a.fov + (b.fov - a.fov) * k,
  ox: (a.ox ?? 0.5) + ((b.ox ?? 0.5) - (a.ox ?? 0.5)) * k,
  oy: (a.oy ?? 0.5) + ((b.oy ?? 0.5) - (a.oy ?? 0.5)) * k,
});

const BOKEH = Array.from({ length: 26 }, (_, i) => {
  const palette = ["255,196,110", "255,214,160", "255,170,90", "255,230,190", "150,170,255"];
  return {
    x: rand(i * 3.1) * 1.3 - 0.15,
    y: rand(i * 7.7) * 0.62 - 0.05,
    s: 40 + rand(i * 5.3) ** 1.6 * 240,
    c: palette[Math.floor(rand(i * 9.1) * (i % 6 === 5 ? 5 : 4))],
    a: 0.16 + rand(i * 2.9) * 0.38,
    depth: 0.4 + rand(i * 4.4) * 0.8,
    tw: rand(i * 6.6) * 6.28,
  };
});

/** The café at night, far out of focus. `alarm` 0…1 bleeds red into it. */
export const Backdrop: React.FC<{ W: number; H: number; yaw: number; t: number; alarm: number; tint: string }> = ({ W, H, yaw, t, alarm, tint }) => {
  const scale = Math.max(W, H) / 1920;
  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: "linear-gradient(180deg, #0d1020 0%, #0b0d18 45%, #07080e 100%)" }}>
      {/* warm room light */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(60% 45% at 30% 28%, rgba(255,170,80,0.16), transparent 70%), radial-gradient(50% 40% at 80% 20%, rgba(255,200,140,0.10), transparent 70%)",
        }}
      />
      {BOKEH.map((b, i) => {
        const s = b.s * scale;
        const x = b.x * W - yaw * 9 * b.depth * scale + Math.sin(t * 0.3 + b.tw) * 6 * scale;
        const y = b.y * H + Math.cos(t * 0.25 + b.tw) * 4 * scale;
        const tw = 0.85 + 0.15 * Math.sin(t * 1.3 + b.tw);
        const a = b.a * tw;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: x - s / 2,
              top: y - s / 2,
              width: s,
              height: s,
              borderRadius: "50%",
              background: `radial-gradient(circle, rgba(${b.c},${a * 0.75}) 0%, rgba(${b.c},${a * 0.62}) 58%, rgba(${b.c},${a}) 66%, rgba(${b.c},0) 71%)`,
            }}
          />
        );
      })}
      <div style={{ position: "absolute", inset: 0, background: tint, mixBlendMode: "color", opacity: alarm * 0.8 }} />
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: `radial-gradient(70% 60% at 50% 45%, rgba(220,38,52,${0.28 * alarm}), transparent 75%)`,
        }}
      />
    </div>
  );
};

/**
 * The 3D room: the table, the laptop and its shadow, seen through `cam`. Children are drawn inside the
 * world (in table coordinates) too.
 */
export const Stage: React.FC<{
  W: number;
  H: number;
  cam: Cam;
  pose: Pose;
  lift: number;
  screen: React.ReactNode;
  glow: string;
  touchId?: React.ReactNode;
  trackpad?: React.ReactNode;
  children?: React.ReactNode;
  lidAngle?: number;
}> = ({ W, H, cam, pose, lift, screen, glow, touchId, trackpad, children, lidAngle }) => {
  const ox = (cam.ox ?? 0.5) * W;
  const oy = (cam.oy ?? 0.5) * H;
  const worldStyle: React.CSSProperties = {
    position: "absolute",
    left: ox,
    top: oy,
    width: 0,
    height: 0,
    transformStyle: "preserve-3d",
    transform: `translateZ(${-cam.dist}px) rotateX(${-cam.pitch}deg) rotateY(${-cam.yaw}deg) translate3d(${-cam.tx}px, ${-cam.ty}px, ${-cam.tz}px)`,
  };
  return (
    <div style={{ position: "absolute", inset: 0, perspective: cam.fov, perspectiveOrigin: `${ox}px ${oy}px`, overflow: "hidden" }}>
      {/* The table lives in its own 3D context, drawn first: it is always behind the laptop, and one
          huge plane sorted together with the lid gets cut wrongly. */}
      <div style={worldStyle}>
        <div
          style={{
            position: "absolute",
            left: -4200,
            top: -2600,
            width: 8400,
            height: 5200,
            transform: "translateY(1px) rotateX(90deg)",
            background: [
              `radial-gradient(28% 34% at 50% 52%, rgba(255,190,120,0.16), transparent 75%)`,
              "linear-gradient(180deg, #120c09 0%, #1c130e 45%, #1a120d 60%, #0f0a07 100%)",
            ].join(", "),
            WebkitMaskImage: "radial-gradient(50% 50% at 50% 52%, #000 55%, transparent 100%)",
            maskImage: "radial-gradient(50% 50% at 50% 52%, #000 55%, transparent 100%)",
          }}
        />
        {/* the screen's light on the table, in front of the laptop */}
        <div
          style={{
            position: "absolute",
            left: -1500,
            top: -1100,
            width: 3000,
            height: 2200,
            transform: `translate3d(0px, 0px, ${BD / 2 + 700}px) rotateX(90deg)`,
            background: `radial-gradient(50% 50% at 50% 0%, ${glow}, transparent 72%)`,
            opacity: 0.9 * (1 - lift * 0.5),
          }}
        />
        {/* soft shadow and contact shadow */}
        <div
          style={{
            position: "absolute",
            left: -(BW + 520) / 2,
            top: -(BD + 520) / 2,
            width: BW + 520,
            height: BD + 520,
            transform: `translate3d(${pose.x}px, -0.5px, ${pose.z + 40}px) rotateX(90deg) scale(${1 + lift * 0.25})`,
            background: "radial-gradient(closest-side, rgba(0,0,0,0.72), rgba(0,0,0,0.35) 60%, transparent)",
            opacity: 1 - lift * 0.55,
          }}
        />
        <div
          style={{
            position: "absolute",
            left: -(BW + 30) / 2,
            top: -(BD + 30) / 2,
            width: BW + 30,
            height: BD + 30,
            borderRadius: 60,
            transform: `translate3d(${pose.x}px, -0.8px, ${pose.z}px) rotateX(90deg)`,
            background: "rgba(0,0,0,0.85)",
            filter: "blur(10px)",
            opacity: Math.max(0, 1 - lift * 3),
          }}
        />
      </div>
      <div style={worldStyle}>
        <Laptop pose={pose} screen={screen} touchId={touchId} trackpad={trackpad} screenGlow={glow} lidAngle={lidAngle} />
        {children}
      </div>
    </div>
  );
};
