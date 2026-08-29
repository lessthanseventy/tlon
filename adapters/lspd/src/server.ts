// adapters-lspd — the supervised LSP sidecar. Owns the warm LspClient pool (one per
// (adapter, root)) behind a Unix socket, so a pi restart leaves Expert warm and the flaky
// startup crash is paid once per daemon life, not per pi life. Runs under `bun --watch`
// (systemd --user) so editing daemon code restarts the daemon, not pi.
//
// Protocol: length-prefixed JSON (codec.ts). Request {id, method, params}; response
// {id, ok, text} | {id, ok:false, error}. No auth, no multiplexing beyond id correlation —
// single user, local socket, filesystem perms.

import * as net from "node:net";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { LspClient, LspError, type LspPosition } from "./client.ts";
import { adapterForFile } from "./adapters.ts";
import { Decoder, encode, type LspdRequest, type LspdResponse } from "./codec.ts";

// The socket path both the daemon and the pi shim agree on. $XDG_RUNTIME_DIR is the
// per-user runtime dir (cleaned at logout); fall back to ~/.pi for a box without it.
export function socketPath(): string {
  const dir = process.env.XDG_RUNTIME_DIR ?? path.join(os.homedir(), ".pi");
  return path.join(dir, "adapters-lspd.sock");
}

// The warm pool — exactly the old in-process `clients` Map, hoisted behind the socket.
// Each entry also carries the initialize promise, so a request can await it before sending
// didOpen — otherwise the first request races the handshake and Expert errors on a didOpen
// that lands before `initialized`, wedging its engine init.
const clients = new Map<string, { client: LspClient; init: Promise<void> }>();

function clientFor(file: string): { client: LspClient; init: Promise<void>; key: string } {
  const adapter = adapterForFile(file);
  if (!adapter) throw new LspError(`no LSP adapter for ${file} (unknown extension)`);
  const root = adapter.rootFor(file);
  if (!root) throw new LspError(`no project root for ${file} (no ${adapter.name} marker found)`);
  const key = `${adapter.name}:${root}`;
  let entry = clients.get(key);
  if (!entry) {
    const client = new LspClient(adapter.command, adapter.args, root);
    // A failed init leaves a client that never sent `initialized` — every request on it
    // would hang or error forever. Evict it so the next call spawns a fresh one (and
    // surfaces a real error) instead of reusing a permanently-wedged connection.
    const init = client.initialize().catch(() => {
      client.dispose();
      clients.delete(key);
    });
    entry = { client, init };
    clients.set(key, entry);
  }
  return { client: entry.client, init: entry.init, key };
}

function evict(key: string): void {
  const dead = clients.get(key);
  if (dead) {
    dead.client.dispose();
    clients.delete(key);
  }
}

// line/col are 1-based (editor convention); converted to 0-based for the LSP protocol.
// Number(undefined) is NaN, and NaN ?? 1 is still NaN (?? only catches null/undefined) — the
// old fallback was dead and a missing coordinate produced {line: NaN}. Finite-check instead.
const coord = (v: unknown): number => (Number.isFinite(Number(v)) ? Number(v) : 1);

const pos = (p: Record<string, unknown>): LspPosition => ({
  line: Math.max(0, coord(p.line) - 1),
  character: Math.max(0, coord(p.col) - 1),
});

async function handle(req: LspdRequest): Promise<LspdResponse> {
  const { id, method, params } = req;
  let key: string | undefined;
  try {
    const c = clientFor(params.path);
    key = c.key;
    await c.init; // the handshake must land before didOpen (see clientFor)
    let text: string;
    switch (method) {
      case "hover":
        text = await c.client.hover(params.path, pos(params));
        break;
      case "definition":
        text = await c.client.definition(params.path, pos(params));
        break;
      case "references":
        text = await c.client.references(params.path, pos(params));
        break;
      case "symbols":
        text = await c.client.documentSymbol(params.path);
        break;
      case "diagnostics":
        text = c.client.diagnostics(params.path);
        break;
      case "impact":
        text = await c.client.impact(params.path, params.ranges ?? []);
        break;
      default:
        throw new LspError(`unknown method ${method}`);
    }
    return { id, ok: true, text };
  } catch (err) {
    const msg = err instanceof LspError ? err.message : err instanceof Error ? err.message : String(err);
    // A timeout means the server took the connection but never answered — usually its process
    // is alive while an internal worker has crashed (e.g. Expert's intermittent Unicode-stdio
    // bug: XPGenLSP.Buffer dies on startup, so no request is ever served). Reusing that wedged
    // server just times out again. Evict it so the NEXT call spawns a fresh one — the crash is
    // flaky, so a respawn usually succeeds — and tell the agent it's worth retrying.
    if (key && /timed out/.test(msg)) {
      evict(key);
      return {
        id,
        ok: false,
        error: `lsp: ${msg} — the language server stopped responding (it may have crashed on startup); it has been restarted, so retry this tool.`,
      };
    }
    return { id, ok: false, error: `lsp: ${msg}` };
  }
}

// Start the daemon on a socket path. Exported so tests can run it on a temp socket.
export function start(port: string): net.Server {
  // A stale socket file from a previous run (crash, logout) would make listen fail — unlink it.
  try {
    fs.unlinkSync(port);
  } catch {
    /* not present */
  }
  const server = net.createServer((sock) => {
    const dec = new Decoder();
    sock.on("data", (chunk: Buffer) => {
      // A corrupt frame (bad length prefix, non-JSON body) throws from the decoder; that must
      // cost the CLIENT its connection, never the shared daemon its life — every warm server
      // dies with the process.
      let msgs: unknown[];
      try {
        msgs = dec.push(chunk);
      } catch (err) {
        console.error(`adapters-lspd: dropping connection on corrupt frame: ${String(err)}`);
        sock.destroy();
        return;
      }
      for (const msg of msgs) {
        const req = msg as LspdRequest;
        void handle(req).then((res) => {
          if (!sock.destroyed) sock.write(encode(res));
        });
      }
    });
    sock.on("error", () => {
      /* a client dropped mid-request — nothing to do */
    });
  });
  // Without this an EADDRINUSE (two daemons racing the unlink+listen) is an UNCAUGHT throw —
  // a crash-loop under systemd. Log and exit nonzero so supervision sees an honest failure.
  server.on("error", (err) => {
    console.error(`adapters-lspd: listen failed on ${port}: ${String(err)}`);
    process.exitCode = 1;
  });
  server.listen(port);
  return server;
}

// Run directly: `bun run src/server.ts`. Also importable for tests (start on a temp socket).
if (import.meta.main) {
  const port = process.env.ADAPTERS_LSPD_SOCK ?? socketPath();
  start(port);
  console.error(`adapters-lspd: listening on ${port}`);
}
