// Render chosen frames of a composition to PNGs, bundling once.
// node scripts/stills.mjs <CompositionId> <outDir> <time-in-seconds>... [--props '{"lang":"zh"}'] [--scale 0.5]
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import path from "node:path";
import fs from "node:fs";

const args = process.argv.slice(2);
let props = {};
let scale = 1;
const rest = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--props") props = JSON.parse(args[++i]);
  else if (args[i] === "--scale") scale = Number(args[++i]);
  else rest.push(args[i]);
}
const [id, outDir, ...times] = rest;
fs.mkdirSync(outDir, { recursive: true });
const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts"), webpackOverride: (c) => c, rspack: true });
const browserExecutable = process.env.REMOTION_CHROME || null;
const composition = await selectComposition({ serveUrl, id, inputProps: props, browserExecutable, chromiumOptions: { gl: "angle" } });
for (const tt of times) {
  const frame = Math.min(composition.durationInFrames - 1, Math.round(Number(tt) * composition.fps));
  const output = path.join(outDir, `${id}-${String(tt).replace(".", "_")}.png`);
  await renderStill({
    serveUrl,
    composition,
    frame,
    output,
    inputProps: props,
    browserExecutable,
    scale,
    chromiumOptions: { gl: "angle" },
    overwrite: true,
  });
  console.log("wrote", output);
}
