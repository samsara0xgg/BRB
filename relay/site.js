// The relay's public pages, which the App Store listing and both apps link to: /privacy, /terms and
// /support in English and Chinese (?lang=en or zh, else the browser's first language), and /mac,
// which sends people to the Mac download. The links live here rather than in the apps so a page, the
// support address or the download can change without an app update.
//
// Optional: SUPPORT_EMAIL, the address the pages give; MAC_DOWNLOAD, where /mac goes (the latest
// GitHub release by default).

import privacyEn from "./legal/privacy.en.md";
import privacyZh from "./legal/privacy.zh.md";
import termsEn from "./legal/terms.en.md";
import termsZh from "./legal/terms.zh.md";

const MAC_DOWNLOAD = "https://github.com/samsara0xgg/BRB/releases/latest/download/BRB.dmg";

/// The day the privacy policy and terms last changed. Bump it with them.
const UPDATED = "2026-10-18";

export const PAGES = new Set(["privacy", "terms", "support", "mac"]);

export function site(request, env, route, url) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("GET only", { status: 405, headers: { "content-type": "text/plain; charset=utf-8", allow: "GET, HEAD" } });
  }
  if (route === "mac") {
    return new Response(null, { status: 302, headers: { location: env.MAC_DOWNLOAD || MAC_DOWNLOAD, "cache-control": "no-store" } });
  }
  const lang = language(url, request);
  const doc = { privacy: PRIVACY, terms: TERMS, support: SUPPORT }[route][lang];
  const body = (doc.md ? markdown(doc.md, lang) : doc.body).replaceAll("{{email}}", email(env.SUPPORT_EMAIL, lang));
  return new Response(shell(route, lang, doc.title, body), {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=300",
      "content-language": lang === "zh" ? "zh-Hans" : "en",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
    },
  });
}

function language(url, request) {
  const asked = url.searchParams.get("lang");
  if (asked === "en" || asked === "zh") return asked;
  return /^\s*zh\b/i.test(request.headers.get("accept-language") ?? "") ? "zh" : "en";
}

