import React from "react";
import { useCtx } from "../lib/ctx";
import { C, FONT } from "../lib/theme";
import { E, clamp, ramp } from "../lib/time";

type Unit = { text: string; accent: boolean; space: boolean };

/** Split a line into words (English) or characters (Chinese); *stars* mark amber words. */
const units = (line: string, zh: boolean): Unit[] => {
  const out: Unit[] = [];
  const parts = line.split("*");
  parts.forEach((part, i) => {
    const accent = i % 2 === 1;
    if (!part) return;
    if (zh) {
      // Keep runs of Latin letters/digits together ("iPhone", "BRB").
      const re = /[A-Za-z0-9’']+|\s+|./gu;
      let m: RegExpExecArray | null;
      while ((m = re.exec(part))) {
        if (/^\s+$/.test(m[0])) {
          if (out.length) out[out.length - 1].space = true;
          continue;
        }
        out.push({ text: m[0], accent, space: false });
      }
    } else {
      const words = part.split(/(\s+)/);
      words.forEach((w) => {
        if (!w) return;
        if (/^\s+$/.test(w)) {
          if (out.length) out[out.length - 1].space = true;
          return;
        }
        out.push({ text: w, accent, space: false });
      });
    }
  });
  return out;
};

export type CaptionPlace = "left" | "bottom" | "top" | "center";

/**
 * A headline that builds word by word (character by character in Chinese) with a little blur, and an
 * optional line under it. Times are the film's seconds.
 */
export const Caption: React.FC<{
  lines: string[];
  sub?: string;
  t: number;
  inAt: number;
  outAt: number;
  place?: CaptionPlace;
  size?: number;
  maxWidth?: number;
  x?: number;
  y?: number;
  /** A soft dark band behind the words, for captions over a bright picture. */
  scrim?: number;
}> = ({ lines, sub, t, inAt, outAt, place = "left", size, maxWidth, x, y, scrim = 0 }) => {
  const { lang, W, H, format } = useCtx();
  if (t < inAt - 0.05 || t > outAt + 0.4) return null;
  const zh = lang === "zh";
  const tall = format === "tall";
  const fs = size ?? (tall ? (zh ? 96 : 100) : zh ? 86 : 92);
  // "|" marks where a long line breaks in the tall frame; the wide frame keeps it on one line.
  const shown = lines.flatMap((l) => (tall ? l.split("|").map((x) => x.trim()) : [l.replace("|", "")]));
  const step = zh ? 0.032 : 0.055;
  const out = ramp(t, outAt, outAt + 0.32, E.in);
  let n = 0;
  const center = place === "center" || place === "top";
  const block: React.CSSProperties = {
    position: "absolute",
    color: "#fff",
    textAlign: center ? "center" : "left",
    opacity: 1 - out,
    filter: out > 0 ? `blur(${out * 14}px)` : undefined,
    transform: `translateY(${-out * 18}px)`,
  };
  if (place === "left")
    Object.assign(block, {
      left: x ?? W * 0.068,
      top: y ?? H * 0.5,
      transform: `translateY(-50%) translateY(${-out * 18}px)`,
      width: maxWidth ?? W * 0.4,
    });
  if (place === "bottom")
    Object.assign(block, {
      left: x ?? W * 0.068,
      bottom: y ?? H * 0.1,
      width: maxWidth ?? W * 0.6,
    });
  if (place === "top")
    Object.assign(block, {
      left: 0,
      right: 0,
      top: y ?? H * 0.1,
      padding: "0 60px",
    });
  if (place === "center")
    Object.assign(block, {
      left: 0,
      right: 0,
      top: y ?? H * 0.5,
      transform: `translateY(-50%) translateY(${-out * 18}px)`,
      padding: "0 60px",
    });

  const scrimO = scrim * ramp(t, inAt - 0.1, inAt + 0.3) * (1 - out);
  const scrimBg =
    place === "bottom"
      ? `linear-gradient(0deg, rgba(3,4,10,${0.78 * scrimO}) 0%, rgba(3,4,10,${0.5 * scrimO}) 40%, rgba(3,4,10,0) 100%)`
      : place === "top"
        ? `linear-gradient(180deg, rgba(3,4,10,${0.78 * scrimO}) 0%, rgba(3,4,10,${0.5 * scrimO}) 45%, rgba(3,4,10,0) 100%)`
        : `linear-gradient(90deg, rgba(3,4,10,${0.72 * scrimO}) 0%, rgba(3,4,10,${0.4 * scrimO}) 45%, rgba(3,4,10,0) 100%)`;
  const scrimBox: React.CSSProperties =
    place === "bottom"
      ? { left: 0, right: 0, bottom: 0, height: H * 0.5 }
      : place === "top"
        ? { left: 0, right: 0, top: 0, height: H * 0.42 }
        : { left: 0, top: 0, bottom: 0, width: W * 0.6 };

  return (
    <>
      {scrimO > 0 && (
        <div
          style={{
            position: "absolute",
            pointerEvents: "none",
            background: scrimBg,
            ...scrimBox,
          }}
        />
      )}
      <div style={block}>
        {shown.map((line, li) => (
          <div
            key={li}
            style={{
              fontFamily: zh ? FONT.zh : FONT.display,
              fontWeight: zh ? 800 : 800,
              fontSize: fs,
              lineHeight: zh ? 1.18 : 1.02,
              letterSpacing: zh ? "0.02em" : "-0.035em",
              whiteSpace: "nowrap",
            }}
          >
            {units(line, zh).map((u, ui) => {
              const k = clamp((t - inAt - n++ * step) / 0.5);
              const e = E.expoOut(k);
              return (
                <span
                  key={ui}
                  style={{
                    display: "inline-block",
                    opacity: e,
                    transform: `translateY(${(1 - e) * 0.32 * fs}px)`,
                    filter: k < 1 ? `blur(${(1 - e) * 12}px)` : undefined,
                    marginRight: u.space ? (zh ? "0.25em" : "0.24em") : 0,
                    ...(u.accent
                      ? {
                          backgroundImage: `linear-gradient(180deg, ${C.amberHi} 10%, ${C.amber} 60%, ${C.amberLow} 100%)`,
                          WebkitBackgroundClip: "text",
                          backgroundClip: "text",
                          color: "transparent",
                          paddingBottom: "0.08em",
                        }
                      : {}),
                  }}
                >
                  {u.text}
                </span>
              );
            })}
          </div>
        ))}
        {sub && (
          <div
            style={{
              marginTop: fs * 0.3,
              fontFamily: zh ? FONT.zh : FONT.text,
              fontWeight: 500,
              fontSize: fs * (tall ? 0.38 : 0.37),
              lineHeight: 1.35,
              letterSpacing: zh ? "0.04em" : "-0.005em",
              color: "rgba(255,255,255,0.66)",
              textWrap: "balance",
              // Chinese breaks at punctuation rather than inside a word.
              wordBreak: zh ? "keep-all" : undefined,
              opacity: E.out(clamp((t - inAt - n * step - 0.05) / 0.45)),
              transform: `translateY(${(1 - E.out(clamp((t - inAt - n * step - 0.05) / 0.45))) * 10}px)`,
            }}
          >
            {sub}
          </div>
        )}
      </div>
    </>
  );
};
