import React from "react";
import { Q } from "../lib/cues";
import { useCtx } from "../lib/ctx";
import { C } from "../lib/theme";
import { E, clamp, map, mix, ramp } from "../lib/time";
import { ICON_X, ICON_Y, SH, SW } from "../mac/Desktop";
import { LID_ANGLE, Pose, REST, TOUCH_ID, TP, deckPoint, screenPoint } from "../mac/Laptop";
import { ScreenAt } from "../mac/Screen";
import { Backdrop, Cam, Stage, lerpCam } from "../mac/Stage";
import { SirenRings, Silhouette } from "../ui/People";

const T = Q.touch;
const L = Q.lift;
const P = Q.putback;
const W8 = Q.welcome;

/** A camera looking straight at the screen, `sx, sy` (screen pixels) landing at the frame's ox/oy. */
const onScreen = (sx: number, sy: number, dist: number, ox = 0.5, oy = 0.5): Cam => {
  const p = screenPoint(sx, sy);
  return { yaw: 0, pitch: LID_ANGLE, dist, tx: p.x, ty: p.y, tz: p.z, fov: 2600, ox, oy };
};

/** The screen fills the frame's height at this distance (frame height `H`). */
const fillDist = (H: number, frac: number) => {
  const scale = (H * frac) / (SH * (1164 / SW));
  return 2600 / scale - 2600;
};

type Shot = { cam: Cam; pose: Pose; lift: number; name: string };

