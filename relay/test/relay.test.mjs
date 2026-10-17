// The worker as deployed, on `wrangler dev --local`: v2 flows that must keep working, then v3.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { macState, random, room, sleep, startRelay, until } from "./harness.mjs";

let relay;
before(async () => { relay = await startRelay(); });
after(async () => { await relay?.stop(); });

const DAY = 86400_000;
const jpeg = (n = 1000) => Buffer.alloc(n, 0xff);
const upload = (r, t, pass, bytes = jpeg()) => relay.http("POST", `/photo/${r.key}?t=${t}&pass=${pass}`, { raw: bytes, headers: { "content-type": "image/jpeg" } });
const photo = (r, t, token) => relay.http("GET", `/p/${r.id}/${t}?t=${token}`);
const cmd = (r, token, body) => relay.http("POST", `/cmd/${r.id}?t=${token}`, { body });
const alarmState = (pass, change = {}) => macState({ phase: "triggered", since: Date.now() - 5000, trigger: "lifted", at: Date.now(), siren: true, stage: "siren", pass, ...change });

describe("v2 flows", () => {
  test("owner, pass and status each see what they may", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token, { hello: 2 });
    const pass = random(16);
    mac.send({
      state: {
        v: 2, phase: "triggered", since: 1, place: "cafe", note: "hi", push: false, test: false, camera: true, trigger: "lifted", at: 2,
        siren: false, bumps: 1, events: [{ t: 1, e: "armed", k: "cafe" }], pass,
      },
    });
    const owner = await relay.phone(r.id, r.token);
    const seen = await owner.waitFor((m) => m.state?.phase === "triggered");
    assert.equal(seen.level, "owner");
    assert.equal(seen.online, true);
    assert.equal(seen.v, 3);
    assert.equal(seen.state.pass, undefined, "the pass is stripped");
    assert.equal(seen.state.v, 2, "an old Mac stays 2");
    assert.equal(seen.state.stage, "soft", "an old Mac's alarm without a siren is the soft stage");
    assert.equal(seen.state.mac, null);
    assert.equal(seen.state.health, null);
    assert.equal(seen.state.note, "hi");

    const guest = await relay.phone(r.id, pass);
    const viaPass = await guest.waitFor((m) => m.state?.phase === "triggered");
    assert.equal(viaPass.level, "pass");
    assert.equal(viaPass.state.trigger, "lifted");
    assert.equal(viaPass.state.pass, undefined);

    const stranger = await relay.phone(r.id, random(24));
    const status = await stranger.waitFor((m) => m.level);
    assert.equal(status.level, "status");
    assert.deepEqual(status.state, { phase: "armed", since: 1 });
    assert.equal(status.photos, undefined);

    mac.send({ state: { v: 2, phase: "idle", since: 0, siren: false, pass: null, events: [] } });
    const expired = await guest.waitFor((m) => m.level === "expired");
    assert.equal(expired.state, undefined, "a used pass sees nothing");
    assert.equal((await owner.waitFor((m) => m.state?.phase === "idle")).level, "owner");
  });

  test("a v2 Mac that says siren is at the siren stage", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token, { hello: 2 });
    mac.send({ state: { v: 2, phase: "triggered", siren: true, pass: random(16) } });
    const owner = await relay.phone(r.id, r.token);
    assert.equal((await owner.waitFor((m) => m.state?.phase === "triggered")).state.stage, "siren");
  });

  test("a room from before v2 lets every page watch", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token, { hello: 0 });
    mac.send({ state: { phase: "armed", since: 5, place: "cafe" } });
    const anyone = await relay.phone(r.id, "whatever");
    const seen = await anyone.waitFor((m) => m.state?.phase === "armed");
    assert.equal(seen.level, "owner");
    assert.equal(seen.state.place, "cafe");
  });

  test("a page for a Mac that never connected shows no state, and the page itself loads", async () => {
    const r = room();
    const page = await relay.http("GET", `/v/${r.id}`);
    assert.equal(page.status, 200);
    assert.match(page.text, /<title>BRB<\/title>/);
    assert.match(page.headers.get("content-type"), /text\/html/);
    const phone = await relay.phone(r.id, "x".repeat(10));
    const seen = await phone.waitFor((m) => m.level);
    assert.equal(seen.online, false);
  });

  test("photos: the owner and the alarm's pass may fetch them, nobody else", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const pass = random(16), other = random(16);
    mac.send({ state: alarmState(pass) });
    const owner = await relay.phone(r.id, r.token);
    const guest = await relay.phone(r.id, pass);
    await guest.waitFor((m) => m.level === "pass" && m.state);
    const t = Date.now() - 3000;
    const bytes = jpeg(2000);
    assert.equal((await upload(r, t, pass, bytes)).status, 200);
    assert.equal((await upload(r, t + 1, pass)).status, 200);
    assert.equal((await upload(r, t + 2, other)).status, 200);
    const mine = await owner.waitFor((m) => m.photos?.length === 3);
    assert.deepEqual(mine.photos, [t + 2, t + 1, t], "newest first");
    assert.deepEqual((await guest.waitFor((m) => m.photos?.length === 2)).photos, [t + 1, t], "the pass sees only its alarm's");

    const got = await photo(r, t, r.token);
    assert.equal(got.status, 200);
    assert.equal(got.headers.get("content-type"), "image/jpeg");
    assert.ok(got.bytes.equals(bytes));
    assert.equal((await photo(r, t, pass)).status, 200);
    assert.equal((await photo(r, t + 2, pass)).status, 404, "another alarm's photo");
    assert.equal((await photo(r, t, random(24))).status, 404);
    assert.equal((await photo(r, t, "")).status, 404);
    assert.equal((await relay.http("GET", `/p/${r.id}/${t}`)).status, 404);

    assert.equal((await upload(r, t + 3, pass, jpeg(300_001))).status, 413);
    assert.equal((await relay.http("POST", `/photo/${r.key}?t=abc`, { raw: jpeg() })).status, 400);
    assert.equal((await relay.http("GET", `/photo/${r.key}`)).status, 405);

    mac.send({ state: macState({ pass: null }) });
    await guest.waitFor((m) => m.level === "expired");
    assert.equal((await photo(r, t, pass)).status, 404, "after the disarm the pass opens nothing");
    assert.equal((await photo(r, t, r.token)).status, 200, "the owner still may");
  });

  test("at most 6 photos of one alarm are kept", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const pass = random(16);
    mac.send({ state: alarmState(pass) });
    const owner = await relay.phone(r.id, r.token);
    const t = Date.now() - 10_000;
    for (let i = 0; i < 8; i++) await upload(r, t + i, pass);
    const seen = await owner.waitFor((m) => m.photos?.length === 6 && m.photos[0] === t + 7);
    assert.equal(seen.photos[5], t + 2);
  });

  test("camera frames go to the owner and the pass, only while an alarm runs", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const pass = random(16);
    mac.send({ state: macState({ phase: "armed", since: Date.now() }) });
    const owner = await relay.phone(r.id, r.token);
    const guest = await relay.phone(r.id, pass);
    const stranger = await relay.phone(r.id, random(24));
    await owner.waitFor((m) => m.state?.phase === "armed");
    mac.send(new Uint8Array([1, 2, 3]));
    await sleep(300);
    assert.equal(owner.frames.length, 0, "not while only armed");
    mac.send({ state: alarmState(pass) });
    await guest.waitFor((m) => m.level === "pass");
    mac.send(new Uint8Array([4, 5, 6]));
    await until(() => owner.frames.length === 1 && guest.frames.length === 1);
    assert.deepEqual([...owner.frames[0]], [4, 5, 6]);
    await sleep(200);
    assert.equal(stranger.frames.length, 0);
  });

  test("resetting wipes the room and closes every page", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const pass = random(16);
    mac.send({ state: alarmState(pass) });
    const owner = await relay.phone(r.id, r.token);
    await owner.waitFor((m) => m.state?.phase === "triggered");
    const t = Date.now() - 1000;
    await upload(r, t, pass);
    await relay.http("POST", `/device/${r.id}?t=${r.token}`, { body: { dev: "DEVICE-WIPE-0001", apns: "ab".repeat(32) } });
    assert.equal((await relay.http("GET", `/wipe/${r.key}`)).status, 405);
    assert.equal((await relay.http("POST", `/wipe/${r.key}`)).status, 200);
    assert.equal((await owner.waitFor((m) => m.level === "reset")).level, "reset");
    await mac.waitClosed();
    await until(() => owner.ws.readyState >= 2);  // closing: wrangler's local runtime never finishes a viewer's close handshake, with v2's worker either
    assert.equal((await photo(r, t, r.token)).status, 404);
    const again = await relay.phone(r.id, r.token);
    assert.equal((await again.waitFor((m) => m.level)).level, "reset");
    assert.equal((await cmd(r, r.token, { id: "c1", k: "hush" })).status, 403, "nothing is left to command");
    assert.equal((await relay.http("POST", `/pair/${r.key}`, { body: { token: r.token } })).status, 410, "a wiped room cannot pair");
    assert.equal((await upload(r, Date.now(), pass)).status, 410, "nor keep photos");
  });

  test("unknown routes and tokens are not found", async () => {
    assert.equal((await relay.http("GET", "/")).status, 404);
    assert.equal((await relay.http("GET", "/nothing/abcdefgh")).status, 404);
    assert.equal((await relay.http("GET", "/constructor/abcdefgh")).status, 404);
    assert.equal((await relay.http("GET", "/v/!!")).status, 404);
    assert.equal((await relay.http("GET", `/watch/${random(32)}`)).status, 426);
    assert.equal((await relay.http("GET", `/cam/${random(32)}`)).status, 426);
  });
});

