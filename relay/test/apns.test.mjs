import assert from "node:assert/strict";
import { generateKeyPairSync, webcrypto } from "node:crypto";
import { describe, test } from "node:test";
import * as apns from "../apns.js";

const pair = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const pem = pair.privateKey.export({ type: "pkcs8", format: "pem" });
const env = { APNS_KEY: pem, APNS_KEY_ID: "ABC123DEFG", APNS_TEAM_ID: "TEAM123456", APNS_TOPIC: "app.example.brb" };

const ID = "0123456789abcdef0123456789abcdef";
const NOW = Date.UTC(2026, 9, 15, 14, 32, 5);
const mac = { name: "Allen's MacBook Pro", model: "MacBook Pro", batt: 80, chg: false };
const health = { ax: true, cam: true, lid: true, mot: true };

const state = (change = {}) => ({
  v: 3, phase: "idle", since: 0, armEnd: 0, lastEnd: null, place: "cafe", note: "", vol: 100, test: false, camera: true, push: false,
  trigger: null, at: null, siren: false, stage: null, softEnd: null, carried: false, bumps: 0, mac, health, events: [], pass: null, ...change,
});
const armed = (change = {}) => state({ phase: "armed", since: NOW - 60_000, ...change });
const alarm = (change = {}) =>
  armed({ phase: "triggered", trigger: "lifted", at: NOW - 1000, stage: "siren", siren: true, pass: "passpasspass1234", ...change });
const device = (change = {}) => ({
  dev: "DEV-0001-AAAA", name: "Allen's iPhone", apns: "a".repeat(64), env: "production", lang: "en", crit: false, pro: false,
  events: { siren: true, back: true, disarm: true, guard: false, sensor: true }, la: null, laStart: null, tz: "UTC", ...change,
});
const plan = (prev, next, devices, more = {}) => apns.plan({ id: ID, prev, next, devices, now: NOW, ...more });
const alerts = (pushes) => pushes.filter((p) => p.type === "alert");
const keys = (pushes) => alerts(pushes).map((p) => p.body.aps.alert["loc-key"]);

describe("provider token", () => {
  const b64 = (s) => Buffer.from(s, "base64url");

  test("is an ES256 JWT that the key's public half verifies", async () => {
    const jwt = await apns.signJwt({ key: pem, keyId: "ABC123DEFG", teamId: "TEAM123456" }, 1_790_000_000);
    const [head, claims, sig] = jwt.split(".");
    assert.deepEqual(JSON.parse(b64(head)), { alg: "ES256", kid: "ABC123DEFG" });
    assert.deepEqual(JSON.parse(b64(claims)), { iss: "TEAM123456", iat: 1_790_000_000 });
    assert.equal(b64(sig).length, 64, "raw r||s, not DER");
    const pub = await webcrypto.subtle.importKey("jwk", pair.publicKey.export({ format: "jwk" }), { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
    const data = new TextEncoder().encode(`${head}.${claims}`);
    assert.ok(await webcrypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pub, b64(sig), data));
    assert.ok(!(await webcrypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pub, b64(sig), new TextEncoder().encode(`${head}.x`))));
  });

  test("reads the .p8 as it is, with escaped newlines, or as bare base64", async () => {
    const bare = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
    for (const key of [pem, pem.replace(/\n/g, "\\n"), bare, `  ${pem}  `]) {
      const jwt = await apns.signJwt({ key, keyId: "K", teamId: "T" }, 1);
      assert.equal(jwt.split(".").length, 3);
    }
  });

  test("is kept for 50 minutes, then signed again", async () => {
    apns.forgetBearer();
    const first = await apns.bearer(env, 1_000_000);
    assert.equal(await apns.bearer(env, 1_000_000 + 49 * 60_000), first);
    const later = await apns.bearer(env, 1_000_000 + 51 * 60_000);
    assert.notEqual(later, first);
    assert.notEqual(await apns.bearer(env, 1_000_000 + 51 * 60_000, true), later, "fresh signs again at once");
    assert.notEqual(await apns.bearer({ ...env, APNS_KEY_ID: "OTHERKEY12" }, 1_000_000 + 51 * 60_000), later, "another key is another token");
  });

  test("secrets all there, or no push", () => {
    assert.ok(apns.configured(env));
    for (const name of Object.keys(env)) assert.ok(!apns.configured({ ...env, [name]: undefined }), name);
    assert.ok(!apns.configured({}));
  });
});

