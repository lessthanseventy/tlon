// A minimal MCP-over-StreamableHTTP client — funes' extension door (pi doc §2a, the
// "two doors, one token" seam). There is no pi API to invoke a tool from a lifecycle
// hook, so the extension is itself a small MCP client: it does the handshake, calls
// `register` and `get_dossier`, and stops. It deliberately reuses the exact JSON-RPC
// dance funes' own e2e test proved over the wire (server_test.exs), not an SDK, so there
// is one fewer moving part between the hook and the channel.
//
// It holds no state beyond one connection's session id, and it never queues or spills:
// funes down ⇒ every call throws and the caller surfaces it (AGENTS.md: an adapter holds
// no state). Identity rides the bearer token, never a call parameter.
//
// PER-CONNECT MINT (the fix for the literal-tmux stale-401 of 2026-08-16): the token is
// NOT read from a frozen TLON_TOKEN env. On every connect (and reconnect), the client
// mints a fresh token against the SAME origin as TLON_MCP_URL (POST /mint — see
// Server.MCP.Gateway), so it always hits the right world (aleph's .dev world on 4041, or
// the always-up service's XDG world on 4040) and a pane is never stranded by a token-
// model change or a world-secret regeneration. Identity travels as the stable,
// format-agnostic (TLON_THREAD, TLON_AUTHOR, TLON_MCP_URL); the token is derived.

import { env } from "node:process";

const PROTOCOL_VERSION = "2025-03-26"; // the version funes' server_test handshakes with

interface ToolResult {
  content?: Array<{ type: string; text?: string }>;
  isError?: boolean;
}

export interface FunesConfig {
  url: string; // TLON_MCP_URL — the MCP endpoint, e.g. http://127.0.0.1:4041/mcp
  threadId: number; // TLON_THREAD — the (thread, agent) the mint binds the token to
  agent: string; // TLON_AUTHOR
}

// Identity travels in the spawn (pi doc §2d): TLON_MCP_URL / TLON_THREAD / TLON_AUTHOR. No
// TLON_TOKEN — the client mints per connect. Missing any of the three (or a non-integer
// thread) means this process wasn't spawned as a citizen: null, and the caller stays quiet
// rather than guessing. One parse for the extension and every claude-code hook.
export function identityFromEnv(
  source: Record<string, string | undefined> = env,
): FunesConfig | null {
  const url = source.TLON_MCP_URL;
  const thread = source.TLON_THREAD;
  const agent = source.TLON_AUTHOR;
  if (!url || !thread || !agent) return null;
  const threadId = Number(thread);
  if (!Number.isInteger(threadId)) return null;
  return { url, threadId, agent };
}

export class FunesUnreachable extends Error {}
export class FunesRejected extends Error {}

export class FunesClient {
  #url: string;
  #threadId: number;
  #agent: string;
  #token: string | null = null;
  #sessionId: string | null = null;
  #rpcId = 0;
  #connected = false;

  constructor({ url, threadId, agent }: FunesConfig) {
    this.#url = url;
    this.#threadId = threadId;
    this.#agent = agent;
  }