describe("state", () => {
  test("clean() keeps the v3 fields, clamps them, and drops the rest", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    mac.send({
      state: {
        v: 3, phase: "triggered", since: 5, armEnd: "soon", lastEnd: 1234, place: "p".repeat(40), note: "n".repeat(100), vol: 250,
        test: "yes", camera: 1, push: true, trigger: "t".repeat(40), at: 777, siren: false, stage: "bogus", softEnd: 888, carried: true,
        bumps: 3, mac: { name: "m".repeat(100), model: 5, batt: 150, chg: 1 }, health: { ax: true, cam: "yes" },
        events: Array.from({ length: 60 }, (_, i) => ({ t: i, e: "e".repeat(30), k: i % 2 ? "k" : null, extra: 1 })),
        pass: "bad pass!", evil: "x",
      },
    });
    const owner = await relay.phone(r.id, r.token);
    const { state } = await owner.waitFor((m) => m.state?.phase === "triggered");
    assert.deepEqual(Object.keys(state).sort(), [
      "armEnd", "at", "bumps", "camera", "carried", "events", "health", "lastEnd", "mac", "note", "phase", "place", "push", "since",
      "siren", "softEnd", "stage", "test", "trigger", "v", "vol",
    ]);
    assert.equal(state.v, 3);
    assert.equal(state.armEnd, 0);
    assert.equal(state.lastEnd, 1234);
    assert.equal(state.place.length, 16);
    assert.equal(state.note.length, 48);
    assert.equal(state.vol, 100);
    assert.equal(state.test, false);
    assert.equal(state.camera, false);
    assert.equal(state.push, true);
    assert.equal(state.trigger.length, 16);
    assert.equal(state.stage, "soft", "an unknown stage falls back");
    assert.equal(state.softEnd, 888);
    assert.equal(state.carried, true);
    assert.deepEqual(state.mac, { name: "m".repeat(40), model: "", batt: 100, chg: false });
    assert.deepEqual(state.health, { ax: true, cam: false, lid: false, mot: false });
    assert.equal(state.events.length, 40);
    assert.deepEqual(state.events[0], { t: 20, e: "e".repeat(16), k: null });
    assert.deepEqual(state.events[1], { t: 21, e: "e".repeat(16), k: "k" });
  });

  test("a good v3 state passes through as it was sent", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const sent = macState({
      phase: "triggered", since: 1000, armEnd: 0, lastEnd: 500, place: "library", note: "Back at 3", vol: 70, test: true, trigger: "keyboard",
      at: 2000, siren: false, stage: "soft", softEnd: 12_000, carried: true, bumps: 2, events: [{ t: 1, e: "armed", k: "library" }, { t: 2, e: "triggered", k: "keyboard" }],
    });
    mac.send({ state: { ...sent, pass: random(16) } });
    const owner = await relay.phone(r.id, r.token);
    const { pass, ...shown } = sent;
    assert.deepEqual((await owner.waitFor((m) => m.state?.phase === "triggered")).state, shown);
  });

  test("each stage is kept, and none outside an alarm", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const owner = await relay.phone(r.id, r.token);
    for (const stage of ["soft", "siren", "back", "hushed"]) {
      mac.send({ state: alarmState(random(16), { stage, siren: stage === "siren" }) });
      await owner.waitFor((m) => m.state?.stage === stage);
    }
    mac.send({ state: macState({ phase: "armed", stage: "hushed" }) });
    assert.equal((await owner.waitFor((m) => m.state?.phase === "armed")).state.stage, null);
  });

  test("an idle Mac is seen with its battery, health and last session", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    mac.send({ state: macState({ lastEnd: Date.now() - 7_200_000, mac: { name: "Mini", model: "Mac14,3", batt: null, chg: true } }) });
    const owner = await relay.phone(r.id, r.token);
    const { state } = await owner.waitFor((m) => m.state?.mac?.name === "Mini");
    assert.equal(state.phase, "idle");
    assert.equal(state.mac.batt, null, "a Mac without a battery");
    assert.ok(state.lastEnd > 0);
  });

  test("the pass sees the alarm, not the Mac's battery or settings", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const pass = random(16);
    mac.send({ state: alarmState(pass, { lastEnd: 5 }) });
    const guest = await relay.phone(r.id, pass);
    const { state } = await guest.waitFor((m) => m.level === "pass" && m.state);
    assert.equal(state.trigger, "lifted");
    assert.equal(state.mac, null);
    assert.equal(state.health, null);
    assert.equal(state.lastEnd, null);
  });

  test("GET /state is the first frame of /watch", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const pass = random(16);
    mac.send({ state: alarmState(pass) });
    const owner = await relay.phone(r.id, r.token);
    const frame = await owner.waitFor((m) => m.state?.phase === "triggered");
    const got = await relay.http("GET", `/state/${r.id}?t=${r.token}`);
    assert.equal(got.status, 200);
    assert.equal(got.headers.get("cache-control"), "no-store");
    assert.equal(got.headers.get("access-control-allow-origin"), "*");
    assert.match(got.headers.get("content-type"), /application\/json/);
    assert.deepEqual(got.json, frame);
    assert.equal(got.json.v, 3);

    const viaPass = await relay.http("GET", `/state/${r.id}?t=${pass}`);
    assert.equal(viaPass.status, 200);
    assert.equal(viaPass.json.level, "pass");
    assert.equal(viaPass.json.state.pass, undefined);

    const none = await relay.http("GET", `/state/${r.id}`);
    assert.equal(none.status, 200);
    assert.equal(none.json.level, "status", "no token: whether the Mac is guarded, as on a socket");
    assert.deepEqual(none.json.state, { phase: "armed", since: frame.state.since });
    assert.equal(none.headers.get("access-control-allow-origin"), "*");

    const wrong = await relay.http("GET", `/state/${r.id}?t=${random(24)}`);
    assert.equal(wrong.status, 403);
    assert.equal(wrong.headers.get("access-control-allow-origin"), "*");
    assert.equal(wrong.headers.get("cache-control"), "no-store");

    assert.equal((await relay.http("GET", `/state/${random(32)}?t=${r.token}`)).status, 404, "a room nobody has used");
    assert.equal((await relay.http("POST", `/state/${r.id}?t=${r.token}`)).status, 405);
    const preflight = await relay.http("OPTIONS", `/state/${r.id}`);
    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get("access-control-allow-origin"), "*");

    mac.send({ state: macState() });
    await owner.waitFor((m) => m.state?.phase === "idle");
    assert.equal((await relay.http("GET", `/state/${r.id}?t=${pass}`)).json.level, "expired", "the used pass");
    await relay.http("POST", `/wipe/${r.key}`);
    const gone = await relay.http("GET", `/state/${r.id}?t=${r.token}`);
    assert.equal(gone.status, 200);
    assert.equal(gone.json.level, "reset", "a widget must learn the link is gone");
  });

  test("GET /state reports a Mac that is offline", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    mac.send({ state: macState({ phase: "armed", since: Date.now() }) });
    const owner = await relay.phone(r.id, r.token);
    await owner.waitFor((m) => m.state?.phase === "armed");
    assert.equal((await relay.http("GET", `/state/${r.id}?t=${r.token}`)).json.online, true);
    mac.close();
    await owner.waitFor((m) => m.online === false);
    const off = (await relay.http("GET", `/state/${r.id}?t=${r.token}`)).json;
    assert.equal(off.online, false);
    assert.ok(off.offlineAt > 0);
    assert.equal(off.state.phase, "armed", "what it last said");
  });
});