/** Which shot is on screen at `t`, and where its camera and the laptop are. */
export const macShot = (t: number, W: number, H: number, tall: boolean): Shot => {
  const ox = tall ? 0.5 : 0.655;
  const heroDist = tall ? 1500 : 860;
  const hero = (yaw: number, pitch: number, dist: number, ty = -300, oy = tall ? 0.6 : 0.52): Cam => ({
    yaw,
    pitch,
    dist,
    tx: 0,
    ty,
    tz: 0,
    fov: 2600,
    ox,
    oy,
  });

  // The laptop: lifted at L.up, put back at P.thud.
  let pose: Pose = REST;
  let lift = 0;
  if (t >= L.up && t < P.thud) {
    const up = ramp(t, L.up, L.up + 0.42, E.expoOut);
    const down = ramp(t, P.down, P.thud, E.in);
    const k = up * (1 - down);
    const shake = Math.sin(t * 2 * Math.PI * 7.5) * (1 - down) * up;
    const sway = Math.sin(t * 2 * Math.PI * 0.9);
    pose = {
      x: 40 * k + sway * 14 * k,
      y: -250 * k + Math.abs(shake) * -6,
      z: 60 * k,
      rx: 8 * k + shake * 0.8,
      ry: -6 * k + sway * 2 * k,
      rz: -7 * k + shake * 1.3,
    };
    lift = k;
  } else if (t >= P.thud && t < P.thud + 0.4) {
    // a small settle after it lands
    const b = Math.sin(((t - P.thud) / 0.4) * Math.PI * 2) * (1 - (t - P.thud) / 0.4);
    pose = { ...REST, y: -4 * Math.max(0, b), rz: 0.6 * b };
  }

  if (t < Q.setup.end) {
    // From inside the icon's light, out to the laptop on its table.
    const a: Cam = hero(-46, 4, tall ? 300 : -260, -320, tall ? 0.55 : 0.5);
    const b: Cam = hero(-34, 9, tall ? 1100 : 380, -300);
    const c: Cam = hero(-24, 13, heroDist + 40, -300);
    const k1 = ramp(t, Q.intro.toMenu - 0.07, Q.intro.end + 0.5, E.expoOut);
    const k2 = ramp(t, Q.intro.end + 0.2, Q.setup.end, E.soft);
    return { cam: lerpCam(lerpCam(a, b, k1), c, k2), pose, lift, name: "setup" };
  }
  if (t < Q.arm.end) {
    const A = Q.arm;
    const fill = fillDist(H, tall ? 0.5 : 0.94);
    const near = tall ? onScreen(1190, 210, fillDist(H, 0.95), 0.5, 0.52) : onScreen(1165, 290, fillDist(H, 1.75), 0.5, 0.5);
    const full = onScreen(SW / 2, SH / 2, fill, 0.5, tall ? 0.55 : 0.5);
    const push = onScreen(SW / 2, 430, fill - (tall ? 260 : 140), 0.5, tall ? 0.55 : 0.5);
    const k1 = ramp(t, A.panelClose - 0.05, A.count + 0.55, E.inOut);
    const k2 = ramp(t, A.count + 0.55, A.end, E.soft);
    const drift = ramp(t, A.start, A.panelClose, E.soft);
    const n0 = { ...near, dist: near.dist + 60 * drift };
    return { cam: lerpCam(lerpCam(n0, full, k1), push, k2), pose, lift, name: "arm" };
  }
  if (t < Q.guard.end) {
    const k = ramp(t, Q.guard.start, Q.guard.end, E.soft);
    return { cam: lerpCam(hero(-14, 11, heroDist + 60), hero(-27, 13, heroDist - 40), k), pose, lift, name: "guard" };
  }
  if (t < T.end) {
    const k = ramp(t, T.start, T.end, E.soft);
    const a: Cam = { yaw: -8, pitch: 27, dist: tall ? 1000 : 360, tx: 60, ty: -250, tz: 60, fov: 2600, ox: tall ? 0.5 : 0.7, oy: tall ? 0.63 : 0.5 };
    const b: Cam = { ...a, yaw: -13, dist: a.dist - 150 };
    return { cam: lerpCam(a, b, k), pose, lift, name: "touch" };
  }
  if (t < Q.phone.start) {
    const k = ramp(t, L.start, Q.phone.start, E.soft);
    return { cam: lerpCam(hero(-18, 9, heroDist + 120, -330), hero(-23, 10, heroDist + 60, -330), k), pose, lift, name: "lift" };
  }
  if (t < P.start) {
    // Behind the phone, out of focus: drift from where the lift shot ends to where the put-back starts.
    const k = ramp(t, Q.phone.start, P.start, E.soft);
    return { cam: lerpCam(hero(-23, 10, heroDist + 60, -330), hero(-20, 10, heroDist + 80, -320), k), pose, lift, name: "phone" };
  }
  if (t < P.end) {
    const k = ramp(t, P.start, P.end, E.soft);
    return { cam: lerpCam(hero(-20, 10, heroDist + 80, -320), hero(-25, 12, heroDist + 10, -300), k), pose, lift, name: "putback" };
  }
  if (t < Q.touchid.end) {
    const k = ramp(t, Q.touchid.start, Q.touchid.end, E.soft);
    const p = deckPoint(TOUCH_ID.x, TOUCH_ID.y);
    const a: Cam = {
      yaw: -30,
      pitch: 50,
      dist: tall ? -820 : -1120,
      tx: p.x - 20,
      ty: p.y,
      tz: p.z + 30,
      fov: 2600,
      ox: tall ? 0.56 : 0.64,
      oy: tall ? 0.56 : 0.42,
    };
    const b: Cam = { ...a, yaw: -24, dist: a.dist - 150 };
    return { cam: lerpCam(a, b, k), pose, lift, name: "touchid" };
  }
  // Welcome back, then into the menu-bar shield.
  const fill = fillDist(H, tall ? 0.5 : 0.94);
  const full = onScreen(SW / 2, SH / 2, fill, 0.5, tall ? 0.55 : 0.5);
  const near = onScreen(SW / 2, SH / 2 - 40, fill - 90, 0.5, tall ? 0.55 : 0.5);
  const icon = onScreen(ICON_X, ICON_Y + 6, tall ? -2150 : -2250, 0.5, 0.5);
  const k1 = ramp(t, W8.start, W8.shrink, E.soft);
  const k2 = ramp(t, W8.shrink - 0.1, W8.land + 0.05, E.inOut);
  return { cam: lerpCam(lerpCam(full, near, k1), icon, k2), pose, lift, name: "welcome" };
};

