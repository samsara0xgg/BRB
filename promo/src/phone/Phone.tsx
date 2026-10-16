import React from "react";
import { Q } from "../lib/cues";
import { useCtx } from "../lib/ctx";
import { C, FONT } from "../lib/theme";
import { E, clamp, map, mix, ramp, springAt } from "../lib/time";
import { Shield } from "../ui/Shield";
import {
  Battery,
  CameraIcon,
  ChevronDown,
  DocText,
  Expand,
  Flashlight,
  OpenIcon,
  Padlock,
  SaveDown,
  Signal,
  SpeakerSlash,
  SpeakerWave,
  Wifi,
} from "./Icons";
import { LiveView } from "./LiveView";

// A 6.1-inch iPhone with the Dynamic Island, in points.
export const PW = 393;
export const PH = 852;
const BEZEL = 6.5;
const BAND = 3.6;
const R = 55;
export const OUT_W = PW + 2 * (BEZEL + BAND);
export const OUT_H = PH + 2 * (BEZEL + BAND);

// The phone app's dark colors (ios/Shared/UI/Theme.swift).
const T = {
  bg: "#0b0f1c",
  cardHi: "rgba(255,255,255,0.10)",
  hair: "rgba(255,255,255,0.08)",
  rim: "rgba(255,255,255,0.13)",
  ink: "#eef1f8",
  ink2: "rgba(238,241,248,0.64)",
  ink3: "rgba(238,241,248,0.40)",
  textRed: "#ff7a80",
  islandRed: "#ff6b72",
};

const P = Q.phone;
// The film's clock against the wall clock: the trackpad was touched at 3:41:25.
const wall = (t: number) => 25 + (t - Q.touch.tap);
const elapsed = (t: number) => `0:${String(Math.max(0, Math.floor(t - Q.touch.tap))).padStart(2, "0")}`;

const StatusBar: React.FC<{ time?: string }> = ({ time }) => (
  <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: 50, fontFamily: FONT.text, color: "#fff" }}>
    {time && (
      <div style={{ position: "absolute", left: 0, width: 132, top: 15, textAlign: "center", fontSize: 17, fontWeight: 600, letterSpacing: -0.3 }}>
        {time}
      </div>
    )}
    <div style={{ position: "absolute", right: 30, top: 19, display: "flex", gap: 6, alignItems: "center" }}>
      <Signal />
      <Wifi />
      <Battery />
    </div>
  </div>
);

const Island: React.FC = () => (
  <div style={{ position: "absolute", left: PW / 2 - 63, top: 11, width: 126, height: 37.3, borderRadius: 18.7, background: "#000" }}>
    <div
      style={{
        position: "absolute",
        right: 22,
        top: 13,
        width: 11,
        height: 11,
        borderRadius: 6,
        background: "radial-gradient(circle at 40% 35%, #1f2b44, #050608 70%)",
      }}
    />
  </div>
);

const wallpaper = [
  "radial-gradient(90% 50% at 85% 104%, rgba(246,181,68,0.45), rgba(246,181,68,0) 70%)",
  "radial-gradient(80% 45% at 0% 0%, rgba(92,108,230,0.6), rgba(92,108,230,0) 70%)",
  "radial-gradient(70% 40% at 70% 40%, rgba(156,86,206,0.32), rgba(156,86,206,0) 72%)",
  "linear-gradient(170deg, #1b2256 0%, #0d1130 55%, #160b26 100%)",
].join(", ");

const LockButton: React.FC<{ x: number; children: React.ReactNode }> = ({ x, children }) => (
  <div
    style={{
      position: "absolute",
      left: x - 25,
      top: 766,
      width: 50,
      height: 50,
      borderRadius: 25,
      background: "rgba(30,34,52,0.55)",
      boxShadow: "inset 0 0 0 0.5px rgba(255,255,255,0.18)",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
    }}
  >
    {children}
  </div>
);