describe("pairing", () => {
  const offer = (r, body = {}) => relay.http("POST", `/pair/${r.key}`, { body: { token: r.token, name: "Allen's MacBook Pro", model: "MacBook Pro 14″", ...body } });
  const claim = (code, device = "Allen's iPhone", headers = {}) => relay.http("POST", "/claim", { body: { code, device }, headers });

  test("an offer is claimed once, and the Mac hears of it", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const made = await offer(r);
    assert.equal(made.status, 200);
    assert.match(made.json.code, /^\d{6}$/);
    assert.match(made.json.qr, /^[a-z2-9]{16}$/);
    assert.ok(made.json.expires > Date.now() + 500_000 && made.json.expires <= Date.now() + 600_000, "10 minutes");

    const got = await claim(made.json.code);
    assert.equal(got.status, 200);
    assert.deepEqual(got.json, { id: r.id, token: r.token, name: "Allen's MacBook Pro", model: "MacBook Pro 14″", host: relay.origin });
    const notice = await mac.waitFor((m) => m.paired);
    assert.equal(notice.paired.device, "Allen's iPhone");
    assert.ok(Math.abs(notice.paired.at - Date.now()) < 5000);

    const again = await claim(made.json.code);
    assert.equal(again.status, 404);
    assert.deepEqual(again.json, { error: "invalid" });
    assert.equal((await claim(made.json.qr)).status, 404, "the QR is the same offer");
  });

  test("the QR's string claims as well as the digits, and spaces do not matter", async () => {
    const r = room();
    const made = await offer(r);
    const got = await claim(` ${made.json.qr.toUpperCase()} `, "iPad");
    assert.equal(got.status, 200);
    assert.equal(got.json.id, r.id);
    const r2 = room();
    const second = await offer(r2);
    const spaced = `${second.json.code.slice(0, 3)} ${second.json.code.slice(3)}`;
    assert.equal((await claim(spaced)).status, 200);
  });

  test("the notice waits for a Mac that is offline, and comes with its hello", async () => {
    const r = room();
    const made = await offer(r);
    assert.equal((await claim(made.json.code, "Allen's iPhone")).status, 200);
    const mac = await relay.mac(r.key, r.token);
    const notice = await mac.waitFor((m) => m.paired);
    assert.equal(notice.paired.device, "Allen's iPhone");
    mac.close();
    await sleep(200);
    const mac2 = await relay.mac(r.key, r.token);
    await sleep(400);
    assert.ok(!mac2.messages.some((m) => m.paired), "told once");
  });

  test("the phone is the owner at once, even before the Mac ever connected", async () => {
    const r = room();
    const made = await offer(r);
    const got = await claim(made.json.code);
    const phone = await relay.phone(r.id, got.json.token);
    assert.equal((await phone.waitFor((m) => m.level)).level, "owner");
    const stranger = await relay.phone(r.id, random(24));
    assert.equal((await stranger.waitFor((m) => m.level)).level, "status", "the room is not open to everyone");
    assert.equal((await cmd(r, got.json.token, { id: "c1", k: "hush" })).json.delivered, false);
  });

  test("a new offer replaces the Mac's previous one", async () => {
    const r = room();
    const first = await offer(r);
    const second = await offer(r);
    assert.notEqual(first.json.code, second.json.code);
    assert.equal((await claim(first.json.code)).status, 404);
    assert.equal((await claim(first.json.qr)).status, 404);
    assert.equal((await claim(second.json.code)).status, 200);
  });

  test("the page behind the QR names the app and never the token", async () => {
    const r = room();
    const made = await offer(r);
    const page = await relay.http("GET", `/pair/${made.json.qr}`);
    assert.equal(page.status, 200);
    assert.match(page.headers.get("content-type"), /text\/html/);
    assert.match(page.text, /brb:\/\/pair\?c=/);
    assert.ok(!page.text.includes(r.token));
    assert.ok(!page.text.includes(made.json.code));
    const used = await relay.http("GET", `/pair/${made.json.qr}`);
    assert.equal(used.status, 200, "the same page whatever the offer's state");
    assert.equal((await relay.http("GET", "/pair/!!")).status, 404);
  });

  test("bad requests", async () => {
    const r = room();
    assert.equal((await relay.http("POST", `/pair/${r.key}`, { body: {} })).status, 400);
    assert.equal((await relay.http("POST", `/pair/${r.key}`, { body: { token: "BAD token" } })).status, 400);
    assert.equal((await relay.http("POST", `/pair/${r.key}`, { body: { token: 12345678 } })).status, 400, "a number is not a token");
    assert.equal((await relay.http("POST", `/pair/${r.key}`, { raw: "not json" })).status, 400);
    assert.equal((await relay.http("PUT", `/pair/${r.key}`, { body: { token: r.token } })).status, 405);
    assert.equal((await relay.http("POST", "/claim", { body: {} })).status, 400);
    assert.equal((await relay.http("POST", "/claim", { body: { code: 123456 } })).status, 400);
    assert.equal((await relay.http("POST", "/claim", { raw: "{" })).status, 400);
    assert.equal((await relay.http("GET", "/claim")).status, 405);
    const none = await claim("000000", "x", { "CF-Connecting-IP": "10.9.9.1" });
    assert.equal(none.status, 404);
    assert.equal((await claim("", "x", { "CF-Connecting-IP": "10.9.9.2" })).status, 404);
  });

  test("a device name is clipped, and a missing one is iPhone", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const made = await offer(r, { name: "N".repeat(100), model: "M".repeat(100) });
    const got = await claim(made.json.code, "D".repeat(100));
    assert.equal(got.json.name.length, 40);
    assert.equal(got.json.model.length, 40);
    assert.equal((await mac.waitFor((m) => m.paired)).paired.device.length, 40);
    const made2 = await offer(r);
    await relay.http("POST", "/claim", { body: { code: made2.json.code } });
    assert.equal((await mac.waitFor((m) => m.paired?.device === "iPhone")).paired.device, "iPhone");
  });

  test("a reset forgets the offers made before it", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const made = await offer(r);
    await relay.http("POST", `/wipe/${r.key}`);
    await mac.waitClosed();
    assert.equal((await claim(made.json.code, "x", { "CF-Connecting-IP": "10.9.9.3" })).status, 404);
  });
});

