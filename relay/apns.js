// Apple Push for the relay: the provider token, the payloads, and the policy that turns a change of
// state into the pushes to send. Pure on purpose (no Cloudflare imports; `fetch` is a parameter), so
// node:test runs it as it is. relay/PROTOCOL.md has the table this implements.

const HOSTS = { production: "https://api.push.apple.com", sandbox: "https://api.sandbox.push.apple.com" };
/// Apple wants a provider token renewed at most every 20 minutes and rejects one older than an hour.
const JWT_SECONDS = 50 * 60;
const PHOTO_WAIT_MS = 2500;
/// Titles of the alarm alert: the Mac was taken (siren at once) or touched (soft stage first).
const TOUCH = new Set(["trackpad", "keyboard", "finger"]);
const ENDED_BY = { fingerprint: "fingerprint", unlock: "fingerprint", password: "fingerprint", phone: "phone" };

/// The Mac's `events.*` preferences, as a device that never said anything has them.
export const DEFAULT_EVENTS = { siren: true, back: true, disarm: true, guard: false, sensor: true };

export function configured(env) {
  return Boolean(env.APNS_KEY && env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_TOPIC);
}

// MARK: provider token

const utf8 = (s) => new TextEncoder().encode(s);

function b64url(bytes) {
  let s = "";
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/// The .p8 file's key. Accepts the PEM as it is, with its newlines written as "\n", or just the base64.
function der(pem) {
  const body = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

/// An ES256 JWT as APNs wants it. WebCrypto's ECDSA signature is already the raw r||s a JWT carries.
export async function signJwt({ key, keyId, teamId }, iat) {
  const head = b64url(utf8(JSON.stringify({ alg: "ES256", kid: keyId })));
  const claims = b64url(utf8(JSON.stringify({ iss: teamId, iat })));
  const k = await crypto.subtle.importKey("pkcs8", der(key), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, k, utf8(`${head}.${claims}`));
  return `${head}.${claims}.${b64url(sig)}`;
}

let cached = null;

/// The token for the secrets in `env`, signed again only after 50 minutes (or when Apple refused it).
export async function bearer(env, now = Date.now(), fresh = false) {
  const id = [env.APNS_KEY_ID, env.APNS_TEAM_ID, env.APNS_KEY].join("|");
  if (!fresh && cached?.id === id && now - cached.at < JWT_SECONDS * 1000) return cached.token;
  const token = await signJwt({ key: env.APNS_KEY, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID }, Math.floor(now / 1000));
  cached = { id, token, at: now };
  return token;
}

export function forgetBearer() {
  cached = null;
}

// MARK: sending

/// POSTs one push to Apple. `push` is what `plan` returns; `device` supplies the environment. `ttl`
/// (seconds) becomes the expiration, so a push held back for a photo still counts from when it goes
/// out. A refused provider token is signed again once. Never throws: `{ok, status, reason}`.
export async function sendPush(env, device, push, fetchImpl = fetch, now = Date.now()) {
  const base = env.APNS_URL || HOSTS[device.env === "sandbox" ? "sandbox" : "production"];
  const topic = push.type === "liveactivity" ? `${env.APNS_TOPIC}.push-type.liveactivity` : env.APNS_TOPIC;
  const attempt = async (fresh) => {
    const res = await fetchImpl(`${base}/3/device/${push.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${await bearer(env, now, fresh)}`,
        "apns-topic": topic,
        "apns-push-type": push.type,
        "apns-priority": String(push.priority),
        "apns-expiration": String(push.ttl ? Math.floor(now / 1000) + push.ttl : 0),
        "content-type": "application/json",
      },
      body: JSON.stringify(push.body),
    });
    let reason = "";
    if (!res.ok) reason = (await res.json().catch(() => null))?.reason ?? "";
    return { ok: res.ok, status: res.status, reason };
  };
  try {
    let r = await attempt(false);
    if (r.status === 403 && /ProviderToken/.test(r.reason)) r = await attempt(true);
    return r;
  } catch (e) {
    return { ok: false, status: 0, reason: String(e?.message ?? e).slice(0, 80) };
  }
}

