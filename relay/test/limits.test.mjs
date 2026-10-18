// What needs short timers: offers that expire, guesses that run out, commands that go stale. The worker
// is started with its TTLs and limits turned down through the same vars a deployment could set.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { macState, random, room, sleep, startRelay } from "./harness.mjs";

const pool = Array.from({ length: 30 }, room);
const stranger = room();  // not in CAM_IDS
let relay;
before(async () => {
  relay = await startRelay({
    PAIR_TTL_MS: 1500, PAIR_TRIES: 3, PAIR_WINDOW_MS: 3000, START_TTL_MS: 1000, CMD_TTL_MS: 3500,
    CAM_IDS: pool.map((r) => r.id).join(","),
  });
});
after(async () => { await relay?.stop(); });

const offer = (r) => relay.http("POST", `/pair/${r.key}`, { body: { token: r.token, name: "Mac", model: "Model" } });
const claim = (code, ip) => relay.http("POST", "/claim", { body: { code, device: "Phone" }, headers: ip ? { "CF-Connecting-IP": ip } : {} });
const cmd = (r, body) => relay.http("POST", `/cmd/${r.id}?t=${r.token}`, { body });

describe("pairing limits", () => {
  test("an offer lasts its TTL, then says expired", async () => {
    const r = pool.pop();
    const made = await offer(r);
    assert.ok(made.json.expires - Date.now() <= 1500);
    await sleep(1700);
    const late = await claim(made.json.code, "10.1.0.1");
    assert.equal(late.status, 410);
    assert.deepEqual(late.json, { error: "expired" });
    assert.equal((await claim(made.json.qr, "10.1.0.1")).status, 410, "the QR's string too");
    assert.equal((await claim("999999", "10.1.0.1")).status, 404);
    assert.equal((await claim(made.json.code, "10.1.0.1")).status, 429, "a late try counts as a wrong one");
  });

  test("an offer claimed in time works, and a fresh one replaces an expired one", async () => {
    const r = pool.pop();
    await offer(r);
    await sleep(1700);
    const fresh = await offer(r);
    assert.equal((await claim(fresh.json.code, "10.1.0.2")).status, 200);
  });

  test("8 wrong guesses become 3 here; then even the right code is turned away until the window passes", async () => {
    const r = pool.pop();
    const made = await offer(r);
    for (let i = 0; i < 3; i++) assert.equal((await claim(`00000${i}`, "10.2.0.1")).status, 404);
    const blocked = await claim(made.json.code, "10.2.0.1");
    assert.equal(blocked.status, 429);
    assert.deepEqual(blocked.json, { error: "slow down" });
    assert.ok(Number(blocked.headers.get("retry-after")) >= 1);
    assert.equal((await claim(made.json.code, "10.2.0.2")).status, 200, "another address is not held back");
    await sleep(3200);
    const again = await offer(r);
    assert.equal((await claim(again.json.code, "10.2.0.1")).status, 200, "the window passed");
  });

  test("right guesses do not count against anyone", async () => {
    for (let i = 0; i < 5; i++) {
      const r = pool.pop();
      const made = await offer(r);
      assert.equal((await claim(made.json.code, "10.3.0.1")).status, 200);
    }
  });

  test("an IPv6 household is one address", async () => {
    for (let i = 0; i < 3; i++) await claim(`00001${i}`, `2001:db8:1:2:aaaa::${i + 1}`);
    assert.equal((await claim("000019", "2001:db8:1:2:bbbb::9")).status, 429);
    assert.equal((await claim("000019", "2001:db8:1:3:bbbb::9")).status, 404, "the next /64 is another");
  });
});

describe("stale commands", () => {
  test("a start waits 30 s (1 s here), the rest longer; the phone is told what went stale", async () => {
    const r = pool.pop();
    const first = await relay.mac(r.key, r.token);
    const owner = await relay.phone(r.id, r.token);
    first.close();
    await owner.waitFor((m) => m.online === false);
    assert.equal((await cmd(r, { id: "st1", k: "start", place: "cafe" })).json.delivered, false);
    assert.equal((await cmd(r, { id: "hu1", k: "hush" })).json.delivered, false);
    await sleep(1300);
    const back = await relay.mac(r.key, r.token);
    await back.waitFor((m) => m.cmd);
    assert.deepEqual(back.messages.filter((m) => m.cmd).map((m) => m.cmd.id), ["hu1"], "the start is gone");
    assert.deepEqual((await owner.waitFor((m) => m.ack)).ack, { id: "st1", ok: false, why: "expired" });
  });

  test("everything goes stale in the end", async () => {
    const r = pool.pop();
    const first = await relay.mac(r.key, r.token);
    const owner = await relay.phone(r.id, r.token);
    first.close();
    await owner.waitFor((m) => m.online === false);
    await cmd(r, { id: "old1", k: "disarm", by: "face" });
    await sleep(3700);
    await cmd(r, { id: "new1", k: "hush" });
    const back = await relay.mac(r.key, r.token);
    await back.waitFor((m) => m.cmd);
    assert.deepEqual(back.messages.filter((m) => m.cmd).map((m) => m.cmd.id), ["new1"]);
    assert.deepEqual((await owner.waitFor((m) => m.ack)).ack, { id: "old1", ok: false, why: "expired" });
  });

  test("a start sent to a Mac that is here is not delayed by any of this", async () => {
    const r = pool.pop();
    const mac = await relay.mac(r.key, r.token);
    mac.send({ state: macState() });
    assert.equal((await cmd(r, { id: "now1", k: "start" })).json.delivered, true);
    assert.equal((await mac.waitFor((m) => m.cmd)).cmd.id, "now1");
  });
});

describe("CAM_IDS", () => {
  test("a camera outside the list is turned away from the camera routes only", async () => {
    await assert.rejects(relay.mac(stranger.key, stranger.token));
    assert.equal((await relay.http("POST", `/photo/${stranger.key}?t=${Date.now()}&pass=${random(16)}`, { raw: Buffer.alloc(10, 1) })).status, 403);
    assert.equal((await offer(stranger)).status, 403, "it cannot pair either");
    const phone = await relay.phone(stranger.id, random(12));
    assert.equal((await phone.waitFor((m) => m.level)).online, false);
    assert.equal((await relay.http("GET", `/state/${stranger.id}`)).status, 404);
  });

  test("a camera on the list is let in", async () => {
    const r = pool.pop();
    assert.equal((await offer(r)).status, 200);
    const mac = await relay.mac(r.key, r.token);
    assert.ok(mac);
  });
});
