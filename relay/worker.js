import { DurableObject } from "cloudflare:workers";
import * as apns from "./apns.js";
import { PAGES, site } from "./site.js";

// One Room per Mac. The Mac connects to /cam/<key>; phones open /v/<id>#<token> and watch
// /watch/<id>?t=<token>, where id = the first 32 hex chars of sha256(key). The id alone shows only
// whether the Mac is guarded. The owner's token (from the Mac's panel) shows everything; the pass in
// an alarm push shows that alarm until it is disarmed. The Mac sends camera frames only after a
// trigger and only while an allowed page is watching; photos of an alarm are kept for 7 days (30 for
// an owner with BRB Pro).
//
// relay/PROTOCOL.md is the contract. In short, protocol v3, Mac to relay: {"hello":{"token":…,"v":3}}
// once per connection, then {"state":{…}} on every change, {"session":{…}} when a session ends,
// {"ack":{…}} for each command, JPEG frames as binary messages, and photos as
// POST /photo/<key>?t=<ms>&pass=<pass>. The owner's phone sends commands (POST /cmd/<id> or a {"cmd"}
// frame), which the Mac gets as {"cmd":{…},"from":"phone"}; the relay queues them while it is offline.
// A phone pairs with a code the Mac asked for (POST /pair/<key>, POST /claim), which the global Codes
// object keeps. A Mac from before v3 keeps working, and one from before v2 never says hello: its room
// lets every page watch, as before.
//
// Optional: CAM_IDS, a comma-separated list of the room ids allowed to connect as a camera; APNS_KEY,
// APNS_KEY_ID, APNS_TEAM_ID and APNS_TOPIC (secrets) to push to the iPhone app. The public pages
// (/privacy, /terms, /support, /mac) are in site.js.

const TOKEN = /^[a-z0-9]{8,64}$/;
const DEVICE = /^[A-Za-z0-9-]{8,64}$/;
const SESSION = /^[A-Za-z0-9_-]{1,24}$/;
const HEX = /^[0-9a-fA-F]{16,400}$/;
const MAX_FRAME = 200_000;
const MAX_PHOTO = 300_000;
const PHOTOS_PER_ALARM = 6;
const PHOTOS_PER_ROOM = PHOTOS_PER_ALARM * 30;  // a pass is any string the camera sends, so cap the room too
const SESSIONS_KEPT = 30;
const QUEUE_KEPT = 8;
const DEVICES_KEPT = 6;
const DAY = 86400_000;
const PLACES = ["library", "cafe", "transit"];
const STAGES = ["soft", "siren", "back", "hushed"];
const KINDS = ["start", "stop", "hush", "disarm", "set", "reset"];
const BY_KEY = new Set(["cam", "photo", "wipe", "pair"]);
const METHODS = {
  cam: "GET", watch: "GET", p: "GET", state: "GET", photo: "POST", wipe: "POST", pair: "POST", cmd: "POST", "test-push": "POST",
  h: "GET DELETE", device: "POST DELETE",
};
const CORS = { "access-control-allow-origin": "*" };

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const [, route, a, b] = url.pathname.split("/");
    if (route === "claim") return claim(request, env, url);
    if (PAGES.has(route) && !a) return site(request, env, route, url);
    if (!TOKEN.test(a ?? "")) return text("not found", 404);
    if (route === "v" && request.method === "GET") return html(PAGE);
    if (route === "pair" && request.method === "GET") return html(PAIR_PAGE);
    if (!Object.hasOwn(METHODS, route)) return text("not found", 404);
    if (route === "state" && request.method === "OPTIONS") return new Response(null, { status: 204, headers: { ...CORS, "access-control-allow-methods": "GET" } });
    const byKey = BY_KEY.has(route);
    const id = byKey ? await viewId(a) : a;
    if ((route === "cam" || route === "photo" || route === "pair") && env.CAM_IDS && !env.CAM_IDS.split(",").map((s) => s.trim()).includes(id)) {
      return text("this camera is not allowed here", 403);
    }
    if ((route === "cam" || route === "watch") && request.headers.get("Upgrade") !== "websocket") return text("websocket only", 426);
    if (!METHODS[route].split(" ").includes(request.method)) {
      return text(`${METHODS[route].split(" ").join(" or ")} only`, 405);
    }
    if (route === "p" && !/^\d{10,16}$/.test(b ?? "")) return text("not found", 404);
    if (route === "device" && request.method === "DELETE" && !DEVICE.test(b ?? "")) return text("not found", 404);
    if (route === "h" && b !== undefined && !SESSION.test(b)) return text("not found", 404);
    if (route === "pair") return offer(request, env, id);
    const room = env.ROOMS.get(env.ROOMS.idFromName(id));
    if (route === "wipe") {
      const response = await room.fetch(request);
      await codes(env).forget(id);  // an offer made before the reset must not pair a phone with the new, empty room
      return response;
    }
    return room.fetch(request);
  },
};

function text(body, status) {
  return new Response(body, { status, headers: { "content-type": "text/plain; charset=utf-8" } });
}

function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers } });
}

function html(page) {
  return new Response(page, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "referrer-policy": "no-referrer" } });
}

async function readJson(request, max = 4096) {
  const raw = await request.text();
  if (raw.length > max) return null;
  try {
    const value = JSON.parse(raw);
    return value && typeof value === "object" ? value : null;
  } catch {
    return null;
  }
}

