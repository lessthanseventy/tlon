// The pi shim's client side of the adapters-lspd Unix socket. Each tool call forwards a
// {id, method, params} request to the long-lived daemon and awaits the {id, ok, text}
// reply. A per-request timeout (longer than the daemon's own 15s LSP timeout, so the
// daemon answers first) means a hung daemon errors rather than hanging pi.
//
// Error taxonomy drives the shim's self-heal:
//   - LspdConnectionError — the daemon isn't reachable (connect refused, socket closed).
//     The shim spawns the daemon detached and retries once.
//   - LspdTimeoutError — the daemon is up but didn't answer in time. Spawning another
//     would hit EADDRINUSE (the hung daemon still holds the socket), so no self-heal —
//     the shim surfaces a clear "restart the daemon" error instead.

import * as net from "node:net";
import * as os from "node:os";
import * as path from "node:path";
import { spawn } from "node:child_process";
import { Decoder, encode, type LspdRequest, type LspdResponse } from "../../lspd/src/codec.ts";

export class LspdConnectionError extends Error {}
export class LspdTimeoutError extends Error {}

// Must agree with the daemon's rendezvous (modules/adapters/lspd/src/server.ts) — including the
// ADAPTERS_LSPD_SOCK override the daemon honors; only the daemon reading it desynced the pair
// (an overridden daemon listened on one path while every shim dialed the default).
export function socketPath(): string {
  const override = process.env.ADAPTERS_LSPD_SOCK;
  if (override) return override;
  const dir = process.env.XDG_RUNTIME_DIR ?? path.join(os.homedir(), ".pi");
  return path.join(dir, "adapters-lspd.sock");
}

const REQUEST_TIMEOUT_MS = 20_000;

interface Pending {
  resolve: (text: string) => void;
  reject: (err: unknown) => void;
  timer: ReturnType<typeof setTimeout>;
}

export class LspdClient {
  #sock: net.Socket | null = null;
  #connecting: Promise<void> | null = null;
  #healing: Promise<void> | null = null;
  #pending = new Map<number, Pending>();
  #nextId = 1;
  #decoder = new Decoder();
  #path: string;
  #timeoutMs: number;

  constructor(sockPath = socketPath(), timeoutMs = REQUEST_TIMEOUT_MS) {
    this.#path = sockPath;
    this.#timeoutMs = timeoutMs;
  }

  // Send one tool op and await the daemon's reply. Throws LspdConnectionError on a dead
  // socket, LspdTimeoutError on a hung daemon, or a plain Error for the daemon's ok:false.
  async request(method: LspdRequest["method"], params: Record<string, unknown>): Promise<string> {
    await this.#connect();
    const id = this.#nextId++;
    return new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.#pending.delete(id);
        reject(new LspdTimeoutError(`${method} timed out after ${this.#timeoutMs}ms — the lspd daemon is not responding (mise run lspd:restart)`));
      }, this.#timeoutMs);
      this.#pending.set(id, { resolve, reject, timer });
      this.#sock!.write(encode({ id, method, params } as LspdRequest));
    });
  }

  // The backstop for a dead socket: spawn the daemon detached, wait for it to bind, retry.
  // ONE heal in flight at a time — two tool calls hitting a dead socket concurrently would each
  // spawn a daemon, and the second daemon's unlink+listen orphans (or EADDRINUSE-crashes) the
  // first. Late arrivals await the same spawn-and-bind, then send their own request.
  async selfHeal(method: LspdRequest["method"], params: Record<string, unknown>): Promise<string> {
    this.#healing ??= (async () => {
      this.spawnDaemon();
      await this.#waitForSocket(2_000);
    })().finally(() => {
      this.#healing = null;
    });
    await this.#healing;
    return this.request(method, params);
  }

  // Spawn the daemon detached (the systemd unit is the normal path; this is the backstop).
  spawnDaemon(): void {
    const entry = new URL("../../lspd/src/server.ts", import.meta.url).pathname;
    const child = spawn("bun", ["run", entry], { detached: true, stdio: "ignore" });
    child.unref();
  }

  #connect(): Promise<void> {
    if (this.#sock && !this.#sock.destroyed) return Promise.resolve();
    if (this.#connecting) return this.#connecting;
    this.#connecting = new Promise<void>((resolve, reject) => {
      const sock = net.createConnection(this.#path);
      this.#sock = sock;
      sock.on("data", (chunk: Buffer) => this.#onData(chunk));
      sock.on("error", (err) => {
        this.#failAll(new LspdConnectionError(err.message));
        this.#sock = null;
        reject(new LspdConnectionError(err.message));
      });
      sock.on("close", () => {
        this.#failAll(new LspdConnectionError("connection closed"));
        this.#sock = null;
      });
      sock.on("connect", () => resolve());
    }).finally(() => {
      this.#connecting = null;
    });
    return this.#connecting;
  }

  #onData(chunk: Buffer): void {
    for (const msg of this.#decoder.push(chunk)) {
      const res = msg as LspdResponse;
      const p = this.#pending.get(res.id);
      if (!p) continue;
      this.#pending.delete(res.id);
      clearTimeout(p.timer);
      if (res.ok) p.resolve(res.text);
      else p.reject(new Error(res.error));
    }
  }

  #failAll(err: LspdConnectionError): void {
    for (const p of this.#pending.values()) {
      clearTimeout(p.timer);
      p.reject(err);
    }
    this.#pending.clear();
  }

  async #waitForSocket(timeoutMs: number): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      try {
        await this.#connect();
        return;
      } catch (err) {
        if (!(err instanceof LspdConnectionError)) throw err;
        if (Date.now() >= deadline) throw err;
        await new Promise((r) => setTimeout(r, 150));
      }
    }
  }
}
