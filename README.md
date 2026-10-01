# BRB

**Be right back.** Off for a coffee, a call or the restroom? Leave your MacBook on the table.
BRB keeps watch until you're back.

**[Download BRB.dmg](https://github.com/samsara0xgg/BRB/releases/latest/download/BRB.dmg)** · [中文说明](README.zh-CN.md)

BRB is a menu-bar guard for leaving a MacBook on a library or café table. While it guards, every screen
turns to frosted glass with one line on it: please don't touch. Walking past records nothing.
Touching it floods the screen red from where it was touched, locks it, sounds the alarm, saves
the 10 seconds before and everything after, and tells your phone.

Apple Silicon MacBooks, macOS 14 or later. On macOS 26 the notice is Liquid Glass.

## Install

[Download BRB.dmg](https://github.com/samsara0xgg/BRB/releases/latest/download/BRB.dmg), open it, drag **BRB** into **Applications** and open it from there.
It needs a MacBook with Apple silicon and macOS 14 or later. A shield appears in the menu bar, BRB
adds itself to your login items, and the panel opens by itself:

1. **Three cards** say what it does, what it records, and how to stop it.
2. **Try a silent run.** BRB asks for Accessibility (to notice the keyboard and trackpad) and
   the camera; the panel lists anything still missing, with a button to fix each one. Keeping the
   Mac awake with the lid shut needs a one-line admin rule, installed with your password once.
3. **Touch the trackpad** once the screen has frosted over: it turns red and locks, as it would for
   a stranger, but stays silent. Unlock, or rest a finger on Touch ID, to stop. Test mode switches
   itself off afterwards.

**How it works** at the bottom of the panel shows the cards again. To remove BRB, quit it from the
panel, drag it to the Trash, and remove the lid rule with `sudo rm /etc/sudoers.d/brb`. Recordings
stay in `~/Movies/BRB/`. The log is at `~/Library/Logs/brb.log`.

### From source

You also need Apple's command line tools (`xcode-select --install`, if you don't have them yet).

```sh
git clone https://github.com/samsara0xgg/BRB.git
cd BRB
./install.sh
```

`install.sh` builds the app, starts it now and at every login (and again after a crash or a kill),
and offers to install the lid rule. `./uninstall.sh` removes both; recordings stay.

## What you see

- **The menu-bar shield.** An outline when off. Amber rises through it during the 5 s countdown,
  it is solid amber while guarding, red with a mark during an alarm, struck through in test mode,
  and half filled when only part of the Mac is guarded (no camera, or the motion sensor stopped).
- **The panel.** Click the shield. Start guarding, where the Mac is (library, café, on the go), a
  note for the screen, the siren's volume, test mode, the frosted screen, phone alerts, the phone
  page, recordings, and the last few sessions. If something is missing (Accessibility, the camera,
  the sleep rule), the panel lists it and fixes what it can.
- **Counting down.** A ring counts 5 s while the fog spreads from the middle of the screen. `esc`
  cancels, and so does a finger resting on Touch ID.
- **Guarding.** The ring stretches into a glass sign: "Please don't touch. This Mac is guarded.
  Touching it sounds the alarm." A green chip under it says "Walking by isn't recorded. Touching it
  is." Your note sits beside it. The footer repeats it in the other language (Chinese under English,
  English under Chinese). Other screens get the frost and one small line.
- **Alarm.** Red spreads from where the Mac was touched (the pointer for the trackpad, the
  keyboard, the hinge for the lid, Touch ID for a finger, the side for the charger), the sign says
  only what is true ("You're on camera. The owner has been notified."), and the screen locks.
- **Welcome back.** Touch ID or unlocking clears the fog from the bottom-right corner. The sign
  says how long you were away and what happened, then shrinks into the menu-bar shield.

## What sets it off

| | siren |
|---|---|
| lifted or carried, turned more than 15°, the lid moved 20°, the charger unplugged (if it was plugged in), the power button | at once |
| a key, a click, a trackpad touch, a finger that isn't yours | after 10 s of soft beeps, the chance to cancel a false alarm |

A knock on the table, a bag set down next to it, or a short nudge that settles does not count; the
welcome-back sign counts them as ignored bumps. **Café** needs firmer, longer movement. **On the go**
ignores shaking and only counts tilt beyond 20°, the lid, the charger and touch.

Volume, mute and brightness keys are yours to use while guarding. A Touch ID press arrives as the
power button, so the power button waits 400 ms for the finger before it counts.

## Privacy

- From the countdown on, the camera keeps only the last 10 seconds, in memory. Nothing reaches the
  disk unless the Mac is touched.
- A trigger saves those 10 seconds and what follows to `~/Movies/BRB/` (kept 7 days, 20 GB at
  most).
- In the recording, the photos and the phone page, every face except the closest one is
  pixellated: the person at the laptop is recognizable, people passing behind them are not.
- The phone page shows the camera only after an alarm.

## Phone

