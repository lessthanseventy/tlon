import { test, expect, mock, afterEach } from "bun:test";
import { TlonClient, TlonRejected, identityFromEnv } from "./mcp";

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

// A mock fetch that scripts the MCP handshake and then 404s the first tool call — exactly what
// anubis does when console restarts and loses the session the token was minted into.
function scriptedFetch() {
  let mints = 0;
  const fn = mock(async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    const body = typeof init?.body === "string" ? init.body : "";
    if (url.endsWith("/mint")) {
      mints += 1;
      return new Response(JSON.stringify({ token: "tok" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    if (body.includes('"initialize"')) {
      return new Response('event: message\ndata: {"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}\n', {
        status: 200,
        headers: { "content-type": "text/event-stream", "mcp-session-id": "sess-1" },
      });
    }
    if (body.includes('"notifications/initialized"')) {
      return new Response("", { status: 202 });
    }
    if (body.includes('"tools/call"')) {
      return new Response(JSON.stringify({ error: "no such session" }), {
        status: 404,
        headers: { "content-type": "application/json" },
      });
    }
    return new Response("{}", { status: 200, headers: { "content-type": "application/json" } });
  });
  return { fn, mints: () => mints };
}

test("a 404 (lost session) drops the connection so the next connect() re-handshakes", async () => {
  const { fn, mints } = scriptedFetch();
  globalThis.fetch = fn as unknown as typeof fetch;

  const c = new TlonClient({ url: "http://127.0.0.1:4041/mcp", threadId: 11, agent: "pi-machine" });

  await c.connect();
  expect(mints()).toBe(1);

  // A tool call 404s — anubis lost the session (the node restarted).
  await expect(c.register(undefined)).rejects.toBeInstanceOf(TlonRejected);

  // Without a #drop() on 404, #connected stays true → this connect() no-ops and the dead session
  // id is reused forever (the Tlön 404 loop). The fix drops on 404, so connect() re-mints.
  await c.connect();
  expect(mints()).toBe(2);
});

// The presence declares are self-thread and argless: the tool NAME is the whole contract, so
// pin that presence_thinking / presence_idle go out exactly as named.
test("presenceThinking / presenceIdle call their argless self-thread tools", async () => {
  const called: string[] = [];
  const fn = mock(async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    const body = typeof init?.body === "string" ? init.body : "";
    if (url.endsWith("/mint")) {
      return new Response(JSON.stringify({ token: "tok" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    if (body.includes('"initialize"')) {
      return new Response('event: message\ndata: {"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}\n', {
        status: 200,
        headers: { "content-type": "text/event-stream", "mcp-session-id": "sess-1" },
      });
    }
    if (body.includes('"notifications/initialized"')) {
      return new Response("", { status: 202 });
    }
    if (body.includes('"tools/call"')) {
      const name = (JSON.parse(body) as { params: { name: string } }).params.name;
      called.push(name);
      return new Response(
        'event: message\ndata: {"jsonrpc":"2.0","id":2,"result":{"content":[],"isError":false}}\n',
        { status: 200, headers: { "content-type": "text/event-stream" } },
      );
    }
    return new Response("{}", { status: 200, headers: { "content-type": "application/json" } });
  });
  globalThis.fetch = fn as unknown as typeof fetch;

  const c = new TlonClient({ url: "http://127.0.0.1:4041/mcp", threadId: 11, agent: "pi-machine" });
  await c.connect();
  await c.presenceThinking();
  await c.presenceIdle();

  expect(called).toEqual(["presence_thinking", "presence_idle"]);
});

// postMessage: pin the tool name + body arg go
// out exactly as the PostMessage tool expects.
test("postMessage calls post_message with the body", async () => {
  const calls: Array<{ name: string; args: unknown }> = [];
  const fn = mock(async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    const body = typeof init?.body === "string" ? init.body : "";
    if (url.endsWith("/mint")) {
      return new Response(JSON.stringify({ token: "tok" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    if (body.includes('"initialize"')) {
      return new Response('event: message\ndata: {"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}\n', {
        status: 200,
        headers: { "content-type": "text/event-stream", "mcp-session-id": "sess-1" },
      });
    }
    if (body.includes('"notifications/initialized"')) {
      return new Response("", { status: 202 });
    }
    if (body.includes('"tools/call"')) {
      const parsed = JSON.parse(body) as { params: { name: string; arguments: unknown } };
      calls.push({ name: parsed.params.name, args: parsed.params.arguments });
      return new Response(
        'event: message\ndata: {"jsonrpc":"2.0","id":2,"result":{"content":[],"isError":false}}\n',
        { status: 200, headers: { "content-type": "text/event-stream" } },
      );
    }
    return new Response("{}", { status: 200, headers: { "content-type": "application/json" } });
  });
  globalThis.fetch = fn as unknown as typeof fetch;

  const c = new TlonClient({ url: "http://127.0.0.1:4041/mcp", threadId: 11, agent: "pi-machine" });
  await c.connect();
  await c.postMessage("README split is on work/t15");

  expect(calls).toEqual([{ name: "post_message", args: { body: "README split is on work/t15" } }]);
});

// identityFromEnv — the one parse of the TLON_* identity, shared by the extension and every
// claude-code hook. All three present + an integer thread → a config; anything less → null,
// so a process not spawned as a citizen stays quiet instead of guessing.
test("identityFromEnv: the full TLON_* triple becomes a TlonConfig", () => {
  expect(
    identityFromEnv({ TLON_MCP_URL: "http://127.0.0.1:4040/mcp", TLON_THREAD: "42", TLON_AUTHOR: "claude-code" }),
  ).toEqual({ url: "http://127.0.0.1:4040/mcp", threadId: 42, agent: "claude-code" });
});

test("identityFromEnv: a missing or empty var, or a non-integer thread, is null", () => {
  const full = { TLON_MCP_URL: "http://127.0.0.1:4040/mcp", TLON_THREAD: "42", TLON_AUTHOR: "pi" };
  expect(identityFromEnv({ ...full, TLON_MCP_URL: undefined })).toBeNull();
  expect(identityFromEnv({ ...full, TLON_THREAD: "" })).toBeNull();
  expect(identityFromEnv({ ...full, TLON_AUTHOR: undefined })).toBeNull();
  expect(identityFromEnv({ ...full, TLON_THREAD: "forty-two" })).toBeNull();
  expect(identityFromEnv({ ...full, TLON_THREAD: "4.2" })).toBeNull();
  expect(identityFromEnv({})).toBeNull();
});
