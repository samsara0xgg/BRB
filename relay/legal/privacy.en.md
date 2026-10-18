## 1. Who we are

Back in 5 is built and run by allen, an individual developer ("we"). There is no company. Back in 5 has three parts:

- **The Mac app**: a macOS menu-bar anti-theft app, distributed as a notarized DMG outside the Mac App Store.
- **The iPhone app**: on the App Store.
- **The relay**: a server program we operate on Cloudflare Workers and Durable Objects. It passes state, alarm photos and commands between your Mac and your phone.

Contact: {{email}}

## 2. In short

- No accounts, no ads, no analytics or tracking SDKs. The iPhone app contains no third-party SDKs. We do not sell personal data.
- From the countdown on, the camera keeps only the last 10 seconds, in memory. Nothing is saved or photographed unless someone touches the Mac (an alarm).
- Recordings stay on your Mac and are never uploaded. Alarm photos, the Mac's state and session records go to the relay so your phone can see them.
- In photos, live frames and recordings, every face except the closest one (the largest in the picture) is pixelated on the Mac.
- The relay's servers are outside mainland China.

## 3. Data we handle

### 3.1 Stays on your Mac

| Data | Purpose | Where | How long |
|---|---|---|---|
| Camera buffer: the last 10 s, about 8 frames a second | To save the 10 s before a touch | Memory only | Constantly overwritten; discarded when guarding ends |
| Alarm recording: the 10 s before the touch and everything until disarm; video only, no sound | Evidence for you | `~/Movies/Back in 5/` | 7 days and 20 GB in total, oldest first (cleaned when the app starts and when guarding starts); delete any time |
| Session records: start and end, trigger, how it was disarmed, ignored bumps, siren time, photo count, recording file name, test or not | The panel's Recent list and the welcome-back summary | `~/Library/Application Support/BRB/` | The last 30 |
| Log: events, errors, the input type or key code that set off an alarm, the paired phone's name | Troubleshooting | `~/Library/Logs/brb.log` | Cut to the last 1 MB once it passes 10 MB; delete any time |
| Settings and secrets: screen note, place, volume, relay key and access token, paired phone's name | Making the app work | App preferences (`com.allen.brb.mac`) | Until you reset the link or delete the app |
| Keyboard, trackpad, motion sensor, lid angle, charger | Detecting a touch in real time | Processed in memory | Not stored or sent (the log notes only what kind of input set off an alarm) |
| Touch ID | Disarming | Handled by macOS | We never get fingerprints, only "passed" or "failed" |

### 3.2 Sent by the Mac to the relay

**Every time you guard, the Mac connects to the relay, whether or not an iPhone is paired.** With an iPhone paired, it also stays connected while idle.

| Data | Purpose | Where | How long |
|---|---|---|---|
| Mac state: guarding phase and times, place, screen note, siren volume, test mode, whether the camera is on, trigger and alarm stage, bumps, the last 40 events | Shown on the phone page and in the iPhone app; decides which pushes to send | Relay | Only the latest copy, replaced on every change; until you reset the link |
| With an iPhone paired, also: computer name (e.g. "Allen's MacBook Pro"), model, battery level, charging, four self-checks | Showing this Mac on the iPhone | Relay | Same as above |
| Alarm photos: currently up to 3 JPEGs per alarm (the relay keeps at most 6 per alarm), bystanders pixelated | Seeing what happened, on your phone | Relay | 7 days; delete earlier any time |
| Live frames: about 8 a second, bystanders pixelated | Watching live during an alarm | Passed through, not stored | Sent only during an alarm, and only while someone allowed is watching |
| Session history: start and end of each session, place, kind (quiet, alarm, test), trigger and disarm, warning and siren time, photo times, events, recording file name | History in the iPhone app | Relay | The last 30 per Mac, no time limit; delete one at a time, or all by resetting the link |
| Pairing code: 6 digits and a QR string, with the computer name, model and access token | Pairing an iPhone | Relay | Valid 10 minutes, single use; removed at the next cleanup one hour after it expires |

### 3.3 Sent by the iPhone app to the relay

