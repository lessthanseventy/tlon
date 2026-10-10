import { expect, test } from "bun:test";
import * as net from "node:net";
import * as os from "node:os";
import * as path from "node:path";
import { Decoder, encode, type LspdRequest } from "../../lspd/src/codec.ts";
import { handle, TOOLS } from "./mcp.ts";
import { LspdClient } from "./socket.ts";

const sock = () => path.join(os.tmpdir(), `adapters-lsp-mcp-test-${process.pid}-${Math.random().toString(36).slice(2)}.sock`);

function daemon(at: string): Promise<net.Server> {
  return new Promise((resolve) => {
    const server = net.createServer((s) => {
      const dec = new Decoder();
      s.on("data", (chunk: Buffer) => {
        for (const req of dec.push(chunk) as LspdRequest[]) s.write(encode({ id: req.id, ok: true, text: `${req.method} of ${req.params.path}` }));
      });
    });
    server.listen(at, () => resolve(server));
  });
}

test("initialize says it serves tools, and tools/list names all six", async () => {
  const client = new LspdClient(sock());
  const init = (await handle(client, { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" } }, "/")) as { result: { capabilities: object } };
  const list = (await handle(client, { jsonrpc: "2.0", id: 2, method: "tools/list" }, "/")) as { result: { tools: { name: string }[] } };

  expect(init.result.capabilities).toEqual({ tools: {} });
  expect(list.result.tools.map((t) => t.name)).toEqual(TOOLS.map((t) => t.name));
  expect(list.result.tools.map((t) => t.name)).toEqual(["hover", "definition", "references", "symbols", "diagnostics", "impact"]);
});

test("a tool call is forwarded to the daemon and its text comes back", async () => {
  const at = sock();
  const server = await daemon(at);
  try {
    const out = (await handle(new LspdClient(at), { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "symbols", arguments: { path: "/x/lib/a.ex" } } }, "/")) as {
      result: { content: { text: string }[] };
    };
    expect(out.result.content[0]!.text).toBe("symbols of /x/lib/a.ex");
  } finally {
    server.close();
  }
});

test("a call without a path is an error result, not a crash", async () => {
  const out = (await handle(new LspdClient(sock()), { jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "hover", arguments: {} } }, "/")) as {
    result: { isError: boolean };
  };
  expect(out.result.isError).toBe(true);
});

test("a notification gets no reply; an unknown method gets an error", async () => {
  const client = new LspdClient(sock());
  expect(await handle(client, { jsonrpc: "2.0", method: "notifications/initialized" }, "/")).toBeNull();
  expect(await handle(client, { jsonrpc: "2.0", id: 5, method: "nope" }, "/")).toMatchObject({ error: { code: -32601 } });
});
