// The public pages the App Store listing and the apps link to.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { startRelay } from "./harness.mjs";

let relay;
before(async () => { relay = await startRelay({ SUPPORT_EMAIL: "help@example.com" }); });
after(async () => { await relay?.stop(); });

describe("pages", () => {
  for (const page of ["privacy", "terms", "support"]) {
    test(`/${page} in English and Chinese`, async () => {
      const en = await relay.http("GET", `/${page}?lang=en`);
      assert.equal(en.status, 200);
      assert.match(en.headers.get("content-type"), /^text\/html/);
      assert.match(en.text, /<html lang="en">/);
      const zh = await relay.http("GET", `/${page}?lang=zh`);
      assert.equal(zh.status, 200);
      assert.match(zh.text, /<html lang="zh-Hans">/);
      for (const r of [en, zh]) {
        assert.match(r.text, /mailto:help@example\.com/, "the support address is filled in");
        assert.doesNotMatch(r.text, /\{\{|\}\}/, "no placeholder is left");
        assert.doesNotMatch(r.text, /<script/i);
      }
    });
  }

  test("the language follows the browser unless the link names one", async () => {
    const zh = await relay.http("GET", "/privacy", { headers: { "accept-language": "zh-CN,zh;q=0.9,en;q=0.8" } });
    assert.match(zh.text, /<h1>隐私政策<\/h1>/);
    const en = await relay.http("GET", "/privacy", { headers: { "accept-language": "en-GB,zh;q=0.5" } });
    assert.match(en.text, /<h1>Privacy Policy<\/h1>/);
    assert.match((await relay.http("GET", "/privacy")).text, /<h1>Privacy Policy<\/h1>/, "English by default");
    const asked = await relay.http("GET", "/terms?lang=en", { headers: { "accept-language": "zh-CN" } });
    assert.match(asked.text, /<h1>Terms of Use<\/h1>/);
  });

  test("the Markdown becomes tables, lists and links", async () => {
    const r = await relay.http("GET", "/privacy?lang=en");
    assert.match(r.text, /<table><tr><th>Data<\/th>/);
    assert.match(r.text, /<li>/);
    assert.match(r.text, /<a href="https:\/\/www\.cloudflare\.com\/privacypolicy\/">/);
    assert.match(r.text, /<code>~\/Movies\/BRB\/<\/code>/);
    assert.match(r.text, /Effective 20\d\d-\d\d-\d\d/);
  });

  test("/mac goes to the download", async () => {
    const r = await fetch(`http://${relay.origin}/mac`, { redirect: "manual" });
    assert.equal(r.status, 302);
    assert.equal(r.headers.get("location"), "https://github.com/samsara0xgg/BRB/releases/latest/download/BRB.dmg");
  });

  test("only GET, and nothing below a page", async () => {
    assert.equal((await relay.http("POST", "/privacy")).status, 405);
    assert.equal((await relay.http("GET", "/privacy/x")).status, 404);
    assert.equal((await relay.http("GET", "/v/abcdefgh12")).status, 200, "the phone page still works");
  });
});

describe("pages without a support address", () => {
  let bare;
  before(async () => { bare = await startRelay({ MAC_DOWNLOAD: "https://example.com/BRB.dmg" }); });
  after(async () => { await bare?.stop(); });

  test("say the address is coming, and /mac goes where MAC_DOWNLOAD says", async () => {
    const r = await bare.http("GET", "/support?lang=zh");
    assert.match(r.text, /支持邮箱即将公布/);
    assert.doesNotMatch(r.text, /mailto:/);
    const mac = await fetch(`http://${bare.origin}/mac`, { redirect: "manual" });
    assert.equal(mac.headers.get("location"), "https://example.com/BRB.dmg");
  });
});