describe("commands", () => {
  async function fixture() {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const pass = random(16);
    mac.send({ state: alarmState(pass) });
    const owner = await relay.phone(r.id, r.token);
    const guest = await relay.phone(r.id, pass);
    const stranger = await relay.phone(r.id, random(24));
    await guest.waitFor((m) => m.level === "pass" && m.state);
    return { r, mac, pass, owner, guest, stranger };
  }

  test("the owner's command reaches the Mac, with who it is from", async () => {
    const { r, mac } = await fixture();
    const sent = await cmd(r, r.token, { id: "c1", k: "hush" });
    assert.equal(sent.status, 200);
    assert.deepEqual(sent.json, { ok: true, delivered: true });
    assert.deepEqual(await mac.waitFor((m) => m.cmd), { cmd: { id: "c1", k: "hush" }, from: "phone" });
    for (const [id, k] of [["c2", "stop"], ["c3", "reset"]]) await cmd(r, r.token, { id, k });
    assert.deepEqual((await mac.waitFor((m) => m.cmd?.id === "c3")).cmd, { id: "c3", k: "reset" });
  });

  test("only what each kind uses is passed on", async () => {
    const { r, mac } = await fixture();
    await cmd(r, r.token, { id: "s1", k: "start", place: "transit", note: "n".repeat(80), test: true, vol: 5, evil: "x", from: "mac" });
    assert.deepEqual((await mac.waitFor((m) => m.cmd?.id === "s1")).cmd, { id: "s1", k: "start", place: "transit", note: "n".repeat(48), test: true });
    await cmd(r, r.token, { id: "s2", k: "start", place: "moon", test: "yes" });
    assert.deepEqual((await mac.waitFor((m) => m.cmd?.id === "s2")).cmd, { id: "s2", k: "start" });
    await cmd(r, r.token, { id: "s3", k: "set", place: "cafe", note: "hi", vol: 150, test: false, by: "face" });
    assert.deepEqual((await mac.waitFor((m) => m.cmd?.id === "s3")).cmd, { id: "s3", k: "set", place: "cafe", note: "hi", vol: 100, test: false });
    await cmd(r, r.token, { id: "s4", k: "disarm", by: "face", place: "cafe" });
    assert.deepEqual((await mac.waitFor((m) => m.cmd?.id === "s4")).cmd, { id: "s4", k: "disarm", by: "face" });
    await cmd(r, r.token, { id: "s5", k: "hush", by: "face", note: "x" });
    assert.deepEqual((await mac.waitFor((m) => m.cmd?.id === "s5")).cmd, { id: "s5", k: "hush" });
  });

  test("only the owner may command", async () => {
    const { r, mac, pass } = await fixture();
    for (const token of [pass, random(24), "", r.id, r.key]) {
      const res = await cmd(r, token, { id: "x1", k: "hush" });
      assert.equal(res.status, 403, `token ${token.slice(0, 6)}`);
    }
    assert.equal((await relay.http("POST", `/cmd/${r.id}`, { body: { id: "x1", k: "hush" } })).status, 403);
    await sleep(300);
    assert.ok(!mac.messages.some((m) => m.cmd), "nothing reached the Mac");
  });

  test("a room with no owner yet does not take commands from anyone", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token, { hello: 0 });
    mac.send({ state: { phase: "armed" } });
    const res = await cmd(r, "anything1", { id: "x1", k: "hush" });
    assert.equal(res.status, 403);
  });

  test("bad commands are refused", async () => {
    const { r } = await fixture();
    for (const body of [{ id: "x", k: "explode" }, { k: "hush" }, { id: "", k: "hush" }, { id: "i".repeat(25), k: "hush" }, { id: 5, k: "hush" }, []]) {
      assert.equal((await cmd(r, r.token, body)).status, 400, JSON.stringify(body));
    }
    assert.equal((await relay.http("POST", `/cmd/${r.id}?t=${r.token}`, { raw: "nope" })).status, 400);
    assert.equal((await relay.http("GET", `/cmd/${r.id}?t=${r.token}`)).status, 405);
  });

  test("a command over the socket is delivered too, and refused for those who may not", async () => {
    const { mac, owner, guest, stranger } = await fixture();
    owner.send({ cmd: { id: "w1", k: "hush", extra: 1 } });
    assert.deepEqual(await mac.waitFor((m) => m.cmd?.id === "w1"), { cmd: { id: "w1", k: "hush" }, from: "phone" });
    stranger.send({ cmd: { id: "w2", k: "hush" } });
    assert.deepEqual((await stranger.waitFor((m) => m.ack)).ack, { id: "w2", ok: false, why: "forbidden" });
    guest.send({ cmd: { id: "w3", k: "disarm", by: "face" } });
    assert.deepEqual((await guest.waitFor((m) => m.ack)).ack, { id: "w3", ok: false, why: "forbidden" });
    owner.send({ cmd: { id: "w4", k: "explode" } });
    assert.deepEqual((await owner.waitFor((m) => m.ack?.id === "w4")).ack, { id: "w4", ok: false, why: "bad-command" });
    owner.send("not json");
    owner.send({ state: macState({ phase: "idle" }) });  // a phone cannot speak for the Mac
    await sleep(300);
    assert.ok(!mac.messages.some((m) => m.cmd && m.cmd.id !== "w1"));
    assert.equal(owner.messages.at(-1).state?.phase ?? "triggered", "triggered");
  });

  test("the Mac's answer goes to the owner's phones and nobody else", async () => {
    const { r, mac, owner, guest, stranger } = await fixture();
    const second = await relay.phone(r.id, r.token);
    await cmd(r, r.token, { id: "a1", k: "start" });
    mac.send({ ack: { id: "a1", ok: false, why: "not-ready" } });
    for (const phone of [owner, second]) assert.deepEqual((await phone.waitFor((m) => m.ack)).ack, { id: "a1", ok: false, why: "not-ready" });
    mac.send({ ack: { id: "a2", ok: true } });
    assert.deepEqual((await owner.waitFor((m) => m.ack?.id === "a2")).ack, { id: "a2", ok: true });
    mac.send({ ack: { id: "x".repeat(40), ok: "yes", why: "w".repeat(40) } });
    assert.deepEqual((await owner.waitFor((m) => m.ack?.id.startsWith("xxx"))).ack, { id: "x".repeat(24), ok: false, why: "w".repeat(24) });
    await sleep(300);
    for (const phone of [guest, stranger]) assert.ok(!phone.messages.some((m) => m.ack), "not for them");
  });

  test("while the Mac is away, commands wait and arrive in order when it says hello", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const owner = await relay.phone(r.id, r.token);
    mac.send({ state: macState({ phase: "armed", since: Date.now() }) });
    await owner.waitFor((m) => m.state?.phase === "armed");
    mac.close();
    await owner.waitFor((m) => m.online === false);
    for (const [id, k] of [["q1", "hush"], ["q2", "stop"], ["q3", "disarm"]]) {
      assert.deepEqual((await cmd(r, r.token, { id, k })).json, { ok: true, delivered: false });
    }
    const back = await relay.mac(r.key, r.token);
    await back.waitFor((m) => m.cmd?.id === "q3");
    assert.deepEqual(back.messages.filter((m) => m.cmd).map((m) => [m.cmd.id, m.cmd.k, m.from]), [["q1", "hush", "phone"], ["q2", "stop", "phone"], ["q3", "disarm", "phone"]]);
    back.close();
    await owner.waitFor((m) => m.online === false && m.offlineAt > 0, 3000).catch(() => {});
    const later = await relay.mac(r.key, r.token);
    await sleep(500);
    assert.ok(!later.messages.some((m) => m.cmd), "delivered once");
  });

  test("a Mac that did not say v3 is not sent what waited", async () => {
    const r = room();
    const first = await relay.mac(r.key, r.token);
    const owner = await relay.phone(r.id, r.token);
    first.close();
    await owner.waitFor((m) => m.online === false);
    await cmd(r, r.token, { id: "q1", k: "hush" });
    const old = await relay.mac(r.key, r.token, { hello: 2 });
    await sleep(500);
    assert.ok(!old.messages.some((m) => m.cmd));
    old.close();
    await sleep(200);
    const current = await relay.mac(r.key, r.token);
    assert.equal((await current.waitFor((m) => m.cmd)).cmd.id, "q1", "kept for a Mac that can act on it");
  });

  test("at most 8 wait; the oldest are dropped", async () => {
    const r = room();
    const first = await relay.mac(r.key, r.token);
    const owner = await relay.phone(r.id, r.token);
    first.close();
    await owner.waitFor((m) => m.online === false);
    for (let i = 1; i <= 10; i++) await cmd(r, r.token, { id: `n${i}`, k: "set", vol: i });
    const back = await relay.mac(r.key, r.token);
    await back.waitFor((m) => m.cmd?.id === "n10");
    assert.deepEqual(back.messages.filter((m) => m.cmd).map((m) => m.cmd.id), ["n3", "n4", "n5", "n6", "n7", "n8", "n9", "n10"]);
  });

  test("a second Mac connection replaces the first", async () => {
    const r = room();
    const first = await relay.mac(r.key, r.token);
    const second = await relay.mac(r.key, r.token);
    await first.waitClosed();
    assert.equal((await cmd(r, r.token, { id: "r1", k: "hush" })).json.delivered, true);
    await second.waitFor((m) => m.cmd);
  });
});

