# BRB relay protocol v3

The relay (`worker.js`, a Cloudflare Worker with one Durable Object per Mac) sits between three
kinds of clients:

- the **Mac** (the camera): holds `WS /cam/<key>` and tells the room what is happening;
- the **iPhone app, Apple Watch and widgets** (the owner): hold `WS /watch/<id>?t=<token>` or call the HTTP routes
  below with the owner token;
- the **phone web page** (`GET /v/<id>#<token>`), still read-only, and the old v2 Macs.

v3 is v2 plus: pairing by code, commands from the phone to the Mac, a history of sessions, device
registration for push (APNs), and a few new state fields. Everything in v2 keeps working.

## Secrets and ids

| name | what | who has it |
| --- | --- | --- |
| `key` | 32 chars, the Mac's secret | the Mac only |
| `id` | first 32 hex chars of sha256(`key`) | everyone paired |
| owner `token` | 24 chars `[a-z2-9]` (regexp `^[a-z0-9]{8,64}$`) | the Mac and every paired phone |
| `pass` | 16 chars, one alarm's viewing token | a push; valid until that alarm is disarmed |

Levels (unchanged): `owner` sees everything and may send commands; `pass` sees one alarm; `status` sees
only whether the Mac is guarded; `expired` / `reset` see nothing.

## Pairing

The Mac asks for a pairing offer, shows it as a QR code and as six digits, and the phone claims it.

`POST /pair/<key>` (Mac), JSON `{"token": "<owner token>", "name": "Allen's MacBook Pro", "model": "MacBook Pro 14″"}`

→ `200 {"code": "123456", "qr": "<16 chars [a-z2-9]>", "expires": <ms>}`

The offer lives 10 minutes and is used once. A new offer replaces the Mac's previous one. The QR
carries `https://<host>/pair/<qr>` (a `GET` on that URL shows a small page that says to open the
BRB app and tries `brb://pair?c=<qr>&h=<host>`); the app also accepts the bare six digits.

`POST /claim` (phone), JSON `{"code": "<6 digits or the qr string>", "device": "Allen's iPhone"}`

→ `200 {"id": "...", "token": "<owner token>", "name": "...", "model": "...", "host": "<host>"}`
→ `404 {"error": "invalid"}` for an unknown or used code, `410 {"error": "expired"}` for an old one,
`429 {"error": "slow down"}` after 8 wrong tries from one IP within 10 minutes.

Claiming deletes the offer and sends the Mac `{"paired": {"device": "Allen's iPhone", "at": <ms>}}`
(held until the Mac is online). A global `Codes` Durable Object keeps the offers; codes are checked
in constant time per attempt.

`GET /pair/<qr>` is the HTML page above; it never reveals the token.

## State, Mac to relay

The Mac sends `{"state": {...}}` on every change, JSON text. v3 keeps all v2 fields and adds the ones
marked new. `clean()` in the relay drops anything else and clamps types.

| field | type | meaning |
| --- | --- | --- |
| `v` | `3` | |
| `phase` | `idle` `arming` `armed` `triggered` | |
| `since` | ms | when this session was armed (0 while idle) |
| `armEnd` | ms, **new** | while `arming`: when the countdown ends |
| `lastEnd` | ms or null, **new** | when the previous session ended (for "last guarded 2 h ago") |
| `place` | `library` `cafe` `transit` | |
| `note` | string ≤ 48 | the note on the frosted screen |
| `vol` | 0–100, **new** | siren volume |
| `test` | bool | test mode: every stage runs without a sound |
| `camera` | bool | the camera works this session |
| `push` | bool | the Mac also sends ntfy alerts |
| `trigger` | `Trigger` raw value or null | `lifted tilted lidClosed lidMoved charger powerKey keyboard trackpad finger restarted` |
| `at` | ms or null | when the alarm started |
| `siren` | bool | the loud stage is playing |
| `stage` | `null` `soft` `siren` `back` `hushed`, **new** | while `triggered`: `soft` (voice warning, siren at `softEnd`), `siren`, `back` (put back in place, siren off), `hushed` (the owner stopped the siren; the Mac stays locked and filming) |
| `softEnd` | ms or null, **new** | when `soft` turns into `siren` |
| `carried` | bool, **new** | the Mac is being carried right now |
| `bumps` | int | ignored bumps this session |
| `mac` | `{name, model, batt, chg}`, **new** | computer name (≤ 40), model (≤ 40), battery 0–100, charging |
| `health` | `{ax, cam, lid, mot}` bools, **new** | Accessibility, camera, lid rule, motion sensor: true = fine |
| `events` | `[{t, e, k}]`, last 40 | `e` ≤ 16 chars: `armed triggered photo siren back lift hushed calledoff disarmed cancelled warning paired`; `k` ≤ 16 chars: the trigger, the place, the disarm (`fingerprint unlock password escape stopped phone sensorsSilent tapFailed`) or the warning (`motion camera`) |
| `pass` | token or null | stripped before the phone sees it |

