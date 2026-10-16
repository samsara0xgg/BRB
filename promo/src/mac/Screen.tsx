import React from "react";
import { Q } from "../lib/cues";
import { useCtx } from "../lib/ctx";
import { E, map, ramp, springAt } from "../lib/time";
import { Shield } from "../ui/Shield";
import { Desktop, ICON_X, ICON_Y, MenuBar, Notch, SH, SW } from "./Desktop";
import { Panel, START_X, START_Y } from "./Panel";
import { Flood, Footer, Frost, Ring, SIGN_CX, SIGN_CY, Sign, SignState } from "./Veil";

/** The stranger's pointer: where the red starts. */
export const TOUCH_X = 1046;
export const TOUCH_Y = 676;

const Arrow: React.FC<{ x: number; y: number; press: number; opacity: number }> = ({ x, y, press, opacity }) => {
  if (opacity <= 0) return null;
  return (
    <svg
      width="30"
      height="30"
      viewBox="0 0 24 24"
      style={{
        position: "absolute",
        left: x - 5,
        top: y - 3,
        opacity,
        transform: `scale(${1 - press * 0.12})`,
        transformOrigin: "5px 3px",
        filter: "drop-shadow(0 2px 3px rgba(0,0,0,0.45))",
      }}
    >
      <path
        d="M5 3 L5 19.6 L9.2 15.7 L12 21.9 L14.9 20.6 L12.1 14.5 L17.9 14.5 Z"
        fill="#000"
        stroke="#fff"
        strokeWidth="1.4"
        strokeLinejoin="round"
      />
    </svg>
  );
};

/** A press ring where the pointer clicks. */
const Click: React.FC<{ x: number; y: number; age: number }> = ({ x, y, age }) => {
  if (age < 0 || age > 0.45) return null;
  const k = age / 0.45;
  const r = 10 + 34 * k;
  return (
    <div
      style={{
        position: "absolute",
        left: x - r,
        top: y - r,
        width: r * 2,
        height: r * 2,
        borderRadius: "50%",
        border: `2px solid rgba(255,255,255,${0.7 * (1 - k)})`,
        background: `rgba(255,255,255,${0.18 * (1 - k)})`,
      }}
    />
  );
};