const Pill: React.FC<{ icon: React.ReactNode; label: string; press?: number }> = ({ icon, label, press = 0 }) => (
  <div
    style={{
      flex: 1,
      height: 38,
      borderRadius: 19,
      background: `rgba(255,255,255,${0.16 + 0.2 * press})`,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      gap: 6,
      fontSize: 14,
      fontWeight: 600,
      transform: `scale(${1 - 0.04 * press})`,
      whiteSpace: "nowrap",
    }}
  >
    {icon}
    {label}
  </div>
);

// The lock screen's Live Activity card (ios/Widgets/BRBLiveActivity.swift), in its siren state.
export const CARD = { x: 12, y: 584, w: PW - 24, h: 156 };

export const ActivityCard: React.FC<{ t: number; press: number }> = ({ t, press }) => {
  const { copy } = useCtx();
  const u = copy.phoneUi;
  return (
    <div
      style={{
        position: "absolute",
        left: CARD.x,
        top: CARD.y,
        width: CARD.w,
        height: CARD.h,
        borderRadius: 26,
        background: "linear-gradient(180deg, rgba(104,16,32,0.94), rgba(84,12,26,0.94))",
        boxShadow: "inset 0 0 0 0.5px rgba(255,255,255,0.14), 0 10px 30px rgba(0,0,0,0.3)",
        padding: "14px 16px",
        boxSizing: "border-box",
        color: "#fff",
        fontFamily: FONT.text,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 9, height: 22 }}>
        <Shield look="armed" size={22} />
        <div style={{ fontSize: 14.5, fontWeight: 600 }}>{u.pickedUp}</div>
        <div style={{ flex: 1 }} />
        <div style={{ fontSize: 12.5, opacity: 0.7 }}>{u.macName}</div>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginTop: 11, height: 44 }}>
        <Shield look="alarm" size={34} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: "flex", gap: 6, alignItems: "baseline" }}>
            <div style={{ fontSize: 16, fontWeight: 600 }}>{u.sirenOn}</div>
            <div style={{ fontSize: 16, fontWeight: 600, color: T.islandRed, fontVariantNumeric: "tabular-nums" }}>{elapsed(t)}</div>
          </div>
          <div style={{ fontSize: 12.5, opacity: 0.72, marginTop: 1, whiteSpace: "nowrap" }}>{u.statusSub}</div>
        </div>
        <div style={{ width: 58, height: 44, borderRadius: 10, overflow: "hidden", flex: "none" }}>
          <LiveView t={t} w={58} h={44} still />
        </div>
      </div>
      <div style={{ display: "flex", gap: 8, marginTop: 11 }}>
        <Pill icon={<SpeakerSlash size={14} />} label={u.stopSiren} />
        <Pill icon={<OpenIcon size={14} />} label={u.open} press={press} />
      </div>
    </div>
  );
};

const LockScreen: React.FC<{ t: number; press: number; card: number }> = ({ t, press, card }) => {
  const { copy, lang } = useCtx();
  const u = copy.phoneUi;
  return (
    <div style={{ position: "absolute", inset: 0, background: wallpaper, fontFamily: FONT.text, color: "#fff" }}>
      <StatusBar />
      <div style={{ position: "absolute", left: PW / 2 - 8, top: 58, opacity: 0.9 }}>
        <Padlock size={16} />
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 86,
          textAlign: "center",
          fontSize: 20,
          fontWeight: 600,
          opacity: 0.86,
          letterSpacing: lang === "zh" ? 1 : 0,
        }}
      >
        {u.date}
      </div>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 104,
          textAlign: "center",
          fontFamily: FONT.display,
          fontSize: 104,
          fontWeight: 700,
          letterSpacing: -2,
          lineHeight: 1.05,
          color: "rgba(255,255,255,0.92)",
        }}
      >
        {u.time}
      </div>
      <div
        style={{
          position: "absolute",
          inset: 0,
          opacity: clamp(card * 1.5),
          transform: `translateY(${(1 - card) * 40}px) scale(${0.94 + 0.06 * card})`,
          transformOrigin: `${PW / 2}px ${CARD.y + CARD.h}px`,
        }}
      >
        <ActivityCard t={t} press={press} />
      </div>
      <LockButton x={68}>
        <Flashlight size={21} />
      </LockButton>
      <LockButton x={PW - 68}>
        <CameraIcon size={22} />
      </LockButton>
    </div>
  );
};