describe("alarm alert", () => {
  const push = (change, dev = device()) => plan(armed(), alarm({ stage: "soft", siren: false, ...change }), [dev]);

  test("has the shape the app's notification extension reads", () => {
    const [p] = push({ trigger: "lifted" });
    assert.equal(p.type, "alert");
    assert.equal(p.token, "a".repeat(64));
    assert.equal(p.wait, "photo", "held for the first photo");
    assert.deepEqual(p.body, {
      aps: {
        alert: { "title-loc-key": "p_alarm_lift", "loc-key": "p_alarm_b", "loc-args": ["Allen's MacBook Pro"] },
        sound: "default", "thread-id": ID, "mutable-content": 1, "interruption-level": "time-sensitive", category: "BRB_ALARM",
      },
      id: ID, pass: "passpasspass1234", photo: null, at: NOW - 1000,
    });
  });

  test("names what happened: taken or touched", () => {
    for (const trigger of ["lifted", "tilted", "lidClosed", "lidMoved", "charger", "powerKey", "restarted"]) {
      assert.equal(push({ trigger })[0].body.aps.alert["title-loc-key"], "p_alarm_lift", trigger);
    }
    for (const trigger of ["trackpad", "keyboard", "finger"]) {
      assert.equal(push({ trigger })[0].body.aps.alert["title-loc-key"], "p_alarm_touch", trigger);
    }
  });

  test("is critical for a device that asked, unless it is only a test", () => {
    const loud = push({}, device({ crit: true }))[0].body;
    assert.deepEqual(loud.aps.sound, { critical: 1, name: "default", volume: 1.0 });
    assert.equal(loud.aps["interruption-level"], "critical");
    const test = push({ test: true }, device({ crit: true }))[0].body;
    assert.equal(test.aps["interruption-level"], "time-sensitive");
    assert.equal(test.test, true);
  });

  test("goes at once when the photo is already there", () => {
    const [p] = plan(armed(), alarm(), [device()], { photo: NOW - 500 });
    assert.equal(p.wait, undefined);
    assert.equal(p.body.photo, NOW - 500);
  });

  test("cannot be switched off", () => {
    const off = device({ events: { siren: false, back: false, disarm: false, guard: false, sensor: false } });
    assert.deepEqual(keys(push({}, off)), ["p_alarm_b"]);
  });

  test("is sent once per alarm, not again when the Mac repeats itself", () => {
    assert.deepEqual(plan(alarm(), alarm(), [device()]), []);
    assert.equal(alerts(plan(null, alarm(), [device()])).length, 1, "a room's first state can be an alarm");
  });

  test("goes to a device with an APNs token only", () => {
    assert.deepEqual(plan(armed(), alarm(), [device({ apns: null })]), []);
    const two = plan(armed(), alarm(), [device(), device({ dev: "DEV-0002-BBBB", apns: "b".repeat(64), crit: true })]);
    assert.deepEqual(two.map((p) => p.dev), ["DEV-0001-AAAA", "DEV-0002-BBBB"]);
  });
});