async function viewId(key) {
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key)));
  return [...hash].map((x) => x.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

/// A number from the environment (a var or a secret is always a string), or `fallback`.
function knob(value, fallback) {
  return value !== undefined && value !== "" && Number.isFinite(Number(value)) ? Number(value) : fallback;
}

const isToken = (v) => typeof v === "string" && TOKEN.test(v);
const str = (v, n) => (typeof v === "string" ? v.slice(0, n) : "");
const num = (v) => (Number.isFinite(v) ? v : 0);
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

/// Equal strings, in a time that depends only on their length.
function same(a, b) {
  const x = String(a), y = String(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x.charCodeAt(i) || 0) ^ (y.charCodeAt(i) || 0);
  return diff === 0;
}

// MARK: pairing

const codes = (env) => env.CODES.get(env.CODES.idFromName("all"));

/// POST /pair/<key>: the Mac, which proves it holds the key, asks for a code to show.
async function offer(request, env, id) {
  const body = await readJson(request);
  if (!body || !isToken(body.token)) return json({ error: "bad request" }, 400);
  const room = env.ROOMS.get(env.ROOMS.idFromName(id));
  // The room learns the owner's token now, so a phone that claims before the Mac ever connects is let in.
  if (!(await room.adopt(body.token))) return json({ error: "reset" }, 410);
  return json(await codes(env).offer(id, body.token, str(body.name, 40), str(body.model, 40)));
}

/// POST /claim: a phone with the digits (or the QR's string) gets the room, once.
async function claim(request, env, url) {
  if (request.method !== "POST") return text("POST only", 405);
  const body = await readJson(request);
  if (!body || typeof body.code !== "string") return json({ error: "bad request" }, 400);
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  const device = str(body.device, 40) || "iPhone";
  const r = await codes(env).claim(body.code, ip);
  if (!r.ok) return json({ error: r.error }, r.status, r.retry ? { "retry-after": String(r.retry) } : {});
  try {
    await env.ROOMS.get(env.ROOMS.idFromName(r.id)).notifyPaired(device, Date.now());
  } catch (e) {
    console.log("paired notice not delivered", String(e));  // the phone has what it needs; the Mac learns at its next hello
  }
  return json({ id: r.id, token: r.token, name: r.name, model: r.model, host: url.host });
}

/// Every pairing offer and every wrong guess, for the whole relay: one object, because a code is
/// looked up without knowing the Mac. Offers live 10 minutes and are kept an hour longer, to tell a
/// late phone "expired" instead of "invalid". TTL, tries and window can be set (PAIR_TTL_MS,
/// PAIR_TRIES, PAIR_WINDOW_MS) so tests need not wait.
export class Codes extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    const sql = ctx.storage.sql;
    sql.exec("CREATE TABLE IF NOT EXISTS offers (code TEXT PRIMARY KEY, qr TEXT NOT NULL, room TEXT NOT NULL, token TEXT NOT NULL, name TEXT NOT NULL, model TEXT NOT NULL, expires INTEGER NOT NULL)");
    sql.exec("CREATE TABLE IF NOT EXISTS tries (ip TEXT NOT NULL, t INTEGER NOT NULL)");
  }

  /// A new offer for a room replaces its old one.
  offer(room, token, name, model) {
    const sql = this.ctx.storage.sql;
    const now = Date.now();
    const expires = now + knob(this.env.PAIR_TTL_MS, 600_000);
    sql.exec("DELETE FROM offers WHERE room = ? OR expires < ?", room, now - 3600_000);
    let code, qr;
    do code = randomString("0123456789", 6);
    while (sql.exec("SELECT 1 FROM offers WHERE code = ?", code).toArray().length);
    do qr = randomString("abcdefghijkmnpqrstuvwxyz23456789", 16);
    while (sql.exec("SELECT 1 FROM offers WHERE qr = ?", qr).toArray().length);
    sql.exec("INSERT INTO offers (code, qr, room, token, name, model, expires) VALUES (?, ?, ?, ?, ?, ?, ?)", code, qr, room, token, name, model, expires);
    return { code, qr, expires };
  }

  claim(input, ip) {
    const sql = this.ctx.storage.sql;
    const now = Date.now();
    const window = knob(this.env.PAIR_WINDOW_MS, 600_000);
    // A /64 is one household on IPv6, as an address is on IPv4.
    const who = ip.includes(":") ? ip.split(":").slice(0, 4).join(":") : ip;
    sql.exec("DELETE FROM tries WHERE t < ?", now - window);
    const recent = sql.exec("SELECT COUNT(*) AS n, MIN(t) AS first FROM tries WHERE ip = ?", who).one();
    if (recent.n >= knob(this.env.PAIR_TRIES, 8)) {
      return { ok: false, status: 429, error: "slow down", retry: Math.max(1, Math.ceil((recent.first + window - now) / 1000)) };
    }
    const wanted = input.trim().replace(/\s+/g, "").toLowerCase();
    // Against every offer, without stopping at a match, so the time says nothing about the digits.
    let hit = null;
    for (const o of sql.exec("SELECT * FROM offers").toArray()) {
      if (same(o.code, wanted) | same(o.qr, wanted)) hit = o;
    }
    if (!hit || hit.expires < now) {
      sql.exec("INSERT INTO tries (ip, t) VALUES (?, ?)", who, now);
      return hit ? { ok: false, status: 410, error: "expired" } : { ok: false, status: 404, error: "invalid" };
    }
    sql.exec("DELETE FROM offers WHERE code = ?", hit.code);
    return { ok: true, id: hit.room, token: hit.token, name: hit.name, model: hit.model };
  }

  forget(room) {
    this.ctx.storage.sql.exec("DELETE FROM offers WHERE room = ?", room);
  }
}

function randomString(alphabet, n) {
  const limit = 256 - (256 % alphabet.length);  // no modulo bias
  let out = "";
  while (out.length < n) {
    for (const byte of crypto.getRandomValues(new Uint8Array(n * 2))) {
      if (byte < limit && out.length < n) out += alphabet[byte % alphabet.length];
    }
  }
  return out;
}

// MARK: room