  // The MCP handshake: mint a fresh token, then initialize (the session id comes back in
  // a header) and send the initialized notification. Guarded so a hook can `await
  // connect()` freely — a second call is a no-op, never a second MCP session. After a
  // mid-session drop, #post resets #connected, so the next connect() re-mints and
  // re-handshakes — the self-heal.
  async connect(): Promise<void> {
    if (this.#connected) return;

    this.#token = await this.#mint();

    try {
      const { headers, body } = await this.#post({
        jsonrpc: "2.0",
        id: this.#nextId(),
        method: "initialize",
        params: {
          protocolVersion: PROTOCOL_VERSION,
          capabilities: {},
          clientInfo: { name: "adapters-pi", version: "0.1.0" },
        },
      });

      this.#sessionId = headers.get("mcp-session-id");
      if (!body || !("result" in body)) {
        throw new FunesRejected(`funes refused the handshake: ${JSON.stringify(body)}`);
      }

      await this.#post({ jsonrpc: "2.0", method: "notifications/initialized" });
      this.#connected = true;
    } catch (err) {
      // A half-open handshake leaves no usable session — drop the id so the next
      // connect() is a clean retry (and re-mint), never one carrying a stale session id.
      this.#sessionId = null;
      throw err;
    }
  }

  // Claim this connection's session and its pane. Supersedes any crashed predecessor
  // for the same (thread, agent) — the zombie guard is funes-side; we just call it.
  async register(paneRef: string | undefined): Promise<void> {
    await this.#callTool("register", paneRef ? { pane_ref: paneRef } : {});
  }

  // The thread's brief, as structured data (the renderer turns it into prompt text).
  async getDossier(): Promise<unknown> {
    const result = await this.#callTool("get_dossier", {});
    return this.#decodeJsonContent(result);
  }

  // Propose a working HABIT (total-recall slice D) — lands PENDING for the operator to approve in
  // the Tlön panel. Fired from a detected correction; it never auto-approves.
  async proposeHabit(text: string, rationale?: string): Promise<void> {
    await this.#callTool("propose_habit", rationale ? { text, rationale } : { text });
  }

  // Bank a DERIVED fact from cadence capture (total-recall slice C). No from_message → funes banks
  // it `derived` (the low-authority lane automation is allowed to fill). funes' own secret scan
  // (slice B) rejects a credential here, which surfaces as a thrown FunesRejected the caller drops.
  // intent (one-ledger Cut 1) is what the fact is FOR — omitted, not sent, when the extractor
  // didn't produce one, so older funes servers still accept the call.
  async bankFact(text: string, kind: "learned" | "decision", intent?: string): Promise<void> {
    await this.#callTool("bank_fact", intent ? { text, kind, intent } : { text, kind });
  }

  // Raise an open question surfaced by capture — a known unknown for the successor.
  async raiseQuestion(text: string): Promise<void> {
    await this.#callTool("raise_question", { text });
  }

  // Thinking presence (the cockpit's typing indicator). Self-thread: agent + thread resolve
  // from the token, so both declares take no args.
  async presenceThinking(): Promise<void> {
    await this.#callTool("presence_thinking", {});
  }

  async presenceIdle(): Promise<void> {
    await this.#callTool("presence_idle", {});
  }

  // Post to this connection's thread — the heartbeat check-in's vehicle (funes thread #3).
  async postMessage(body: string): Promise<void> {
    await this.#callTool("post_message", { body });
  }

  // Promote this connection's thread into the stage machine (reshape slice B). Idempotent
  // server-side; called mechanically when a turn lands a git commit.
  async trackThread(): Promise<void> {
    await this.#callTool("track_thread", {});
  }

  async #callTool(name: string, args: Record<string, unknown>): Promise<ToolResult> {
    const { body } = await this.#post({
      jsonrpc: "2.0",
      id: this.#nextId(),
      method: "tools/call",
      params: { name, arguments: args },
    });

    if (!body || !("result" in body)) {
      throw new FunesRejected(`funes returned no result for ${name}: ${JSON.stringify(body)}`);
    }

    const result = body.result as ToolResult;
    if (result.isError) {
      throw new FunesRejected(`funes rejected ${name}: ${this.#textOf(result)}`);
    }
    return result;
  }

  #decodeJsonContent(result: ToolResult): unknown {
    const text = this.#textOf(result);
    if (!text) throw new FunesRejected("funes returned an empty tool result");
    return JSON.parse(text);
  }

  #textOf(result: ToolResult): string | undefined {
    return result.content?.find((c) => c.type === "text")?.text;
  }

  #nextId(): number {
    this.#rpcId += 1;
    return this.#rpcId;
  }

  // Mint a fresh token against the TLON_MCP_URL origin's /mint endpoint — unauthenticated
  // loopback (same trust as bin/funes rpc). The token is signed with THIS node's world
  // secret, so it always verifies at /mcp on the same node. A mint failure (node down, no
  // /mint endpoint on an older node) is a FunesRejected — never a fallback to a frozen
  // token, which would just defer the 401 to the handshake and hide the real cause.
  async #mint(): Promise<string> {
    const mintUrl = new URL(this.#url).origin + "/mint";
    let res: Response;
    try {
      res = await fetch(mintUrl, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ thread_id: this.#threadId, agent: this.#agent }),
      });
    } catch (cause) {
      throw new FunesUnreachable(`funes mint endpoint not reachable at ${mintUrl}`, { cause });
    }
    if (!res.ok) {
      throw new FunesRejected(`funes mint failed (HTTP ${res.status}) at ${mintUrl}`);
    }
    const json = (await res.json()) as { token?: string };
    if (!json.token) throw new FunesRejected("funes mint returned no token");
    return json.token;
  }

  // One POST of a JSON-RPC message. A StreamableHTTP reply is JSON or a one-shot SSE
  // stream — accept both, exactly as funes' e2e test does. A transport failure (funes
  // not listening) becomes FunesUnreachable; a 401 becomes FunesRejected. Either resets
  // #connected so the next connect() re-mints and re-handshakes instead of no-oping on a
  // dead session.
  async #post(
    message: Record<string, unknown>,
  ): Promise<{ headers: Headers; body: Record<string, unknown> | null }> {
    const headers: Record<string, string> = {
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
      authorization: `Bearer ${this.#token}`,
    };
    if (this.#sessionId) headers["mcp-session-id"] = this.#sessionId;

    let res: Response;
    try {
      res = await fetch(this.#url, { method: "POST", headers, body: JSON.stringify(message) });
    } catch (cause) {
      this.#drop();
      throw new FunesUnreachable(`funes is not reachable at ${this.#url}`, { cause });
    }

    if (res.status === 401) {
      this.#drop();
      throw new FunesRejected("funes rejected the token (401) — the minted token didn't verify");
    }
    // 5xx is the node booting or down, not a refusal — surface it AS unreachable so the
    // human reads the honest cause; both surface, only the label differs.
    if (res.status >= 500) {
      this.#drop();
      throw new FunesUnreachable(`funes returned HTTP ${res.status} — the node may be starting or down`);
    }
    // 404 = the node lost this session (restarted) — dead like a 401, so drop and let the next
    // connect() re-mint + re-handshake instead of hammering the stale session id.
    if (res.status === 404) {
      this.#drop();
      throw new FunesRejected("funes lost the session (404) — the node restarted; reconnecting");
    }
    if (res.status >= 400) throw new FunesRejected(`funes returned HTTP ${res.status}`);

    return { headers: res.headers, body: await this.#decodeBody(res) };
  }

  // Mark the connection dead so the next connect() re-mints and re-handshakes. Called on
  // any transport failure or 401 — the session is no longer usable, and a fresh mint +
  // handshake is the recovery, not a retry on stale state.
  #drop(): void {
    this.#connected = false;
    this.#sessionId = null;
  }

  async #decodeBody(res: Response): Promise<Record<string, unknown> | null> {
    const raw = await res.text();
    if (!raw) return null;
    const contentType = res.headers.get("content-type") ?? "";
    if (contentType.includes("event-stream")) {
      for (const line of raw.split("\n")) {
        if (line.startsWith("data:")) return JSON.parse(line.slice(5).trim());
      }
      return null;
    }
    return JSON.parse(raw);
  }
}