// MARK: payloads

/// "14:32" in the device's time zone (the relay has no clock of its own to ask).
export function hhmm(ms, tz = "UTC") {
  const options = { hour: "2-digit", minute: "2-digit", hourCycle: "h23" };
  try {
    return new Intl.DateTimeFormat("en-GB", { ...options, timeZone: tz }).format(ms);
  } catch {
    return new Intl.DateTimeFormat("en-GB", { ...options, timeZone: "UTC" }).format(ms);
  }
}

/// An alert as `aps.alert` with the app's own strings: the title is `title`, the body `loc`.
/// `critical` bypasses the silent switch; `passive` makes no sound and does not light the screen.
function alertBody({ id, loc, title, args, level, critical = false, category, pass = null, photo = null, at, test = false }) {
  const alert = { "loc-key": loc };
  if (title) alert["title-loc-key"] = title;
  if (args?.length) alert["loc-args"] = args;
  const aps = { alert, "thread-id": id, "mutable-content": 1, "interruption-level": critical ? "critical" : level };
  if (critical) aps.sound = { critical: 1, name: "default", volume: 1.0 };
  else if (level !== "passive") aps.sound = "default";
  if (category) aps.category = category;
  return { aps, id, pass, photo, at, ...(test ? { test: true } : {}) };
}

export function alarmTitleKey(trigger) {
  return TOUCH.has(trigger) ? "p_alarm_touch" : "p_alarm_lift";
}

export function alarmAlert({ id, state, device, photo = null, now = Date.now() }) {
  const critical = device.crit === true && state.test !== true;  // a test run must not break through the silent switch
  return alertBody({
    id, title: alarmTitleKey(state.trigger), loc: "p_alarm_b", args: [state.mac?.name || "Mac"],
    level: "time-sensitive", critical, category: "BRB_ALARM", pass: state.pass, photo, at: state.at || now, test: state.test,
  });
}

/// What the Live Activity shows, from the state. `online` is the relay's own knowledge of the Mac.
export function look(s, online = true) {
  if (!s || s.phase === "idle") return "clear";
  if (!online) return "offline";
  if (s.phase === "arming") return "arming";
  if (s.phase === "armed") return s.test ? "test" : !s.camera || s.health?.mot === false ? "partial" : "armed";
  return { soft: "warn", siren: "alarm", back: "back", hushed: "hushed" }[s.stage] ?? "alarm";
}

/// How the last session ended, if the state's events say.
export function endedBy(s) {
  const last = [...(s?.events ?? [])].reverse().find((e) => e.e === "disarmed");
  return ENDED_BY[last?.k] ?? null;
}

export function contentState(s, { online = true, photo = null } = {}) {
  return {
    look: look(s, online), place: s.place || "", since: s.since || 0, armEnd: s.armEnd || 0, at: s.at || 0, softEnd: s.softEnd || 0,
    bumps: s.bumps || 0, trigger: s.trigger ?? null, photo: photo || 0, by: s.phase === "idle" ? endedBy(s) : null, test: s.test === true,
    pass: s.pass ?? null,
  };
}

export function testAlert({ id, device }) {
  const zh = device.lang === "zh";
  return {
    aps: {
      alert: { title: "BRB", body: zh ? "测试提醒：能收到这条，说明报警会送到这台手机。" : "Test alert: if you see this, alarms will reach this phone." },
      sound: "default", "thread-id": id, "interruption-level": "active",
    },
    id,
  };
}

// MARK: policy

const key = (e) => `${e.t}|${e.e}|${e.k}`;