export class Room extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      const stored = await ctx.storage.get(["id", "owner", "state", "offlineAt", "oldPasses", "wiped", "queue", "paired", "devices", "pro", "pending"]);
      this.id = stored.get("id") ?? null;
      this.owner = stored.get("owner") ?? null;
      this.state = stored.get("state") ?? null;
      this.offlineAt = stored.get("offlineAt") ?? null;
      this.oldPasses = stored.get("oldPasses") ?? [];
      this.wiped = stored.get("wiped") ?? false;
      this.queue = stored.get("queue") ?? [];  // [{cmd, at}], for a Mac that is offline
      this.notice = stored.get("paired") ?? null;  // {device, at}, for a Mac that is offline
      this.devices = stored.get("devices") ?? [];
      this.pro = stored.get("pro") ?? false;
      this.pending = stored.get("pending") ?? null;  // {due, pass, items}: the alarm alert, waiting for a photo
    });
  }

  async fetch(request) {
    const url = new URL(request.url);
    const [, route, a, b] = url.pathname.split("/");
    const t = url.searchParams.get("t") ?? "";
    await this.learn(BY_KEY.has(route) ? await viewId(a) : a);
    switch (route) {
      case "cam": return this.connectCam();
      case "watch": return this.connectViewer(t);
      case "state": return this.snapshot(t);
      case "photo": return this.storePhoto(request, url);
      case "p": return this.servePhoto(Number(b), t);
      case "wipe": return this.wipe();
      case "cmd": return this.command(request, t);
      case "h": return request.method === "DELETE" ? this.erase(t, b) : this.history(t);
      case "device": return request.method === "DELETE" ? this.unregister(t, b) : this.register(request, t);
      case "test-push": return this.testPush(t);
    }
    return text("not found", 404);
  }

  /// The room's own id, which only the paths say; the pushes carry it.
  async learn(id) {
    if (this.id === id) return;
    this.id = id;
    await this.ctx.storage.put("id", id);
  }

  /// The Mac proves it holds the key by asking for a code; its token becomes the owner's.
  async adopt(token) {
    if (this.wiped) return false;
    if (this.owner !== token) {
      this.owner = token;
      await this.ctx.storage.put("owner", token);
      this.refresh();
    }
    return true;
  }

  /// A phone claimed a code: the Mac hears of it now, or at its next hello.
  async notifyPaired(device, at) {
    if (this.wiped) return;
    const notice = { device, at };
    const cams = this.ctx.getWebSockets("cam");
    if (cams.length) {
      try {
        for (const cam of cams) cam.send(JSON.stringify({ paired: notice }));
        return;
      } catch {}
    }
    this.notice = notice;
    await this.ctx.storage.put("paired", notice);
  }

  // MARK: sockets

  async connectCam() {
    const wasOnline = this.ctx.getWebSockets("cam").length > 0;
    for (const old of this.ctx.getWebSockets("cam")) old.close(1000, "replaced");
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server, ["cam"]);
    this.offlineAt = null;
    this.ctx.storage.delete("offlineAt");
    this.refresh();
    if (!wasOnline && this.state) await this.notify(this.state, this.state, { wasOnline: false });
    return new Response(null, { status: 101, webSocket: client });
  }

  connectViewer(t) {
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server, ["viewer"]);
    server.serializeAttachment({ t: t.slice(0, 64), level: null });
    this.refresh();
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, message) {
    if (!this.ctx.getTags(ws).includes("cam")) return this.fromViewer(ws, message);
    if (typeof message !== "string") {
      if (message.byteLength > MAX_FRAME || this.state?.phase !== "triggered") return;
      for (const viewer of this.ctx.getWebSockets("viewer")) {
        if (seesCamera(viewer.deserializeAttachment()?.level)) try { viewer.send(message); } catch {}
      }
      return;
    }
    if (message.length > MAX_FRAME) return;
    let msg;
    try { msg = JSON.parse(message); } catch { return; }
    let greet = false;
    if (msg.hello && isToken(msg.hello.token)) {
      if (msg.hello.token !== this.owner) {
        this.owner = msg.hello.token;
        await this.ctx.storage.put("owner", this.owner);
      }
      greet = msg.hello.v >= 3;  // a Mac that does not know commands is not sent any
    }
    let change = null;
    if (msg.state && typeof msg.state === "object") {
      const previous = this.state?.pass;
      const next = clean(msg.state);
      if (previous && previous !== next.pass && !this.oldPasses.includes(previous)) {
        this.oldPasses = [...this.oldPasses, previous].slice(-10);
        await this.ctx.storage.put("oldPasses", this.oldPasses);
      }
      change = { prev: this.state, next };
      this.state = next;
      await this.ctx.storage.put("state", this.state);
    }
    if (msg.session && typeof msg.session === "object") this.storeSession(msg.session);
    if (msg.ack && typeof msg.ack === "object") {
      this.tellOwners({ ack: { id: str(msg.ack.id, 24), ok: msg.ack.ok === true, ...(msg.ack.why ? { why: str(msg.ack.why, 24) } : {}) } });
    }
    if (greet) await this.greet(ws);
    this.refresh();
    if (change) await this.notify(change.prev, change.next);
  }

  /// A phone's text frame: only `{"cmd": {...}}` means anything, and only from the owner.
  async fromViewer(ws, message) {
    if (typeof message !== "string" || message.length > 4096) return;
    let msg;
    try { msg = JSON.parse(message); } catch { return; }
    if (!msg?.cmd || typeof msg.cmd !== "object") return;
    const id = str(msg.cmd.id, 24);
    const refuse = (why) => { try { ws.send(JSON.stringify({ ack: { id, ok: false, why } })); } catch {} };
    if (!this.isOwner(ws.deserializeAttachment()?.t ?? "")) return refuse("forbidden");
    const cmd = cleanCommand(msg.cmd);
    if (!cmd) return refuse("bad-command");
    await this.dispatch(cmd);
  }

  async webSocketClose(ws) {
    await this.gone(ws);
  }

  async webSocketError(ws) {
    await this.gone(ws);
  }

  async gone(ws) {
    if (this.ctx.getTags(ws).includes("cam") && this.ctx.getWebSockets("cam").every((w) => w === ws)) {
      this.offlineAt = Date.now();
      await this.ctx.storage.put("offlineAt", this.offlineAt);
      this.refresh(ws);
      if (this.state) await this.notify(this.state, this.state, { online: false, wasOnline: true });
      return;
    }
    this.refresh(ws);
  }

  /// What a token may see: everything (the owner, or anyone in a room from before v2), this alarm
  /// (its pass, until the disarm), or only whether the Mac is guarded.
  level(t) {
    if (this.wiped) return "reset";
    if (!this.owner) return "owner";
    if (t && same(t, this.owner)) return "owner";
    if (t && this.state?.pass && same(t, this.state.pass) && this.state.phase === "triggered") return "pass";
    if (t && this.oldPasses.includes(t)) return "expired";
    return "status";
  }

  /// Who may send commands, change devices and read the history. Unlike `level`, never a room that
  /// has no owner yet.
  isOwner(t) {
    return !this.wiped && this.owner !== null && t !== "" && same(t, this.owner);
  }

  /// Tells each page what it may see, and the Mac how many pages may see the camera.
  refresh(gone) {
    const cams = this.ctx.getWebSockets("cam").filter((w) => w !== gone);
    const viewers = this.ctx.getWebSockets("viewer").filter((w) => w !== gone);
    const photos = this.photoList();
    let watching = 0;
    for (const viewer of viewers) {
      const seen = viewer.deserializeAttachment() ?? { t: "" };
      const level = this.level(seen.t);
      if (level !== seen.level) viewer.serializeAttachment({ ...seen, level });
      if (seesCamera(level)) watching++;
      try { viewer.send(JSON.stringify(this.view(level, seen.t, cams.length > 0, photos))); } catch {}
    }
    for (const cam of cams) try { cam.send(JSON.stringify({ viewers: watching })); } catch {}
  }

  view(level, t, online, photos) {
    const s = this.state;
    const base = { v: 3, level, online, offlineAt: this.offlineAt };
    if (level === "reset" || level === "expired") return base;
    if (level === "status") return { ...base, state: s ? { phase: s.phase === "idle" ? "idle" : "armed", since: s.since } : null };
    const { pass, ...visible } = s ?? {};
    const mine = level === "owner" ? photos : photos.filter((p) => p.pass === t);
    // An alarm's pass is for its photos and its story, not for the Mac's battery or settings.
    const shown = level === "owner" ? visible : { ...visible, mac: null, health: null, lastEnd: null };
    return { ...base, state: s ? shown : null, photos: mine.map((p) => p.t) };
  }

  /// GET /state: the first frame of /watch, for the widgets, the Watch and background refreshes. A
  /// token that opens nothing is refused here (a socket shows it the status view instead).
  snapshot(t) {
    if (!this.owner && !this.state && !this.wiped) return json({ error: "not found" }, 404, CORS);
    const level = this.level(t);
    if (level === "status" && t) return json({ error: "forbidden" }, 403, CORS);
    return json(this.view(level, t, this.ctx.getWebSockets("cam").length > 0, this.photoList()), 200, CORS);
  }

  /// Sends to every phone that is the owner's.
  tellOwners(frame) {
    const body = JSON.stringify(frame);
    for (const viewer of this.ctx.getWebSockets("viewer")) {
      if (this.isOwner(viewer.deserializeAttachment()?.t ?? "")) try { viewer.send(body); } catch {}
    }
  }

  // MARK: commands

  /// POST /cmd/<id>
  async command(request, t) {
    if (!this.isOwner(t)) return json({ error: "forbidden" }, 403);
    const cmd = cleanCommand(await readJson(request));
    if (!cmd) return json({ error: "bad command" }, 400);
    return json({ ok: true, delivered: await this.dispatch(cmd) });
  }

  /// To the Mac if it is here, otherwise into the queue (8 at most, the oldest dropped).
  async dispatch(cmd) {
    const cams = this.ctx.getWebSockets("cam");
    if (cams.length) {
      try {
        for (const cam of cams) cam.send(JSON.stringify({ cmd, from: "phone" }));
        return true;
      } catch {}
    }
    this.queue = [...this.queue, { cmd, at: Date.now() }].slice(-QUEUE_KEPT);
    await this.ctx.storage.put("queue", this.queue);
    return false;
  }

  /// A start is stale after 30 s: nobody wants a Mac that begins guarding when it wakes up an hour
  /// later. The rest keep for 10 minutes.
  ttl(kind) {
    return kind === "start" ? knob(this.env.START_TTL_MS, 30_000) : knob(this.env.CMD_TTL_MS, 600_000);
  }

  /// The Mac said hello with v3: what waited for it is delivered, in order. The owner's phone is told
  /// of each command that went stale.
  async greet(ws) {
    if (this.notice) {
      try {
        ws.send(JSON.stringify({ paired: this.notice }));
        this.notice = null;
        await this.ctx.storage.delete("paired");
      } catch {}
    }
    if (!this.queue.length) return;
    const queue = this.queue;
    this.queue = [];
    await this.ctx.storage.delete("queue");
    const now = Date.now();
    for (const { cmd, at } of queue) {
      if (now - at > this.ttl(cmd.k)) {
        this.tellOwners({ ack: { id: cmd.id, ok: false, why: "expired" } });
        continue;
      }
      try { ws.send(JSON.stringify({ cmd, from: "phone" })); } catch {}
    }
  }

  // MARK: photos

  table() {
    const sql = this.ctx.storage.sql;
    sql.exec("CREATE TABLE IF NOT EXISTS photos (t INTEGER PRIMARY KEY, pass TEXT, data BLOB)");
    sql.exec('CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, "end" INTEGER, json TEXT)');
  }

  photoList() {
    this.table();
    return this.ctx.storage.sql.exec("SELECT t, pass FROM photos ORDER BY t DESC").toArray();
  }

  latestPhoto(pass) {
    if (!pass) return null;
    this.table();
    return this.ctx.storage.sql.exec("SELECT MAX(t) AS t FROM photos WHERE pass = ?", pass).one().t ?? null;
  }

  /// 7 days, or 30 when a registered device says it has Pro.
  keepMs() {
    return (this.pro ? 30 : 7) * DAY;
  }

  purge() {
    this.table();
    this.ctx.storage.sql.exec("DELETE FROM photos WHERE t < ?", Date.now() - this.keepMs());
  }

  async storePhoto(request, url) {
    if (this.wiped) return text("reset", 410);
    const t = Number(url.searchParams.get("t"));
    const pass = url.searchParams.get("pass") ?? "";
    if (!Number.isSafeInteger(t) || t <= 0) return text("bad time", 400);
    const data = await request.arrayBuffer();
    if (data.byteLength === 0 || data.byteLength > MAX_PHOTO) return text("photo too large", 413);
    this.table();
    const kept = TOKEN.test(pass) ? pass : "";
    const sql = this.ctx.storage.sql;
    sql.exec("INSERT OR REPLACE INTO photos (t, pass, data) VALUES (?, ?, ?)", t, kept, data);
    sql.exec("DELETE FROM photos WHERE pass = ? AND t NOT IN (SELECT t FROM photos WHERE pass = ? ORDER BY t DESC LIMIT ?)", kept, kept, PHOTOS_PER_ALARM);
    sql.exec("DELETE FROM photos WHERE t NOT IN (SELECT t FROM photos ORDER BY t DESC LIMIT ?)", PHOTOS_PER_ROOM);
    this.purge();
    if (this.pending && this.pending.pass === kept) {
      await this.flush(t);
    } else {
      await this.reschedule();
      if (kept && this.state?.phase === "triggered" && this.state.pass === kept) {
        await this.notify(this.state, this.state, { force: true });  // the Live Activity learns of the photo
      }
    }
    this.refresh();
    return text("ok", 200);
  }

  servePhoto(t, token) {
    const level = this.level(token);
    if (level !== "owner" && level !== "pass") return text("not found", 404);
    this.table();
    const row = this.ctx.storage.sql.exec("SELECT pass, data FROM photos WHERE t = ?", t).toArray()[0];
    if (!row || (level === "pass" && row.pass !== token)) return text("not found", 404);
    return new Response(row.data, { headers: { "content-type": "image/jpeg", "cache-control": "private, max-age=86400", "referrer-policy": "no-referrer" } });
  }

  /// The room's one alarm clock, set to the earlier of the next photo to expire and the alarm alert
  /// that waits for a photo. A Durable Object alarm and not a setTimeout: it survives the object
  /// being evicted or restarted in those 2.5 s, and a lost alarm alert is the one failure that matters.
  async reschedule() {
    this.table();
    const due = [];
    if (this.pending) due.push(this.pending.due);
    const oldest = this.ctx.storage.sql.exec("SELECT MIN(t) AS t FROM photos").one().t;
    if (oldest) due.push(oldest + this.keepMs());
    if (due.length) await this.ctx.storage.setAlarm(Math.min(...due));
    else await this.ctx.storage.deleteAlarm();
  }

  /// Photos past their time go, and the alarm alert that waited long enough goes without one.
  async alarm() {
    if (this.pending && Date.now() >= this.pending.due - 25) await this.flush(this.latestPhoto(this.pending.pass));
    this.purge();
    await this.reschedule();
    this.refresh();
  }

  // MARK: history

  storeSession(raw) {
    const s = cleanSession(raw);
    if (!s) return;
    this.table();
    const sql = this.ctx.storage.sql;
    sql.exec('INSERT OR REPLACE INTO sessions (id, "end", json) VALUES (?, ?, ?)', s.id, s.end, JSON.stringify(s));
    sql.exec(`DELETE FROM sessions WHERE id NOT IN (SELECT id FROM sessions ORDER BY "end" DESC LIMIT ${SESSIONS_KEPT})`);
  }

  /// GET /h/<id>: newest first, each with the photos the room still has.
  history(t) {
    if (!this.isOwner(t)) return json({ error: "forbidden" }, 403);
    this.table();
    const have = new Set(this.photoList().map((p) => p.t));
    const sessions = this.ctx.storage.sql.exec('SELECT json FROM sessions ORDER BY "end" DESC').toArray().map((row) => {
      const s = JSON.parse(row.json);
      return { ...s, photos: s.photos.filter((p) => have.has(p)) };
    });
    return json({ sessions });
  }

  /// DELETE /h/<id>/<session>: the session and its photos. DELETE /h/<id>: every photo, and the list stays.
  async erase(t, id) {
    if (!this.isOwner(t)) return json({ error: "forbidden" }, 403);
    this.table();
    const sql = this.ctx.storage.sql;
    if (id) {
      const row = sql.exec("SELECT json FROM sessions WHERE id = ?", id).toArray()[0];
      if (row) {
        const s = JSON.parse(row.json);
        sql.exec("DELETE FROM photos WHERE t >= ? AND t <= ?", s.start, s.end);
        for (const p of s.photos) sql.exec("DELETE FROM photos WHERE t = ?", p);
        sql.exec("DELETE FROM sessions WHERE id = ?", id);
      }
    } else {
      sql.exec("DELETE FROM photos");
    }
    await this.reschedule();
    this.refresh();
    return json({ ok: true });
  }

  // MARK: devices and push

  /// POST /device/<id>: the app says how to reach it. The seventh device replaces the one that
  /// registered longest ago, because a reinstall brings a new id.
  async register(request, t) {
    if (!this.isOwner(t)) return json({ error: "forbidden" }, 403);
    const device = cleanDevice(await readJson(request), request.cf?.timezone);
    if (!device) return json({ error: "bad device" }, 400);
    device.seen = Date.now();
    this.devices = [...this.devices.filter((d) => d.dev !== device.dev), device]
      .sort((x, y) => y.seen - x.seen)
      .slice(0, DEVICES_KEPT);
    await this.saveDevices();
    return json({ ok: true });
  }

  async unregister(t, dev) {
    if (!this.isOwner(t)) return json({ error: "forbidden" }, 403);
    this.devices = this.devices.filter((d) => d.dev !== dev);
    await this.saveDevices();
    return json({ ok: true });
  }

  async saveDevices() {
    const pro = this.devices.some((d) => d.pro);
    await this.ctx.storage.put({ devices: this.devices, pro });
    if (pro !== this.pro) {
      this.pro = pro;
      this.purge();
      await this.reschedule();
      this.refresh();
    }
  }

  /// POST /test-push/<id>: "send a test alert".
  async testPush(t) {
    if (!this.isOwner(t)) return json({ error: "forbidden" }, 403);
    if (!apns.configured(this.env)) return json({ error: "push not configured" }, 501);
    const sends = this.devices.filter((d) => d.apns).map((device) =>
      apns.sendPush(this.env, device, { type: "alert", token: device.apns, priority: 10, ttl: 300, body: apns.testAlert({ id: this.id, device }) }));
    const results = await Promise.all(sends);
    return json({ ok: true, sent: results.filter((r) => r.ok).length, failed: results.filter((r) => !r.ok).length });
  }

  /// A state changed (or the Mac went away or came back): the pushes that calls for. Nothing at all
  /// without the APNS_* secrets. The alarm alert is held for the first photo, up to 2.5 s.
  async notify(prev, next, { online = true, wasOnline = online, force = false } = {}) {
    if (!apns.configured(this.env) || this.devices.length === 0) return;
    await this.flush();  // an alert still waiting for its photo goes first, so they arrive in order
    const photo = this.latestPhoto(next.pass);
    const pushes = apns.plan({ id: this.id, prev, next, devices: this.devices, online, wasOnline, photo, force, now: Date.now() });
    const held = pushes.filter((p) => p.wait);
    if (held.length) {
      this.pending = { due: Date.now() + apns.PHOTO_WAIT_MS, pass: next.pass, items: held };
      await this.ctx.storage.put("pending", this.pending);
      await this.reschedule();
    }
    await this.deliver(pushes.filter((p) => !p.wait));
  }

  /// Sends the held alert, with the photo's time if there is one.
  async flush(photo = null) {
    const pending = this.pending;
    if (!pending) return;
    this.pending = null;
    await this.ctx.storage.delete("pending");
    for (const item of pending.items) if (photo) item.body.photo = photo;
    await this.reschedule();
    await this.deliver(pending.items);
  }

  async deliver(pushes) {
    const results = await Promise.all(pushes.map(async (push) => {
      const device = this.devices.find((d) => d.dev === push.dev);
      return { push, result: device ? await apns.sendPush(this.env, device, push) : null };
    }));
    // Apple says this token is gone for good, or the activity it updated just ended: stop using it,
    // so the next session starts a new activity with laStart instead of updating the old one.
    const dead = results.filter(({ push, result }) => result?.status === 410 || (push.field === "la" && push.body?.aps?.event === "end"));
    if (!dead.length) return;
    for (const { push } of dead) {
      const device = this.devices.find((d) => d.dev === push.dev);
      if (device) device[push.field] = null;
    }
    await this.saveDevices();
  }

  /// The owner reset the link: forget everything, and tell open pages the link is gone.
  async wipe() {
    this.table();
    this.ctx.storage.sql.exec("DELETE FROM photos");
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
    this.owner = null;
    this.state = null;
    this.offlineAt = null;
    this.oldPasses = [];
    this.queue = [];
    this.notice = null;
    this.devices = [];
    this.pro = false;
    this.pending = null;
    this.wiped = true;
    await this.ctx.storage.put("wiped", true);
    this.refresh();
    for (const ws of this.ctx.getWebSockets()) try { ws.close(1000, "reset"); } catch {}
    return text("ok", 200);
  }
}

