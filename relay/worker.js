import { DurableObject } from "cloudflare:workers";

// One Room per Mac. The Mac connects to /cam/<key>; phones open /v/<id>#<token> and watch
// /watch/<id>?t=<token>, where id = the first 32 hex chars of sha256(key). The id alone shows only
// whether the Mac is guarded. The owner's token (from the Mac's panel) shows everything; the pass in
// an alarm push shows that alarm until it is disarmed. The Mac sends camera frames only after a
// trigger and only while an allowed page is watching; photos of an alarm are kept for 30 days.
//
// Protocol v2, Mac to relay: {"hello":{"token":…,"v":2}} once per connection, then {"state":{…}} on
// every change, JPEG frames as binary messages, and photos as POST /photo/<key>?t=<ms>&pass=<pass>.
// A Mac from before v2 never says hello: its room lets every page watch, as before.
//
// Optional: CAM_IDS, a comma-separated list of the room ids allowed to connect as a camera.

const TOKEN = /^[a-z0-9]{8,64}$/;
const MAX_FRAME = 200_000;
const MAX_PHOTO = 300_000;
const PHOTOS_KEPT = 6;
const PHOTO_DAYS = 30;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const [, route, a, b] = url.pathname.split("/");
    if (!TOKEN.test(a ?? "")) return text("not found", 404);
    if (route === "v" && request.method === "GET") {
      return new Response(PAGE, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "referrer-policy": "no-referrer" } });
    }
    const byKey = { cam: true, photo: true, wipe: true }[route];
    const byId = { watch: true, p: true }[route];
    if (!byKey && !byId) return text("not found", 404);
    const id = byKey ? await viewId(a) : a;
    if ((route === "cam" || route === "photo") && env.CAM_IDS && !env.CAM_IDS.split(",").map((s) => s.trim()).includes(id)) {
      return text("this camera is not allowed here", 403);
    }
    if ((route === "cam" || route === "watch") && request.headers.get("Upgrade") !== "websocket") return text("websocket only", 426);
    if ((route === "photo" || route === "wipe") && request.method !== "POST") return text("POST only", 405);
    if (route === "p" && !/^\d{10,16}$/.test(b ?? "")) return text("not found", 404);
    return env.ROOMS.get(env.ROOMS.idFromName(id)).fetch(request);
  },
};

function text(body, status) {
  return new Response(body, { status, headers: { "content-type": "text/plain; charset=utf-8" } });
}

