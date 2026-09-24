import { DurableObject } from "cloudflare:workers";

// One Room per Mac. The Mac connects to /cam/<key>; phones open /v/<id> and watch /watch/<id>,
// where id = the first 32 hex chars of sha256(key). A view link therefore lets you watch, not pose
// as the camera. The Mac sends JPEG frames only while the Room says someone is watching.
export default {
  async fetch(request, env) {
    const [, route, token] = new URL(request.url).pathname.split("/");
    if (!/^[a-z0-9]{20,64}$/.test(token ?? "")) return new Response("not found", { status: 404 });
    if (route === "v") return new Response(PAGE, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });
    if (route !== "cam" && route !== "watch") return new Response("not found", { status: 404 });
    if (request.headers.get("Upgrade") !== "websocket") return new Response("websocket only", { status: 426 });
    const id = route === "cam" ? await viewId(token) : token;
    return env.ROOMS.get(env.ROOMS.idFromName(id)).fetch(request);
  },
};

async function viewId(key) {
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key)));
  return [...hash].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

export class Room extends DurableObject {
  async fetch(request) {
    const role = new URL(request.url).pathname.startsWith("/cam/") ? "cam" : "viewer";
    const [client, server] = Object.values(new WebSocketPair());
    if (role === "cam") for (const old of this.ctx.getWebSockets("cam")) old.close(1000, "replaced");
    this.ctx.acceptWebSocket(server, [role]);
    this.announce();
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws, message) {
    if (!this.ctx.getTags(ws).includes("cam") || typeof message === "string") return;
    for (const viewer of this.ctx.getWebSockets("viewer")) {
      try { viewer.send(message); } catch {}
    }
  }

  webSocketClose(ws) {
    this.announce(ws);
  }

  webSocketError(ws) {
    this.announce(ws);
  }

  /// Tells the Mac how many are watching, and the watchers whether the Mac is connected.
  announce(gone) {
    const cams = this.ctx.getWebSockets("cam").filter((w) => w !== gone);
    const viewers = this.ctx.getWebSockets("viewer").filter((w) => w !== gone);
    for (const cam of cams) try { cam.send(JSON.stringify({ viewers: viewers.length })); } catch {}
    for (const viewer of viewers) try { viewer.send(JSON.stringify({ cam: cams.length > 0 })); } catch {}
  }
}

const PAGE = `<!doctype html>
<html lang="zh">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>GuardMode 实时画面</title>
<style>
  html, body { margin: 0; height: 100%; background: #000; color: #ddd; font: 15px -apple-system, sans-serif; }
  img { display: block; width: 100%; height: 100%; object-fit: contain; }
  #status { position: fixed; left: 0; right: 0; bottom: 0; padding: 12px 16px calc(12px + env(safe-area-inset-bottom));
            background: rgba(0, 0, 0, .6); text-align: center; }
</style>
<img id="frame" alt="">
<div id="status">连接中…</div>
<script>
  const id = location.pathname.split("/")[2];
  const img = document.getElementById("frame"), status = document.getElementById("status");
  let shown = null, last = 0, camOnline = false;
  function connect() {
    const ws = new WebSocket("wss://" + location.host + "/watch/" + id);
    ws.binaryType = "blob";
    ws.onmessage = (e) => {
      if (typeof e.data === "string") {
        camOnline = JSON.parse(e.data).cam;
        if (!camOnline) status.textContent = "电脑不在线：警戒没开，或者电脑断网了";
        else if (!last) status.textContent = "等待画面…";
        return;
      }
      const url = URL.createObjectURL(e.data);
      img.onload = () => { if (shown) URL.revokeObjectURL(shown); shown = url; };
      img.src = url;
      last = Date.now();
    };
    ws.onclose = () => { status.textContent = "连接断开，正在重连…"; setTimeout(connect, 2000); };
  }
  // The frame time, so a frozen picture (lid shut, network gone) is easy to spot.
  setInterval(() => {
    if (!last || !camOnline) return;
    const age = Math.round((Date.now() - last) / 1000);
    status.textContent = age < 3 ? "实时画面，同时在录像" : "画面停在 " + age + " 秒前：可能合上了盖子或者网络不好";
  }, 1000);
  connect();
</script>
</html>`;