function seesCamera(level) {
  return level === "owner" || level === "pass";
}

function cleanEvents(list) {
  const events = Array.isArray(list) ? list.slice(-40) : [];
  return events.map((e) => ({ t: num(e?.t), e: str(e?.e, 16), k: str(e?.k, 16) || null }));
}

/// Only the fields the page shows, with sane types, from whatever the Mac sent. A Mac from before
/// v3 says nothing of the new ones: its `siren` becomes `stage: "siren"`, a triggered state without
/// a stage is `soft`, and `v` stays 2 so the app knows to offer no commands.
function clean(s) {
  const phase = ["idle", "arming", "armed", "triggered"].includes(s.phase) ? s.phase : "idle";
  const siren = s.siren === true;
  const mac = s.mac && typeof s.mac === "object" ? s.mac : null;
  const health = s.health && typeof s.health === "object" ? s.health : null;
  return {
    v: s.v >= 3 ? 3 : 2,
    phase,
    since: num(s.since),
    armEnd: num(s.armEnd),
    lastEnd: num(s.lastEnd) || null,
    place: str(s.place, 16),
    note: str(s.note, 48),
    vol: Number.isFinite(s.vol) ? clamp(Math.round(s.vol), 0, 100) : 100,
    test: s.test === true,
    camera: s.camera === true,
    push: s.push === true,
    trigger: str(s.trigger, 16) || null,
    at: num(s.at) || null,
    siren,
    stage: phase !== "triggered" ? null : STAGES.includes(s.stage) ? s.stage : siren ? "siren" : "soft",
    softEnd: num(s.softEnd) || null,
    carried: s.carried === true,
    bumps: num(s.bumps),
    mac: mac && { name: str(mac.name, 40), model: str(mac.model, 40), batt: Number.isFinite(mac.batt) ? clamp(Math.round(mac.batt), 0, 100) : null, chg: mac.chg === true },
    health: health && { ax: health.ax === true, cam: health.cam === true, lid: health.lid === true, mot: health.mot === true },
    events: cleanEvents(s.events),
    pass: isToken(s.pass) ? s.pass : null,
  };
}

