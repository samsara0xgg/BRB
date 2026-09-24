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
  siren at full volume. The siren plays on the built-in speakers and holds that volume even if
  you muted them.
- Unlocking the Mac (Touch ID or password) disarms and restores your volume.
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
  12 s of lock screen (display on). Recording after the display sleeps is not measured.
- Do the brightness keys arrive as system-defined key codes 2/3 or as key codes 144/145? Step 1
  shows it.
- Does the siren play from the speakers with the lid shut?
