# BRB for iPhone and Apple Watch

The phone side of BRB. It pairs with the Mac app through the relay, shows what the Mac sees, and stops or
disarms an alarm from anywhere. SwiftUI, iOS 17 and watchOS 10, no third-party packages.

```sh
brew install xcodegen
./ios/open.sh          # generates BRB.xcodeproj from project.yml and opens it
```

The project file is generated, not committed. Set `DEVELOPMENT_TEAM` in `project.yml` (or in Xcode) to run on a
device. The bundle ids are `com.allen.brb` (app), `.widgets`, `.notifications`, `.watchkitapp` and
`.watchkitapp.widgets`, and all of them share the app group `group.com.allen.brb`.

## What is where

| Folder | What |
|---|---|
| `App/` | The iPhone app. `Model/` holds state (`AppStore`, one `MacModel` per Mac, the demo and the real backend), `UI/` the screens. |
| `Shared/Core/` | Foundation-only: models, the relay client, the viewer socket, storage. Also compiled into the notification extension and the tests. |
| `Shared/UI/` | The colors and the shield, shared by the app, the widgets and the Watch. |
| `Widgets/` | Home and lock screen widgets, the Live Activity and Dynamic Island, the Control Center control, App Intents. |
| `NotificationService/` | Adds the photo to an alarm notification. |
| `Watch/`, `WatchWidgets/` | The Apple Watch app and its complication. |
| `Gallery/` | `BRBGallery`, a scheme that draws the widgets, the Live Activity and the Dynamic Island in a plain app, for screenshots. Not shipped. |
| `Resources/` | `Localizable.strings` and `.stringsdict` in English and Simplified Chinese, plus `Widgets` and `Watch` tables. |
| `Tests/` | Unit tests for the Core. |

The relay protocol (v3) is in `relay/PROTOCOL.md`.

## Try it without a Mac

Launch with `-demo 1` (Xcode: Edit Scheme, Run, Arguments) to get two pretend Macs that play a real alarm,
or tap "No Mac? Try the demo" in the pairing flow. Settings then has buttons to bump, touch or lift the demo Mac.
Other launch arguments, all harmless in a normal launch:

- `-scene idle|arming|armed|partial|test|warn|siren|back|muted|offline|offlineAlarm|done|empty`
- `-open mac|alarm|records|record|settings|privacy|faq|start|paywall|share|evidence|sendlink`
- `-onb welcome|notif|crit|scan|code|paired|done|camdenied|expired|macoffline|nomac`
- `-pstate loading|error|empty|offline`, `-pro 1`, `-notifOff 1`
- The Watch app: `-wdemo idle|armed|arming|warn|siren|offline|done|many|nopro|empty`
- The gallery app: `-page home1|home2|home3|lock|live1|live2|island1|island2|island3`, `-dark 0`

`scripts/shots.sh` (iPhone, widgets) and `scripts/watch-shots.sh` take a screenshot of each of these in the simulator.

## Before the App Store

- **Critical alerts** need an entitlement Apple grants on request. Add `com.apple.developer.usernotifications.critical-alerts`
  to the app's entitlements and the `CRITICAL_ALERTS` compilation condition; until then BRB uses Time Sensitive alerts
  and hides the switch.
- **Push**: `aps-environment` is `development`; the relay needs the APNs key (see `relay/PROTOCOL.md`).
- **In-app purchase**: create the non-consumable `com.allen.brb.pro` in App Store Connect (BRB Pro, one time).
- **Links**: the support address, privacy policy, terms and the App Store id are placeholders in `App/Model/AppLinks.swift`.
- **App Review**: reviewers have no Mac; the demo (above) is how they see every screen.
