import React from "react";

/** A person seen against the light: head, shoulders, arms. Always drawn out of focus. */
export const Silhouette: React.FC<{
  x: number;
  y: number;
  h: number;
  blur: number;
  color?: string;
  opacity?: number;
  step?: number; // walking phase, radians
  flip?: boolean;
  rim?: string; // a little light along one edge
}> = ({ x, y, h, blur, color = "#020306", opacity = 1, step = 0, flip = false, rim }) => {
  const w = h * 0.42;
  const bob = Math.abs(Math.sin(step)) * h * 0.012;
  const swing = Math.sin(step) * 5;
  return (
    <svg
      width={w}
      height={h}
      viewBox="0 0 200 480"
      style={{
        position: "absolute",
        left: x - w / 2,
        top: y - bob,
        opacity,
        filter: `blur(${blur}px)`,
        transform: flip ? "scaleX(-1)" : undefined,
        overflow: "visible",
      }}
    >
      {rim && <ellipse cx="108" cy="62" rx="40" ry="48" fill={rim} />}
      <ellipse cx="100" cy="60" rx="38" ry="46" fill={color} />
      <path d="M86 98 L114 98 L118 128 L82 128 Z" fill={color} />
      <g transform={`rotate(${swing} 46 150)`}>
        <path d="M46 140 C 26 150, 22 200, 24 270 C 25 300, 30 330, 36 352 L 56 350 C 54 300, 56 240, 64 190 Z" fill={color} />
      </g>
      <g transform={`rotate(${-swing} 154 150)`}>
        <path d="M154 140 C 174 150, 178 200, 176 270 C 175 300, 170 330, 164 352 L 144 350 C 146 300, 144 240, 136 190 Z" fill={color} />
      </g>
      <path d="M38 150 C 60 122, 140 122, 162 150 L 150 300 L 156 480 L 44 480 L 50 300 Z" fill={color} />
    </svg>
  );
};

/** Red rings spreading from the laptop while the siren sounds. */
export const SirenRings: React.FC<{ x: number; y: number; t: number; from: number; to: number; scale: number }> = ({ x, y, t, from, to, scale }) => {
  if (t < from || t > to + 1.2) return null;
  const period = 0.42;
  const rings: React.ReactNode[] = [];
  for (let i = 0; i < 6; i++) {
    const born = from + i * period + Math.floor(Math.max(0, t - from - i * period) / (period * 6)) * period * 6;
    const age = t - born;
    if (age < 0 || age > 1.3 || born > to) continue;
    const k = age / 1.3;
    const r = (180 + 900 * (1 - Math.pow(1 - k, 2))) * scale;
    const a = (1 - k) * 0.55;
    rings.push(
      <div
        key={i}
        style={{
          position: "absolute",
          left: x - r,
          top: y - r * 0.62,
          width: r * 2,
          height: r * 1.24,
          borderRadius: "50%",
          border: `${(10 - 7 * k) * scale}px solid rgba(255,77,85,${a})`,
          boxShadow: `0 0 ${40 * scale}px rgba(255,60,70,${a * 0.6})`,
        }}
      />,
    );
  }
  return <>{rings}</>;
};