// The alarm page (ios/App/UI/AlarmView.swift).
const HeaderBeat: React.FC<{ t: number }> = ({ t }) => {
  const p = (((t - Q.lift.siren) % 1) + 1) % 1;
  const o = p < 0.15 ? 1 : 1 - (p - 0.15) / 0.85;
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        background: "radial-gradient(320px 320px at 50% 0%, rgba(255,255,255,0.3), rgba(255,255,255,0) 100%)",
        opacity: o,
      }}
    />
  );
};

const Chip: React.FC<{ children: React.ReactNode; red?: boolean }> = ({ children, red }) => (
  <div
    style={{
      height: 24,
      padding: "0 9px",
      borderRadius: 12,
      display: "flex",
      alignItems: "center",
      gap: 6,
      background: red ? C.red : "rgba(0,0,0,0.5)",
      color: "#fff",
      fontSize: 11.5,
      fontWeight: red ? 800 : 600,
      letterSpacing: red ? 0.7 : 0,
      whiteSpace: "nowrap",
    }}
  >
    {children}
  </div>
);

type Ev = { at: number; text: string; hot?: boolean; photo?: boolean };

const EventRow: React.FC<{ e: Ev; t: number; first: boolean; last: boolean }> = ({ e, t, first, last }) => {
  const s = wall(e.at);
  const time = `3:41:${String(Math.floor(s)).padStart(2, "0")}`;
  const { lang } = useCtx();
  const shown = lang === "zh" ? `15:41:${String(Math.floor(s)).padStart(2, "0")}` : time;
  const k = E.expoOut(clamp((t - e.at) / 0.45));
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 8, height: 33 * k, overflow: "hidden", opacity: k }}>
      <div style={{ width: 62, fontSize: 12, color: T.ink3, fontVariantNumeric: "tabular-nums", letterSpacing: 0.2 }}>{shown}</div>
      <div style={{ position: "relative", width: 14, height: 33, flex: "none" }}>
        <div style={{ position: "absolute", left: 6.5, top: 0, height: 16.5, width: 1, background: first ? "transparent" : T.hair }} />
        <div style={{ position: "absolute", left: 6.5, top: 16.5, height: 16.5, width: 1, background: last ? "transparent" : T.hair }} />
        <div style={{ position: "absolute", left: 2.5, top: 12, width: 9, height: 9, borderRadius: 5, background: e.hot ? C.red : T.ink3 }} />
      </div>
      <div style={{ flex: 1, fontSize: 14.5, color: e.hot ? T.textRed : T.ink, whiteSpace: "nowrap" }}>{e.text}</div>
      {e.photo && (
        <div style={{ width: 44, height: 33, borderRadius: 7, overflow: "hidden", flex: "none" }}>
          <LiveView t={e.at} w={44} h={33} />
        </div>
      )}
    </div>
  );
};

const SecondaryButton: React.FC<{ icon: React.ReactNode; label: string }> = ({ icon, label }) => (
  <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", gap: 4, paddingTop: 8 }}>
    <div style={{ width: 40, height: 40, borderRadius: 20, background: T.cardHi, display: "flex", alignItems: "center", justifyContent: "center" }}>
      {icon}
    </div>
    <div style={{ fontSize: 11.5, fontWeight: 600, color: T.ink2 }}>{label}</div>
  </div>
);

const headerH = (zh: boolean) => 50 + 42 + (zh ? 34 : 66) + 24 + 16;
const MEDIA_H = PW / 1.6;
/** Where the live picture's middle sits on the page, in points from the top. */
export const liveCenterY = (zh: boolean) => headerH(zh) + MEDIA_H / 2;

