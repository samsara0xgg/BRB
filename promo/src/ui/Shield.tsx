import React from "react";
import { C } from "../lib/theme";

// The shield of design A, in the 24 × 24 space of the app's SVG (StatusIcon.swift).
export const SHIELD = "M12 2.8 L19.4 5.6 L19.4 11.4 C19.4 16.2 16.3 20 12 21.5 C7.7 20 4.6 16.2 4.6 11.4 L4.6 5.6 Z";
const LIGHT = "M12 9 a2.4 2.4 0 1 0 0.001 0 Z"; // circle r 2.4 at (12, 11.4)
const TICK = "M8.4 11.8 L10.9 14.3 L15.7 9.3";

export type Look = "outline" | "arming" | "armed" | "alarm" | "clear" | "ink";

export const Shield: React.FC<{
  look: Look;
  size: number;
  /** arming: 0…1 amber rising from the bottom. clear: 0…1 the tick drawing in. */
  level?: number;
  color?: string;
  stroke?: number;
  glow?: number;
  style?: React.CSSProperties;
}> = ({ look, size, level = 1, color = "#fff", stroke = 1.9, glow = 0, style }) => {
  const id = React.useId().replace(/:/g, "");
  const top = 21.5 - 18.7 * Math.min(1, Math.max(0, level));
  const glowFilter =
    glow > 0 ? `drop-shadow(0 0 ${size * 0.12 * glow}px ${look === "alarm" ? C.red : look === "clear" ? C.green : C.amber})` : undefined;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" style={{ overflow: "visible", filter: glowFilter, ...style }}>
      <defs>
        <linearGradient id={`a${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={C.amberHi} />
          <stop offset="1" stopColor={C.amberLow} />
        </linearGradient>
        <clipPath id={`c${id}`}>
          <rect x="0" y={top} width="24" height={24 - top} />
        </clipPath>
      </defs>
      {look === "outline" && <path d={SHIELD} fill="none" stroke={color} strokeWidth={stroke} strokeLinejoin="round" />}
      {look === "arming" && (
        <>
          <path d={SHIELD} fill="none" stroke={C.amber} strokeWidth={stroke} strokeLinejoin="round" />
          <path d={SHIELD} fill={`url(#a${id})`} clipPath={`url(#c${id})`} />
        </>
      )}
      {look === "armed" && <path d={`${SHIELD} ${LIGHT}`} fill={`url(#a${id})`} fillRule="evenodd" />}
      {look === "ink" && (
        <>
          <path d={SHIELD} fill={C.ink} />
          <circle cx="12" cy="11.4" r="2.4" fill={C.amber} />
        </>
      )}
      {look === "alarm" && (
        <>
          <path d={SHIELD} fill={C.red} />
          <rect x="11" y="6.6" width="2" height="7.4" rx="1" fill="#fff" />
          <circle cx="12" cy="16.9" r="1.25" fill="#fff" />
        </>
      )}
      {look === "clear" && (
        <>
          <path d={SHIELD} fill={C.green} />
          <path
            d={TICK}
            fill="none"
            stroke="#fff"
            strokeWidth={2.2}
            strokeLinecap="round"
            strokeLinejoin="round"
            pathLength={1}
            strokeDasharray={1}
            strokeDashoffset={1 - Math.min(1, Math.max(0, level))}
          />
        </>
      )}
    </svg>
  );
};
