import { continueRender, delayRender, staticFile } from "remotion";
import noto from "./noto-sc.json";

// Every face the film uses, loaded up front so no frame is drawn with a fallback font.
// Inter / Inter Display stand in for SF Pro; Noto Sans SC (思源黑体) for PingFang SC.
const inter: [string, string, number][] = [
  ["Inter", "Inter-Regular.otf", 400],
  ["Inter", "Inter-Medium.otf", 500],
  ["Inter", "Inter-SemiBold.otf", 600],
  ["Inter", "Inter-Bold.otf", 700],
  ["Inter Display", "InterDisplay-Medium.otf", 500],
  ["Inter Display", "InterDisplay-SemiBold.otf", 600],
  ["Inter Display", "InterDisplay-Bold.otf", 700],
  ["Inter Display", "InterDisplay-ExtraBold.otf", 800],
  ["Inter Display", "InterDisplay-Black.otf", 900],
];

let started = false;

export const loadFonts = () => {
  if (started || typeof document === "undefined") return;
  started = true;
  const handle = delayRender("Loading fonts", { timeoutInMilliseconds: 60000 });
  const faces: FontFace[] = [
    ...inter.map(([family, file, weight]) => new FontFace(family, `url(${staticFile(`fonts/${file}`)})`, { weight: String(weight) })),
    ...(noto as { file: string; range: string }[]).map(
      ({ file, range }) =>
        new FontFace("Noto Sans SC", `url(${staticFile(`fonts/noto-sc/${file}`)}) format("woff2")`, {
          weight: "100 900",
          unicodeRange: range,
        }),
    ),
  ];
  Promise.all(
    faces.map((face) =>
      face.load().then((f) => {
        document.fonts.add(f);
      }),
    ),
  )
    .then(() => continueRender(handle))
    .catch((err) => {
      console.error(err);
      continueRender(handle);
    });
};