describe("the other alerts", () => {
  test("soft to siren is a time-sensitive alert, if the device wants it", () => {
    const soft = alarm({ stage: "soft", siren: false });
    const [p] = plan(soft, alarm(), [device()], { photo: NOW - 900 });
    assert.deepEqual(p.body.aps, {
      alert: { "loc-key": "p_siren" }, sound: "default", "thread-id": ID, "mutable-content": 1, "interruption-level": "time-sensitive", category: "BRB_ALARM",
    });
    assert.equal(p.body.photo, NOW - 900);
    assert.equal(p.body.pass, "passpasspass1234");
    assert.equal(p.priority, 10);
    assert.deepEqual(plan(soft, alarm(), [device({ events: { siren: false } })]), []);
  });

  test("a hushed or put-back Mac that sounds again is told too", () => {
    for (const stage of ["hushed", "back"]) assert.deepEqual(keys(plan(alarm({ stage, siren: false }), alarm(), [device()])), ["p_siren"], stage);
  });

  test("put back is time-sensitive without a category, if wanted", () => {
    const [p] = plan(alarm(), alarm({ stage: "back", siren: false }), [device()]);
    assert.equal(p.body.aps.alert["loc-key"], "p_back");
    assert.equal(p.body.aps["interruption-level"], "time-sensitive");
    assert.equal(p.body.aps.category, undefined);
    assert.deepEqual(plan(alarm(), alarm({ stage: "back", siren: false }), [device({ events: { back: false } })]), []);
  });

  test("hushed makes no alert", () => {
    assert.deepEqual(plan(alarm(), alarm({ stage: "hushed", siren: false }), [device()]), []);
  });

  test("a disarm is passive, with the time in the device's zone", () => {
    const idle = state({ events: [{ t: NOW, e: "disarmed", k: "fingerprint" }] });
    const [p] = plan(alarm(), idle, [device({ tz: "America/Toronto" })]);
    assert.equal(p.body.aps.alert["loc-key"], "p_dis");
    assert.deepEqual(p.body.aps.alert["loc-args"], ["10:32"]);
    assert.equal(p.body.aps["interruption-level"], "passive");
    assert.equal(p.body.aps.sound, undefined);
    assert.equal(p.priority, 5);
    assert.deepEqual(plan(alarm(), idle, [device({ events: { disarm: false } })]), []);
    assert.deepEqual(plan(alarm(), idle, [device({ tz: "Not/AZone" })])[0].body.aps.alert["loc-args"], ["14:32"], "an unknown zone is UTC");
  });

  test("guarding starting and ending is for devices that opt in", () => {
    const on = device({ events: { guard: true } });
    assert.deepEqual(keys(plan(state(), armed(), [on])), ["p_start"]);
    assert.deepEqual(keys(plan(armed(), state(), [on])), ["p_end"]);
    assert.deepEqual(plan(state(), armed(), [device()]), []);
    assert.deepEqual(plan(armed(), state(), [device()]), []);
    assert.deepEqual(plan(state(), state({ phase: "arming" }), [on]), [], "a countdown is not guarding yet");
    assert.deepEqual(plan(state({ phase: "arming" }), state(), [on]), [], "a cancelled countdown ends nothing");
    assert.deepEqual(keys(plan(state({ phase: "arming" }), armed(), [on])), ["p_start"]);
    assert.deepEqual(plan(alarm(), state(), [on]).map((p) => p.body.aps.alert["loc-key"]), ["p_dis"], "an alarm's end is a disarm, not an end");
  });

  test("a sensor warning is time-sensitive, if wanted, once", () => {
    const warning = { t: NOW, e: "warning", k: "motion" };
    const [p] = plan(armed(), armed({ events: [warning] }), [device()]);
    assert.equal(p.body.aps.alert["loc-key"], "p_sensor");
    assert.equal(p.body.aps["interruption-level"], "time-sensitive");
    assert.deepEqual(plan(armed({ events: [warning] }), armed({ events: [warning], bumps: 1 }), [device()]), []);
    assert.deepEqual(plan(armed(), armed({ events: [warning] }), [device({ events: { sensor: false } })]), []);
    assert.deepEqual(plan(armed(), armed({ events: [{ t: NOW, e: "photo", k: null }] }), [device()]), []);
  });

  test("no change, no push", () => {
    assert.deepEqual(plan(armed(), armed({ bumps: 2 }), [device()]), []);
    assert.deepEqual(plan(state(), state({ mac: { ...mac, batt: 50 } }), [device({ la: "c".repeat(64) })]), []);
  });
});