/// One finished session, as the history keeps it. Without an id and an end there is nothing to keep.
function cleanSession(s) {
  if (typeof s.id !== "string" || !SESSION.test(s.id) || !(num(s.end) > 0)) return null;
  const count = (v) => Math.max(0, Math.round(num(v)));
  return {
    id: s.id,
    start: num(s.start),
    end: num(s.end),
    place: str(s.place, 16),
    bumps: count(s.bumps),
    kind: ["quiet", "alarm", "test"].includes(s.kind) ? s.kind : "quiet",
    trigger: str(s.trigger, 16) || null,
    at: num(s.at) || null,
    how: str(s.how, 16) || null,
    soft: count(s.soft),
    siren: count(s.siren),
    photos: (Array.isArray(s.photos) ? s.photos : []).filter(Number.isFinite).slice(-12),
    events: cleanEvents(s.events),
    clip: str(s.clip, 80) || null,
  };
}

/// A command from the owner's phone, or null. Only what its kind uses is kept.
function cleanCommand(c) {
  if (!c || typeof c !== "object" || typeof c.id !== "string" || c.id.length < 1 || c.id.length > 24 || !KINDS.includes(c.k)) return null;
  const cmd = { id: c.id, k: c.k };
  const take = (...names) => {
    for (const name of names) {
      const v = c[name];
      if (name === "place" && PLACES.includes(v)) cmd.place = v;
      else if (name === "note" && typeof v === "string") cmd.note = v.slice(0, 48);
      else if (name === "test" && typeof v === "boolean") cmd.test = v;
      else if (name === "vol" && Number.isFinite(v)) cmd.vol = clamp(Math.round(v), 0, 100);
      else if (name === "by" && typeof v === "string") cmd.by = v.slice(0, 16);
    }
  };
  if (c.k === "start") take("place", "note", "test");
  if (c.k === "set") take("place", "note", "vol", "test");
  if (c.k === "disarm") take("by");
  return cmd;
}

