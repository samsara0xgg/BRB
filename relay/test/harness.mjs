// Starts the real worker with `wrangler dev --local`, and gives the tests a fake Mac and fake phones.
import { spawn } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789";
export const random = (n) => Array.from(randomBytes(n), (b) => ALPHABET[b % ALPHABET.length]).join("");
export const roomId = (key) => createHash("sha256").update(key).digest("hex").slice(0, 32);

/// A Mac's room: its key, id and owner token.
export function room() {
  const key = random(32);
  return { key, id: roomId(key), token: random(24) };
}

/// Waits until `check()` is true.
export async function until(check, ms = 5000) {
  const end = Date.now() + ms;
  while (!check()) {
    if (Date.now() > end) throw new Error("timed out waiting for a condition");
    await sleep(25);
  }
}

function freePort() {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
  });
}

/// `vars` become the worker's environment (`--var`), as the secrets of a deployment would be.
export async function startRelay(vars = {}, { dir = root } = {}) {
  const port = await freePort();
  const inspector = await freePort();
  const state = await mkdtemp(join(tmpdir(), "brb-relay-"));
  const args = [
    join(root, "node_modules/wrangler/bin/wrangler.js"), "dev", "--local", "--ip", "127.0.0.1", "--port", String(port),
    "--inspector-port", String(inspector), "--persist-to", state,
    ...Object.entries(vars).flatMap(([name, value]) => ["--var", `${name}:${value}`]),
  ];
  const quiet = `${process.env.NO_PROXY ?? ""},127.0.0.1,localhost`;
  const child = spawn(process.execPath, args, {
    cwd: dir,
    detached: true,  // its own process group, so the workerd under it goes too
    env: { ...process.env, WRANGLER_SEND_METRICS: "false", NO_COLOR: "1", NO_PROXY: quiet, no_proxy: quiet },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let log = "";
  const ready = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`wrangler dev did not start in 90 s:\n${log}`)), 90_000);
    const listen = (chunk) => {
      log += chunk;
      if (/Ready on/.test(log)) {
        clearTimeout(timer);
        resolve();
      }
    };
    child.stdout.on("data", listen);
    child.stderr.on("data", listen);
    child.on("exit", (code) => {
      clearTimeout(timer);
      reject(new Error(`wrangler dev exited with ${code}:\n${log}`));
    });
  });
  const clients = [];
  const stop = async () => {
    for (const client of clients) client.close();
    child.removeAllListeners("exit");
    try { process.kill(-child.pid, "SIGTERM"); } catch {}
    await sleep(300);
    try { process.kill(-child.pid, "SIGKILL"); } catch {}
    await rm(state, { recursive: true, force: true });
  };
  try {
    await ready;
  } catch (e) {
    await stop();
    throw e;
  }
  const origin = `127.0.0.1:${port}`;
  const relay = {
    origin,
    log: () => log,
    stop,

    /// A request, with the body as JSON if it is an object. `json` is the parsed reply when there is one.
    async http(method, path, { body, headers = {}, raw } = {}) {
      const response = await fetch(`http://${origin}${path}`, {
        method,
        headers: { ...(body !== undefined ? { "content-type": "application/json" } : {}), ...headers },
        body: raw ?? (body === undefined ? undefined : JSON.stringify(body)),
      });
      const bytes = Buffer.from(await response.arrayBuffer());
      let json = null;
      try { json = JSON.parse(bytes.toString()); } catch {}
      return { status: response.status, headers: response.headers, bytes, text: bytes.toString(), json };
    },

    async connect(path) {
      const client = await Client.open(`ws://${origin}${path}`);
      clients.push(client);
      return client;
    },

    /// A Mac as the app is: hello, then whatever the test sends.
    async mac(key, token, { hello = 3 } = {}) {
      const mac = await relay.connect(`/cam/${key}`);
      if (hello) mac.send({ hello: { token, v: hello } });
      return mac;
    },

    phone(id, token) {
      return relay.connect(`/watch/${id}?t=${encodeURIComponent(token)}`);
    },
  };
  return relay;
}

/// A WebSocket that remembers what it received: JSON frames in `messages`, binary ones in `frames`.
export class Client {
  messages = [];
  frames = [];
  closed = false;
  #waiters = [];

  static open(url) {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(url);
      ws.binaryType = "arraybuffer";
      const client = new Client(ws);
      ws.addEventListener("open", () => resolve(client), { once: true });
      ws.addEventListener("error", () => reject(new Error(`could not open ${url}`)), { once: true });
    });
  }

  constructor(ws) {
    this.ws = ws;
    ws.addEventListener("message", ({ data }) => {
      if (typeof data === "string") this.messages.push(JSON.parse(data));
      else this.frames.push(Buffer.from(data));
      for (const waiter of this.#waiters.splice(0)) waiter();
    });
    ws.addEventListener("close", ({ code, reason }) => {
      this.closed = { code, reason };
      for (const waiter of this.#waiters.splice(0)) waiter();
    });
  }

  send(value) {
    this.ws.send(typeof value === "string" || value instanceof Uint8Array ? value : JSON.stringify(value));
  }

  close() {
    try { this.ws.close(); } catch {}
  }

  /// The first message (already received or yet to come) that `match` accepts.
  async waitFor(match, ms = 8000) {
    const end = Date.now() + ms;
    let from = 0;
    for (;;) {
      for (; from < this.messages.length; from++) if (match(this.messages[from])) return this.messages[from];
      const left = end - Date.now();
      if (left <= 0 || this.closed) {
        throw new Error(`no matching message in ${ms} ms; got ${JSON.stringify(this.messages).slice(0, 1500)}`);
      }
      await new Promise((resolve) => {
        const timer = setTimeout(resolve, left);
        this.#waiters.push(() => { clearTimeout(timer); resolve(); });
      });
    }
  }

  /// Forgets what came so far, so the next wait is for something new.
  clear() {
    this.messages.length = 0;
    this.frames.length = 0;
  }

  async waitClosed(ms = 5000) {
    const end = Date.now() + ms;
    while (!this.closed && Date.now() < end) await sleep(25);
    if (!this.closed) throw new Error("socket still open");
    return this.closed;
  }
}

/// A state as a v3 Mac sends it, with what a test changes on top.
export function macState(change = {}) {
  return {
    v: 3, phase: "idle", since: 0, armEnd: 0, lastEnd: null, place: "cafe", note: "", vol: 80, test: false, camera: true, push: false,
    trigger: null, at: null, siren: false, stage: null, softEnd: null, carried: false, bumps: 0,
    mac: { name: "Allen's MacBook Pro", model: "MacBook Pro 14″", batt: 80, chg: false },
    health: { ax: true, cam: true, lid: true, mot: true }, events: [], pass: null, ...change,
  };
}
