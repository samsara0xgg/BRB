// Render the four cuts into out/, bundling once.
// node scripts/render-all.mjs [CompositionId...]
import { bundle } from "@remotion/bundler";
import { renderMedia, selectComposition } from "@remotion/renderer";
import path from "node:path";

const ids = process.argv.slice(2).length ? process.argv.slice(2) : ["BRB-EN-16x9", "BRB-EN-9x16", "BRB-ZH-16x9", "BRB-ZH-9x16"];
const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts"), webpackOverride: (c) => c, rspack: true });
const browserExecutable = process.env.REMOTION_CHROME || null;
const chromiumOptions = { gl: "angle" };

for (const id of ids) {
  const composition = await selectComposition({ serveUrl, id, browserExecutable, chromiumOptions });
  const outputLocation = path.join("out", `${id}.mp4`);
  const started = Date.now();
  let last = -1;
  await renderMedia({
    serveUrl,
    composition,
    codec: "h264",
    crf: 18,
    x264Preset: "slow",
    colorSpace: "bt709",
    audioCodec: "aac",
    audioBitrate: "320k",
    jpegQuality: 95,
    outputLocation,
    browserExecutable,
    chromiumOptions,
    onProgress: ({ progress }) => {
      const pct = Math.floor(progress * 10);
      if (pct !== last) {
        last = pct;
        console.log(`${id} ${pct * 10}%`);
      }
    },
  });
  console.log(`wrote ${outputLocation} in ${Math.round((Date.now() - started) / 1000)} s`);
}