/// A device's registration, or null. Its preferences have defaults, so an old app that does not
/// know a switch leaves it as it is.
function cleanDevice(d, requestZone) {
  if (!d || typeof d.dev !== "string" || !DEVICE.test(d.dev)) return null;
  const token = (v) => (v === undefined || v === null ? null : typeof v === "string" && HEX.test(v) ? v.toLowerCase() : false);
  const apnsToken = token(d.apns), la = token(d.la), laStart = token(d.laStart);
  if (apnsToken === false || la === false || laStart === false) return null;
  const events = {};
  for (const [name, fallback] of Object.entries(apns.DEFAULT_EVENTS)) events[name] = typeof d.events?.[name] === "boolean" ? d.events[name] : fallback;
  return {
    dev: d.dev,
    name: str(d.name, 40),
    apns: apnsToken,
    env: d.env === "sandbox" ? "sandbox" : "production",
    lang: d.lang === "zh" ? "zh" : "en",
    crit: d.crit === true,
    pro: d.pro === true,
    events,
    la,
    laStart,
    tz: zone(d.tz) ?? zone(requestZone) ?? "UTC",
  };
}

/// An IANA time zone name the runtime knows, or undefined. Alerts show the time of day in it.
function zone(name) {
  if (typeof name !== "string" || name.length > 64) return undefined;
  try {
    new Intl.DateTimeFormat("en", { timeZone: name });
    return name;
  } catch {
    return undefined;
  }
}