describe("live activity", () => {
  const la = "c".repeat(100), laStart = "d".repeat(100);

  test("content state says what to draw", () => {
    const cs = apns.contentState(alarm({ stage: "soft", siren: false, softEnd: NOW + 9000, bumps: 1 }), { photo: NOW - 100 });
    assert.deepEqual(cs, {
      look: "warn", place: "cafe", since: NOW - 60_000, armEnd: 0, at: NOW - 1000, softEnd: NOW + 9000, bumps: 1, trigger: "lifted",
      photo: NOW - 100, by: null, test: false, pass: "passpasspass1234",
    });
  });

  test("looks", () => {
    const look = apns.look;
    assert.equal(look(state()), "clear");
    assert.equal(look(state({ phase: "arming" })), "arming");
    assert.equal(look(armed()), "armed");
    assert.equal(look(armed({ test: true })), "test");
    assert.equal(look(armed({ camera: false })), "partial");
    assert.equal(look(armed({ health: { ...health, mot: false } })), "partial");
    assert.equal(look(armed(), false), "offline");
    assert.equal(look(state(), false), "clear", "idle needs no connection");
    assert.equal(look(alarm({ stage: "soft" })), "warn");
    assert.equal(look(alarm()), "alarm");
    assert.equal(look(alarm({ stage: "back" })), "back");
    assert.equal(look(alarm({ stage: "hushed" })), "hushed");
    assert.equal(look(alarm({ stage: null })), "alarm");
  });

  test("a running activity is updated on a change and not on silence", () => {
    const d = device({ la, apns: null });
    const [p] = plan(armed(), alarm({ stage: "soft", siren: false }), [d]);
    assert.equal(p.type, "liveactivity");
    assert.equal(p.token, la);
    assert.equal(p.field, "la");
    assert.equal(p.priority, 10);
    assert.deepEqual(Object.keys(p.body.aps), ["timestamp", "event", "content-state"]);
    assert.equal(p.body.aps.event, "update");
    assert.equal(p.body.aps.timestamp, Math.floor(NOW / 1000));
    assert.equal(p.body.aps["content-state"].look, "warn");
    assert.deepEqual(plan(alarm(), alarm({ events: [{ t: 1, e: "photo", k: null }] }), [d]), [], "nothing the activity shows changed");
    assert.equal(plan(alarm(), alarm(), [d], { force: true }).length, 1, "forced: a photo came in");
    assert.equal(plan(armed(), armed(), [d], { online: false, wasOnline: true })[0].body.aps["content-state"].look, "offline");
    assert.equal(plan(armed(), armed(), [d], { online: true, wasOnline: false })[0].body.aps["content-state"].look, "armed");
  });

  test("it ends at the disarm, and dismisses itself 6 s later", () => {
    const d = device({ la, apns: null });
    const idle = state({ events: [{ t: NOW, e: "disarmed", k: "phone" }] });
    const [p] = plan(alarm(), idle, [d]);
    assert.equal(p.body.aps.event, "end");
    assert.equal(p.body.aps["dismissal-date"], Math.floor(NOW / 1000) + 6);
    assert.equal(p.body.aps["content-state"].look, "clear");
    assert.equal(p.body.aps["content-state"].by, "phone");
    assert.equal(plan(armed(), state({ events: [{ t: NOW, e: "disarmed", k: "unlock" }] }), [d])[0].body.aps["content-state"].by, "fingerprint");
    assert.deepEqual(plan(state(), state(), [d]), []);
  });

  test("one starts when guarding begins or an alarm does, for a device with a start token and no activity", () => {
    const d = device({ laStart, apns: null });
    const [p] = plan(state(), state({ phase: "arming", armEnd: NOW + 5000, since: NOW }), [d]);
    assert.equal(p.body.aps.event, "start");
    assert.equal(p.token, laStart);
    assert.equal(p.field, "laStart");
    assert.equal(p.body.aps["attributes-type"], "BRBActivityAttributes");
    assert.deepEqual(p.body.aps.attributes, { macId: ID, macName: "Allen's MacBook Pro" });
    assert.equal(p.body.aps["content-state"].look, "arming");
    assert.deepEqual(p.body.aps.alert, { "loc-key": "p_start" });
    const [s] = plan(armed(), alarm(), [d]);
    assert.equal(s.body.aps.event, "start");
    assert.equal(s.body.aps.alert["title-loc-key"], "p_alarm_lift");
    assert.deepEqual(plan(armed(), armed({ bumps: 1 }), [d]), [], "no start for a change mid-session");
    assert.equal(plan(state(), armed(), [device({ la, laStart, apns: null })])[0].body.aps.event, "update", "one is running: update it");
  });

  test("a device with both tokens gets the alert and the activity", () => {
    const pushes = plan(armed(), alarm(), [device({ la })]);
    assert.deepEqual(pushes.map((p) => p.type), ["alert", "liveactivity"]);
  });
});