function email(address, lang) {
  const a = (address ?? "").trim();
  if (!/^[^\s@<>"&]+@[^\s@<>"&]+\.[^\s@<>"&]+$/.test(a)) return lang === "zh" ? "（支持邮箱即将公布）" : "(support address coming soon)";
  return `<a href="mailto:${a}?subject=BRB">${a}</a>`;
}

/// The little Markdown the documents in legal/ use: ## and ### headings, paragraphs, "- " lists,
/// tables, **bold**, `code` and bare https links. Everything else is text.
function markdown(md, lang) {
  const out = [`  <p class="dim">${lang === "zh" ? "生效日期" : "Effective"} ${UPDATED}</p>`];
  const lines = md.split("\n");
  for (let i = 0; i < lines.length;) {
    const line = lines[i];
    const heading = /^(#{2,3}) (.*)$/.exec(line);
    if (!line.trim()) {
      i++;
    } else if (heading) {
      const n = heading[1].length;
      out.push(`  <h${n}>${inline(heading[2])}</h${n}>`);
      i++;
    } else if (line.startsWith("|")) {
      const rows = [];
      while (i < lines.length && lines[i].startsWith("|")) rows.push(lines[i++]);
      const cells = (row, tag) => row.trim().slice(1, -1).split("|").map((c) => `<${tag}>${inline(c.trim())}</${tag}>`).join("");
      const [head, , ...body] = rows;
      out.push(`  <div class="table"><table><tr>${cells(head, "th")}</tr>${body.map((r) => `<tr>${cells(r, "td")}</tr>`).join("")}</table></div>`);
    } else if (line.startsWith("- ")) {
      const items = [];
      while (i < lines.length && lines[i].startsWith("- ")) items.push(lines[i++].slice(2));
      out.push(`  <ul>${items.map((x) => `<li>${inline(x)}</li>`).join("")}</ul>`);
    } else {
      const para = [];
      while (i < lines.length && lines[i].trim() && !/^(#|\||- )/.test(lines[i])) para.push(lines[i++]);
      out.push(`  <p>${inline(para.join(" "))}</p>`);
    }
  }
  return out.join("\n");
}

function inline(s) {
  return s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
    .replace(/https:\/\/[^\s<>()（）]*[^\s<>()（）.,;:。，；：]/g, (u) => `<a href="${u}">${u}</a>`);
}

function shell(route, lang, title, body) {
  const zh = lang === "zh";
  const other = zh ? "en" : "zh";
  const nav = [["support", zh ? "支持" : "Support"], ["privacy", zh ? "隐私政策" : "Privacy Policy"], ["terms", zh ? "用户协议" : "Terms of Use"]]
    .map(([r, name]) => (r === route ? `<span>${name}</span>` : `<a href="/${r}?lang=${lang}">${name}</a>`))
    .join("");
  return `<!doctype html>
<html lang="${zh ? "zh-Hans" : "en"}">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<title>${title} · BRB</title>
<style>
  :root { --bg: #f7f7f9; --ink: #16181d; --dim: #5d6270; --rim: #e3e4e9; --link: #b26a00; color-scheme: light dark; }
  @media (prefers-color-scheme: dark) { :root { --bg: #0b0f1c; --ink: #eef1f8; --dim: rgba(238, 241, 248, .62); --rim: rgba(255, 255, 255, .12); --link: #f6b544; } }
  * { box-sizing: border-box; }
  html, body { margin: 0; background: var(--bg); color: var(--ink); }
  body { font: 16px/1.6 -apple-system, BlinkMacSystemFont, "PingFang SC", "Helvetica Neue", sans-serif; padding: calc(16px + env(safe-area-inset-top)) 16px calc(32px + env(safe-area-inset-bottom)); }
  main { max-width: 680px; margin: 0 auto; }
  header { display: flex; align-items: center; gap: 10px; padding-bottom: 14px; border-bottom: 1px solid var(--rim); }
  header svg { width: 26px; height: 26px; flex: none; }
  header b { flex: 1; font-size: 17px; }
  a { color: var(--link); }
  h1 { font-size: 28px; line-height: 1.25; margin: 24px 0 4px; }
  h2 { font-size: 19px; margin: 28px 0 6px; }
  h3 { font-size: 16px; margin: 20px 0 4px; }
  p, li { color: var(--ink); }
  .dim, small { color: var(--dim); }
  ul { padding-left: 1.3em; }
  li { margin: 4px 0; }
  .table { overflow-x: auto; margin: 8px 0; }
  table { border-collapse: collapse; width: 100%; min-width: 560px; font-size: 14px; }
  code { font: 13px ui-monospace, Menlo, monospace; overflow-wrap: anywhere; }
  th, td { text-align: left; vertical-align: top; padding: 8px 10px 8px 0; border-bottom: 1px solid var(--rim); }
  nav { display: flex; flex-wrap: wrap; gap: 16px; margin-top: 40px; padding-top: 14px; border-top: 1px solid var(--rim); font-size: 14px; }
  nav span { color: var(--dim); }
</style>
<main>
  <header>
    <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.8 19.4 5.6v5.8c0 4.8-3.1 8.6-7.4 10.1-4.3-1.5-7.4-5.3-7.4-10.1V5.6Z" fill="#f6b544"/><circle cx="12" cy="11.4" r="2.4" fill="#2b1a00"/></svg>
    <b>BRB</b>
    <a href="/${route}?lang=${other}" hreflang="${other === "zh" ? "zh-Hans" : "en"}">${zh ? "English" : "中文"}</a>
  </header>
  <h1>${title}</h1>
${body}
  <nav>${nav}</nav>
</main>
</html>`;
}

const PRIVACY = {
  en: { title: "Privacy Policy", md: privacyEn },
  zh: { title: "隐私政策", md: privacyZh },
};

const TERMS = {
  en: { title: "Terms of Use", md: termsEn },
  zh: { title: "用户协议", md: termsZh },
};

const SUPPORT = {
  en: {
    title: "Support",
    body: `
  <p>Something not working, or an idea? Email {{email}}. Say which Mac and macOS version you have, your iPhone's iOS version, and what happened when. We read every message.</p>

  <h2>Get the Mac app</h2>
  <p>BRB for Mac needs a MacBook with Apple silicon and macOS 14 or later. <a href="/mac">Download BRB.dmg</a>, open it, drag BRB into Applications and open it from there.</p>

  <h2>Questions</h2>
  <h3>How do I pair my iPhone with my Mac?</h3>
  <p>On the Mac, click the BRB shield in the menu bar and choose “Settings…”, then “Phone” and “Pair iPhone…”. Scan the code on the Mac's screen with BRB on your iPhone, or type the six digits.</p>
  <h3>Will my phone ring on silent?</h3>
  <p>Yes, with “Ring when silenced” on. Only alarms use it.</p>
  <h3>A friend bumped my Mac. Now what?</h3>
  <p>Tap Disarm on the alarm screen and confirm with Face ID, or use Touch ID on the Mac.</p>
  <h3>Stop siren or Disarm?</h3>
  <p>Stop siren only silences it: the Mac stays locked and keeps filming, and lifting it again restarts the siren. Disarm ends the session.</p>
  <h3>How do I delete what BRB keeps online?</h3>
  <p>On the Mac, open “Settings…”, then “Phone” and “Reset link…”. The photos, history and pairings kept for your Mac are deleted at once, and every paired iPhone is unpaired. Deleting BRB from your iPhone deletes what it keeps on the phone. See the <a href="/privacy?lang=en">Privacy Policy</a> for the details.</p>`,
  },
  zh: {
    title: "支持",
    body: `
  <p>遇到问题，或者有建议，发邮件到 {{email}}。写上 Mac 型号和 macOS 版本、iPhone 的 iOS 版本，以及什么时候出了什么事。每封邮件我们都会看。</p>

  <h2>下载 Mac 版</h2>
  <p>BRB Mac 版需要 Apple 芯片的 MacBook，macOS 14 或更新。<a href="/mac">下载 BRB.dmg</a>，打开后把 BRB 拖进「应用程序」，再从那里打开。</p>

  <h2>常见问题</h2>
  <h3>怎么把 iPhone 和 Mac 配对？</h3>
  <p>在 Mac 上点菜单栏的 BRB 盾牌，选「设置…」，再点「手机」和「配对 iPhone…」。用 iPhone 上的 BRB 扫 Mac 屏幕上的码，或者输入那 6 位数字。</p>
  <h3>手机静音时，报警会响吗？</h3>
  <p>打开「静音也响」就会。只有报警用它。</p>
  <h3>朋友不小心碰了电脑怎么办？</h3>
  <p>在报警页点「解除警报」，用 Face ID 确认；或者回到 Mac 前按指纹。</p>
  <h3>「停止鸣笛」和「解除警报」有什么不同？</h3>
  <p>停止鸣笛只让它安静，Mac 仍锁屏、继续录像，再被拿起会重新响。解除警报会结束这次守护。</p>
  <h3>怎么删除 BRB 存在云端的数据？</h3>
  <p>在 Mac 上打开「设置…」，点「手机」和「重置链接…」。为这台 Mac 存的照片、记录和配对会马上删除，所有配对过的 iPhone 都会解除配对。从 iPhone 上删除 BRB，会删掉手机里存的数据。详细内容见<a href="/privacy?lang=zh">隐私政策</a>。</p>`,
  },
};
