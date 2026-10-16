import React from "react";
import { rand } from "../lib/time";

// What the Mac's camera sees while someone carries it off: the person holding it, lit red by the
// screen, and the café behind with every other face pixelated (BRB keeps only the closest person clear).
const VW = 400;
const VH = 250;

const BOKEH = Array.from({ length: 12 }, (_, i) => ({
  x: rand(i * 2.3 + 1) * VW,
  y: rand(i * 4.1 + 2) * VH * 0.55,
  r: 6 + rand(i * 6.7) * 16,
  a: 0.18 + rand(i * 3.3) * 0.3,
  c: ["255,196,120", "255,170,90", "255,220,170"][i % 3],
}));

// The face colors of a pixelated passer-by.
const MOSAIC = ["#5a4034", "#6e4e3e", "#3e2c25", "#7d5a47", "#4b362c", "#2e221d", "#86634e"];

const Mosaic: React.FC<{ x: number; y: number; cols: number; rows: number; cell: number; seed: number }> = ({ x, y, cols, rows, cell, seed }) => (
  <g>
    {Array.from({ length: cols * rows }, (_, i) => {
      const c = i % cols;
      const r = Math.floor(i / cols);
      // round off the corners so the block reads as a head
      const corner = (c === 0 || c === cols - 1) && (r === 0 || r === rows - 1);
      if (corner) return null;
      return (
        <rect
          key={i}
          x={x + c * cell}
          y={y + r * cell}
          width={cell + 0.3}
          height={cell + 0.3}
          fill={MOSAIC[Math.floor(rand(seed + i * 1.37) * MOSAIC.length)]}
        />
      );
    })}
  </g>
);

/**
 * The live picture, `w` × `h` on screen. `t` moves it: the laptop is being carried, so the picture
 * sways. `still` freezes it (for a photo).
 */
