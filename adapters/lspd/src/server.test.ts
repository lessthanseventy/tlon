import { describe, expect, test } from "bun:test";
import * as net from "node:net";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { Decoder, encode, type LspdRequest, type LspdResponse } from "./codec.ts";
import { start } from "./server.ts";

// --- the wire codec (the pure seam both daemon and shim share) ---

describe("codec — length-prefixed JSON framing", () => {
  test("encode → decode round-trips a request", () => {
    const req: LspdRequest = { id: 7, method: "hover", params: { path: "/x/lib/foo.ex", line: 3, col: 5 } };
    const dec = new Decoder();
    const msgs = dec.push(encode(req));
    expect(msgs).toEqual([req]);
  });

  test("a message split across chunks reassembles", () => {
    const req: LspdRequest = { id: 1, method: "symbols", params: { path: "/x/lib/foo.ex" } };
    const buf = encode(req);
    const dec = new Decoder();
    const half = Math.floor(buf.length / 2);
    expect(dec.push(buf.subarray(0, half))).toEqual([]);
    expect(dec.push(buf.subarray(half))).toEqual([req]);
  });

  test("several messages in one chunk all come out", () => {
    const a: LspdRequest = { id: 1, method: "symbols", params: { path: "/a.ex" } };
    const b: LspdRequest = { id: 2, method: "diagnostics", params: { path: "/b.ex" } };
    const dec = new Decoder();
    expect(dec.push(Buffer.concat([encode(a), encode(b)]))).toEqual([a, b]);
  });

  test("multibyte paths survive the byte framing", () => {
    const req: LspdRequest = { id: 3, method: "symbols", params: { path: "/Tlön — Uqbar 😀/foo.ex" } };
    const dec = new Decoder();
    expect(dec.push(encode(req))).toEqual([req]);
  });

  test("a response round-trips", () => {
    const res: LspdResponse = { id: 4, ok: true, text: "def greet(name)" };
    const dec = new Decoder();
    expect(dec.push(encode(res))).toEqual([res]);
  });

  test("an absurd length prefix throws instead of buffering toward it forever", () => {
    const corrupt = Buffer.alloc(8);
    corrupt.writeUInt32BE(0xffffffff, 0);
    expect(() => new Decoder().push(corrupt)).toThrow(/frame length/);
  });

  test("a non-JSON body throws (the caller drops the connection, not the daemon)", () => {
    const body = Buffer.from("not json", "utf-8");
    const len = Buffer.alloc(4);
    len.writeUInt32BE(body.length, 0);
    expect(() => new Decoder().push(Buffer.concat([len, body]))).toThrow();
  });
});

// --- the daemon over a real socket (integration) ---

// Expert is the Elixir LSP the daemon spawns for a .ex file. It's installed outside the
// flake (~/.local/bin/expert), so the test skips on a box without it rather than failing.
const hasExpert = (() => {
  try {
    return fs.existsSync("/home/andrew/.local/bin/expert");
  } catch {
    return false;
  }
})();

function tempSocket(): string {
  return path.join(os.tmpdir(), `adapters-lspd-test-${process.pid}-${Math.random().toString(36).slice(2)}.sock`);
}

// `start` calls server.listen (async) and returns synchronously, so the socket isn't bound yet —
// await `listening` before connecting. (In production the shim's #waitForSocket retries instead.)
function listening(server: net.Server): Promise<net.Server> {
  return new Promise((resolve, reject) => {
    if (server.listening) return resolve(server);
    server.once("listening", () => resolve(server));
    server.once("error", reject);
  });
}

// A tiny client that speaks the codec — mirrors the pi shim's socket client.
function request(sockPath: string, req: LspdRequest): Promise<LspdResponse> {
  return new Promise((resolve, reject) => {
    const sock = net.createConnection(sockPath);
    const dec = new Decoder();
    sock.on("connect", () => sock.write(encode(req)));
    sock.on("data", (chunk: Buffer) => {
      for (const msg of dec.push(chunk)) {
        sock.destroy();
        resolve(msg as LspdResponse);
      }
    });
    sock.on("error", reject);
  });
}

describe("adapters-lspd — the daemon serves LSP requests over a Unix socket", () => {
  test("symbols for a fixture .ex returns the module outline", async () => {
    if (!hasExpert) return; // skip on a box without Expert
    const sockPath = tempSocket();
    const server = await listening(start(sockPath));
    try {
      const fixture = path.resolve("test/fixtures/elixir/lib/sample.ex");
      // Expert cold-indexes the project before it can answer — poll until the outline is
      // ready (this is exactly the warm-Expert cost the sidecar exists to amortize).
      let text = "";
      for (let i = 0; i < 40; i++) {
        const res = await request(sockPath, { id: 1, method: "symbols", params: { path: fixture } });
        expect(res.ok).toBe(true);
        if (res.ok && res.text !== "(no symbols)") {
          text = res.text;
          break;
        }
        await new Promise((r) => setTimeout(r, 500));
      }
      expect(text).toContain("Sample");
      expect(text).toContain("greet");
    } finally {
      server.close();
      try {
        fs.unlinkSync(sockPath);
      } catch {
        /* already gone */
      }
    }
  }, 30_000);

  test("an unknown extension returns a clear error, not a hang", async () => {
    const sockPath = tempSocket();
    const server = await listening(start(sockPath));
    try {
      const res = await request(sockPath, { id: 2, method: "symbols", params: { path: "/x/README.md" } });
      expect(res.ok).toBe(false);
      if (!res.ok) expect(res.error).toContain("no LSP adapter");
    } finally {
      server.close();
      try {
        fs.unlinkSync(sockPath);
      } catch {
        /* already gone */
      }
    }
  });
});