async function viewId(key) {
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key)));
  return [...hash].map((x) => x.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

export class Room extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.owner = (await ctx.storage.get("owner")) ?? null;
      this.state = (await ctx.storage.get("state")) ?? null;
      this.offlineAt = (await ctx.storage.get("offlineAt")) ?? null;
      this.oldPasses = (await ctx.storage.get("oldPasses")) ?? [];
      this.wiped = (await ctx.storage.get("wiped")) ?? false;
    });
  }

  async fetch(request) {
    const url = new URL(request.url);
    const route = url.pathname.split("/")[1];
    if (route === "cam") return this.connectCam();
    if (route === "watch") return this.connectViewer(url.searchParams.get("t") ?? "");
    if (route === "photo") return this.storePhoto(request, url);
    if (route === "p") return this.servePhoto(Number(url.pathname.split("/")[3]), url.searchParams.get("t") ?? "");
    if (route === "wipe") return this.wipe();
    return text("not found", 404);
  }

  // MARK: sockets

  connectCam() {
    for (const old of this.ctx.getWebSockets("cam")) old.close(1000, "replaced");
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server, ["cam"]);
    this.offlineAt = null;
    this.ctx.storage.delete("offlineAt");
    this.refresh();
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
    if (!this.ctx.getTags(ws).includes("cam")) return;  // pages only watch
    if (typeof message !== "string") {
      if (message.byteLength > MAX_FRAME) return;
      for (const viewer of this.ctx.getWebSockets("viewer")) {
        if (seesCamera(viewer.deserializeAttachment()?.level)) try { viewer.send(message); } catch {}
      }
      return;
    }
    if (message.length > MAX_FRAME) return;
    let msg;
    try { msg = JSON.parse(message); } catch { return; }
    if (msg.hello && TOKEN.test(msg.hello.token ?? "") && msg.hello.token !== this.owner) {
      this.owner = msg.hello.token;
      await this.ctx.storage.put("owner", this.owner);
    }
    if (msg.state && typeof msg.state === "object") {
      const previous = this.state?.pass;
      const next = clean(msg.state);
      if (previous && previous !== next.pass && !this.oldPasses.includes(previous)) {
        this.oldPasses = [...this.oldPasses, previous].slice(-10);
        await this.ctx.storage.put("oldPasses", this.oldPasses);
      }
      this.state = next;
      await this.ctx.storage.put("state", this.state);
    }
    this.refresh();
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
    }
    this.refresh(ws);
  }

  /// What a token may see: everything (the owner, or anyone in a room from before v2), this alarm
  /// (its pass, until the disarm), or only whether the Mac is guarded.
  level(t) {
    if (this.wiped) return "reset";
    if (!this.owner) return "owner";
    if (t && t === this.owner) return "owner";
    if (t && this.state?.pass && t === this.state.pass && this.state.phase === "triggered") return "pass";
    if (t && this.oldPasses.includes(t)) return "expired";
    return "status";
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
    const base = { v: 2, level, online, offlineAt: this.offlineAt };
    if (level === "reset" || level === "expired") return base;
    if (level === "status") return { ...base, state: s ? { phase: s.phase === "idle" ? "idle" : "armed", since: s.since } : null };
    const { pass, ...visible } = s ?? {};
    const mine = level === "owner" ? photos : photos.filter((p) => p.pass === t);
    return { ...base, state: s ? visible : null, photos: mine.map((p) => p.t) };
  }

  // MARK: photos

  table() {
    this.ctx.storage.sql.exec("CREATE TABLE IF NOT EXISTS photos (t INTEGER PRIMARY KEY, pass TEXT, data BLOB)");
  }

  photoList() {
    this.table();
    return this.ctx.storage.sql.exec("SELECT t, pass FROM photos ORDER BY t DESC").toArray();
  }

  async storePhoto(request, url) {
    const t = Number(url.searchParams.get("t"));
    const pass = url.searchParams.get("pass") ?? "";
    if (!Number.isSafeInteger(t) || t <= 0) return text("bad time", 400);
    const data = await request.arrayBuffer();
    if (data.byteLength === 0 || data.byteLength > MAX_PHOTO) return text("photo too large", 413);
    this.table();
    this.ctx.storage.sql.exec("INSERT OR REPLACE INTO photos (t, pass, data) VALUES (?, ?, ?)", t, TOKEN.test(pass) ? pass : "", data);
    this.ctx.storage.sql.exec(`DELETE FROM photos WHERE t NOT IN (SELECT t FROM photos ORDER BY t DESC LIMIT ${PHOTOS_KEPT})`);
    if (!(await this.ctx.storage.getAlarm())) await this.ctx.storage.setAlarm(Date.now() + PHOTO_DAYS * 86400_000);
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

  /// Photos older than 30 days go.
  async alarm() {
    this.table();
    this.ctx.storage.sql.exec("DELETE FROM photos WHERE t < ?", Date.now() - PHOTO_DAYS * 86400_000);
    const oldest = this.ctx.storage.sql.exec("SELECT MIN(t) AS t FROM photos").toArray()[0]?.t;
    if (oldest) await this.ctx.storage.setAlarm(oldest + PHOTO_DAYS * 86400_000);
    this.refresh();
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

/// Only the fields the page shows, with sane types, from whatever the Mac sent.
function clean(s) {
  const str = (v, n) => (typeof v === "string" ? v.slice(0, n) : "");
  const num = (v) => (Number.isFinite(v) ? v : 0);
  const events = Array.isArray(s.events) ? s.events.slice(-40) : [];
  return {
    v: 2,
    phase: ["idle", "arming", "armed", "triggered"].includes(s.phase) ? s.phase : "idle",
    since: num(s.since),
    place: str(s.place, 16),
    note: str(s.note, 48),
    push: s.push === true,
    test: s.test === true,
    camera: s.camera === true,
    trigger: str(s.trigger, 16) || null,
    at: num(s.at) || null,
    siren: s.siren === true,
    bumps: num(s.bumps),
    events: events.map((e) => ({ t: num(e?.t), e: str(e?.e, 16), k: str(e?.k, 16) || null })),
    pass: TOKEN.test(s.pass ?? "") ? s.pass : null,
  };
}

const PAGE = `<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex">
<meta name="referrer" content="no-referrer">
<meta name="theme-color" content="#0b0f1c">
<title>Guard Mode</title>
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
  ol.timeline { list-style: none; margin: 0; padding: 4px 18px; }
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
    <h1>Guard Mode</h1>
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
    photos: "照片", timeline: "经过", lastAlarm: "上次报警",
    places: { library: "图书馆", cafe: "咖啡馆", transit: "路上" },
    headline: { lifted: "电脑被拿起来了", tilted: "电脑被挪动了", lidClosed: "屏幕被合上了", lidMoved: "屏幕被掰动了", charger: "电源被拔掉了", powerKey: "有人按了电源键", keyboard: "有人碰了键盘", trackpad: "有人碰了触控板", finger: "有人试了指纹", restarted: "程序重启后继续报警" },
    event: { armed: "开始警戒", photo: "拍了一张照片", siren: "警笛响了", warning: "运动传感器停了", cancelled: "取消了" },
    disarm: { fingerprint: "用指纹解除", unlock: "解锁后解除", password: "用指纹或密码解除", escape: "取消了", stopped: "警戒模式被停止", sensorsSilent: "传感器没有数据，已停止", tapFailed: "为了监听键盘而重启" },
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
    photos: "Photos", timeline: "What happened", lastAlarm: "Last alarm",
    places: { library: "Library", cafe: "Café", transit: "On the go" },
    headline: { lifted: "Your Mac was picked up", tilted: "Your Mac was moved", lidClosed: "The lid was closed", lidMoved: "The lid was moved", charger: "The charger was unplugged", powerKey: "The power button was pressed", keyboard: "Someone touched the keyboard", trackpad: "Someone touched the trackpad", finger: "Someone tried a fingerprint", restarted: "The alarm resumed after a restart" },
    event: { armed: "Guarding started", photo: "Took a photo", siren: "The siren started", warning: "The motion sensor stopped", cancelled: "Cancelled" },
    disarm: { fingerprint: "Disarmed with Touch ID", unlock: "Disarmed by unlocking", password: "Disarmed with Touch ID or password", escape: "Cancelled", stopped: "Guard Mode was stopped", sensorsSilent: "Stopped: the sensors sent no data", tapFailed: "Restarted to watch the keyboard" },
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
  document.title = "Guard Mode";

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
      if (last && v.level !== "status") sub = T.lastAlarm + ": " + (T.headline[last.k] ?? T.alarm) + " · " + when(last.t);
    }
    if (v?.level === "status") sub = (sub ? sub + ". " : "") + T.onlyStatus;
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