describe("history", () => {
  const base = Date.now() - 3600_000;
  const session = (n, change = {}) => ({
    id: String(base + n * 300_000), start: base + n * 300_000, end: base + n * 300_000 + 200_000, place: "cafe", bumps: 2, kind: "alarm",
    trigger: "lifted", at: base + n * 300_000 + 100_000, how: "fingerprint", soft: 0, siren: 42, photos: [], events: [{ t: base, e: "armed", k: "cafe" }],
    clip: "alarm.mov", ...change,
  });
  const history = (r, token = r.token) => relay.http("GET", `/h/${r.id}?t=${token}`);

  test("the latest sessions, newest first, for the owner only", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    for (const n of [1, 3, 2]) mac.send({ session: session(n) });
    let got;
    for (let i = 0; i < 40 && (got = (await history(r)).json?.sessions)?.length !== 3; i++) await sleep(50);
    assert.deepEqual(got.map((s) => s.id), [3, 2, 1].map((n) => String(base + n * 300_000)));
    assert.deepEqual(got[2], session(1));
    assert.equal((await history(r, random(24))).status, 403);
    assert.equal((await history(r, "")).status, 403);
    const pass = random(16);
    mac.send({ state: alarmState(pass) });
    await sleep(200);
    assert.equal((await history(r, pass)).status, 403, "a pass is for one alarm");
  });

  test("a session is sanitized, and one without an id or end is ignored", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    mac.send({ session: session(1, { kind: "weird", place: "p".repeat(40), trigger: "", how: null, clip: null, at: null, photos: [1, "x", null, 2], bumps: -3, soft: 2.6, extra: 1 }) });
    mac.send({ session: { ...session(2), id: undefined } });
    mac.send({ session: { ...session(3), end: 0 } });
    mac.send({ session: { ...session(4), id: "bad id!" } });
    mac.send({ session: session(5) });
    let got;
    for (let i = 0; i < 40 && (got = (await history(r)).json?.sessions)?.length !== 2; i++) await sleep(50);
    assert.equal(got.length, 2);
    const clean = got[1];
    assert.deepEqual(clean, session(1, { kind: "quiet", place: "p".repeat(16), trigger: null, how: null, clip: null, at: null, photos: [], bumps: 0, soft: 3 }));
  });

  test("30 are kept", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    for (let n = 0; n < 33; n++) mac.send({ session: session(n) });
    let got;
    for (let i = 0; i < 60 && (got = (await history(r)).json?.sessions)?.length !== 30; i++) await sleep(50);
    assert.equal(got.length, 30);
    assert.equal(got[0].id, String(base + 32 * 300_000));
    assert.equal(got.at(-1).id, String(base + 3 * 300_000));
    await sleep(200);
    assert.equal((await history(r)).json.sessions.length, 30);
  });

  test("deleting a session deletes its photos; deleting the photos keeps the list", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const pass1 = random(16), pass2 = random(16);
    const s1 = session(1), s2 = session(2);
    const t1 = s1.start + 1000, t2 = s2.start + 1000;
    mac.send({ state: alarmState(pass1) });
    await upload(r, t1, pass1);
    await upload(r, t1 + 1, pass1);
    await upload(r, t2, pass2);
    mac.send({ session: { ...s1, photos: [t1, t1 + 1] } });
    mac.send({ session: { ...s2, photos: [t2] } });
    let got;
    for (let i = 0; i < 40 && (got = (await history(r)).json?.sessions)?.length !== 2; i++) await sleep(50);
    assert.deepEqual(got.map((s) => s.photos), [[t2], [t1, t1 + 1]]);

    assert.equal((await relay.http("DELETE", `/h/${r.id}/${s1.id}?t=${random(24)}`)).status, 403);
    assert.equal((await photo(r, t1, r.token)).status, 200);
    const deleted = await relay.http("DELETE", `/h/${r.id}/${s1.id}?t=${r.token}`);
    assert.equal(deleted.status, 200);
    assert.deepEqual((await history(r)).json.sessions.map((s) => s.id), [s2.id]);
    assert.equal((await photo(r, t1, r.token)).status, 404);
    assert.equal((await photo(r, t1 + 1, r.token)).status, 404);
    assert.equal((await photo(r, t2, r.token)).status, 200, "another session's photos stay");
    assert.equal((await relay.http("DELETE", `/h/${r.id}/${s1.id}?t=${r.token}`)).status, 200, "idempotent");

    mac.send({ session: { ...s1, photos: [t1] } });
    for (let i = 0; i < 40 && (await history(r)).json.sessions.length !== 2; i++) await sleep(50);
    assert.equal((await relay.http("DELETE", `/h/${r.id}?t=${random(24)}`)).status, 403);
    assert.equal((await relay.http("DELETE", `/h/${r.id}?t=${r.token}`)).status, 200);
    assert.equal((await photo(r, t2, r.token)).status, 404, "every photo");
    const after = (await history(r)).json.sessions;
    assert.equal(after.length, 2, "the list stays");
    assert.deepEqual(after.map((s) => s.photos), [[], []], "with no photos left to open");
  });

  test("bad ids and methods", async () => {
    const r = room();
    assert.equal((await relay.http("DELETE", `/h/${r.id}/${"x".repeat(30)}?t=${r.token}`)).status, 404);
    assert.equal((await relay.http("POST", `/h/${r.id}?t=${r.token}`)).status, 405);
    assert.equal((await relay.http("GET", `/h/${r.id}?t=${r.token}`)).status, 403, "a room with no owner");
  });
});