/** Everything on the Mac's screen, as a function of the film's time. */
export const ScreenAt: React.FC<{ t: number }> = ({ t }) => {
  const { fps, copy } = useCtx();
  const A = Q.arm;

  // The panel and the pointer.
  const open = springAt(t, A.panelOpen, fps, { damping: 16, stiffness: 210 });
  const close = ramp(t, A.panelClose, A.panelClose + 0.18);
  const press = Math.max(0, 1 - Math.abs(t - (A.clickStart + 0.06)) / 0.1);
  const iconPress = Math.max(0, 1 - Math.abs(t - (A.clickIcon + 0.05)) / 0.1);

  let px = 880;
  let py = 560;
  const toIcon = ramp(t, A.start - 0.1, A.clickIcon - 0.02, E.inOut);
  const toStart = ramp(t, A.clickIcon + 0.12, A.clickStart - 0.02, E.inOut);
  px = 880 + (ICON_X - 880) * toIcon;
  py = 560 + (ICON_Y + 2 - 560) * toIcon;
  px = px + (START_X - 30 - px) * toStart;
  py = py + (START_Y - py) * toStart;
  const armPointer = t < A.panelClose + 0.25 ? 1 - ramp(t, A.panelClose + 0.05, A.panelClose + 0.25) : 0;

  // The stranger's pointer slides a little, then the red starts under it.
  const T = Q.touch;
  const sx = map(t, [T.tap - 0.32, T.tap], [TOUCH_X - 70, TOUCH_X], E.out);
  const sy = map(t, [T.tap - 0.32, T.tap], [TOUCH_Y + 40, TOUCH_Y], E.out);
  const strangerPointer =
    t > T.tap - 0.32 && t < T.flood + 0.5 ? map(t, [T.tap - 0.32, T.tap - 0.2, T.flood + 0.25, T.flood + 0.5], [0, 1, 1, 0]) : 0;

  // Frost and countdown.
  const frostR = map(t, [A.frost, A.frost + 1.45], [0, 1150], E.soft);
  const count = t - A.count;
  const n = Math.max(1, 5 - Math.floor(count / A.step));
  const nAge = count - (5 - n) * A.step;
  const ringProgress = Math.min(1, Math.max(0, count / (A.step * 5)));
  const appear = springAt(t, A.sign, fps, { damping: 15, stiffness: 120 });
  const ringOpacity = t >= A.count ? Math.min(1, count / 0.15) * (t < A.sign + 0.5 ? 1 : 0) : 0;

  // The notice's states.
  const W = Q.welcome;
  const alarmAt = T.flood + 0.12;
  const offAt = Q.putback.thud + 0.08;
  let from: SignState = "guard";
  let to: SignState = "guard";
  let k = 0;
  if (t >= W.sign) {
    from = "off";
    to = "welcome";
    k = ramp(t, W.sign, W.sign + 0.45);
  } else if (t >= offAt) {
    from = "alarm";
    to = "off";
    k = ramp(t, offAt, offAt + 0.4);
  } else if (t >= alarmAt) {
    from = "guard";
    to = "alarm";
    k = ramp(t, alarmAt, alarmAt + 0.35);
  }

  // Red, then calmer once it's back in place, then cleared from the bottom-right.
  const floodR = map(t, [T.flood, T.flood + 0.75], [0, 2300], E.out);
  const calm = ramp(t, Q.putback.thud, Q.putback.thud + 0.6);
  const clearR = map(t, [W.clear, W.clear + 0.85], [0, 2000], E.soft);

  // The notice shrinks into the menu-bar shield.
  const shrink = ramp(t, W.shrink, W.land, E.inOut);
  const signScale = 1 - 0.97 * shrink;
  const sdx = (ICON_X - SIGN_CX) * shrink;
  const sdy = (ICON_Y - SIGN_CY) * shrink;
  const signOpacity = 1 - ramp(t, W.land - 0.12, W.land);

  const pulse = 0.5 + 0.5 * Math.sin(t * Math.PI * 2 * 1.4);

  // The menu-bar shield.
  let icon: React.ReactNode = <Shield look="outline" size={19} stroke={2} />;
  if (t >= A.count && t < A.sign) icon = <Shield look="arming" size={19} stroke={2} level={ringProgress} />;
  else if (t >= A.sign && t < T.flood) icon = <Shield look="armed" size={19} />;
  else if (t >= T.flood && t < W.clear) icon = <Shield look="alarm" size={19} />;
  else if (t >= W.land) {
    const pop = springAt(t, W.land, fps, { damping: 9, stiffness: 260 });
    icon = (
      <div style={{ transform: `scale(${0.4 + 0.6 * pop})` }}>
        <Shield look="clear" size={19} level={ramp(t, W.land + 0.05, W.land + 0.35)} glow={1 - ramp(t, W.land + 0.3, W.land + 1.2)} />
      </div>
    );
  }
  const iconBox = (
    <div
      style={{
        width: 26,
        height: 26,
        borderRadius: 6,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: iconPress > 0 || (open > 0.02 && close < 1) ? "rgba(255,255,255,0.18)" : "transparent",
      }}
    >
      {icon}
    </div>
  );

  const frostTint = "linear-gradient(180deg, rgba(22,28,58,0.46), rgba(14,18,38,0.52))";

  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, overflow: "hidden", background: "#000" }}>
      <Desktop />
      <MenuBar icon={iconBox} clock={t < W.start ? copy.mac.clock : copy.mac.clockBack} />
      <Panel open={open} press={press} fade={close} />
      <Frost r={frostR} clearR={clearR} tint={frostTint} />
      <Flood x={TOUCH_X} y={TOUCH_Y} r={floodR} calm={calm} clearR={clearR} />
      <Ring progress={ringProgress} n={n} nAge={nAge} k={ramp(t, A.sign, A.sign + 0.3)} opacity={ringOpacity} />
      <Sign from={from} to={to} k={k} appear={appear} scale={signScale} dx={sdx} dy={sdy} opacity={signOpacity} pulse={pulse} />
      <Footer opacity={frostR > 700 ? ramp(t, A.sign + 0.2, A.sign + 0.6) * (1 - ramp(t, W.clear, W.clear + 0.4)) : 0} />
      <Arrow x={px} y={py} press={Math.max(press, iconPress)} opacity={t >= A.start - 0.1 ? armPointer : 0} />
      <Click x={ICON_X} y={ICON_Y} age={t - A.clickIcon} />
      <Click x={START_X - 30} y={START_Y} age={t - A.clickStart} />
      <Arrow x={sx} y={sy} press={0} opacity={strangerPointer} />
      <Notch light={t >= A.count && t < W.clear + 0.3 ? 1 : 0} />
    </div>
  );
};