export const LiveView: React.FC<{ t: number; w: number; h: number; still?: boolean; style?: React.CSSProperties }> = ({ t, w, h, still, style }) => {
  const id = React.useId().replace(/:/g, "");
  const tt = still ? 14.6 : t;
  const sway = Math.sin(tt * 2 * Math.PI * 0.9);
  const shake = Math.sin(tt * 2 * Math.PI * 7.5);
  const rot = sway * 1.6 + shake * 0.5;
  const dx = sway * 5 + shake * 1.2;
  const dy = Math.cos(tt * 2 * Math.PI * 0.7) * 3 + shake * 1.5;
  const breathe = 1 + 0.015 * Math.sin(tt * 1.3);
  const seed = Math.floor(tt * 24) % 50;
  return (
    <svg width={w} height={h} viewBox={`0 0 ${VW} ${VH}`} preserveAspectRatio="xMidYMid slice" style={{ display: "block", ...style }}>
      <defs>
        <linearGradient id={`room${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#24170f" />
          <stop offset="0.55" stopColor="#150d0a" />
          <stop offset="1" stopColor="#0a0606" />
        </linearGradient>
        <radialGradient id={`win${id}`} cx="0.14" cy="0.22" r="0.5">
          <stop offset="0" stopColor="#ffc888" stopOpacity="0.42" />
          <stop offset="1" stopColor="#ffc888" stopOpacity="0" />
        </radialGradient>
        <radialGradient id={`face${id}`} cx="0.5" cy="0.92" r="0.85">
          <stop offset="0" stopColor="#ef7468" />
          <stop offset="0.32" stopColor="#c2463f" />
          <stop offset="0.62" stopColor="#5e1a1d" />
          <stop offset="1" stopColor="#170709" />
        </radialGradient>
        <linearGradient id={`hood${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#14151b" />
          <stop offset="0.7" stopColor="#1d1b22" />
          <stop offset="1" stopColor="#3c1418" />
        </linearGradient>
        <linearGradient id={`body${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#1e1d24" />
          <stop offset="0.55" stopColor="#36151a" />
          <stop offset="1" stopColor="#6a1a20" />
        </linearGradient>
        <linearGradient id={`red${id}`} x1="0" y1="1" x2="0" y2="0">
          <stop offset="0" stopColor="#ff2d3a" stopOpacity="0.38" />
          <stop offset="0.6" stopColor="#ff2d3a" stopOpacity="0.08" />
          <stop offset="1" stopColor="#ff2d3a" stopOpacity="0" />
        </linearGradient>
        <radialGradient id={`vig${id}`} cx="0.5" cy="0.5" r="0.75">
          <stop offset="0.55" stopColor="#000" stopOpacity="0" />
          <stop offset="1" stopColor="#000" stopOpacity="0.6" />
        </radialGradient>
        <filter id={`soft${id}`} x="-20%" y="-20%" width="140%" height="140%">
          <feGaussianBlur stdDeviation="2.2" />
        </filter>
        <filter id={`bok${id}`} x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="3.5" />
        </filter>
        <filter id={`feat${id}`} x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="1.6" />
        </filter>
        <filter id={`grain${id}`} x="0" y="0" width="100%" height="100%">
          <feTurbulence type="fractalNoise" baseFrequency="0.95" numOctaves="2" seed={seed} />
          <feColorMatrix type="saturate" values="0" />
        </filter>
      </defs>
      <g transform={`translate(${dx} ${dy}) rotate(${rot} 200 125) scale(${1.08 * breathe}) translate(${-VW * 0.04} ${-VH * 0.04})`}>
        {/* the café */}
        <rect x={-40} y={-40} width={VW + 80} height={VH + 80} fill={`url(#room${id})`} />
        <rect x={-40} y={-40} width={VW + 80} height={VH + 80} fill={`url(#win${id})`} />
        <rect x={-40} y={128} width={VW + 80} height={10} fill="#2b1e16" opacity="0.8" filter={`url(#soft${id})`} />
        <g filter={`url(#bok${id})`}>
          {BOKEH.map((b, i) => (
            <circle key={i} cx={b.x} cy={b.y} r={b.r} fill={`rgba(${b.c},${b.a})`} />
          ))}
          <ellipse cx="118" cy="8" rx="16" ry="7" fill="rgba(255,214,150,0.75)" />
          <ellipse cx="296" cy="14" rx="13" ry="6" fill="rgba(255,214,150,0.65)" />
        </g>

        {/* two people further back, faces pixelated */}
        <g filter={`url(#soft${id})`}>
          <path d="M28 250 L30 136 C30 112 44 102 62 102 C80 102 94 112 94 136 L98 250 Z" fill="#2a2930" />
          <ellipse cx="62" cy="80" rx="15" ry="18" fill="#2a2124" />
          <path d="M316 250 L318 140 C318 118 328 108 340 108 C352 108 364 118 364 140 L368 250 Z" fill="#33261f" />
          <ellipse cx="340" cy="88" rx="12" ry="15" fill="#2b201b" />
        </g>
        <Mosaic x={48} y={63} cols={4} rows={5} cell={7} seed={3} />
        <Mosaic x={329} y={73} cols={3} rows={4} cell={7.5} seed={9} />

        {/* the person carrying the Mac, up close and clear */}
        <path d="M70 250 C 76 214, 112 196, 162 188 L 258 188 C 308 196, 344 214, 350 250 Z" fill={`url(#body${id})`} />
        <path
          d="M146 196 C 136 150, 146 92, 172 70 C 196 50, 226 50, 250 70 C 276 92, 286 150, 274 196 C 252 210, 168 210, 146 196 Z"
          fill={`url(#hood${id})`}
        />
        <path d="M150 192 C 146 160, 150 120, 166 96" stroke="rgba(255,70,80,0.35)" strokeWidth="2.5" fill="none" filter={`url(#feat${id})`} />
        <path d="M270 192 C 274 160, 270 120, 254 96" stroke="rgba(255,70,80,0.35)" strokeWidth="2.5" fill="none" filter={`url(#feat${id})`} />
        <ellipse cx="210" cy="134" rx="35" ry="44" fill={`url(#face${id})`} />
        {/* the hood's shadow over the brow, eyes, nose and mouth catching the red */}
        <ellipse cx="210" cy="100" rx="42" ry="24" fill="#0b0709" opacity="0.88" filter={`url(#feat${id})`} />
        <g filter={`url(#feat${id})`}>
          <ellipse cx="195" cy="121" rx="7.5" ry="3.6" fill="#1c0507" opacity="0.75" />
          <ellipse cx="225" cy="121" rx="7.5" ry="3.6" fill="#1c0507" opacity="0.75" />
          <ellipse cx="210" cy="138" rx="4.5" ry="9" fill="rgba(255,150,140,0.28)" />
          <path d="M199 158 Q 210 161 221 158" stroke="#3b0b0f" strokeWidth="2.6" fill="none" opacity="0.7" />
          <ellipse cx="210" cy="170" rx="17" ry="6" fill="rgba(255,130,120,0.32)" />
        </g>
        <path d="M193 190 L 188 238" stroke="#d8cfc6" strokeWidth="2.6" strokeLinecap="round" opacity="0.7" />
        <path d="M227 190 L 232 238" stroke="#d8cfc6" strokeWidth="2.6" strokeLinecap="round" opacity="0.7" />
        <rect x={-40} y={-40} width={VW + 80} height={VH + 80} fill={`url(#red${id})`} />
      </g>
      <rect width={VW} height={VH} filter={`url(#grain${id})`} opacity="0.14" />
      <rect width={VW} height={VH} fill={`url(#vig${id})`} />
    </svg>
  );
};