| Data | Purpose | Where | How long |
|---|---|---|---|
| Device registration: a random install ID, device name (iOS usually reports just "iPhone"), Apple push token, Live Activity tokens, language, time zone (the phone's setting, to show alarm times in your local time), notification choices, "Ring when silenced" | Sending alarm pushes and Live Activity updates to this phone | Relay (at most 6 devices per Mac) | Until you unpair on the iPhone, reset the link, or a 7th device replaces it |
| Device name at pairing | Telling the Mac which phone paired | Passed to the Mac, which keeps it in its settings and log | The relay deletes it once the Mac next connects |
| Your commands: start, stop, silence, disarm, change settings (may include the note text), reset | Controlling the Mac | Relay (queued while the Mac is offline, at most 8) | Deleted on delivery; "start" expires after 30 s, the rest after 10 minutes |
| The IP address (first 64 bits for IPv6) and time of a wrong pairing code | Stopping guessing: 8 tries per address per 10 minutes | Relay | Removed at the next cleanup after 10 minutes |

### 3.4 Stays on your iPhone

| Data | Purpose | Where | How long |
|---|---|---|---|
| Paired Macs: room ID, access token, relay address, name, model, the name you gave it | Connecting to the relay | Shared app-group settings (not the Keychain) | Until you unpair or delete the app |
| Each Mac's latest state and latest session | Widgets, showing something while offline | App group | Replaced on each update; a Mac's record and state are removed when you unpair it |
| Alarm photo cache | Notifications, Live Activity, widgets | The app group's `photos/` folder; iOS's network cache | The newest 12, at most 2 days; the network cache is managed by iOS; a notification's photo is kept by iOS with the notification |
| Settings: Face ID before disarming, notification choices, random install ID, last note and place | Making the app work | App group | Until you delete the app |
| Live frames | Watching during an alarm | Memory only | Not stored |

This local data may be included in your iCloud or computer backups, depending on your settings.

### 3.5 Permissions

- **iPhone camera**: only to scan the pairing QR code on your Mac. Nothing is saved or uploaded.
- **Face ID or passcode**: to confirm it's you before disarming or stopping. iOS handles it; we never get biometric data.
- **Photos (add only)**: only when you choose to save alarm photos or a share card. We never read your library.
- **Notifications**: alarm alerts; "Ring when silenced" needs your permission.
- **Mac**: the camera; Accessibility (to notice the keyboard and trackpad); a one-time admin rule to stay awake with the lid shut.

## 4. The camera and people nearby (sensitive data)

Alarm photos and recordings can show faces, which many laws treat as sensitive. This is how Back in 5 handles them:

- Nothing is saved or photographed until the Mac is touched. Until then there are only 10 constantly overwritten seconds in memory, so people walking past are not kept.
- Before a photo, live frame or recording frame leaves the camera pipeline, the Mac pixelates every face except the largest. This uses Apple Vision face detection, which finds where faces are. Back in 5 does not recognise faces and does not extract or store face features.
- Pixelation can miss a face (in profile, covered, in poor light). The person closest to the Mac stays clear, because that is the evidence.
- While guarding, the screen says in English and Chinese: please don't touch; walking by isn't recorded, touching it is.
- You decide where and when to use Back in 5. For other people in the pictures, we only store and deliver the photos for you. You must follow your local laws on recording and personal data; see the Terms of Use.

## 5. Who can see what

- **Holders of the owner token**: your Mac, every paired iPhone, and anyone with the "phone page" link from the Mac's panel. They see the state, photos and history, the live camera during an alarm, and the iPhone app can send commands. Don't share that link casually.
- **An alarm pass**: made for each alarm and included in that alarm's push. It shows only that alarm's photos, timeline and live camera, and stops working when the alarm is disarmed. It does not show the computer name, battery or settings.
- **Someone with only the room ID**: sees only whether the Mac is guarded.
- **We (as relay operator) and Cloudflare**: data on the server is not end-to-end encrypted and is technically accessible. We do not look at photos or other content except to keep the service running, to deal with abuse, or when the law requires it.

## 6. Who we share data with

| Recipient | Role | Data | Purpose | Location | Privacy policy |
|---|---|---|---|---|---|
| Cloudflare, Inc. | Processor, hosts the relay | All relay data in sections 3.2 and 3.3, and the IP addresses needed to deliver it | Running the relay | US company, global network, outside mainland China | https://www.cloudflare.com/privacypolicy/ |
| Apple Inc. (Apple Push Notification service) | Push channel | Push tokens; push content: alert type, computer name, room ID, alarm pass, photo time, time of day; Live Activity content: place, times, trigger, bumps | Notifications and Live Activity updates | US, outside mainland China | https://www.apple.com/legal/privacy/ |

We share personal data with no one else, except where the law requires it.

## 7. International transfers (separate consent)

The relay (Cloudflare) and Apple's push service are outside mainland China. Whenever you guard, the Mac sends the data in section 3.2 to the relay; with an iPhone paired, the data in section 3.3 and pushes follow.

- Names and contacts of the overseas recipients: section 6.
- Purpose and method: running the relay and sending alerts, always over HTTPS or WSS.
- Kinds of data: sections 3.2, 3.3 and 6.
- How to use your rights: section 8, or contact us.

**Separate consent (for users in mainland China, under the PIPL)**: before using Back in 5's guarding, please separately confirm that you agree to this data, including face images in alarm photos, being transferred outside mainland China. If you don't agree, don't use guarding, or run your own relay (section 11). You can withdraw at any time by resetting the link and stopping use; this does not affect processing that happened before.

## 8. Your rights, and how to delete

You can access, copy, correct and delete your data, withdraw consent, and ask us to explain how we process it. In the EU and UK you can also restrict or object to processing, ask for portability, and complain to your local supervisory authority.

You can do most of this yourself:

- **Delete one session and its photos**: in the iPhone app, open it under Records and tap Delete.
- **Delete all photos in the cloud**: iPhone app, Settings → Privacy & data → "Delete all my photos in the cloud". The history list stays.
- **Delete everything the relay holds for this Mac**: "Reset link…" in the Mac's panel, or Mac Settings → Phone → "Unpair all phones…", or "Reset link" on this Mac's page in the iPhone app (the Mac must come online within 10 minutes). The old link stops working, every phone is unpaired, and the relay deletes photos, history, state and device registrations. It keeps only a "reset" marker so the old link can say it was reset.
- **Unpair one iPhone**: removes this phone's registration on the relay and the pairing on the phone. The Mac's photos and history stay.
- **Data on the Mac**: delete the recordings in `~/Movies/Back in 5/`, `~/Library/Logs/brb.log` and `~/Library/Application Support/BRB/`.
- **Data on the iPhone**: delete the app.

Or email {{email}}. There are no accounts, so include the room ID (the part of the phone-page link after `/v/`) so we can find the data. We reply within 15 working days. Resetting the link yourself is still the fastest way.

## 9. Security

- Everything travels over HTTPS or WSS (TLS).
- Random secrets: a 32-character Mac key, a 24-character owner token, a 16-character pass per alarm. The room ID is a hash of the Mac key, so knowing it does not let anyone pose as your Mac.
- Pairing codes last 10 minutes and work once; 8 tries per IP address per 10 minutes; comparisons leak no timing.
- Only the owner token can send commands. By default the iPhone asks for Face ID before disarming or stopping.
- The relay keeps only the fields in its protocol, with limits on length and count. Live frames are never written to disk.
- Faces are pixelated on the Mac before anything is uploaded.
- Limits: data on the server is not end-to-end encrypted. Tokens are kept in the apps' settings on the Mac and iPhone (not the Keychain) and rely on the system's protection. If you think a link has leaked, reset it at once.

## 10. Children

Back in 5 is not directed at children under 14 (under 13 elsewhere, or a higher age where local law requires). We do not knowingly collect children's data. If you think a child has used Back in 5, reset the link or contact us.

## 11. Running your own relay

You can deploy your own relay and point the Mac at it with `defaults write com.allen.brb.mac relayHost <your-host>` (see the project README). The data in sections 3.2 and 3.3 then goes only to your server, not to us, and you are responsible for running it lawfully. The iPhone uses the relay address in the pairing QR code.

## 12. What we don't do

No ads, no analytics, no tracking across apps, no selling or renting data, no profiling, no face recognition, no sound recording, no location, contacts or advertising identifiers. The relay sees only IP addresses (needed to deliver traffic, and to stop code guessing). If you choose "Share with App Developers" in iPhone Settings, Apple may give us crash reports and similar aggregated data.

## 13. Legal bases (EU GDPR)

- Contract: providing the features you use (guarding, pushes, phone view, history).
- Legitimate interests: security and abuse prevention (such as logging IPs of wrong pairing codes); keeping photos of other people from an alarm as evidence for you.
- Consent: notification permission, and international transfers where the law requires consent.

## 14. Changes

When this policy changes, we update this page and its effective date. We tell you about significant changes in the app or in the release notes.

## 15. Contact

allen (individual developer) · {{email}}