/** The light the screen throws: cool, amber while arming, red in an alarm, green once disarmed. */
export const screenGlow = (t: number) => {
  const A = Q.arm;
  if (t < A.frost) return "rgba(120,140,255,0.22)";
  if (t < A.sign) return `rgba(246,181,68,${mix(0.12, 0.28, ramp(t, A.frost, A.sign))})`;
  if (t < T.flood) return "rgba(150,165,230,0.2)";
  if (t < W8.clear) {
    const siren = t >= L.siren && t < P.thud;
    const pulse = siren ? 0.5 + 0.5 * Math.abs(Math.sin(((t - L.siren) / 1.2) * Math.PI)) : 0.6;
    const calm = ramp(t, P.thud, P.thud + 0.6);
    return `rgba(${Math.round(mix(255, 190, calm))},40,52,${(0.28 + 0.2 * pulse) * (1 - 0.35 * calm)})`;
  }
  const g = 1 - ramp(t, W8.clear + 0.8, W8.end);
  return `rgba(${Math.round(mix(120, 70, g))},${Math.round(mix(140, 212, g))},${Math.round(mix(255, 131, g))},${mix(0.22, 0.3, g)})`;
};

/** How red the room is. */
export const alarmLevel = (t: number) => {
  if (t < T.flood || t >= W8.clear + 0.6) return 0;
  const on = ramp(t, T.flood, T.flood + 0.5);
  const off = 1 - ramp(t, W8.clear, W8.clear + 0.6);
  const calm = ramp(t, P.thud, P.thud + 0.5);
  const siren = t >= L.siren && t < P.thud ? 0.65 + 0.35 * Math.abs(Math.sin(((t - L.siren) / 1.2) * Math.PI)) : mix(0.45, 0.22, calm);
  return on * off * siren;
};

/** A touch on the trackpad: a soft ring that spreads under the finger. */
const TrackpadTouch: React.FC<{ t: number }> = ({ t }) => {
  const age = t - T.tap;
  if (age < -0.25 || age > 0.9) return null;
  const x = TP.w * 0.62;
  const y = TP.h * 0.46;
  const press = clamp(1 - Math.abs(age) / 0.25);
  const rings = [0, 0.16].map((d, i) => {
    const a = age - d;
    if (a < 0) return null;
    const k = clamp(a / 0.7);
    const r = 20 + 160 * E.out(k);
    return (
      <div
        key={i}
        style={{
          position: "absolute",
          left: x - r,
          top: y - r,
          width: r * 2,
          height: r * 2,
          borderRadius: "50%",
          border: `3px solid rgba(255,${Math.round(200 - 140 * k)},${Math.round(200 - 140 * k)},${0.8 * (1 - k)})`,
        }}
      />
    );
  });
  return (
    <>
      <div
        style={{
          position: "absolute",
          left: x - 34,
          top: y - 34,
          width: 68,
          height: 68,
          borderRadius: "50%",
          background: `radial-gradient(circle, rgba(255,255,255,${0.5 * press}) 0%, rgba(255,255,255,0) 70%)`,
        }}
      />
      {rings}
    </>
  );
};

/** The owner's finger on Touch ID: the key lights green and a print draws in. */
const TouchIdGlow: React.FC<{ t: number }> = ({ t }) => {
  const TI = Q.touchid;
  const on = ramp(t, TI.press, TI.press + 0.15);
  const ok = ramp(t, TI.ok, TI.ok + 0.25);
  const fade = 1 - ramp(t, Q.welcome.start + 0.6, Q.welcome.start + 1.2);
  if (on <= 0 || fade <= 0) return null;
  const ringR = 18 + 50 * E.out(clamp((t - TI.ok) / 0.6));
  return (
    <div style={{ position: "absolute", inset: 0, opacity: fade }}>
      <div
        style={{
          position: "absolute",
          inset: 3,
          borderRadius: 7,
          boxShadow: `inset 0 0 0 ${1.5 + ok}px rgba(70,212,131,${0.25 + 0.7 * ok}), 0 0 ${24 * ok}px rgba(70,212,131,${0.6 * ok})`,
          background: `radial-gradient(circle, rgba(70,212,131,${0.25 * ok}) 0%, rgba(70,212,131,0) 75%)`,
        }}
      />
      <svg
        width="36"
        height="36"
        viewBox="0 0 24 24"
        style={{ position: "absolute", left: "50%", top: "50%", marginLeft: -18, marginTop: -18, opacity: on }}
      >
        {[3.2, 5.6, 8].map((r, i) => (
          <path
            key={i}
            d={`M ${12 - r} 13 A ${r} ${r} 0 0 1 ${12 + r} 13`}
            stroke={ok > 0.5 ? C.green : "rgba(255,255,255,0.85)"}
            strokeWidth="1.4"
            fill="none"
            strokeLinecap="round"
            pathLength={1}
            strokeDasharray={1}
            strokeDashoffset={1 - clamp((t - TI.press - i * 0.05) / 0.25)}
          />
        ))}
        <path d="M12 13 L12 18" stroke={ok > 0.5 ? C.green : "rgba(255,255,255,0.85)"} strokeWidth="1.4" strokeLinecap="round" />
      </svg>
      {ok > 0 && (
        <div
          style={{
            position: "absolute",
            left: "50%",
            top: "50%",
            width: ringR * 2,
            height: ringR * 2,
            marginLeft: -ringR,
            marginTop: -ringR,
            borderRadius: "50%",
            border: `2px solid rgba(70,212,131,${0.8 * (1 - clamp((t - TI.ok) / 0.6))})`,
          }}
        />
      )}
    </div>
  );
};