/// The pushes a change of state calls for, one object per push to send:
/// `{dev, field, type, token, priority, ttl, body, wait?}`. `field` says which of the device's tokens
/// it goes to (`apns`, `la`, `laStart`), so a token Apple has dropped can be forgotten. `wait: "photo"`
/// marks the alarm alert, which the room holds for the first photo (`PHOTO_WAIT_MS`).
///
/// `prev` is the state before (null for a room's first), `online` whether the Mac is connected now and
/// `wasOnline` whether it was. `photo` is the newest photo of the alarm's pass. `force` also sends
/// Live Activity updates that change nothing, for a photo that arrived on its own.
///
/// The alarm alert never depends on a device's preferences; the others follow `events.*`.
export function plan({ id, prev, next, devices, online = true, wasOnline = online, photo = null, force = false, now = Date.now() }) {
  const before = prev ?? { phase: "idle", events: [] };
  const out = [];
  const stage = next.phase === "triggered" ? next.stage : null;
  const was = before.phase === "triggered" ? before.stage : null;
  const alarmStarts = next.phase === "triggered" && before.phase !== "triggered";
  const sirenAgain = stage === "siren" && was !== null && was !== "siren";
  const putBack = stage === "back" && was !== "back";
  const disarmed = next.phase === "idle" && before.phase === "triggered";
  const guardStarts = next.phase === "armed" && before.phase !== "armed" && before.phase !== "triggered";
  const guardEnds = next.phase === "idle" && before.phase === "armed";
  const seen = new Set((before.events ?? []).map(key));
  const warned = (next.events ?? []).some((e) => e.e === "warning" && !seen.has(key(e)));

  for (const device of devices) {
    const prefs = { ...DEFAULT_EVENTS, ...device.events };
    const base = { dev: device.dev };
    const alert = (body, extra = {}) => {
      const passive = body.aps["interruption-level"] === "passive";
      out.push({ ...base, field: "apns", type: "alert", token: device.apns, priority: passive ? 5 : 10, ttl: passive ? 300 : 3600, body, ...extra });
    };
    // Of an alarm: its pass and photo. The rest of the alerts have no alarm to open.
    const alarm = { id, pass: next.pass, photo, at: now, test: next.test };
    const plain = { id, at: now, test: next.test };
    if (device.apns) {
      if (alarmStarts) alert(alarmAlert({ id, state: next, device, photo, now }), photo ? {} : { wait: "photo" });
      if (sirenAgain && prefs.siren) alert(alertBody({ ...alarm, loc: "p_siren", level: "time-sensitive", category: "BRB_ALARM" }));
      if (putBack && prefs.back) alert(alertBody({ ...alarm, loc: "p_back", level: "time-sensitive" }));
      if (disarmed && prefs.disarm) alert(alertBody({ ...plain, loc: "p_dis", args: [hhmm(now, device.tz)], level: "passive" }));
      if (guardStarts && prefs.guard) alert(alertBody({ ...plain, loc: "p_start", level: "passive" }));
      if (guardEnds && prefs.guard) alert(alertBody({ ...plain, loc: "p_end", level: "passive" }));
      if (warned && prefs.sensor && next.phase !== "idle") alert(alertBody({ ...plain, loc: "p_sensor", level: "time-sensitive" }));
    }
    const state = contentState(next, { online, photo });
    const live = (event, token, field, extra = {}, priority = 5) => {
      const aps = { timestamp: Math.floor(now / 1000), event, "content-state": state, ...extra };
      out.push({ ...base, field, type: "liveactivity", token, priority, ttl: 3600, body: { aps } });
    };
    const urgent = ["warn", "alarm", "back", "hushed"].includes(state.look) ? 10 : 5;
    if (next.phase === "idle") {
      if (device.la && before.phase !== "idle") live("end", device.la, "la", { "dismissal-date": Math.floor(now / 1000) + 6 }, 10);
    } else if (device.la) {
      const changed = JSON.stringify(state) !== JSON.stringify(contentState(before, { online: wasOnline, photo }));
      if (changed || force) live("update", device.la, "la", {}, urgent);
    } else if (device.laStart && (before.phase === "idle" || alarmStarts)) {
      const lead = alarmStarts
        ? { "title-loc-key": alarmTitleKey(next.trigger), "loc-key": "p_alarm_b", "loc-args": [next.mac?.name || "Mac"] }
        : { "loc-key": "p_start" };
      live("start", device.laStart, "laStart",
           { "attributes-type": "BRBActivityAttributes", attributes: { macId: id, macName: next.mac?.name || "Mac" }, alert: lead }, 10);
    }
  }
  return out;
}

export { PHOTO_WAIT_MS };
