import { Easing, interpolate, spring } from "remotion";

export const clamp = (v: number, a = 0, b = 1) => Math.min(b, Math.max(a, v));

/** 0 → 1 between two times (seconds), eased. */
export const ramp = (t: number, from: number, to: number, ease: (n: number) => number = Easing.bezier(0.22, 0.9, 0.3, 1)) =>
  interpolate(t, [from, to], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease });

export const lin = (t: number, from: number, to: number) => ramp(t, from, to, (n) => n);

/** Map with clamping over several stops. */
export const map = (t: number, input: number[], output: number[], ease?: (n: number) => number) =>
  interpolate(t, input, output, { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease });

/** A spring that starts at `start` seconds; 0 before. */
export const springAt = (t: number, start: number, fps: number, config: { damping?: number; stiffness?: number; mass?: number } = {}) => {
  if (t < start) return 0;
  return spring({ frame: (t - start) * fps, fps, config: { damping: 14, stiffness: 160, mass: 1, ...config } });
};

export const E = {
  out: Easing.bezier(0.22, 0.9, 0.3, 1),
  inOut: Easing.bezier(0.65, 0, 0.35, 1),
  in: Easing.bezier(0.55, 0, 0.9, 0.35),
  expoOut: Easing.bezier(0.16, 1, 0.3, 1),
  expoInOut: Easing.bezier(0.87, 0, 0.13, 1),
  soft: Easing.bezier(0.4, 0, 0.2, 1),
};

export const mix = (a: number, b: number, k: number) => a + (b - a) * k;

/** Pseudo-random in [0,1) from a seed, stable across frames. */
export const rand = (seed: number) => {
  const x = Math.sin(seed * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
};