While the Mac is paired it keeps the socket open **also when idle** and sends a state with
`phase: "idle"`, `mac`, `health`, `vol`, `place`, `note`, `lastEnd` at connect and when anything
changes (and the battery at most every 5 minutes). The relay's hibernating sockets make this free.

### What a phone sees

`WS /watch/<id>?t=<token>`: JSON text frames

```json
{ "v": 3, "level": "owner", "online": true, "offlineAt": null,
  "state": { ...as above without pass... }, "photos": [<ms>, ...] }
```

`GET /state/<id>?t=<token>` returns the same JSON as the first frame (`200`, `{"v":3,"level":...}`; `403` for an unknown
token, `404` for an unknown room, with the same level rules). Widgets, the Watch and background refreshes use it
instead of a socket; `Cache-Control: no-store`, CORS open.

`photos` lists photo times (newest first) the level may see. Binary frames are camera JPEGs, sent only
while `phase` is `triggered` and the level is `owner` or `pass`. A viewer also receives
`{"ack": {"id": "<cmd id>", "ok": true|false, "why": "<reason>"}}` for commands it sent.

## Commands, phone to Mac

`POST /cmd/<id>?t=<owner token>`, JSON `{"id": "<≤ 24 chars>", "k": "<kind>", ...}`, or the same object
as a viewer WebSocket text frame `{"cmd": {...}}`. Only the `owner` level may send commands (403
otherwise).

→ `200 {"ok": true, "delivered": true}` when the Mac was online and got it, `{"ok": true, "delivered": false}` when it
was queued.

| `k` | extra fields | the Mac does |
| --- | --- | --- |
| `start` | `place?`, `note?`, `test?` | applies them, runs the normal 5 s countdown. `ack` fails with `why: "not-ready"` (a permission is missing), `"busy"` (already guarding), `"locked"` |
| `stop` | | cancels the countdown or stops guarding (the phone has asked for Face ID) |
| `hush` | | stage `soft` → called off; stage `siren` → siren stops. The Mac stays locked, keeps filming, and a new lift starts the siren again |
| `disarm` | `by: "face"` | ends the alarm as if its owner had disarmed it (`Disarm.phone`) |
| `set` | `place?`, `note?`, `vol?`, `test?` | changes the Mac's settings (not while armed except `note`) |
| `reset` | | resets the link (new key and token; the relay forgets the room) |

The Mac answers every command with `{"ack": {"id", "ok", "why?"}}`; the relay forwards it to owner
viewers and drops it. While the Mac is offline the relay queues commands in storage (at most 8; `start` for 30 s,
the others for 10 minutes) and delivers them, in order, when the Mac connects. `hush`, `stop` and
`disarm` are idempotent; a stale one does nothing.

The Mac must never act on a command that did not come through the relay as `{"cmd": ..., "from": "phone"}`.

## Sessions (history)

When a session ends the Mac sends `{"session": {...}}` once:

```json
{ "id": "<armed ms as string>", "start": <ms>, "end": <ms>, "place": "cafe", "bumps": 2,
  "kind": "quiet" | "alarm" | "test", "trigger": "lifted" | null, "at": <ms> | null,
  "how": "fingerprint", "soft": 0, "siren": 42, "photos": [<ms>, ...], "events": [{t, e, k}, ...], "clip": "name.mov" | null }
```

The relay keeps the latest 30 per room in SQLite. `GET /h/<id>?t=<owner>` → `{"sessions": [...]}`
(newest first); `DELETE /h/<id>/<session id>?t=<owner>` deletes one and its photos. `DELETE /h/<id>?t=<owner>`
deletes every photo and clip ("delete my photos in the cloud") and keeps the list.

Photos: `POST /photo/<key>?t=<ms>&pass=<pass>` (unchanged), `GET /p/<id>/<ms>?t=<owner or pass>`
(unchanged). The relay keeps at most 6 photos per alarm for 7 days, or 30 days when a registered
device says `pro: true`.

## Devices and push

`POST /device/<id>?t=<owner token>`, JSON (upsert by `dev`, at most 6 per room):

```json
{ "dev": "<stable uuid of this app install>", "name": "Allen's iPhone", "apns": "<hex token>", "env": "sandbox" | "production",
  "lang": "zh" | "en", "crit": true, "pro": false,
  "events": { "siren": true, "back": true, "disarm": true, "guard": true, "sensor": true },
  "la": "<hex Live Activity update token>" | null, "laStart": "<hex push-to-start token>" | null }
```

`DELETE /device/<id>/<dev>?t=<owner>` removes it. `POST /test-push/<id>?t=<owner>` sends a test alert to every
registered device (for "send a test alert").