const AlarmPage: React.FC<{ t: number }> = ({ t }) => {
  const { copy, lang } = useCtx();
  const u = copy.phoneUi;
  const zh = lang === "zh";
  const events: Ev[] = [
    { at: 16.62, text: u.ev.photo, photo: true },
    { at: 14.6, text: u.ev.photo, photo: true },
    { at: 12.95, text: u.ev.push },
    { at: Q.lift.siren, text: u.ev.siren, hot: true },
    { at: Q.lift.up, text: u.ev.lift, hot: true },
    { at: Q.touch.tap, text: u.ev.touch, hot: true },
  ].filter((e) => e.at <= t);
  const blink = Math.sin(t * Math.PI * 2) > -0.2 ? 1 : 0.2;
  return (
    <div style={{ position: "absolute", inset: 0, background: T.bg, fontFamily: FONT.text, color: T.ink, display: "flex", flexDirection: "column" }}>
      <div
        style={{
          position: "relative",
          height: headerH(zh),
          flex: "none",
          background: "linear-gradient(180deg, #ff4d55, #d5232f)",
          color: "#fff",
          overflow: "hidden",
        }}
      >
        <HeaderBeat t={t} />
        <StatusBar time={u.time} />
        <div style={{ position: "absolute", left: 18, right: 18, top: 50 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, height: 36, marginBottom: 6 }}>
            <div
              style={{
                width: 34,
                height: 34,
                borderRadius: 17,
                background: "rgba(0,0,0,0.18)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <ChevronDown size={15} />
            </div>
            <div style={{ fontSize: 13, fontWeight: 700, letterSpacing: 0.8, opacity: 0.85 }}>{u.alarmCaps}</div>
          </div>
          <div
            style={{
              fontSize: 27,
              fontWeight: 800,
              lineHeight: 1.18,
              letterSpacing: zh ? 0.5 : -0.3,
              fontFamily: zh ? FONT.zh : FONT.display,
              textWrap: "balance",
            }}
          >
            {u.headline}
          </div>
          <div style={{ fontSize: 13.5, marginTop: 6, color: "rgba(255,255,255,0.86)", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>
            {u.metaFmt.replace("{e}", elapsed(t))}
          </div>
        </div>
      </div>
      <div style={{ position: "relative", height: MEDIA_H, flex: "none", background: "#000", overflow: "hidden" }}>
        <LiveView t={t} w={PW} h={MEDIA_H} />
        <div style={{ position: "absolute", left: 12, top: 12 }}>
          <Chip red>
            <div style={{ width: 6, height: 6, borderRadius: 3, background: "#fff", opacity: blink }} />
            {u.live}
          </Chip>
        </div>
        <div style={{ position: "absolute", left: 12, bottom: 12 }}>
          <Chip>{u.zoom}</Chip>
        </div>
        <div
          style={{
            position: "absolute",
            right: 12,
            bottom: 12,
            width: 34,
            height: 34,
            borderRadius: 17,
            background: "rgba(0,0,0,0.45)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <Expand size={14} />
        </div>
      </div>
      <div style={{ display: "flex", gap: 12, padding: "14px 18px 2px", flex: "none" }}>
        <div
          style={{
            width: 40,
            height: 40,
            borderRadius: 13,
            background: "rgba(255,77,85,0.16)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            flex: "none",
          }}
        >
          <SpeakerWave size={20} color={T.textRed} />
        </div>
        <div>
          <div style={{ fontSize: 19, fontWeight: 800 }}>{u.statusTitle}</div>
          <div style={{ fontSize: 13.5, color: T.ink2, marginTop: 2 }}>{u.statusSub}</div>
        </div>
      </div>
      <div style={{ flex: 1, padding: "8px 18px 6px", overflow: "hidden" }}>
        {events.map((e, i) => (
          <EventRow key={`${e.at}`} e={e} t={t} first={i === 0} last={i === events.length - 1} />
        ))}
      </div>
      <div style={{ display: "flex", gap: 6, padding: "6px 14px 6px", flex: "none" }}>
        <SecondaryButton icon={<SaveDown size={18} color={T.ink} />} label={u.savePhotos} />
        <SecondaryButton icon={<DocText size={18} color={T.ink} />} label={u.evidence} />
      </div>
      <div style={{ display: "flex", gap: 10, padding: "8px 14px 44px", flex: "none" }}>
        <div
          style={{
            flex: 1,
            height: 62,
            borderRadius: 24,
            background: T.ink,
            color: T.bg,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            gap: 8,
            fontSize: 18,
            fontWeight: 800,
          }}
        >
          <SpeakerSlash size={20} color={T.bg} />
          {u.stopSiren}
        </div>
        <div
          style={{
            flex: 1,
            height: 62,
            borderRadius: 24,
            background: T.cardHi,
            boxShadow: `inset 0 0 0 1px ${T.rim}`,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 18,
            fontWeight: 800,
          }}
        >
          {u.disarm}
        </div>
      </div>
    </div>
  );
};

/** The phone itself: titanium band, black border, the screen and its glass. */
const PhoneBody: React.FC<{ children: React.ReactNode; glow: number }> = ({ children, glow }) => (
  <div style={{ position: "absolute", left: 0, top: 0, width: OUT_W, height: OUT_H }}>
    {[
      { side: -1, top: 168, h: 30 },
      { side: -1, top: 222, h: 62 },
      { side: -1, top: 296, h: 62 },
      { side: 1, top: 250, h: 96 },
    ].map((b, i) => (
      <div
        key={i}
        style={{
          position: "absolute",
          left: b.side < 0 ? -2.6 : OUT_W - 1.4,
          top: b.top,
          width: 4,
          height: b.h,
          borderRadius: 2,
          background: "linear-gradient(90deg, #4a4d55, #23252a)",
        }}
      />
    ))}
    <div
      style={{
        position: "absolute",
        inset: 0,
        borderRadius: R + BEZEL + BAND,
        background: "linear-gradient(135deg, #6b6e76 0%, #2b2d33 16%, #1b1c21 50%, #2c2e34 84%, #74777f 100%)",
        boxShadow: `0 50px 100px rgba(0,0,0,0.55), 0 0 140px rgba(255,60,72,${0.32 * glow}), inset 0 0 0 1px rgba(255,255,255,0.14)`,
      }}
    />
    <div style={{ position: "absolute", inset: BAND, borderRadius: R + BEZEL, background: "#030304" }} />
    <div
      style={{
        position: "absolute",
        left: BAND + BEZEL,
        top: BAND + BEZEL,
        width: PW,
        height: PH,
        borderRadius: R,
        overflow: "hidden",
        background: "#000",
      }}
    >
      {children}
      <Island />
      <div
        style={{ position: "absolute", left: PW / 2 - 67, bottom: 8, width: 134, height: 5, borderRadius: 3, background: "rgba(255,255,255,0.85)" }}
      />
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: "linear-gradient(118deg, rgba(255,255,255,0.10) 0%, rgba(255,255,255,0.02) 34%, rgba(255,255,255,0) 50%)",
        }}
      />
    </div>
  </div>
);

/** How much the room behind is out of focus while the phone is up (0 → 1). */
export const phoneFocus = (t: number) => ramp(t, P.start - 0.12, P.start + 0.25, E.out) * (1 - ramp(t, P.end - 0.3, P.end + 0.08, E.inOut));

/** The phone in the frame: it rises, lights up red, opens the alarm and pushes in on the live picture. */
export const PhoneScene: React.FC = () => {
  const { t, W, H, format, fps, lang } = useCtx();
  if (t < P.start - 0.12 || t > P.end + 0.05) return null;
  const tall = format === "tall";
  const zh = lang === "zh";

  const base = tall ? (H * 0.6) / OUT_H : (H * 0.86) / OUT_H;
  const enter = ramp(t, P.start - 0.1, P.start + 0.55, E.expoOut);
  const push = ramp(t, 15.72, 17.25, E.inOut);
  const exit = ramp(t, P.end - 0.48, P.end + 0.02, E.in);
  const pre = ramp(t, P.island - 0.1, P.page + 0.3, E.soft);
  const scale = base * mix(mix(1, 1.08, pre), tall ? 1.32 : 1.4, push);

  // Push in so the live picture ends up in the middle of the frame.
  const liveOff = (PH / 2 - liveCenterY(zh)) * scale;
  const cx = (tall ? 0.5 : 0.685) * W;
  const cy = (tall ? 0.6 : 0.5) * H + push * liveOff * (tall ? 0.85 : 1) + (1 - enter) * H * 0.95 + exit * H * 1.15;

  const ry = mix(-26, -15, enter) * (1 - push) + mix(0, -4, push) * (1 - exit) + exit * -10;
  const rx = mix(16, 7, enter) * (1 - push) + push * 1.5;
  const rz = mix(9, -3.5, enter) * (1 - push) + exit * 7;

  // A buzz when the alarm arrives.
  const bz = t > P.island && t < P.island + 0.38 ? Math.sin((t - P.island) * Math.PI * 2 * 26) * 3.2 * (1 - (t - P.island) / 0.38) : 0;

  const wake = ramp(t, P.island, P.island + 0.16);
  const card = springAt(t, P.island + 0.02, fps, { damping: 13, stiffness: 170 });
  const tapAge = t - P.tapOpen;
  const press = clamp(1 - Math.abs(tapAge - 0.04) / 0.12);
  const open = ramp(t, P.page, P.page + 0.46, E.expoOut);

  // The page grows out of the card.
  const inset = {
    top: CARD.y * (1 - open),
    left: CARD.x * (1 - open),
    right: (PW - CARD.x - CARD.w) * (1 - open),
    bottom: (PH - CARD.y - CARD.h) * (1 - open),
    r: 26 + (R - 26) * open,
  };

  return (
    <div style={{ position: "absolute", inset: 0, perspective: 2600, overflow: "hidden" }}>
      <div
        style={{
          position: "absolute",
          left: cx - OUT_W / 2 + bz,
          top: cy - OUT_H / 2,
          width: OUT_W,
          height: OUT_H,
          transform: `rotateY(${ry}deg) rotateX(${rx}deg) rotateZ(${rz}deg) scale(${scale})`,
          transformOrigin: "50% 50%",
        }}
      >
        <PhoneBody glow={wake}>
          <LockScreen t={t} press={press} card={card} />
          {t >= P.page && (
            <div
              style={{
                position: "absolute",
                inset: 0,
                clipPath: `inset(${inset.top}px ${inset.right}px ${inset.bottom}px ${inset.left}px round ${inset.r}px)`,
              }}
            >
              <div
                style={{
                  position: "absolute",
                  inset: 0,
                  opacity: clamp(open * 2.2),
                  transform: `scale(${0.94 + 0.06 * open})`,
                  transformOrigin: `50% ${CARD.y + CARD.h / 2}px`,
                }}
              >
                <AlarmPage t={t} />
              </div>
            </div>
          )}
          {/* the screen wakes when the alarm arrives */}
          <div style={{ position: "absolute", inset: 0, background: "#000", opacity: 1 - wake }} />
          {tapAge > -0.15 && tapAge < 0.35 && (
            <div
              style={{
                position: "absolute",
                left: CARD.x + CARD.w * 0.75 - 22,
                top: CARD.y + CARD.h - 33 - 22,
                width: 44,
                height: 44,
                borderRadius: 22,
                background: "rgba(255,255,255,0.4)",
                opacity: map(tapAge, [-0.15, 0, 0.12, 0.35], [0, 0.9, 0.9, 0]),
                transform: `scale(${map(tapAge, [-0.15, 0.04, 0.35], [1.4, 0.8, 1.2])})`,
              }}
            />
          )}
        </PhoneBody>
      </div>
    </div>
  );
};
