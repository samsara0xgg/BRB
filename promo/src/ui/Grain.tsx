import React from "react";
import { Img, staticFile } from "remotion";
import { rand } from "../lib/time";

// The grain texture is 1920 × 1080. It is drawn at one fixed scale and tiled, so the grain is the same
// size in the 16:9 and the 9:16 cut.
const TILE_W = 1920 * 1.28;
const TILE_H = 1080 * 1.28;

/** A light film grain that changes on every other frame, and a soft vignette. The grain is kept faint:
 * it hides banding in the dark gradients, and heavier grain turns to mush when platforms re-encode. */
export const Grain: React.FC<{ t: number; W: number; H: number; amount?: number }> = ({ t, W, H, amount = 0.07 }) => {
  const f = Math.floor(t * 15 + 1e-6);
  const dx = Math.round(rand(f * 1.7) * 400);
  const dy = Math.round(rand(f * 3.1 + 2) * 300);
  const nx = Math.ceil((W + 400) / TILE_W);
  const ny = Math.ceil((H + 300) / TILE_H);
  return (
    <>
      <div style={{ position: "absolute", inset: 0, overflow: "hidden", pointerEvents: "none", opacity: amount }}>
        {Array.from({ length: nx * ny }, (_, i) => (
          <Img
            key={i}
            src={staticFile("img/film-grain.png")}
            style={{ position: "absolute", left: (i % nx) * TILE_W - dx, top: Math.floor(i / nx) * TILE_H - dy, width: TILE_W, height: TILE_H }}
          />
        ))}
      </div>
      <div
        style={{
          position: "absolute",
          inset: 0,
          pointerEvents: "none",
          background: "radial-gradient(120% 100% at 50% 50%, rgba(0,0,0,0) 55%, rgba(0,0,0,0.5) 100%)",
        }}
      />
    </>
  );
};
