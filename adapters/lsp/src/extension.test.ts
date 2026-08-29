import { describe, expect, test } from "bun:test";
import * as net from "node:net";
import * as os from "node:os";
import * as path from "node:path";
import { Decoder, encode, type LspdRequest, type LspdResponse } from "../../lspd/src/codec.ts";
import { LspdClient, LspdConnectionError, LspdTimeoutError } from "./socket.ts";

function tempSocket(): string {
  return path.join(os.tmpdir(), `adapters-lsp-shim-test-${process.pid}-${Math.random().toString(36).slice(2)}.sock`);
}

// A fake daemon: speaks the codec, answers each request with a canned reply. Lets the shim's
// socket client be tested without spawning a real LSP server.
function fakeDaemon(sockPath: string, reply: (req: LspdRequest) => LspdResponse): Promise<net.Server> {
  return new Promise((resolve) => {
    const server = net.createServer((sock) => {
      const dec = new Decoder();
      sock.on("data", (chunk: Buffer) => {
        for (const msg of dec.push(chunk)) {
          const req = msg as LspdRequest;
          sock.write(encode(reply(req)));
        }
      });
    });
    server.listen(sockPath, () => resolve(server));
  });
}

describe("LspdClient — the shim's socket client", () => {
  test("forwards a request and returns the daemon's text", async () => {
    const sockPath = tempSocket();
    const server = await fakeDaemon(sockPath, (req) => ({ id: req.id, ok: true, text: `outline of ${req.params.path}` }));
    try {
      const client = new LspdClient(sockPath);
      const text = await client.request("symbols", { path: "/x/lib/foo.ex" });
      expect(text).toBe("outline of /x/lib/foo.ex");
    } finally {
      server.close();
    }
  });

  test("an ok:false reply surfaces as a plain Error (no self-heal trigger)", async () => {
    const sockPath = tempSocket();
    const server = await fakeDaemon(sockPath, (req) => ({ id: req.id, ok: false, error: "lsp: no LSP adapter for /x/README.md" }));
    try {
      const client = new LspdClient(sockPath);
      await expect(client.request("symbols", { path: "/x/README.md" })).rejects.toThrow("no LSP adapter");
    } finally {
      server.close();
    }
  });

  test("a dead socket throws LspdConnectionError (the self-heal trigger)", async () => {
    const client = new LspdClient(tempSocket()); // nothing listening
    await expect(client.request("symbols", { path: "/x/lib/foo.ex" })).rejects.toBeInstanceOf(LspdConnectionError);
  });

  test("a hung daemon throws LspdTimeoutError, not a connection error", async () => {
    const sockPath = tempSocket();
    // Accept the connection but never answer — the shim's own timeout must fire.
    const server = await new Promise<net.Server>((resolve) => {
      const s = net.createServer(() => {});
      s.listen(sockPath, () => resolve(s));
    });
    try {
      const client = new LspdClient(sockPath, 300);
      await expect(client.request("symbols", { path: "/x/lib/foo.ex" })).rejects.toBeInstanceOf(LspdTimeoutError);
    } finally {
      server.close();
    }
  });
});
