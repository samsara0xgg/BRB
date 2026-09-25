# GuardMode

Menu-bar guard for leaving the MacBook on a library or cafe table.

- Arm from the menu-bar dot (gray = off, yellow ring = 5 s countdown, yellow = armed, red = alarm).
- While armed: the built-in camera records to `~/Movies/GuardMode/` (kept 7 days), and the Mac
  stays awake with the lid shut. These trigger the alarm: the lid angle moving 20 degrees, the
  laptop turned more than 15 degrees or moving for about a second (a knock or a short nudge does
  not count), any key, click, or trackpad touch, and unplugging the charger if it was plugged in
  at arming. A shut lid pauses the recording; it continues in the same file once the lid opens.
- Volume, mute, and brightness keys are yours to use while armed. They pass through and never
  trigger.
- A trigger swallows the stranger's input, locks the screen, beeps softly for 10 s, then sounds a
  siren. The siren plays on the built-in speakers and holds its volume even if you muted them.
- The siren's volume is set in the menu under 报警音量 (full when never set). 静音（测试用） is the
  silent test mode: everything else runs as usual (lock, recording, stages), the speakers stay
  muted.
- To disarm, rest a finger on Touch ID, or press it (seen live: the finger is read before the press
  locks the screen). Nothing shows on screen; GuardMode holds the keyboard focus while armed and
  hands it back. A finger that is not yours, tried until macOS gives up, triggers. Unlocking
  the Mac also disarms, and restores your volume after an alarm.
- Once the screen is locked (the display slept, or after a trigger), keys and touches no longer
  trigger, so waking the Mac to unlock it stays silent. Lifting, the lid, and the charger still do.
- Phone push (optional, off by default): turn it on under 手机推送 in the menu, subscribe to the
  copied name in the ntfy app (iPhone or Android, server ntfy.sh), then send the test push. A
  trigger then pushes the reason and a camera photo at ntfy's top priority. ntfy.sh keeps the photo
  for 3 hours; the subscription name is the only secret.
- Live view: while armed (from the countdown on), the camera can be watched in any browser. Tapping
  the push, or its 看实时画面 button, opens the link; 复制实时画面链接 in the menu copies it.
  Frames (640x360, about 7.5 a second, about 17 MB a minute) flow only while the page is open, and
  the page shows how old the last frame is. The link can watch but not pose as the camera. It goes
  through the relay in `relay/`, a Cloudflare Worker on Allen's account
  (`guardmode-relay.guardmode-gf1n2.workers.dev`); redeploy with `cd relay && npx wrangler deploy`.
- A crash or kill while armed relaunches and resumes the session. A reboot starts idle.

## Setup

1. Sudo rule, so arming can keep the Mac awake with the lid shut (`pmset disablesleep`). The
   first command validates the file; install it only after that prints `parsed OK`:

   ```sh
   cd ~/Projects/guard-mode
   sudo visudo -cf guard-mode.sudoers
   sudo install -m 0440 -o root -g wheel guard-mode.sudoers /etc/sudoers.d/guard-mode
   ```

2. `./install.sh` builds, signs, and loads the LaunchAgent `com.allen.guard-mode`. The log is at
   `~/Library/Logs/guard-mode.log`.
3. The first arm asks for Accessibility and Camera access. Arming refuses and names every missing
   piece until all of them are present.

## Commands

`build/GuardMode.app/Contents/MacOS/guard-mode <command>`:

| command | what | noise |
|---|---|---|
| `selftest` | detectors on synthetic data, key classification, hardware present | silent |
| `sensors [s]` | live lid angle, motion, and detector triggers, for calibrating | silent |
| `keys [s]` | how each real key or trackpad event is treated (needs Accessibility for the terminal) | silent |
| `camera [s]` | records like an armed session and prints the recording state every second | silent |
| `record [s]` | raw accelerometer and lid samples as CSV, for tuning offline | silent |
| `siren [s]` | soft stage, then the siren, then the volume is restored | LOUD |
| `live [s]` | camera on and connected to the relay, no recording or guarding; prints the link (run through `open -n -W build/GuardMode.app --args live 60` for the camera grant) | silent |
| `push` | the menu's test push, with a camera photo, to the subscribed phone (a terminal without camera access sends no photo: `open -n -W build/GuardMode.app --args push`) | silent on the Mac |

The calibration knobs are `MotionDetector` (`tiltLimit`, `shakeLimit`, `sustainFraction`),
`LidDetector.limit`, and `GuardApp.countdownSeconds` / `softSeconds`.

## First live test (with Allen)

Silent steps first:

1. `keys 30`: volume, mute, and brightness keys print nothing. Letters, clicks, and trackpad touches
   print `TRIGGER`.
2. `sensors 60`: a knock on the table must not trigger. Lifting, carrying, tilting, and closing the
   lid halfway must trigger.

Then the steps that make sound:

3. `siren 3`.
4. Arm, wait out the countdown, touch the trackpad. Expected: the screen locks and soft beeps
   start. Touch ID within 10 s silences it, and your volume comes back.
5. Arm, close the lid. Expected: soft, then loud, and it keeps sounding with the lid shut. Open the
   lid and use Touch ID.
6. Arm, lift the laptop.
7. Arm, then `kill -9` the process. Expected: launchd relaunches it, still armed.

Steps 8 to 11 work in the silent test mode and passed live on 2026-09-24:

8. On the charger, arm, unplug. Expected: triggers and locks.
9. Arm, trigger, then `kill -9` the process while it alarms. Expected: it relaunches and alarms
   again, and unlocking disarms and restores your volume. (Live: relaunched in under 1 s, reached
   the loud stage, the speakers came back to their earlier level.)
10. Arm, then `pmset displaysleepnow`; lift the laptop; `pmset displaysleepnow` again. Expected: the
    recording keeps growing through both (live: about 78 MB a minute, frames not frozen).
11. Arm, rest an unenrolled finger on Touch ID. Expected: triggers.

## Emergency stop

`kill -9` relaunches the app and resumes the alarm (soft, then loud). `bootout` sends SIGTERM,
which disarms: it restores the volume and lets the Mac sleep again, and the app stays down:

```sh
launchctl bootout gui/$(id -u)/com.allen.guard-mode
```

`./install.sh` brings it back. If the Mac still will not sleep with the lid shut, run
`sudo pmset -a disablesleep 0`.

## Open questions

- Camera while locked: measured 2026-09-24. The camera kept delivering ~30 frames/s through
  the lock screen, with the display on (12 s) and asleep (step 10).
- Do the brightness keys arrive as system-defined key codes 2/3 or as key codes 144/145? Step 1
  shows it.
- Does the siren play from the speakers with the lid shut?
