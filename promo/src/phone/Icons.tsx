import React from "react";

// Small stand-ins for the SF Symbols the phone app uses, drawn in a 24 × 24 box.
type P = { size?: number; color?: string; style?: React.CSSProperties };

const Box: React.FC<P & { children: React.ReactNode }> = ({ size = 16, style, children }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" style={{ overflow: "visible", flex: "none", ...style }}>
    {children}
  </svg>
);

export const SpeakerSlash: React.FC<P> = ({ color = "#fff", ...p }) => (
  <Box {...p}>
    <path d="M3 9.2 H7 L12.2 4.6 V19.4 L7 14.8 H3 Z" fill={color} />
    <path d="M15.6 9 L21.2 15 M21.2 9 L15.6 15" stroke={color} strokeWidth="2.3" strokeLinecap="round" />
  </Box>
);

export const SpeakerWave: React.FC<P> = ({ color = "#fff", ...p }) => (
  <Box {...p}>
    <path d="M2.5 9.2 H6.5 L11.6 4.6 V19.4 L6.5 14.8 H2.5 Z" fill={color} />
    <path d="M14.6 9.1 A4 4 0 0 1 14.6 14.9" stroke={color} strokeWidth="2" fill="none" strokeLinecap="round" />
    <path d="M17.2 6.6 A7.6 7.6 0 0 1 17.2 17.4" stroke={color} strokeWidth="2" fill="none" strokeLinecap="round" />
    <path d="M19.8 4.1 A11.2 11.2 0 0 1 19.8 19.9" stroke={color} strokeWidth="2" fill="none" strokeLinecap="round" />
  </Box>
);

export const OpenIcon: React.FC<P> = ({ color = "#fff", ...p }) => (
  <Box {...p}>
    <path
      d="M10 4.5 H6.5 A2.5 2.5 0 0 0 4 7 V17.5 A2.5 2.5 0 0 0 6.5 20 H17 A2.5 2.5 0 0 0 19.5 17.5 V14"
      stroke={color}
      strokeWidth="2"
      fill="none"
      strokeLinecap="round"
    />
    <path d="M13.5 4 H20 V10.5 M20 4 L11.5 12.5" stroke={color} strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round" />
  </Box>
);

export const ChevronDown: React.FC<P> = ({ color = "#fff", ...p }) => (
  <Box {...p}>
    <path d="M5.5 9 L12 15.5 L18.5 9" stroke={color} strokeWidth="2.8" fill="none" strokeLinecap="round" strokeLinejoin="round" />
  </Box>
);

export const SaveDown: React.FC<P> = ({ color = "#fff", ...p }) => (
  <Box {...p}>
    <path
      d="M8 9 H6 A2 2 0 0 0 4 11 V19 A2 2 0 0 0 6 21 H18 A2 2 0 0 0 20 19 V11 A2 2 0 0 0 18 9 H16"
      stroke={color}
      strokeWidth="1.8"
      fill="none"
      strokeLinecap="round"
    />
    <path d="M12 2.5 V14.5 M8 10.8 L12 14.8 L16 10.8" stroke={color} strokeWidth="1.8" fill="none" strokeLinecap="round" strokeLinejoin="round" />
  </Box>
);

export const DocText: React.FC<P> = ({ color = "#fff", ...p }) => (
  <Box {...p}>
    <path
      d="M6.5 2.8 H13.5 L19 8.3 V19.2 A2 2 0 0 1 17 21.2 H6.5 A2 2 0 0 1 4.5 19.2 V4.8 A2 2 0 0 1 6.5 2.8 Z"
      stroke={color}
      strokeWidth="1.8"
      fill="none"
      strokeLinejoin="round"
    />
    <path d="M8.5 12.5 H15 M8.5 16 H15" stroke={color} strokeWidth="1.8" strokeLinecap="round" />
  </Box>
);

export const Expand: React.FC<P> = ({ color = "#fff", ...p }) => (
  <Box {...p}>
    <path
      d="M4 10 V4 H10 M4 4 L10.5 10.5 M20 14 V20 H14 M20 20 L13.5 13.5"
      stroke={color}
      strokeWidth="2.2"
      fill="none"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </Box>
);

export const Padlock: React.FC<P> = ({ color = "#fff", ...p }) => (
  <Box {...p}>
    <path d="M7.5 10.5 V7.5 A4.5 4.5 0 0 1 16.5 7.5 V10.5" stroke={color} strokeWidth="2.2" fill="none" />
    <rect x="5" y="10.2" width="14" height="11" rx="2.6" fill={color} />
  </Box>
);

export const Flashlight: React.FC<P> = ({ color = "#fff", ...p }) => (
  <Box {...p}>
    <path d="M7.5 2.5 H16.5 V6.5 L14.5 10 V21.5 H9.5 V10 L7.5 6.5 Z" fill={color} />
    <rect x="11.2" y="12" width="1.6" height="3.4" rx="0.8" fill="#000" opacity="0.45" />
  </Box>
);

export const CameraIcon: React.FC<P> = ({ color = "#fff", ...p }) => (
  <Box {...p}>
    <path d="M3 8.5 A2 2 0 0 1 5 6.5 H7.6 L9.2 4.5 H14.8 L16.4 6.5 H19 A2 2 0 0 1 21 8.5 V18 A2 2 0 0 1 19 20 H5 A2 2 0 0 1 3 18 Z" fill={color} />
    <circle cx="12" cy="13" r="4.1" fill="#000" opacity="0.55" />
    <circle cx="12" cy="13" r="2.7" fill={color} />
  </Box>
);

export const Signal: React.FC<{ color?: string }> = ({ color = "#fff" }) => (
  <svg width="19" height="12" viewBox="0 0 19 12" style={{ flex: "none" }}>
    {[0, 1, 2, 3].map((i) => (
      <rect key={i} x={i * 5} y={9 - i * 3} width="3.2" height={3 + i * 3} rx="1" fill={color} />
    ))}
  </svg>
);

export const Wifi: React.FC<{ color?: string }> = ({ color = "#fff" }) => (
  <svg width="17" height="12" viewBox="0 0 17 12" style={{ flex: "none" }}>
    <path d="M8.5 11.6 L5.9 8.9 A3.7 3.7 0 0 1 11.1 8.9 Z" fill={color} />
    <path d="M3.5 6.6 A7 7 0 0 1 13.5 6.6" stroke={color} strokeWidth="1.8" fill="none" strokeLinecap="round" />
    <path d="M1 4 A10.6 10.6 0 0 1 16 4" stroke={color} strokeWidth="1.8" fill="none" strokeLinecap="round" />
  </svg>
);

export const Battery: React.FC<{ color?: string; level?: number }> = ({ color = "#fff", level = 0.8 }) => (
  <svg width="27" height="13" viewBox="0 0 27 13" style={{ flex: "none" }}>
    <rect x="0.6" y="0.6" width="23" height="11.8" rx="3.6" stroke={color} strokeOpacity="0.4" strokeWidth="1.2" fill="none" />
    <rect x="2.4" y="2.4" width={19.4 * level} height="8.2" rx="2" fill={color} />
    <path d="M25.2 4.4 C26.5 4.8 26.5 8.2 25.2 8.6 Z" fill={color} fillOpacity="0.4" />
  </svg>
);