When `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID` and `APNS_TOPIC` secrets are set, the relay sends APNs
alerts on state changes (HTTP/2 to `api.push.apple.com`, or `api.sandbox.push.apple.com` per device
`env`, ES256 JWT cached for 50 minutes). Without them it sends nothing and the Mac's ntfy alerts remain
the only push.

| event (from the state change) | level | `loc-key`s in the app's strings | category |
| --- | --- | --- | --- |
| `triggered` | `critical` if `crit`, else `time-sensitive` | title `p_alarm_<trigger>` (`lifted`→`lift`, `tilted`/`trackpad` mapped by the app: see below), body `p_alarm_b` with the Mac name | `BRB_ALARM` |
| stage `soft` → `siren` | time-sensitive | `p_siren` | `BRB_ALARM` |
| stage `back` | time-sensitive | `p_back` | none |
| stage `hushed` | none (Live Activity only) | | |
| `disarmed` | passive | `p_dis` with `loc-args` `[HH:mm]` | none |
| `armed` / back to `idle` | passive, only if `events.guard` | `p_start` / `p_end` | none |
| `warning` event | time-sensitive | `p_sensor` | none |

Title keys: `p_alarm_lift` (lifted, tilted, lidClosed, lidMoved, charger, powerKey, restarted),
`p_alarm_touch` (trackpad, keyboard, finger). Payload: `aps.alert` with `title-loc-key`, `loc-key`,
`loc-args`; `aps.sound` (`default`, or `{"critical": 1, "name": "default", "volume": 1.0}`), `aps.thread-id` =
the room id, `aps.mutable-content: 1`, `aps.interruption-level`, and custom keys `{"id": "<room id>", "pass": "<alarm pass>",
"photo": <ms or null>, "at": <ms>}`. The alarm alert waits for the first photo (at most 2.5 s)
so the app's notification service extension can fetch it from `/p/<id>/<photo>?t=<pass>`.

Preferences the device registered (`events.*`, `crit`) decide which alerts it gets. The alarm alert
cannot be switched off.

Live Activity: when a device registered `la`, the relay sends `apns-push-type: liveactivity`
updates (topic `<APNS_TOPIC>.push-type.liveactivity`) on every state change with
`content-state` as below, and an `end` (dismissal 6 s later) on disarm. A device that registered
`laStart` gets a `start` push when guarding begins or an alarm starts and none is running (attributes
type `BRBActivityAttributes`, attributes `{"macId": "<id>", "macName": "..."}`).

```json
{ "look": "armed" | "arming" | "partial" | "test" | "warn" | "alarm" | "back" | "hushed" | "clear" | "offline",
  "place": "cafe", "since": <ms>, "armEnd": <ms|0>, "at": <ms|0>, "softEnd": <ms|0>, "bumps": 0,
  "trigger": "lifted" | null, "photo": <ms|0>, "by": "fingerprint" | "phone" | null, "test": false, "pass": "<alarm pass>" | null }
```

## Storage in a room (SQLite + KV)

`owner`, `state`, `offlineAt`, `oldPasses`, `wiped` (as in v2); new: `queue` (commands), `paired` (a pending
notice for the Mac), `devices`, `pro`; tables `photos(t, pass, data)` (as in v2) and `sessions(id, end, json)`.

## Compatibility

A v2 Mac keeps working: it never says `hello` with `v: 3`, sends no `mac`, `health`, `stage`; the relay then
treats `siren` as `stage: "siren"` and a missing `stage` in `triggered` as `soft`. The v2 phone page ignores new fields.
The app needs a v3 Mac only for commands, history and the device cards; against a v2 Mac it shows
the same screens read-only and says "update BRB on your Mac".

## Decisions

