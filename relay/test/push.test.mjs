// The whole path to Apple, with a stand-in for api.push.apple.com on a local port: the room sees a
// state change, the policy picks the pushes, the JWT is signed and the request is made. Which pushes
// for which change is checked in detail in apns.test.mjs; this checks they get sent.
import assert from "node:assert/strict";
import { generateKeyPairSync, randomBytes, webcrypto } from "node:crypto";
import { createServer } from "node:http";
import { after, before, describe, test } from "node:test";
import { macState, random, room, sleep, startRelay, until } from "./harness.mjs";

const keys = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const received = [];  // {token, headers, body}
let answer = () => ({ status: 200 });
let server, relay;

before(async () => {
  server = createServer((req, res) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      const entry = { token: req.url.split("/").pop(), url: req.url, method: req.method, headers: req.headers, body: JSON.parse(Buffer.concat(chunks).toString() || "null"), at: Date.now() };
      received.push(entry);
      const { status, reason } = answer(entry);
      res.writeHead(status, { "content-type": "application/json" });
      res.end(JSON.stringify(reason ? { reason } : {}));
    });
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  relay = await startRelay({
    APNS_KEY: keys.privateKey.export({ type: "pkcs8", format: "der" }).toString("base64"),
    APNS_KEY_ID: "KEYID12345", APNS_TEAM_ID: "TEAMID1234", APNS_TOPIC: "app.example.brb",
    APNS_URL: `http://127.0.0.1:${server.address().port}`,
  });
});
after(async () => {
  await relay?.stop();
  server?.close();
});

const hex = (n = 32) => randomBytes(n).toString("hex");
const device = (change = {}) => ({
  dev: `PUSH-${random(12)}`, name: "Allen's iPhone", apns: hex(), env: "sandbox", lang: "en", crit: false, pro: false,
  events: { siren: true, back: true, disarm: true, guard: false, sensor: true }, la: null, laStart: null, tz: "UTC", ...change,
});
const register = async (r, d) => {
  const res = await relay.http("POST", `/device/${r.id}?t=${r.token}`, { body: d });
  assert.equal(res.status, 200);
  return d;
};
const sent = (token) => received.filter((p) => p.token === token);
const find = async (token, match, ms = 6000) => {
  let found;
  await until(() => (found = sent(token).find((p) => match(p.body, p))), ms).catch(() => { throw new Error(`no push to ${token.slice(0, 8)}; got ${JSON.stringify(sent(token).map((p) => p.body.aps))}`); });
  return found;
};
const key = (loc) => (body) => body.aps?.alert?.["loc-key"] === loc;
const event = (name) => (body) => body.aps?.event === name;

/// A Mac and its room, armed.
async function guarded(devices = [], change = {}) {
  const r = room();
  const mac = await relay.mac(r.key, r.token);
  for (const d of devices) await register(r, d);
  const state = (more = {}) => macState({ phase: "armed", since: Date.now() - 60_000, ...change, ...more });
  const pass = random(16);
  const alarm = (more = {}) => state({ phase: "triggered", trigger: "lifted", at: Date.now(), stage: "siren", siren: true, pass, ...more });
  const photo = (t, token = pass) => relay.http("POST", `/photo/${r.key}?t=${t}&pass=${token}`, { raw: Buffer.alloc(500, 1) });
  return { r, mac, state, alarm, pass, photo };
}