- **Alerts** (optional) go through [ntfy](https://ntfy.sh). Turn them on in the panel, scan the code
  with the ntfy app, and send a test. An alarm sends what happened and a photo; a disarm follows.
  The topic name is the only secret, and ntfy.sh keeps a photo for 3 hours.
- **The phone page** is a link in the panel, with a QR code. Before an alarm it shows whether the
  Mac is guarded; after one, the live camera, up to 6 photos (kept 30 days) and what happened. It
  can only watch. The link in an alarm push works only until that alarm is disarmed, because ntfy
  keeps its messages; the panel's link keeps working. **Reset link** in the panel makes the old
  one stop working and forgets what the relay kept.

The page runs on the relay in `relay/`, a Cloudflare Worker; out of the box the app uses the
author's. To run your own: `cd relay && npx wrangler deploy`, then
`defaults write com.allen.guard-mode relayHost <your-worker>.workers.dev` and restart BRB.
Optionally set `CAM_IDS` on the Worker to the room ids allowed to connect (the part of the panel's
phone link after `/v/`).

## Commands

`build/BRB.app/Contents/MacOS/brb <command>`:

| command | what | noise |
|---|---|---|
| `selftest [--no-hardware]` | detectors on synthetic data, input kinds, history, icons, copy, then the hardware | silent |
| `sensors [s]` | live lid angle, motion, bumps and detector triggers, for the place set in the panel | silent |
| `keys [s]` | how each real key or trackpad event is treated (needs Accessibility for the terminal) | silent |
| `camera [s]` | buffers like a guarded session, saves halfway as a trigger would | silent |
| `record [s]` | raw accelerometer and lid samples as CSV, for tuning offline | silent |
| `siren [s]` | soft stage, then the siren, then the volume is restored | LOUD |
| `live [s]` | camera on with live frames allowed, connected to the relay; prints the owner's link (`open -n -W build/BRB.app --args live 60` for the camera grant) | silent |
| `push` | the panel's test push, with a photo | silent on the Mac |
| `snapshot <stage> [png]` | shows the frosted screen at `countdown`, `armed`, `test`, `alarm` or `welcome`, or the `panel` / `notready` page, for 3.5 s; add `-AppleLanguages "(zh-Hans)"` for Chinese | silent |

The calibration knobs are `MotionDetector` (`tiltLimit`, `shakeLimit`, `sustainFraction`), `Place`
for the per-place values, `LidDetector.limit`, and `GuardApp.countdownSeconds` / `softSeconds`.

## Languages

English is the base language. Every string in the Swift sources is its own English key, and
`Resources/zh-Hans.lproj/Localizable.strings` has the Chinese; a Mac set to Chinese shows the
Chinese. `scripts/check-strings.py` (run in CI) fails when a string has no translation or the
arguments differ.

## Development

`./build.sh` builds `build/BRB.app`; `SIGN_IDENTITY=-` signs ad hoc. CI
(`.github/workflows/build.yml`, macOS 26) builds, lints the plists and strings, runs
`selftest --no-hardware`, and checks the relay's syntax, on pull requests and `main` only. It also
installs from a downloaded copy of the source, and builds the disk image ad hoc and runs BRB from
`/Applications`.

`scripts/release.sh` publishes the download: it signs BRB with your Developer ID and the hardened
runtime, notarizes the app and the disk image, and makes the GitHub release for the version in
`Info.plist`. It needs the certificate, a notarytool keychain profile (`NOTARY_PROFILE`) and the
GitHub CLI; bump `CFBundleShortVersionString` and `CFBundleVersion` first.

## Still to check on a real Mac

These can't run in CI:

1. The frost at the shielding level actually blurs the desktop behind it (`NSVisualEffectView`,
   behind-window), and the fog spreads smoothly over the countdown.
2. A finger on Touch ID disarms while the frosted window is key, from the countdown on.
3. The red starts under the pointer after a trackpad touch, and the lock screen follows 1.2 s later.
4. After a trigger, the saved movie starts about 10 s before the touch and plays after a `kill -9`.
5. With two people in front of the camera, only the closer face is sharp in the movie, the photos
   and the phone page.
6. The welcome-back sign shrinks into the menu-bar shield.
7. The display stays on while guarding, and the notice survives plugging in a second screen.
8. The panel's note field takes typing, and each "Fix" button lands in the right Settings pane.
9. After `npx wrangler deploy`: the phone page with the panel's link, and with a push link before
   and after the disarm.

Then the earlier live steps, all in test mode except the siren:

1. `keys 30`: volume, mute and brightness print nothing; letters, clicks and trackpad touches print
   `TRIGGER`.
2. `sensors 60`: a knock on the table must not trigger; lifting, carrying, tilting and closing the
   lid halfway must.
3. `siren 3`.
4. Guard, touch the trackpad: the screen floods red and locks, soft beeps, then the siren after
   10 s. Touch ID within 10 s silences it and your volume comes back.
5. Guard, lift the laptop: the siren starts at once.
6. On the charger, guard, unplug: triggers.
7. Guard, trigger, `kill -9` the process: it relaunches, alarms again, and unlocking disarms.
8. Guard, rest an unenrolled finger on Touch ID: triggers.
9. During the countdown, rest your finger on Touch ID, or press `esc`: cancels.

## Emergency stop

`kill -9` relaunches the app and resumes the alarm. `bootout` sends SIGTERM, which disarms: it
restores the volume and lets the Mac sleep again, and the app stays down:

```sh
launchctl bootout gui/$(id -u)/com.allen.guard-mode
```

`./install.sh` brings it back, and `./uninstall.sh` removes it for good. For the copy in
Applications, `pkill -TERM -x brb` does the same as `bootout`. If the Mac still won't sleep with the lid shut, run
`sudo pmset -a disablesleep 0`. Quitting from the panel works only while it isn't guarding.