What the first implementation of this document (`worker.js`, `apns.js`, the Mac's `Live.swift`) settled where the
text above was silent or ambiguous. Field names are as written above.

State
- `state.v` is the Mac's own version: `3` from a v3 Mac, `2` from an older one (that is how the app knows to offer no commands).
  The top-level `v` of what a phone receives is the relay's, always `3`.
- A field an old Mac does not send is `null` for `mac`, `health`, `lastEnd`, `at`, `softEnd` and `stage` outside an alarm, `0` for
  `armEnd` and `bumps`, `100` for `vol`. `mac.batt` is `null` for a Mac without a battery. `health.*` is `true` only when the Mac said `true`.
- The `pass` level sees the alarm (`trigger`, `stage`, `events`, …) but `mac`, `health` and `lastEnd` are `null`.
- Camera frames are relayed only while `phase` is `triggered`, whoever is watching.

Pairing
- `POST /pair/<key>` also makes `token` the room's owner token, so a phone that claims before the Mac ever connected is the owner
  (and nobody else is). It answers `410` for a room that was reset, and it obeys `CAM_IDS` like `/cam`.
- Offers are kept an hour past their expiry so `/claim` can say `410 expired` instead of `404 invalid`. An expired code counts as a
  wrong try. A `429` carries `Retry-After`. On IPv6 the limit is per /64. Codes are compared against every live offer without
  stopping at a match. Digits may be typed with spaces; the QR string is case-insensitive.
- `PAIR_TTL_MS`, `PAIR_TRIES` and `PAIR_WINDOW_MS` (vars) override 10 minutes, 8 and 10 minutes, for tests.
- `{"paired"}` is delivered with the Mac's `hello` when `hello.v >= 3` (or at once if it is online), then forgotten. `POST /wipe` also
  forgets the room's open offer.

Commands
- Only a room whose owner token is known takes commands (a room from before v2, where everyone is "owner", takes none). `id` is
  1 to 24 characters; fields not used by a kind are dropped; `place` must be a known place, `vol` is clamped to 0–100, `note` to 48.
- The queue is delivered when the Mac says `hello` with `v >= 3`, not merely when it connects. A command that outlived its TTL
  is dropped and the owner's phones get `{"ack": {"id", "ok": false, "why": "expired"}}`. `START_TTL_MS` and `CMD_TTL_MS` (vars)
  override 30 s and 10 minutes, for tests.
- The Mac's `ack` goes to every owner viewer, including for commands sent with `POST /cmd`. A `{"cmd"}` frame from a viewer that
  may not send commands, or with a malformed command, is answered to that viewer with `{"ack": {"id", "ok": false, "why": "forbidden"}}`
  or `"bad-command"`. `why` is at most 24 characters.

History and photos
- A session without an `id` (`[A-Za-z0-9_-]`, at most 24) or without an `end` is ignored. `GET /h/<id>` lists only the photos the room still
  has. `DELETE /h/<id>/<session>` removes the session, the photos it lists and any photo taken between its `start` and `end`; it
  and `DELETE /h/<id>` answer `200 {"ok": true}` whether or not there was something to delete.
- The relay keeps at most 6 photos per alarm (per `pass`), as v2 kept 6 in all. A photo older than the retention (7 days, 30 with a
  Pro device) is accepted and dropped at once; the rest go when the room's Durable Object alarm fires, or when the Pro flag changes.

Devices and push
- Missing keys of `events` default to `siren`, `back`, `disarm`, `sensor`: `true`, `guard`: `false`. The registration may also carry
  `tz` (an IANA zone, `p_dis`'s time of day is shown in it); without it the relay uses the zone of the request, then UTC. Tokens are hex (16 to
  400 digits), `la` and `laStart` may be `null`. The seventh device replaces the one that registered longest ago. A token that
  Apple answers `410` for is set to `null`.
- Apart from the alarm alert, an alert carries `loc-key` (and `loc-args`) and no `title-loc-key`; the app shows its own name as the
  title. `p_siren` is also sent when a hushed or put-back Mac sounds again. `p_dis` follows an alarm (`triggered` to `idle`);
  `p_start` and `p_end` are for the quiet case (`armed`, and `armed` to `idle`) and only with `events.guard`. `p_sensor` follows a `warning` event
  and `events.sensor`. A test run's alarm alert is `time-sensitive` even for a `crit` device and has `"test": true`.
  Alerts with `passive` have priority 5 and expire after 5 minutes, the others priority 10 and one hour.
- The held alarm alert is a Durable Object alarm (it survives the object being evicted); a photo with the alarm's `pass` releases it
  early, and a state that arrives meanwhile releases it first so the order holds.
- Live Activity: `look` is `clear` when idle, `offline` when the Mac is not connected during a session, `arming`, `armed`, `test`,
  `partial` (no camera or `health.mot` false), and for an alarm `warn` (soft), `alarm` (siren), `back`, `hushed`. `by` on `end` is
  `phone` for a `phone` disarm, `fingerprint` for `fingerprint`, `unlock` and `password`, otherwise `null`. Updates are also sent
  when the Mac goes offline or returns and when a photo arrives, and are skipped when nothing the activity shows changed. A `start`
  carries an `alert` (`p_start`, or the alarm's) because Apple wants one to start an activity by push.
- `POST /test-push` sends a plain `title`/`body` alert (`BRB`, in the device's `lang`) so it needs no string in the app. It answers
  `{"ok": true, "sent": n, "failed": m}`, or `501 {"error": "push not configured"}` without the APNS_* secrets.
- `APNS_URL` (var, for tests) replaces Apple's host.

State snapshot
- `GET /state/<id>`: no `t` is the status view, as a socket would show; a `t` that matches nothing is `403`; `404` is for a room that
  never had an owner or a state; a reset room answers `200` with `level: "reset"` so a widget can tell. `OPTIONS` answers `204`.