describe("devices", () => {
  const device = (n, change = {}) => ({
    dev: `DEVICE-${String(n).padStart(4, "0")}-AAAA`, name: "Allen's iPhone", apns: "ab".repeat(32), env: "sandbox", lang: "zh", crit: true, pro: false,
    events: { siren: true, back: true, disarm: true, guard: false, sensor: true }, la: null, laStart: null, ...change,
  });
  const register = (r, body, token = r.token) => relay.http("POST", `/device/${r.id}?t=${token}`, { body });
  const forget = (r, dev, token = r.token) => relay.http("DELETE", `/device/${r.id}/${dev}?t=${token}`);

  test("register, update and unregister", async () => {
    const r = room();
    await relay.mac(r.key, r.token);
    assert.deepEqual((await register(r, device(1))).json, { ok: true });
    assert.equal((await register(r, device(1, { name: "Renamed", la: "cd".repeat(40), laStart: "ef".repeat(40) }))).status, 200);
    assert.equal((await register(r, device(2, { apns: null }))).status, 200, "no push token yet");
    assert.equal((await forget(r, device(1).dev)).status, 200);
    assert.equal((await forget(r, device(1).dev)).status, 200, "idempotent");
  });

  test("only the owner may", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const pass = random(16);
    mac.send({ state: alarmState(pass) });
    await sleep(200);
    for (const token of [random(24), pass, ""]) {
      assert.equal((await register(r, device(1), token)).status, 403);
      assert.equal((await forget(r, device(1).dev, token)).status, 403);
      assert.equal((await relay.http("POST", `/test-push/${r.id}?t=${token}`)).status, 403);
    }
  });

  test("a registration with something wrong is refused", async () => {
    const r = room();
    await relay.mac(r.key, r.token);
    for (const bad of [null, {}, device(1, { dev: "short" }), device(1, { dev: "has space in it" }), device(1, { apns: "not hex!" }), device(1, { la: 5 }), device(1, { laStart: "zz".repeat(20) })]) {
      assert.equal((await register(r, bad)).status, 400, JSON.stringify(bad)?.slice(0, 60));
    }
    assert.equal((await relay.http("POST", `/device/${r.id}?t=${r.token}`, { raw: "{{" })).status, 400);
    assert.equal((await relay.http("DELETE", `/device/${r.id}/short?t=${r.token}`)).status, 404);
    assert.equal((await relay.http("GET", `/device/${r.id}?t=${r.token}`)).status, 405);
  });

  test("a test alert says push is not set up when the relay has no APNs secrets", async () => {
    const r = room();
    await relay.mac(r.key, r.token);
    await register(r, device(1));
    const res = await relay.http("POST", `/test-push/${r.id}?t=${r.token}`);
    assert.equal(res.status, 501);
    assert.deepEqual(res.json, { error: "push not configured" });
  });

  test("an alarm with devices registered and no APNs secrets does nothing and breaks nothing", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    await register(r, device(1, { la: "cd".repeat(40) }));
    const owner = await relay.phone(r.id, r.token);
    mac.send({ state: alarmState(random(16)) });
    assert.equal((await owner.waitFor((m) => m.state?.phase === "triggered")).level, "owner");
  });

  test("photos are kept 7 days, 30 when a device says Pro", async () => {
    const r = room();
    const mac = await relay.mac(r.key, r.token);
    const pass = random(16);
    mac.send({ state: alarmState(pass) });
    const old = Date.now() - 10 * DAY, ancient = Date.now() - 40 * DAY, fresh = Date.now() - 6 * DAY;
    await upload(r, old, pass);
    await upload(r, fresh, pass);
    assert.equal((await photo(r, old, r.token)).status, 404, "10 days is too old without Pro");
    assert.equal((await photo(r, fresh, r.token)).status, 200, "6 days is fine");

    await register(r, device(1, { pro: true }));
    await upload(r, old, pass);
    await upload(r, ancient, pass);
    assert.equal((await photo(r, old, r.token)).status, 200, "10 days is fine with Pro");
    assert.equal((await photo(r, ancient, r.token)).status, 404, "40 days is too old for anyone");

    await forget(r, device(1).dev);
    assert.equal((await photo(r, old, r.token)).status, 404, "Pro gone, the old photo goes with it");
    assert.equal((await photo(r, fresh, r.token)).status, 200);
  });
});