describe("alarm alert", () => {
  test("is held for the first photo up to 2.5 s, then goes without one", async () => {
    const d = device();
    const { mac, alarm, r } = await guarded([d]);
    const start = Date.now();
    mac.send({ state: alarm({ stage: "soft", siren: false }) });
    await sleep(900);
    assert.equal(sent(d.apns).length, 0, "not yet");
    const p = await find(d.apns, key("p_alarm_b"));
    const waited = p.at - start;
    assert.ok(waited >= 2200 && waited < 5000, `waited ${waited} ms`);
    assert.equal(p.body.photo, null);
    assert.equal(p.body.id, r.id);
    assert.deepEqual(p.body.aps.alert, { "title-loc-key": "p_alarm_lift", "loc-key": "p_alarm_b", "loc-args": ["Allen's MacBook Pro"] });
    assert.equal(p.body.aps["interruption-level"], "time-sensitive");
    assert.equal(p.body.aps.category, "BRB_ALARM");
    assert.equal(p.body.aps["thread-id"], r.id);
  });

  test("goes out at once with the photo when it comes first, and says which photo", async () => {
    const d = device();
    const { mac, alarm, pass, photo } = await guarded([d]);
    const start = Date.now();
    mac.send({ state: alarm() });
    await sleep(150);
    const t = Date.now() - 100;
    assert.equal((await photo(t)).status, 200);
    const p = await find(d.apns, key("p_alarm_b"));
    assert.ok(p.at - start < 2000, `took ${p.at - start} ms`);
    assert.equal(p.body.photo, t);
    assert.equal(p.body.pass, pass);
    assert.equal(sent(d.apns).filter((x) => key("p_alarm_b")(x.body)).length, 1, "once");
  });

  test("does not wait for a photo that is already there", async () => {
    const d = device();
    const { mac, alarm, photo } = await guarded([d]);
    const first = Date.now() - 50;
    mac.send({ state: alarm({ stage: "soft", siren: false }) });
    await photo(first);
    await find(d.apns, key("p_alarm_b"));
    const again = sent(d.apns).length;
    mac.send({ state: alarm({ stage: "soft", siren: false, bumps: 1 }) });
    await sleep(300);
    assert.equal(sent(d.apns).length, again, "the same alarm is not announced twice");
  });

  test("the request is what Apple wants, signed by the key", async () => {
    const d = device({ env: "production" });
    const { mac, alarm, photo } = await guarded([d]);
    mac.send({ state: alarm() });
    await photo(Date.now());
    const p = await find(d.apns, key("p_alarm_b"));
    assert.equal(p.method, "POST");
    assert.equal(p.url, `/3/device/${d.apns}`);
    assert.equal(p.headers["apns-topic"], "app.example.brb");
    assert.equal(p.headers["apns-push-type"], "alert");
    assert.equal(p.headers["apns-priority"], "10");
    assert.ok(Number(p.headers["apns-expiration"]) > Date.now() / 1000);
    const [head, claims, sig] = p.headers.authorization.replace(/^bearer /, "").split(".");
    assert.deepEqual(JSON.parse(Buffer.from(head, "base64url")), { alg: "ES256", kid: "KEYID12345" });
    const iss = JSON.parse(Buffer.from(claims, "base64url"));
    assert.equal(iss.iss, "TEAMID1234");
    assert.ok(Math.abs(iss.iat - Date.now() / 1000) < 60);
    const pub = await webcrypto.subtle.importKey("jwk", keys.publicKey.export({ format: "jwk" }), { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
    assert.ok(await webcrypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pub, Buffer.from(sig, "base64url"), Buffer.from(`${head}.${claims}`)));
  });

  test("is critical for a device that asked, unless the run is a test", async () => {
    const loud = device({ crit: true });
    const quiet = device({ crit: true });
    const real = await guarded([loud]);
    real.mac.send({ state: real.alarm() });
    await real.photo(Date.now());
    const p = await find(loud.apns, key("p_alarm_b"));
    assert.equal(p.body.aps["interruption-level"], "critical");
    assert.deepEqual(p.body.aps.sound, { critical: 1, name: "default", volume: 1 });
    const trial = await guarded([quiet], { test: true });
    trial.mac.send({ state: trial.alarm() });
    await trial.photo(Date.now());
    const t = await find(quiet.apns, key("p_alarm_b"));
    assert.equal(t.body.aps["interruption-level"], "time-sensitive");
    assert.equal(t.body.test, true);
  });
});

describe("following the alarm", () => {
  test("siren, put back, hushed and disarmed, each as the device's preferences allow", async () => {
    const all = device({ tz: "America/Toronto" });
    const none = device({ events: { siren: false, back: false, disarm: false, guard: false, sensor: false } });
    const { mac, alarm, photo } = await guarded([all, none]);
    mac.send({ state: alarm({ stage: "soft", siren: false }) });
    await photo(Date.now());
    await find(all.apns, key("p_alarm_b"));
    await find(none.apns, key("p_alarm_b"));

    mac.send({ state: alarm() });
    const siren = await find(all.apns, key("p_siren"));
    assert.equal(siren.body.aps.category, "BRB_ALARM");
    mac.send({ state: alarm({ stage: "hushed", siren: false }) });
    mac.send({ state: alarm({ stage: "back", siren: false }) });
    await find(all.apns, key("p_back"));
    mac.send({ state: macState({ events: [{ t: Date.now(), e: "disarmed", k: "fingerprint" }] }) });
    const dis = await find(all.apns, key("p_dis"));
    assert.equal(dis.body.aps["interruption-level"], "passive");
    assert.equal(dis.headers["apns-priority"], "5");
    assert.match(dis.body.aps.alert["loc-args"][0], /^\d\d:\d\d$/);
    assert.equal(dis.body.aps.sound, undefined);

    await sleep(300);
    assert.deepEqual(sent(all.apns).map((p) => p.body.aps.alert["loc-key"]).sort(), ["p_alarm_b", "p_back", "p_dis", "p_siren"].sort(), "hushed said nothing");
    assert.deepEqual(sent(none.apns).map((p) => p.body.aps.alert["loc-key"]), ["p_alarm_b"], "the alarm alert cannot be switched off, the rest can");
  });

  test("guarding starting and stopping, for those who opt in; and a sensor warning", async () => {
    const watcher = device({ events: { siren: true, back: true, disarm: true, guard: true, sensor: true } });
    const other = device({ events: { guard: false, sensor: false } });
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    await register(r, watcher);
    await register(r, other);
    mac.send({ state: macState({ phase: "arming", since: Date.now(), armEnd: Date.now() + 5000 }) });
    mac.send({ state: macState({ phase: "armed", since: Date.now() }) });
    await find(watcher.apns, key("p_start"));
    mac.send({ state: macState({ phase: "armed", since: Date.now(), events: [{ t: Date.now(), e: "warning", k: "motion" }] }) });
    await find(watcher.apns, key("p_sensor"));
    mac.send({ state: macState({ lastEnd: Date.now() }) });
    await find(watcher.apns, key("p_end"));
    await sleep(300);
    assert.equal(sent(other.apns).length, 0);
    assert.deepEqual(sent(watcher.apns).map((p) => p.body.aps["interruption-level"]).sort(), ["passive", "passive", "time-sensitive"]);
  });
});

describe("live activity", () => {
  test("starts, updates through the alarm, and ends 6 s after the disarm", async () => {
    const running = device({ apns: null, la: hex(48), events: { guard: false } });
    const fresh = device({ apns: null, laStart: hex(48) });
    const { mac, state, alarm, photo, pass } = await guarded([running, fresh]);
    mac.send({ state: state({ phase: "arming", armEnd: Date.now() + 5000 }) });
    const start = await find(fresh.laStart, event("start"));
    assert.equal(start.headers["apns-push-type"], "liveactivity");
    assert.equal(start.headers["apns-topic"], "app.example.brb.push-type.liveactivity");
    assert.equal(start.body.aps["attributes-type"], "BRBActivityAttributes");
    assert.equal(start.body.aps.attributes.macName, "Allen's MacBook Pro");
    assert.equal(start.body.aps["content-state"].look, "arming");
    await find(running.la, event("update"));

    mac.send({ state: state() });
    mac.send({ state: alarm({ stage: "soft", siren: false, softEnd: Date.now() + 10_000 }) });
    const warn = await find(running.la, (b) => b.aps["content-state"].look === "warn");
    assert.equal(warn.body.aps["content-state"].pass, pass);
    assert.equal(warn.body.aps["content-state"].trigger, "lifted");
    const t = Date.now();
    await photo(t);
    await find(running.la, (b) => b.aps["content-state"].photo === t);
    mac.send({ state: alarm({ stage: "hushed", siren: false }) });
    await find(running.la, (b) => b.aps["content-state"].look === "hushed");
    mac.send({ state: macState({ events: [{ t: Date.now(), e: "disarmed", k: "phone" }] }) });
    const end = await find(running.la, event("end"));
    assert.equal(end.body.aps["content-state"].look, "clear");
    assert.equal(end.body.aps["content-state"].by, "phone");
    assert.ok(Math.abs(end.body.aps["dismissal-date"] - (Date.now() / 1000 + 6)) < 5);
    assert.equal(sent(running.la).every((p) => p.headers["apns-push-type"] === "liveactivity"), true);
  });

  test("shows the Mac offline, and armed again when it is back", async () => {
    const d = device({ apns: null, la: hex(48) });
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    await register(r, d);
    mac.send({ state: macState({ phase: "armed", since: Date.now() }) });
    await find(d.la, (b) => b.aps["content-state"].look === "armed");
    mac.close();
    await find(d.la, (b) => b.aps["content-state"].look === "offline");
    await relay.mac(r.key, r.token);
    await until(() => sent(d.la).filter((p) => p.body.aps["content-state"].look === "armed").length === 2);
  });
});

describe("devices and tokens", () => {
  test("a test alert goes to every device with a token, in its language", async () => {
    const a = device({ lang: "zh" });
    const b = device({ apns: null, la: hex(48) });
    const r = room();
    await relay.mac(r.key, r.token);
    await register(r, a);
    await register(r, b);
    const res = await relay.http("POST", `/test-push/${r.id}?t=${r.token}`);
    assert.deepEqual(res.json, { ok: true, sent: 1, failed: 0 });
    const p = await find(a.apns, (body) => body.aps.alert.title === "BRB");
    assert.match(p.body.aps.alert.body, /测试/);
    assert.equal(p.headers["apns-push-type"], "alert");
    assert.equal(sent(b.la).length, 0);
  });

  test("a test alert reports Apple's refusal", async () => {
    const bad = device();
    const r = room();
    await relay.mac(r.key, r.token);
    await register(r, bad);
    answer = ({ token }) => (token === bad.apns ? { status: 400, reason: "BadDeviceToken" } : { status: 200 });
    try {
      assert.deepEqual((await relay.http("POST", `/test-push/${r.id}?t=${r.token}`)).json, { ok: true, sent: 0, failed: 1 });
    } finally {
      answer = () => ({ status: 200 });
    }
  });

  test("a token Apple says is gone is not used again", async () => {
    const gone = device();
    const kept = device();
    const { mac, alarm, photo } = await guarded([gone, kept]);
    answer = ({ token }) => (token === gone.apns ? { status: 410, reason: "Unregistered" } : { status: 200 });
    try {
      mac.send({ state: alarm() });
      await photo(Date.now());
      await find(gone.apns, key("p_alarm_b"));
      await find(kept.apns, key("p_alarm_b"));
      mac.send({ state: macState({ events: [{ t: Date.now(), e: "disarmed", k: "fingerprint" }] }) });
      await find(kept.apns, key("p_dis"));
      await sleep(300);
      assert.equal(sent(gone.apns).length, 1, "asked once");
    } finally {
      answer = () => ({ status: 200 });
    }
  });

  test("only the six most recently registered devices are kept", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const devices = [];
    for (let i = 0; i < 7; i++) {
      devices.push(await register(r, device()));
      await sleep(5);
    }
    const pass = random(16);
    mac.send({ state: macState({ phase: "triggered", trigger: "lifted", at: Date.now(), stage: "siren", siren: true, pass }) });
    await relay.http("POST", `/photo/${r.key}?t=${Date.now()}&pass=${pass}`, { raw: Buffer.alloc(100, 1) });
    for (const d of devices.slice(1)) await find(d.apns, key("p_alarm_b"));
    await sleep(300);
    assert.equal(sent(devices[0].apns).length, 0, "the first to register was dropped");
  });

  test("a device that registers again replaces its old record", async () => {
    const first = device();
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    await register(r, first);
    const second = await register(r, { ...first, apns: hex(), events: { siren: true, back: true, disarm: false, guard: false, sensor: true } });
    mac.send({ state: macState({ phase: "armed", since: Date.now() }) });
    mac.send({ state: macState({ phase: "triggered", trigger: "keyboard", at: Date.now(), stage: "soft", pass: random(16) }) });
    const p = await find(second.apns, key("p_alarm_b"));
    assert.equal(p.body.aps.alert["title-loc-key"], "p_alarm_touch");
    assert.equal(sent(first.apns).length, 0);
  });
});