/**
 * The laptop in the café, through whichever camera the cut calls for. `blur` softens the whole room
 * (behind the phone).
 */
export const MacWorld: React.FC<{ blur?: number; dim?: number }> = ({ blur = 0, dim = 0 }) => {
  const { t, W, H, format } = useCtx();
  const tall = format === "tall";
  const shot = macShot(t, W, H, tall);
  const glow = screenGlow(t);
  const alarm = alarmLevel(t);
  const G = Q.guard;
  const scale = W / 1920;

  // Someone walks behind the table, then someone close to the lens wipes across the frame.
  const bgWalk = map(t, [G.start, G.wipe + 0.2], [-0.12, 1.12]);
  const fgWalk = map(t, [G.wipe - 0.05, G.start + (G.end - G.start), G.end + 0.32], [1.55, 0.5, -0.6], E.soft);
  const sirenOn = t >= L.siren && t < P.thud;

  // Where the laptop sits in the frame, for the rings (hand-placed per shot).
  const ringX = W * (tall ? 0.5 : 0.655);
  const ringY = H * (tall ? 0.56 : 0.47);

  return (
    <div style={{ position: "absolute", inset: 0, overflow: "hidden", filter: blur > 0 ? `blur(${blur}px)` : undefined }}>
      <Backdrop W={W} H={H} yaw={shot.cam.yaw} t={t} alarm={alarm} tint={C.flood} />
      {shot.name === "guard" && (
        <Silhouette
          x={bgWalk * W}
          y={H * (tall ? 0.3 : 0.12)}
          h={H * (tall ? 0.42 : 0.82)}
          blur={10 * scale}
          opacity={0.85}
          step={t * 7}
          rim="rgba(255,190,120,0.25)"
        />
      )}
      <Stage
        W={W}
        H={H}
        cam={shot.cam}
        pose={shot.pose}
        lift={shot.lift}
        glow={glow}
        screen={<ScreenAt t={t} />}
        trackpad={<TrackpadTouch t={t} />}
        touchId={<TouchIdGlow t={t} />}
      />
      {sirenOn && (shot.name === "lift" || shot.name === "phone") && (
        <SirenRings x={ringX} y={ringY} t={t} from={L.siren} to={P.thud} scale={scale * (tall ? 0.8 : 1)} />
      )}
      {/* the red in the air while the siren sounds */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          pointerEvents: "none",
          background: `radial-gradient(80% 80% at 50% 50%, rgba(255,40,52,0) 40%, rgba(220,38,52,${0.35 * alarm * (sirenOn ? 1 : 0.5)}) 100%)`,
        }}
      />
      {t > G.wipe - 0.05 && t < G.end + 0.32 && (
        <Silhouette x={fgWalk * W} y={H * -0.12} h={H * 3.3} blur={40 * scale} color="#010103" step={t * 6} flip />
      )}
      {dim > 0 && <div style={{ position: "absolute", inset: 0, background: `rgba(4,5,10,${dim})` }} />}
    </div>
  );
};