const PAGE = `<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex">
<meta name="referrer" content="no-referrer">
<meta name="theme-color" content="#0b0f1c">
<title>BRB</title>
<style>
  :root {
    --bg: #0b0f1c; --ink: #eef1f8; --dim: rgba(238, 241, 248, .62); --faint: rgba(238, 241, 248, .38);
    --glass: rgba(255, 255, 255, .07); --rim: rgba(255, 255, 255, .14);
    --amber: #f6b544; --red: #ff4d55; --green: #3ef07a;
    color-scheme: dark;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; background: var(--bg); color: var(--ink); }
  body {
    font: 15px/1.45 -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", sans-serif;
    min-height: 100vh; padding: calc(14px + env(safe-area-inset-top)) 16px calc(28px + env(safe-area-inset-bottom));
    background: radial-gradient(120% 60% at 50% 0%, #1b2440 0%, var(--bg) 60%) fixed;
  }
  main { max-width: 480px; margin: 0 auto; display: grid; gap: 14px; }
  header { display: flex; align-items: center; gap: 10px; padding: 4px 2px 6px; }
  header svg { width: 26px; height: 26px; flex: none; }
  header h1 { font-size: 17px; font-weight: 600; margin: 0; flex: 1; }
  .pill { font-size: 12px; font-weight: 600; padding: 4px 10px; border-radius: 99px; background: var(--glass); color: var(--dim); white-space: nowrap; }
  .pill.on { color: var(--amber); background: rgba(246, 181, 68, .14); }
  .pill.alarm { color: #fff; background: var(--red); }
  .card { background: var(--glass); border: 1px solid var(--rim); border-radius: 22px; padding: 18px; backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px); }
  .card h2 { font-size: 22px; line-height: 1.25; margin: 0 0 4px; font-weight: 650; text-wrap: balance; }
  .card p { margin: 0; color: var(--dim); }
  .row { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
  .chip { font-size: 13px; padding: 6px 12px; border-radius: 99px; background: rgba(255, 255, 255, .08); border: 1px solid var(--rim); color: var(--ink); display: inline-flex; align-items: center; gap: 7px; }
  .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--green); box-shadow: 0 0 8px var(--green); }
  .dot.red { background: var(--red); box-shadow: 0 0 8px var(--red); border: 1.5px solid #fff; }
  .alarm { background: linear-gradient(180deg, rgba(255, 77, 85, .28), rgba(160, 16, 30, .22)); border-color: rgba(255, 110, 118, .5); }
  .alarm h2 { font-size: 24px; }
  .live { position: relative; border-radius: 22px; overflow: hidden; background: #000; aspect-ratio: 16 / 9; border: 1px solid var(--rim); }
  .live img { width: 100%; height: 100%; object-fit: cover; display: block; }
  .live .tag { position: absolute; left: 10px; top: 10px; font-size: 12px; font-weight: 700; padding: 4px 9px; border-radius: 99px; background: var(--red); color: #fff; letter-spacing: .04em; }
  .live .tag.stale { background: rgba(0, 0, 0, .6); color: var(--dim); font-weight: 600; letter-spacing: 0; }
  .live .empty { position: absolute; inset: 0; display: grid; place-items: center; color: var(--faint); font-size: 14px; padding: 16px; text-align: center; }
  h3 { font-size: 13px; font-weight: 600; color: var(--faint); margin: 6px 4px 0; letter-spacing: .02em; }
  .photos { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; }
  .photos a { display: block; aspect-ratio: 4 / 3; border-radius: 14px; overflow: hidden; background: #000; border: 1px solid var(--rim); }
  .photos img { width: 100%; height: 100%; object-fit: cover; display: block; }
  ol.timeline { list-style: none; margin: -6px 0; padding: 0; }
  ol.timeline li { display: flex; gap: 12px; padding: 10px 0; border-bottom: 1px solid rgba(255, 255, 255, .07); }
  ol.timeline li:last-child { border-bottom: 0; }
  ol.timeline time { color: var(--faint); font-variant-numeric: tabular-nums; min-width: 3.6em; }
  ol.timeline .hot { color: #ff8a90; }
  .test { color: #241700; background: var(--amber); border: 0; font-weight: 600; }
  footer { text-align: center; color: var(--faint); font-size: 12.5px; margin-top: 8px; }
  [hidden] { display: none !important; }
</style>
<main>
  <header>
    <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.8 19.4 5.6v5.8c0 4.8-3.1 8.6-7.4 10.1-4.3-1.5-7.4-5.3-7.4-10.1V5.6Z" fill="#f6b544"/><circle cx="12" cy="11.4" r="2.4" fill="#2b1a00"/></svg>
    <h1>BRB</h1>
    <span class="pill" id="pill"></span>
  </header>
  <div class="live" id="live" hidden><img id="frame" alt=""><span class="tag" id="age"></span><div class="empty" id="waiting"></div></div>
  <section class="card" id="card"><h2 id="title"></h2><p id="sub"></p><div class="row" id="chips"></div></section>
  <h3 id="photosLabel" hidden></h3>
  <div class="photos" id="photos" hidden></div>
  <h3 id="timelineLabel" hidden></h3>
  <section class="card" id="timelineCard" hidden><ol class="timeline" id="timeline"></ol></section>
  <footer id="footer"></footer>
</main>
<script>
  const zh = (navigator.languages || [navigator.language]).some((l) => /^zh/i.test(l || ""));
  const T = zh ? {
    connecting: "连接中…", off: "未警戒", guarding: "警戒中", alarm: "已报警", offline: "离线", arming: "即将开始",
    guardedTitle: "电脑正在警戒", guardedSince: (t) => t + " 起开始警戒", notGuarding: "现在没有警戒",
    beforeAlarm: "报警后才会有画面", onlyStatus: "这个链接只能看电脑有没有在警戒。完整的页面在电脑的菜单栏面板里。",
    expiredTitle: "这个报警链接已失效", expiredSub: "它只在报警解除之前有效。照片可以在电脑面板里的手机页面链接看到。",
    resetTitle: "这个链接已被重置", resetSub: "在电脑的菜单栏面板里重新扫码。",
    offlineSince: (t) => "电脑 " + t + " 起离线：可能断网了，或者合上了盖子",
    live: "实时", stale: (s) => s + " 秒前的画面", waiting: "等画面…", noCamera: "这次没有开摄像头",
    siren: "警笛在响", soft: "已锁屏，10 秒后响警笛", testSilent: "测试 · 不出声", recording: "正在录像",
    photos: "照片", timeline: "经过", lastAlarm: "上次报警：", then: "。",
    places: { library: "图书馆", cafe: "咖啡馆", transit: "路上" },
    headline: { lifted: "电脑被拿起来了", tilted: "电脑被挪动了", lidClosed: "屏幕被合上了", lidMoved: "屏幕被掰动了", charger: "电源被拔掉了", powerKey: "有人按了电源键", keyboard: "有人碰了键盘", trackpad: "有人碰了触控板", finger: "有人试了指纹", restarted: "程序重启后继续报警" },
    event: { armed: "开始警戒", photo: "拍了一张照片", siren: "警笛响了", warning: "运动传感器停了", cancelled: "取消了" },
    disarm: { fingerprint: "用指纹解除", unlock: "解锁后解除", password: "用指纹或密码解除", escape: "取消了", stopped: "警戒被停止", sensorsSilent: "传感器没有数据，已停止", tapFailed: "为了监听键盘而重启" },
    disarmed: "已解除", footer: "这个页面只能看，不能控制电脑",
  } : {
    connecting: "Connecting…", off: "Off", guarding: "Guarding", alarm: "Alarm", offline: "Offline", arming: "Starting",
    guardedTitle: "Your Mac is guarded", guardedSince: (t) => "Guarding since " + t, notGuarding: "Not guarding right now",
    beforeAlarm: "There's only a picture after an alarm", onlyStatus: "This link only shows whether the Mac is guarded. The full page is in the Mac's menu-bar panel.",
    expiredTitle: "This alarm link has expired", expiredSub: "It works until the alarm is disarmed. The photos are on the phone-page link in the Mac's panel.",
    resetTitle: "This link was reset", resetSub: "Scan the code in the Mac's menu-bar panel again.",
    offlineSince: (t) => "The Mac has been offline since " + t + ": no network, or the lid is shut",
    live: "LIVE", stale: (s) => "Picture from " + s + " s ago", waiting: "Waiting for the picture…", noCamera: "The camera is off this time",
    siren: "The siren is sounding", soft: "Screen locked, siren in 10 s", testSilent: "Test · silent", recording: "Recording",
    photos: "Photos", timeline: "What happened", lastAlarm: "Last alarm: ", then: ". ",
    places: { library: "Library", cafe: "Café", transit: "On the go" },
    headline: { lifted: "Your Mac was picked up", tilted: "Your Mac was moved", lidClosed: "The lid was closed", lidMoved: "The lid was moved", charger: "The charger was unplugged", powerKey: "The power button was pressed", keyboard: "Someone touched the keyboard", trackpad: "Someone touched the trackpad", finger: "Someone tried a fingerprint", restarted: "The alarm resumed after a restart" },
    event: { armed: "Guarding started", photo: "Took a photo", siren: "The siren started", warning: "The motion sensor stopped", cancelled: "Cancelled" },
    disarm: { fingerprint: "Disarmed with Touch ID", unlock: "Disarmed by unlocking", password: "Disarmed with Touch ID or password", escape: "Cancelled", stopped: "Guarding was stopped", sensorsSilent: "Stopped: the sensors sent no data", tapFailed: "Restarted to watch the keyboard" },
    disarmed: "Disarmed", footer: "This page can only watch. It can't control the Mac.",
  };
  document.documentElement.lang = zh ? "zh-Hans" : "en";
  const $ = (id) => document.getElementById(id);
  const id = location.pathname.split("/")[2];
  const token = location.hash.slice(1);
  const clock = new Intl.DateTimeFormat(zh ? "zh-CN" : undefined, { hour: "numeric", minute: "2-digit" });
  const day = new Intl.DateTimeFormat(zh ? "zh-CN" : undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
  const when = (ms) => (new Date(ms).toDateString() === new Date().toDateString() ? clock : day).format(ms);
  let view = null, lastFrame = 0, shown = null, pending = null, socket = null;
  $("footer").textContent = T.footer;
  $("photosLabel").textContent = T.photos;
  $("timelineLabel").textContent = T.timeline;
  document.title = "BRB";

  function chip(text, cls) {
    const el = document.createElement("span");
    el.className = "chip" + (cls ? " " + cls : "");
    if (cls === "rec") { const d = document.createElement("span"); d.className = "dot red"; el.append(d); el.className = "chip"; }
    if (cls === "green") { const d = document.createElement("span"); d.className = "dot"; el.append(d); el.className = "chip"; }
    el.append(text);
    return el;
  }

  function render() {
    const v = view, s = v?.state;
    const phase = s?.phase ?? "idle";
    const triggered = phase === "triggered";
    const pill = $("pill"), card = $("card"), chips = $("chips");
    chips.replaceChildren();
    card.className = "card";
    pill.className = "pill";
    $("live").hidden = true;
    let title = T.connecting, sub = "";
    if (!v) {
      pill.textContent = "…";
    } else if (v.level === "reset") {
      title = T.resetTitle; sub = T.resetSub; pill.textContent = T.off;
    } else if (v.level === "expired") {
      title = T.expiredTitle; sub = T.expiredSub; pill.textContent = T.off;
    } else if (triggered) {
      pill.textContent = T.alarm; pill.className = "pill alarm";
      card.className = "card alarm";
      title = T.headline[s.trigger] ?? T.alarm;
      sub = (s.at ? when(s.at) + " · " : "") + (s.siren ? T.siren : T.soft);
      if (s.camera) chips.append(chip(T.recording, "rec"));
      if (s.test) chips.append(chip(T.testSilent, "test"));
      $("live").hidden = !s.camera && !lastFrame;
      $("waiting").textContent = s.camera ? T.waiting : T.noCamera;
    } else if (phase === "armed" || phase === "arming") {
      pill.textContent = phase === "armed" ? T.guarding : T.arming; pill.className = "pill on";
      title = T.guardedTitle;
      sub = s.since ? T.guardedSince(when(s.since)) : "";
      if (v.level !== "status") {
        if (s.place && T.places[s.place]) chips.append(chip(T.places[s.place]));
        if (s.note) chips.append(chip("“" + s.note + "”"));
        if (s.test) chips.append(chip(T.testSilent, "test"));
        chips.append(chip(T.beforeAlarm, "green"));
      }
    } else {
      pill.textContent = T.off;
      title = T.notGuarding;
      const last = [...(s?.events ?? [])].reverse().find((e) => e.e === "triggered");
      if (last && v.level !== "status") sub = T.lastAlarm + (T.headline[last.k] ?? T.alarm) + " · " + when(last.t);
    }
    if (v?.level === "status") sub = (sub ? sub + T.then : "") + T.onlyStatus;
    if (v && !v.online && v.offlineAt && phase !== "idle" && v.level !== "reset" && v.level !== "expired") sub = T.offlineSince(when(v.offlineAt));
    if (v && !v.online && phase !== "idle" && pill.className !== "pill alarm") { pill.textContent = T.offline; pill.className = "pill"; }
    $("title").textContent = title;
    $("sub").textContent = sub;
    chips.hidden = !chips.childElementCount;
    renderPhotos(v?.photos ?? []);
    renderTimeline(v?.level === "owner" || v?.level === "pass" ? s?.events ?? [] : []);
  }

  let photoKey = "";
  function renderPhotos(list) {
    const key = list.join(",");
    if (key === photoKey) return;
    photoKey = key;
    const grid = $("photos");
    grid.replaceChildren(...list.map((t) => {
      const a = document.createElement("a");
      a.href = "/p/" + id + "/" + t + "?t=" + encodeURIComponent(token);
      a.target = "_blank";
      a.rel = "noreferrer";
      const img = document.createElement("img");
      img.loading = "lazy";
      img.alt = when(t);
      img.src = a.href;
      a.append(img);
      return a;
    }));
    grid.hidden = $("photosLabel").hidden = !list.length;
  }

  function renderTimeline(events) {
    const items = events.slice(-12).reverse().map((e) => {
      const li = document.createElement("li");
      const time = document.createElement("time");
      time.textContent = clock.format(e.t);
      const what = document.createElement("span");
      if (e.e === "triggered") { what.textContent = T.headline[e.k] ?? T.alarm; what.className = "hot"; }
      else if (e.e === "disarmed") what.textContent = T.disarm[e.k] ?? T.disarmed;
      else if (e.e === "cancelled") what.textContent = T.disarm[e.k] ?? T.event.cancelled;
      else if (e.e === "armed") what.textContent = T.event.armed + (T.places[e.k] ? " · " + T.places[e.k] : "");
      else what.textContent = T.event[e.e] ?? e.e;
      li.append(time, what);
      return li;
    });
    $("timeline").replaceChildren(...items);
    $("timelineCard").hidden = $("timelineLabel").hidden = !items.length;
  }

  function showFrame(blob) {
    if (pending) URL.revokeObjectURL(pending);  // a newer frame replaces one still loading
    const url = URL.createObjectURL(blob);
    pending = url;
    const img = $("frame");
    img.onload = () => {
      if (shown && shown !== url) URL.revokeObjectURL(shown);
      shown = url;
      if (pending === url) pending = null;
    };
    img.onerror = () => { URL.revokeObjectURL(url); if (pending === url) pending = null; };
    img.src = url;
    lastFrame = Date.now();
    $("live").hidden = false;
    $("waiting").hidden = true;
    tick();
  }

  function tick() {
    const age = $("age");
    if (!lastFrame) { age.hidden = true; $("waiting").hidden = false; return; }
    const s = Math.round((Date.now() - lastFrame) / 1000);
    age.hidden = false;
    age.textContent = s < 3 ? T.live : T.stale(s);
    age.className = s < 3 ? "tag" : "tag stale";
  }
  setInterval(tick, 1000);

  function connect() {
    const scheme = location.protocol === "https:" ? "wss://" : "ws://";
    socket = new WebSocket(scheme + location.host + "/watch/" + id + "?t=" + encodeURIComponent(token));
    socket.binaryType = "blob";
    socket.onmessage = (e) => {
      if (typeof e.data !== "string") { showFrame(e.data); return; }
      try { view = JSON.parse(e.data); } catch { return; }
      if (view.state?.phase !== "triggered") { lastFrame = 0; tick(); }
      render();
    };
    socket.onclose = () => {
      if (view?.level === "reset") return;
      $("pill").textContent = "…";
      setTimeout(connect, 2000);
    };
  }
  render();
  connect();
</script>
</html>`;


