# BRB promo film

A 30-second launch film for BRB, made in code with [Remotion](https://www.remotion.dev). Four cuts come
out of one project: English and Chinese, each in 16:9 (YouTube, the website) and 9:16 (TikTok, Douyin,
Xiaohongshu, Reels).

| Composition   | Size        | For                         |
| ------------- | ----------- | --------------------------- |
| `BRB-EN-16x9` | 1920 × 1080 | YouTube, X, the website     |
| `BRB-EN-9x16` | 1080 × 1920 | TikTok, Reels, Shorts       |
| `BRB-ZH-16x9` | 1920 × 1080 | Bilibili, WeChat Channels   |
| `BRB-ZH-9x16` | 1080 × 1920 | Douyin, Xiaohongshu         |

## The story

| Time        | Shot                                                                 | Caption (EN / ZH)                                        |
| ----------- | -------------------------------------------------------------------- | -------------------------------------------------------- |
| 0.0 – 2.5   | "Be Right Back." folds into BRB; the icon; through its watch light   | —                                                        |
| 2.5 – 5.0   | A MacBook on a café table at night                                   | Stepping away? / 要离开一下？                            |
| 5.0 – 8.5   | The menu-bar panel, Start guarding, the screen frosts, 5 → 1         | One click. / 一键开启。                                  |
| 8.5 – 11.0  | People walk past; nothing happens                                    | Walk past? Nothing happens. / 有人路过？什么都不会发生。 |
| 11.0 – 12.6 | A touch on the trackpad; the screen floods red                       | Touch it, and it raises the alarm. / 有人碰它，立刻报警。 |
| 12.6 – 14.0 | Picked up; BRB's real siren                                          | Take it? The siren won't stop. / 想拿走？警笛响个不停。  |
| 14.0 – 18.0 | The owner's iPhone: Live Activity, then the alarm page, live picture | See it live on your iPhone. / 在 iPhone 上实时看到。     |
| 18.0 – 20.0 | Put back down; the siren stops                                       | Put it back. It goes quiet. / 放回原处，警笛就停。       |
| 20.0 – 23.5 | Touch ID; "Welcome back"; the notice flies into the menu bar         | Back? One touch and it's yours. / 回来了？指纹一按…      |
| 23.5 – 27.0 | Six tiles: what it does, all free                                    | All of this is free. / 这些，全部免费。                  |
| 27.0 – 30.0 | Icon, name, "Free for Mac"                                           | —                                                        |

Everything on the Mac and iPhone screens is rebuilt from the app itself: the panel, the frosted veil and
its notices use the strings and colors of `Panel.swift`, `Veil.swift` and `Theme.swift`; the phone
screens follow `ios/` (`AlarmView.swift`, `BRBLiveActivity.swift`); the siren and the soft beeps are
the formulas in `Alarm.swift`.

The put-back-stops-the-siren behavior and the iPhone app are shown as launch features; as of
2026-10-16 they are still being built (see the iOS pull request).

## Working on it

```sh
npm install
npm run dev          # Remotion Studio: scrub, edit, preview
```

- `src/cues.json` is the cue sheet. Picture and sound both read it, so moving a beat moves both.
- `src/lib/copy.ts` holds every word in both languages. `*stars*` paint words amber; `|` marks where a
  long line breaks in the 9:16 cut.
- `src/mac/` is the 3D MacBook (CSS 3D) and everything on its screen, `src/phone/` the iPhone,
  `src/scenes/` the shots, `src/ui/` captions and small parts.

## Rendering

```sh
python3 scripts/soundtrack.py                         # only after changing cues or the score; needs numpy + scipy
npx remotion render BRB-EN-16x9 out/BRB-EN-16x9.mp4   # one cut
node scripts/render-all.mjs                           # all four, into out/
node scripts/stills.mjs BRB-ZH-9x16 out/check 3.5 12 16.4 --scale 0.5   # a few frames as PNGs
```

`render-all.mjs` writes H.264 at CRF 18 (BT.709) with 320 kbps AAC. On a machine where Remotion can't
download its own headless Chrome, point it at one: `REMOTION_CHROME=/path/to/chrome-headless-shell`.

The film grain (`src/ui/Grain.tsx`) is faint on purpose: at the strength it started with, the files
were three times the size and the grain turned to blocks once a platform re-encoded them.

## Sound

`scripts/soundtrack.py` writes `public/audio/soundtrack.wav` (48 kHz, about −14 LUFS): an original
score in A minor at 120 BPM that resolves to C major on the end card, plus every click, tick, whoosh and
thud, placed from the cue sheet. It's seeded, so it renders the same every time.

## Fonts

Inter and Inter Display (SIL Open Font License) stand in for SF Pro, Noto Sans SC (SIL OFL) for PingFang
SC. Both licenses allow use in videos; the texts are in `public/fonts/Inter-OFL.txt` and `public/fonts/noto-sc/OFL.txt`.