describe("sending", () => {
  const push = (change = {}) => ({ dev: "d", field: "apns", type: "alert", token: "ab".repeat(32), priority: 10, ttl: 3600, body: { aps: { alert: "x" } }, ...change });
  const reply = (status, body) => new Response(body === undefined ? null : JSON.stringify(body), { status });

  test("posts to Apple's production or sandbox host with the headers Apple wants", async () => {
    apns.forgetBearer();
    const calls = [];
    const fetchImpl = async (url, init) => (calls.push({ url, init }), reply(200));
    const ok = await apns.sendPush(env, device(), push(), fetchImpl, NOW);
    assert.deepEqual(ok, { ok: true, status: 200, reason: "" });
    await apns.sendPush(env, device({ env: "sandbox" }), push({ type: "liveactivity", priority: 5, ttl: 0 }), fetchImpl, NOW);
    assert.equal(calls[0].url, `https://api.push.apple.com/3/device/${"ab".repeat(32)}`);
    assert.equal(calls[1].url, `https://api.sandbox.push.apple.com/3/device/${"ab".repeat(32)}`);
    const [h0, h1] = calls.map((c) => c.init.headers);
    assert.match(h0.authorization, /^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    assert.equal(h0["apns-topic"], "app.example.brb");
    assert.equal(h0["apns-push-type"], "alert");
    assert.equal(h0["apns-priority"], "10");
    assert.equal(h0["apns-expiration"], String(Math.floor(NOW / 1000) + 3600));
    assert.equal(h1["apns-topic"], "app.example.brb.push-type.liveactivity");
    assert.equal(h1["apns-push-type"], "liveactivity");
    assert.equal(h1["apns-expiration"], "0");
    assert.equal(calls[0].init.method, "POST");
    assert.deepEqual(JSON.parse(calls[0].init.body), { aps: { alert: "x" } });
  });

  test("reports Apple's reason", async () => {
    const r = await apns.sendPush(env, device(), push(), async () => reply(410, { reason: "Unregistered" }), NOW);
    assert.deepEqual(r, { ok: false, status: 410, reason: "Unregistered" });
  });

  test("signs a refused provider token again, once", async () => {
    apns.forgetBearer();
    const seen = [];
    const fetchImpl = async (url, init) => {
      seen.push(init.headers.authorization);
      return seen.length === 1 ? reply(403, { reason: "ExpiredProviderToken" }) : reply(200);
    };
    const r = await apns.sendPush(env, device(), push(), fetchImpl, NOW);
    assert.equal(r.ok, true);
    assert.equal(seen.length, 2);
    const always = await apns.sendPush(env, device(), push(), async () => reply(403, { reason: "InvalidProviderToken" }), NOW);
    assert.equal(always.status, 403, "no third try");
  });

  test("does not throw when the network does", async () => {
    const r = await apns.sendPush(env, device(), push(), async () => { throw new Error("down"); }, NOW);
    assert.deepEqual(r, { ok: false, status: 0, reason: "down" });
  });

  test("a test alert reads in the device's language", () => {
    assert.match(apns.testAlert({ id: ID, device: device() }).aps.alert.body, /Test alert/);
    assert.match(apns.testAlert({ id: ID, device: device({ lang: "zh" }) }).aps.alert.body, /测试/);
  });
});