/// What the QR code's link opens in Safari: the app, or a line that says to install it. It never
/// touches the relay, so it cannot reveal anything; the code travels in the link to the app.
const PAIR_PAGE = `<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex">
<meta name="referrer" content="no-referrer">
<meta name="theme-color" content="#0b0f1c">
<title>BRB</title>
<style>
  :root { --bg: #0b0f1c; --ink: #eef1f8; --dim: rgba(238, 241, 248, .62); --amber: #f6b544; color-scheme: dark; }
  * { box-sizing: border-box; }
  html, body { margin: 0; background: var(--bg); color: var(--ink); }
  body {
    font: 15px/1.45 -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", sans-serif;
    min-height: 100vh; display: grid; place-items: center; padding: 24px 16px;
    background: radial-gradient(120% 60% at 50% 0%, #1b2440 0%, var(--bg) 60%) fixed;
  }
  main { max-width: 360px; text-align: center; display: grid; gap: 14px; justify-items: center; }
  svg { width: 44px; height: 44px; }
  h1 { font-size: 22px; line-height: 1.25; margin: 0; font-weight: 650; text-wrap: balance; }
  p { margin: 0; color: var(--dim); }
  a { display: inline-block; margin-top: 6px; padding: 12px 26px; border-radius: 99px; background: var(--amber); color: #241700; font-weight: 600; text-decoration: none; }
</style>
<main>
  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.8 19.4 5.6v5.8c0 4.8-3.1 8.6-7.4 10.1-4.3-1.5-7.4-5.3-7.4-10.1V5.6Z" fill="#f6b544"/><circle cx="12" cy="11.4" r="2.4" fill="#2b1a00"/></svg>
  <h1 id="title"></h1>
  <p id="sub"></p>
  <a id="open" href="#"></a>
</main>
<script>
  const zh = (navigator.languages || [navigator.language]).some((l) => /^zh/i.test(l || ""));
  document.documentElement.lang = zh ? "zh-Hans" : "en";
  document.getElementById("title").textContent = zh ? "在 iPhone 上打开 BRB" : "Open BRB on your iPhone";
  document.getElementById("sub").textContent = zh ? "如果没有自动打开，先安装 BRB，再回到这里点下面的按钮。" : "If it doesn't open by itself, install BRB, then come back and tap the button.";
  const open = document.getElementById("open");
  open.textContent = zh ? "打开 BRB" : "Open BRB";
  open.href = "brb://pair?c=" + encodeURIComponent(location.pathname.split("/")[2] || "") + "&h=" + encodeURIComponent(location.host);
  setTimeout(() => { location.href = open.href; }, 150);
</script>
</html>`;
