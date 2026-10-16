import React from "react";

// Resources/AppIcon.svg, as a component: the midnight tile, the frost and the amber shield.
export const AppIcon: React.FC<{ size: number; sheen?: number; style?: React.CSSProperties }> = ({ size, sheen = -1, style }) => {
  const id = React.useId().replace(/:/g, "");
  return (
    <svg width={size} height={size} viewBox="100 100 824 824" style={{ overflow: "visible", ...style }}>
      <defs>
        <linearGradient id={`bg${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#2a3354" />
          <stop offset="1" stopColor="#0c1122" />
        </linearGradient>
        <radialGradient id={`glow${id}`} cx="0.5" cy="0.44" r="0.5">
          <stop offset="0" stopColor="#f6b544" stopOpacity="0.28" />
          <stop offset="1" stopColor="#f6b544" stopOpacity="0" />
        </radialGradient>
        <linearGradient id={`frost${id}`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#ffffff" stopOpacity="0.16" />
          <stop offset="0.5" stopColor="#ffffff" stopOpacity="0.04" />
          <stop offset="1" stopColor="#ffffff" stopOpacity="0.10" />
        </linearGradient>
        <linearGradient id={`amber${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#ffcf6e" />
          <stop offset="1" stopColor="#ec9f22" />
        </linearGradient>
        <linearGradient id={`rim${id}`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#ffffff" stopOpacity="0.55" />
          <stop offset="0.4" stopColor="#ffffff" stopOpacity="0.08" />
          <stop offset="1" stopColor="#ffffff" stopOpacity="0.3" />
        </linearGradient>
        <linearGradient id={`sheen${id}`} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#ffffff" stopOpacity="0" />
          <stop offset="0.5" stopColor="#ffffff" stopOpacity="0.22" />
          <stop offset="1" stopColor="#ffffff" stopOpacity="0" />
        </linearGradient>
        <clipPath id={`tile${id}`}>
          <rect x="100" y="100" width="824" height="824" rx="186" />
        </clipPath>
      </defs>
      <rect x="100" y="100" width="824" height="824" rx="186" fill={`url(#bg${id})`} />
      <g clipPath={`url(#tile${id})`}>
        <rect x="100" y="100" width="824" height="824" fill={`url(#glow${id})`} />
        <rect x="100" y="100" width="824" height="824" fill={`url(#frost${id})`} />
        <path d="M100 640 C 330 560, 640 720, 924 600 L924 924 L100 924 Z" fill="#ffffff" opacity="0.035" />
        {sheen > -1 && sheen < 2 && (
          <rect x={100 + (sheen - 0.5) * 1300} y="0" width="360" height="1100" fill={`url(#sheen${id})`} transform={`rotate(20 512 512)`} />
        )}
      </g>
      <rect x="101.5" y="101.5" width="821" height="821" rx="185" fill="none" stroke={`url(#rim${id})`} strokeWidth="3" />
      <g transform="translate(512 518) scale(24) translate(-12 -12.15)">
        <path
          d="M12 2.8 L19.4 5.6 L19.4 11.4 C19.4 16.2 16.3 20 12 21.5 C7.7 20 4.6 16.2 4.6 11.4 L4.6 5.6 Z"
          fill={`url(#amber${id})`}
          style={{ filter: "drop-shadow(0 0.4px 0.7px rgba(107,60,0,0.55))" }}
        />
        <path d="M12 3.4 L18.8 6 L18.8 11.4 C18.8 13.4 18.2 15.2 17.1 16.7 C14 11 9 8.5 5.2 8.6 L5.2 6 Z" fill="#ffffff" opacity="0.18" />
        <circle cx="12" cy="11.4" r="2.4" fill="#2b1a00" />
      </g>
    </svg>
  );
};
